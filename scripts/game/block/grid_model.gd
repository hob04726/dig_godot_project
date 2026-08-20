class_name GridModel
extends RefCounted

## 数据层唯一容器 + 全游戏唯一事件源。
## 规则：
##   1. 所有写操作走 try_* / remove_*，成功后才发信号；
##   2. 实体（OreBlock 等）不反向引用网格、不对外发跨系统信号；
##   3. 信号回调里禁止再写模型（视图/经济只读订阅）。

signal ore_spawned(ore: OreBlock, cell: Vector2i)
signal ore_landed(ore: OreBlock, cell: Vector2i)
signal ore_removed(ore: OreBlock, cell: Vector2i, reward_ratio: float)
signal ore_discarded(ore: OreBlock, cell: Vector2i)
signal ore_moved(ore: OreBlock, from_cell: Vector2i, to_cell: Vector2i)
signal tile_changed(cell: Vector2i)
## spawn 地皮请求生成矿石（视图层负责实例化场景再走 try_spawn_ore）
signal tile_request_spawn(cell: Vector2i, ore_id: StringName)
## 地块行为参数 override 更新（TILE_BEHAVIOR_UP 天赋；配置注入，非玩法写操作）
signal overrides_changed

const CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const DIAGONALS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
## 影响邻接格的地皮效果范围：自身 + 四邻（升级台 / 石头 / 草地 / 稀有矿脉 / 水晶矿脉）
const AREA_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## 地块群的锚点：最中间的地块，永远不可删除
const CENTER_CELL := Vector2i.ZERO

## 地皮数据（TileInstance 阶段会替换掉 CellData 槽位）
var cells: Dictionary[Vector2i, CellData] = {}
## 矿石运行时：cell -> OreBlock（矿石占用的唯一权威来源）
var ores: Dictionary[Vector2i, OreBlock] = {}
## 周期性地块行为的计时（cell -> 已累计秒数），由 tick(delta) 驱动
var _tile_timers: Dictionary[Vector2i, float] = {}
## 地块行为参数 override（tile_id -> {参数名: 值}）：由 TalentSystem 计算、
## 组合根在加载后一次性推送（TILE_BEHAVIOR_UP 的运行时修改，不改共享 .tres）。
## 这是配置注入而非玩法写操作：不改变网格状态、不发 tile_changed。
var tile_overrides: Dictionary[StringName, Dictionary] = {}

## 水域沉没返还比例（由 GameManager 根据 meta_water_sink 设置）。
## 0.0 = 默认吞矿不给钱；>0 则 ore 落水/被推入水时按该比例结算。
var water_sink_refund_ratio: float = 0.0

## 本 tick 已升级过的矿石实例（防止多个升级台叠加导致同一矿连升多级）
var _upgraded_this_tick: Dictionary[int, bool] = {}
## 本 tick 已请求生成矿石的格子（防止多个 spawn 地皮同一帧往同一格重复请求）
var _spawned_this_tick: Dictionary[Vector2i, bool] = {}


# ==================== 地皮数据 ====================

func has_cell(position: Vector2i) -> bool:
	return cells.has(position)


func get_cell(position: Vector2i) -> CellData:
	return cells.get(position) as CellData


func set_cell(position: Vector2i, cell: CellData) -> void:
	cells[position] = cell
	tile_changed.emit(position)


func set_block(is_above: bool, position: Vector2i, block_def: BlockDef) -> void:
	var cell := get_cell(position)
	if cell == null:
		cell = CellData.new()
		set_cell(position, cell)
	cell.set_block(is_above, block_def)
	tile_changed.emit(position)


## 推送地块行为参数 override（TILE_BEHAVIOR_UP 天赋）。
## 这是配置注入而非玩法写操作：不改变网格状态、不发 tile_changed（单独发 overrides_changed）。
## 由组合根在加载后一次性调用；参数名与 TileDef 字段一致。
func set_tile_overrides(overrides: Dictionary[StringName, Dictionary]) -> void:
	tile_overrides = overrides
	overrides_changed.emit()


# ==================== 矿石唯一写入口 ====================

func has_ore(cell: Vector2i) -> bool:
	return ores.has(cell)


func get_ore(cell: Vector2i) -> OreBlock:
	return ores.get(cell) as OreBlock


func try_spawn_ore(cell: Vector2i, ore: OreBlock) -> MutResult:
	if ore == null:
		return MutResult.fail(MutResult.Code.UNKNOWN_ORE, "矿石为空")
	if not _has_tile(cell):
		return MutResult.fail(MutResult.Code.NO_CELL, "格子 %s 没有地皮" % cell)
	if ores.has(cell):
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "格子 %s 已有矿石" % cell)
	# TNT 地皮只允许承载 TNT 矿；水允许生成（落地时沉没）
	var tile := get_tile_at(cell)
	if tile != null and tile.behavior == TileDef.Behavior.TNT and ore.get_def().id != &"tnt":
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "TNT 地皮上只能承载 TNT")
	ores[cell] = ore
	ore.cell = cell
	# 新矿入场：重置该格的周期行为计时，让首次效果从完整间隔开始
	_tile_timers.erase(cell)
	ore_spawned.emit(ore, cell)
	return MutResult.ok()


func try_move_ore(from_cell: Vector2i, to_cell: Vector2i) -> MutResult:
	if not ores.has(from_cell):
		return MutResult.fail(MutResult.Code.NO_ORE, "格子 %s 没有矿石" % from_cell)
	if not cells.has(to_cell):
		return MutResult.fail(MutResult.Code.NO_CELL, "格子 %s 没有地皮" % to_cell)
	if ores.has(to_cell):
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "格子 %s 已有矿石" % to_cell)
	if _is_hazard_cell(to_cell):
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "目标 %s 是危险格，无法移动" % to_cell)
	# TNT 地皮只能由 TNT 矿进入
	var target_tile := get_tile_at(to_cell)
	if target_tile != null and target_tile.behavior == TileDef.Behavior.TNT:
		var moving_ore := ores[from_cell]
		if moving_ore.get_def().id != &"tnt":
			return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "目标 %s 是 TNT 地皮，只能进入 TNT" % to_cell)
	var ore := ores[from_cell]
	ores.erase(from_cell)
	ores[to_cell] = ore
	ore.cell = to_cell
	ore_moved.emit(ore, from_cell, to_cell)
	return MutResult.ok()


## 移除矿石的唯一路径：返回被移除的矿石供结算。
## reward_ratio = 返还价值比例（1.0=全额、0.1=10%、0=无奖励，如删除地块连带移除）。
## ratio > 0 发 ore_removed（结算金币）；ratio = 0 发 ore_discarded（不给金币）。
func remove_ore(cell: Vector2i, reward_ratio: float = 1.0) -> OreBlock:
	var ore := ores.get(cell) as OreBlock
	if ore == null:
		return null
	ores.erase(cell)
	if reward_ratio > 0.0:
		ore_removed.emit(ore, cell, reward_ratio)
	else:
		ore_discarded.emit(ore, cell)
	return ore


## 落地事件：fall 动画结束由 GameManager 上报。
## 水/火山不让矿停留：水沉没按 _effective_sink_refund 结算（默认 0，购买 meta_water_sink 后 10%，
## TILE_BEHAVIOR_UP 可进一步覆盖）；火山视为"击杀"，全额（落地安全网）。
func notify_ore_landed(ore: OreBlock) -> void:
	if _is_hazard_cell(ore.cell):
		var ratio := 1.0
		if _is_water(ore.cell):
			ratio = _effective_sink_refund(get_tile_at(ore.cell))
		remove_ore(ore.cell, ratio)
		return
	ore_landed.emit(ore, ore.cell)


# ==================== 邻居查询（只返回坐标，由调用方决定查什么）====================

func get_neighbor_cells(cell: Vector2i, include_diagonal := false) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = CARDINALS.duplicate()
	if include_diagonal:
		dirs.append_array(DIAGONALS)
	var result: Array[Vector2i] = []
	for dir in dirs:
		result.append(cell + dir)
	return result


# ==================== 地皮放置 / 删除规则 ====================
## 地块群以 CENTER_CELL 为锚，连通性只按 CARDINALS（逻辑上下左右）判定。
## 放置：只能放在紧邻"与中心连通地块"的位置；删除：中心不可删、上方有方块不可删、
## 删除后会让其余已连接地块断开的"桥"不可删；地块上的矿石随地块一起移除且不给金币。
## 所有写入返回 MutResult，成功才发信号。地块存在性的唯一判定是 _has_tile
## （below_block != null），各规则共享同一谓词，避免"有格子但没地块"的状态产生矛盾判定。

func try_place_tile(cell: Vector2i, tile_def: TileDef) -> MutResult:
	if tile_def == null:
		return MutResult.fail(MutResult.Code.UNKNOWN_TILE, "未选择要放置的地皮")
	var existing_tile := get_tile_at(cell)
	if existing_tile != null and existing_tile.behavior != TileDef.Behavior.WATER:
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "位置 %s 已有地块" % cell)
	# 规则：放置只要求目标格是水域（或空地），不需要与中心连通
	var existing := cells.get(cell) as CellData
	cells[cell] = CellData.new(existing.above_block if existing != null else null, tile_def)
	tile_changed.emit(cell)
	return MutResult.ok()


func try_remove_tile(cell: Vector2i, water_tile_def: TileDef = null) -> MutResult:
	if not _has_tile(cell):
		return MutResult.fail(MutResult.Code.NO_TILE_HERE, "位置 %s 没有地块" % cell)
	var tile := get_tile_at(cell)
	if tile != null and tile.behavior == TileDef.Behavior.WATER:
		return MutResult.fail(MutResult.Code.NO_TILE_HERE, "位置 %s 是水域，不可删除" % cell)
	var cell_data := cells[cell] as CellData
	if cell_data.above_block != null:
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "地块上方有方块，先移走再删")
	# 规则：中心地块也可删除；删除后若造成其他地块与中心断开，那些地块不再受保护（玩家可自由编辑）
	# 删除地块时连带移除其上的矿石（不给金币，走 ore_discarded）
	if ores.has(cell):
		remove_ore(cell, 0.0)
	if water_tile_def != null:
		# 右键删除 = 用指定水域地块替换（可再次花钱替换回来）
		cells[cell] = CellData.new(null, water_tile_def)
	else:
		cells.erase(cell)
	_tile_timers.erase(cell)
	tile_changed.emit(cell)
	return MutResult.ok()


## 只读查询：该位置能否放置（悬停提示用，不写模型）。
## 水域格允许替换；空地格也允许（用于无限放置/区域外扩张）。
## 不再要求与中心连通。
func can_place_tile(cell: Vector2i) -> bool:
	var tile := get_tile_at(cell)
	if tile != null and tile.behavior != TileDef.Behavior.WATER:
		return false
	return true


## 只读查询：该位置能否删除（矿石不挡删除，会随地块一起移除）。
## 水域格不可删除；中心地块现在可删除。
func can_remove_tile(cell: Vector2i) -> bool:
	if not _has_tile(cell):
		return false
	var tile := get_tile_at(cell)
	if tile != null and tile.behavior == TileDef.Behavior.WATER:
		return false
	var cell_data := cells[cell] as CellData
	if cell_data.above_block != null:
		return false
	return true


## cell 是否紧邻地块群：要求邻居是与中心连通的陆地地块。
## 孤立块（本就不连中心）不算，防止挂到错误的分支上。
func _has_connected_neighbor(cell: Vector2i) -> bool:
	var connected := _center_connected_tiles()
	for dir in CARDINALS:
		if connected.has(cell + dir):
			return true
	return false


## 从中心沿 CARDINALS 洪水填充，返回与中心连通的陆地地块集合（不含 excluded）。
## 水域不参与连通，避免删除后替换为水仍被视为连通。
func _center_connected_tiles(excluded: Vector2i = Vector2i(999999, 999999)) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {}
	if not _has_land_tile(CENTER_CELL) or CENTER_CELL == excluded:
		return seen
	seen[CENTER_CELL] = true
	var stack: Array[Vector2i] = [CENTER_CELL]
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		for dir in CARDINALS:
			var neighbor := current + dir
			if neighbor == excluded or seen.has(neighbor):
				continue
			if _has_land_tile(neighbor):
				seen[neighbor] = true
				stack.append(neighbor)
	return seen


## 删除 excluded 后，"原本与中心连通"的地块是否仍全部连通。
## 已孤立的地块不参与约束：删除操作不会让它们"更断"，且它们本身可被清理，
## 避免历史写入口造出孤儿后把其余所有删除都锁死。
func is_tile_group_connected(excluded: Vector2i = Vector2i(999999, 999999)) -> bool:
	var before := _center_connected_tiles()
	var after := _center_connected_tiles(excluded)
	for key: Vector2i in before.keys():
		if key == excluded:
			continue
		if not after.has(key):
			return false
	return true


func _has_tile(cell: Vector2i) -> bool:
	var data := cells.get(cell) as CellData
	return data != null and data.below_block != null


## 陆地地块：有地块且不是水域（水域只作为可替换占位，不参与连通）
func _has_land_tile(cell: Vector2i) -> bool:
	var tile := get_tile_at(cell)
	return tile != null and tile.behavior != TileDef.Behavior.WATER


# ==================== 地面行为（地皮阶段） ====================
## 周期性行为由 GameManager 每帧调用 tick(delta) 驱动。
## 水/火山是"危险格"：矿石无法停留（落上即消失，自动落矿与位移目标也排除）。

func tick(delta: float) -> void:
	_upgraded_this_tick.clear()
	_spawned_this_tick.clear()
	for cell: Vector2i in cells.keys():
		var tile := get_tile_at(cell)
		if tile == null or not _is_periodic(tile.behavior):
			continue
		_advance_behavior(cell, tile, delta)


## 只读查询：该格能否承载矿石（有地块、无矿、非水/火山）
func can_hold_ore(cell: Vector2i) -> bool:
	if ores.has(cell):
		return false
	return not _is_hazard_cell(cell)


## 只读查询：格子上的地皮定义（无地块返回 null）
func get_tile_at(cell: Vector2i) -> TileDef:
	var data := cells.get(cell) as CellData
	if data == null:
		return null
	return data.below_block as TileDef


## 结算价值（stone 地皮倍率 + 天赋 override）——GameManager 发金币时用
func settle_value(ore: OreBlock) -> int:
	return int(roundf(ore.get_value() * effective_value_multiplier(ore.cell)))


## 挖矿伤害（grass 地皮倍率 + 天赋 override）——GameManager 攻击时用
func hit_damage(ore: OreBlock, base_damage: int) -> int:
	return int(roundf(base_damage * effective_damage_multiplier(ore.cell)))


# ==================== 地块行为参数（含天赋 override） ====================

## 读 override：tile_id 有 override 且含该参数则用之，否则回落 .tres 原值
func _override_param(tile: TileDef, param: StringName, fallback: Variant) -> Variant:
	if tile == null:
		return fallback
	var ov: Dictionary = tile_overrides.get(tile.id, {})
	return ov.get(param, fallback)


func _effective_value_multiplier(tile: TileDef) -> float:
	return float(_override_param(tile, &"value_multiplier", tile.value_multiplier if tile != null else 1.0))


func _effective_damage_multiplier(tile: TileDef) -> float:
	return float(_override_param(tile, &"damage_multiplier", tile.damage_multiplier if tile != null else 1.0))


func _effective_damage(tile: TileDef) -> float:
	return float(_override_param(tile, &"damage", tile.damage if tile != null else 0.0))


func _effective_tick_interval(tile: TileDef) -> float:
	return float(_override_param(tile, &"tick_interval", tile.tick_interval if tile != null else 2.0))


func _effective_min_rarity(tile: TileDef) -> int:
	return int(_override_param(tile, &"min_rarity", tile.min_rarity if tile != null else 1))


func _effective_sink_refund(tile: TileDef) -> float:
	# 先读 TILE_BEHAVIOR_UP 的 override；无 override 时回退到 GridModel 级基础比例
	#（由 GameManager 根据 meta_water_sink 设置，默认 0.0，解锁后 0.1）
	var override = tile_overrides.get(tile.id, {}).get(&"sink_refund_ratio", null) if tile != null else null
	if override != null:
		return float(override)
	return water_sink_refund_ratio


## per-cell 公开只读（GameManager / 测试用）。
## 石头（STONE）的价值倍率影响自身及四邻，多个石头倍率相乘。
func effective_value_multiplier(cell: Vector2i) -> float:
	var mult := 1.0
	for offset in AREA_OFFSETS:
		var tile := get_tile_at(cell + offset)
		if tile != null and tile.behavior == TileDef.Behavior.STONE:
			mult *= _effective_value_multiplier(tile)
	return mult


## 草地（GRASS）的伤害倍率影响自身及四邻，多个草地倍率相乘。
func effective_damage_multiplier(cell: Vector2i) -> float:
	var mult := 1.0
	for offset in AREA_OFFSETS:
		var tile := get_tile_at(cell + offset)
		if tile != null and tile.behavior == TileDef.Behavior.GRASS:
			mult *= _effective_damage_multiplier(tile)
	return mult


## 稀有矿脉（RARITY）的 min_rarity 影响自身及四邻，取最大值。
func effective_min_rarity(cell: Vector2i) -> int:
	var min_r := 1
	for offset in AREA_OFFSETS:
		var tile := get_tile_at(cell + offset)
		if tile != null and tile.behavior == TileDef.Behavior.RARITY:
			min_r = maxi(min_r, _effective_min_rarity(tile))
	return min_r


func _advance_behavior(cell: Vector2i, tile: TileDef, delta: float) -> void:
	var interval := _effective_tick_interval(tile)
	if interval <= 0.0:
		return
	_tile_timers[cell] = _tile_timers.get(cell, 0.0) + delta
	if _tile_timers[cell] < interval:
		return
	_tile_timers[cell] = 0.0
	match tile.behavior:
		TileDef.Behavior.UPGRADE:
			_upgrade_tick(cell)
		TileDef.Behavior.SPAWN:
			_spawn_tick(cell, tile)
		TileDef.Behavior.PUSH:
			_push_tick(cell)
		TileDef.Behavior.PULL:
			_pull_tick(cell)
		TileDef.Behavior.FIRE:
			_fire_tick(cell, tile)
		TileDef.Behavior.CONVEYOR_BELT_LEFTDOWN, TileDef.Behavior.CONVEYOR_BELT_LEFTUP, \
		TileDef.Behavior.CONVEYOR_BELT_RIGHTDOWN, TileDef.Behavior.CONVEYOR_BELT_RIGHTUP:
			_conveyor_tick(cell, tile)
		TileDef.Behavior.TNT_SPAWN:
			_tnt_spawn_tick(cell, tile)


## 升级台：给自身及四邻已落地的矿升一级（每个矿石每 tick 最多升一次）
func _upgrade_tick(cell: Vector2i) -> void:
	for offset in AREA_OFFSETS:
		var target := cell + offset
		var ore := ores.get(target) as OreBlock
		if ore == null or not ore.has_landed:
			continue
		if _upgraded_this_tick.has(ore.get_instance_id()):
			continue
		ore.upgrade_level()
		_upgraded_this_tick[ore.get_instance_id()] = true


## 水晶矿脉：自身及四邻有空地块时请求生成矿石（实例化交给视图层）
func _spawn_tick(cell: Vector2i, tile: TileDef) -> void:
	for offset in AREA_OFFSETS:
		var target := cell + offset
		if not cells.has(target) or ores.has(target) or _spawned_this_tick.has(target):
			continue
		_spawned_this_tick[target] = true
		tile_request_spawn.emit(target, tile.spawn_ore_id)


## 目标格能否作为 push/conveyor 的落点：需要地皮，且不是 TNT（水允许，推进去会沉没）
func _is_push_target_blocked(cell: Vector2i) -> bool:
	var tile := get_tile_at(cell)
	if tile == null:
		return true
	return tile.behavior == TileDef.Behavior.TNT


## push 地皮：把四邻已落地的 ore 向外（远离 push）推一格；
## 水可作为目标（推进去会沉没），TNT/无地皮不能作为目标。
func _push_tick(cell: Vector2i) -> void:
	for dir in CARDINALS:
		var neighbor := cell + dir
		var ore := ores.get(neighbor) as OreBlock
		if ore == null or not ore.has_landed:
			continue
		# 目标 = 邻居再沿同一方向走一格，即远离 push 的方向
		var target := neighbor + dir
		if ores.has(target):
			continue
		if _is_push_target_blocked(target):
			continue
		if _is_water(target):
			remove_ore(neighbor, _effective_sink_refund(get_tile_at(target)))
		else:
			try_move_ore(neighbor, target)


## 定向传送带：把上方已落地的矿按固定方向推一格；
## 目标有水则沉没，TNT/无地皮/有矿则不动。
func _conveyor_tick(cell: Vector2i, tile: TileDef) -> void:
	var ore := ores.get(cell) as OreBlock
	if ore == null or not ore.has_landed:
		return
	var dir := _conveyor_direction(tile.behavior)
	var target := cell + dir
	if ores.has(target):
		return
	if _is_push_target_blocked(target):
		return
	if _is_water(target):
		remove_ore(cell, _effective_sink_refund(get_tile_at(target)))
	else:
		try_move_ore(cell, target)


func _conveyor_direction(behavior: TileDef.Behavior) -> Vector2i:
	match behavior:
		TileDef.Behavior.CONVEYOR_BELT_LEFTDOWN:
			return Vector2i(0, 1)
		TileDef.Behavior.CONVEYOR_BELT_LEFTUP:
			return Vector2i(-1, 0)
		TileDef.Behavior.CONVEYOR_BELT_RIGHTDOWN:
			return Vector2i(1, 0)
		TileDef.Behavior.CONVEYOR_BELT_RIGHTUP:
			return Vector2i(0, -1)
	return Vector2i.ZERO


## TNT 生成器：自身及四邻有空地块时请求生成 TNT（实例化交给视图层）
func _tnt_spawn_tick(cell: Vector2i, tile: TileDef) -> void:
	for offset in AREA_OFFSETS:
		var target := cell + offset
		if not cells.has(target) or ores.has(target) or _spawned_this_tick.has(target):
			continue
		_spawned_this_tick[target] = true
		tile_request_spawn.emit(target, tile.spawn_ore_id)


## 磁吸：自身空着时把邻格已落地的矿吸过来
func _pull_tick(cell: Vector2i) -> void:
	if ores.has(cell):
		return
	var sources: Array[Vector2i] = []
	for dir in CARDINALS:
		var neighbor := cell + dir
		var ore := ores.get(neighbor) as OreBlock
		if ore != null and ore.has_landed:
			sources.append(neighbor)
	if sources.is_empty():
		return
	try_move_ore(sources.pick_random(), cell)


## 熔岩：持续给上方已落地的矿伤害，打死的给金币
func _fire_tick(cell: Vector2i, tile: TileDef) -> void:
	var ore := ores.get(cell) as OreBlock
	if ore == null or not ore.has_landed:
		return
	if ore.take_damage(int(_effective_damage(tile))):
		remove_ore(cell)


func _is_periodic(behavior: TileDef.Behavior) -> bool:
	return behavior in [
		TileDef.Behavior.UPGRADE, TileDef.Behavior.SPAWN,
		TileDef.Behavior.PUSH, TileDef.Behavior.PULL, TileDef.Behavior.FIRE,
		TileDef.Behavior.CONVEYOR_BELT_LEFTDOWN, TileDef.Behavior.CONVEYOR_BELT_LEFTUP,
		TileDef.Behavior.CONVEYOR_BELT_RIGHTDOWN, TileDef.Behavior.CONVEYOR_BELT_RIGHTUP,
		TileDef.Behavior.TNT_SPAWN,
	]


## 水：矿石无法停留的格子（没有地块也算）。TNT 地皮允许承载 TNT 矿，不算危险格。
func _is_hazard_cell(cell: Vector2i) -> bool:
	var tile := get_tile_at(cell)
	if tile == null:
		return true
	return tile.behavior == TileDef.Behavior.WATER


func _is_water(cell: Vector2i) -> bool:
	var tile := get_tile_at(cell)
	return tile != null and tile.behavior == TileDef.Behavior.WATER


func print_data() -> void:
	for position in cells.keys():
		var cell: CellData = cells[position]
		print("position", position)
		cell.print_data()
		print("--------------------")


# ==================== 计数 / 存档快照 ====================

## 各地块类型的已放置数量（从 cells 推导，永远与网格一致，无第二份事实源）
func get_placed_counts() -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for cell: Vector2i in cells.keys():
		var tile := get_tile_at(cell)
		if tile != null:
			counts[tile.id] = counts.get(tile.id, 0) + 1
	return counts


func get_placed_count(tile_id: StringName) -> int:
	return get_placed_counts().get(tile_id, 0)


## 存档快照（数据层只描述"有什么"，恢复由组合根做——它持有 DefDb 和场景工厂）。
## 返回 [{x,y,below,above}, ...]，id 为空串表示该槽位无方块。
func snapshot_cells() -> Array:
	var list: Array = []
	for cell: Vector2i in cells.keys():
		var data := cells[cell] as CellData
		list.append({
			"x": cell.x, "y": cell.y,
			"below": data.below_block.id if data.below_block != null else "",
			"above": data.above_block.id if data.above_block != null else "",
		})
	return list


## 存档快照：矿石的运行时数据（定义 id + 等级 + 血量，恢复时重建 OreBlock）
func snapshot_ores() -> Array:
	var list: Array = []
	for cell: Vector2i in ores.keys():
		var ore := ores[cell] as OreBlock
		list.append({
			"x": cell.x, "y": cell.y,
			"ore": ore.get_def().id,
			"level": ore.level,
			"hp": ore.hp,
		})
	return list
