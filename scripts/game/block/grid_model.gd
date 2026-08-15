class_name GridModel
extends RefCounted

## 数据层唯一容器 + 全游戏唯一事件源。
## 规则：
##   1. 所有写操作走 try_* / remove_*，成功后才发信号；
##   2. 实体（OreBlock 等）不反向引用网格、不对外发跨系统信号；
##   3. 信号回调里禁止再写模型（视图/经济只读订阅）。

signal ore_spawned(ore: OreBlock, cell: Vector2i)
signal ore_landed(ore: OreBlock, cell: Vector2i)
signal ore_removed(ore: OreBlock, cell: Vector2i)
signal ore_discarded(ore: OreBlock, cell: Vector2i)
signal ore_moved(ore: OreBlock, from_cell: Vector2i, to_cell: Vector2i)
signal tile_changed(cell: Vector2i)
## spawn 地皮请求生成矿石（视图层负责实例化场景再走 try_spawn_ore）
signal tile_request_spawn(cell: Vector2i, ore_id: StringName)

const CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const DIAGONALS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## 地块群的锚点：最中间的地块，永远不可删除
const CENTER_CELL := Vector2i.ZERO

## 地皮数据（TileInstance 阶段会替换掉 CellData 槽位）
var cells: Dictionary[Vector2i, CellData] = {}
## 矿石运行时：cell -> OreBlock（矿石占用的唯一权威来源）
var ores: Dictionary[Vector2i, OreBlock] = {}
## 周期性地块行为的计时（cell -> 已累计秒数），由 tick(delta) 驱动
var _tile_timers: Dictionary[Vector2i, float] = {}


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
	# 火山不允许落矿；水允许生成（落地时由 notify_ore_landed 沉没，做出"沉入水"的效果）
	var tile := get_tile_at(cell)
	if tile.behavior == TileDef.Behavior.VOLCANO:
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "火山上不能承载矿石")
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
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "目标 %s 是水/火山，无法移动" % to_cell)
	var ore := ores[from_cell]
	ores.erase(from_cell)
	ores[to_cell] = ore
	ore.cell = to_cell
	ore_moved.emit(ore, from_cell, to_cell)
	return MutResult.ok()


## 移除矿石的唯一路径：返回被移除的矿石供结算。
## award_coins=false 时（例如随地块一起删除）改发 ore_discarded，不产生金币。
func remove_ore(cell: Vector2i, award_coins := true) -> OreBlock:
	var ore := ores.get(cell) as OreBlock
	if ore == null:
		return null
	ores.erase(cell)
	if award_coins:
		ore_removed.emit(ore, cell)
	else:
		ore_discarded.emit(ore, cell)
	return ore


## 落地事件：fall 动画结束由 GameManager 上报。
## 水/火山不让矿停留：落地即沉没/消失（算作地皮打掉的矿，给金币奖励）。
func notify_ore_landed(ore: OreBlock) -> void:
	if _is_hazard_cell(ore.cell):
		remove_ore(ore.cell)
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
	if _has_tile(cell):
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "位置 %s 已有地块" % cell)
	if not _has_connected_neighbor(cell):
		return MutResult.fail(MutResult.Code.NO_ADJACENT_TILE, "只能放置在已连接地块旁边")
	var existing := cells.get(cell) as CellData
	cells[cell] = CellData.new(existing.above_block if existing != null else null, tile_def)
	tile_changed.emit(cell)
	return MutResult.ok()


func try_remove_tile(cell: Vector2i) -> MutResult:
	if not _has_tile(cell):
		return MutResult.fail(MutResult.Code.NO_TILE_HERE, "位置 %s 没有地块" % cell)
	if cell == CENTER_CELL:
		return MutResult.fail(MutResult.Code.CENTER_PROTECTED, "中心地块不可删除")
	var cell_data := cells[cell] as CellData
	if cell_data.above_block != null:
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "地块上方有方块，先移走再删")
	if not is_tile_group_connected(cell):
		return MutResult.fail(MutResult.Code.WOULD_DISCONNECT, "删除会让地块群断开")
	# 删除地块时连带移除其上的矿石（不给金币，走 ore_discarded）
	if ores.has(cell):
		remove_ore(cell, false)
	cells.erase(cell)
	_tile_timers.erase(cell)
	tile_changed.emit(cell)
	return MutResult.ok()


## 只读查询：该位置能否放置（悬停提示用，不写模型）
func can_place_tile(cell: Vector2i) -> bool:
	if _has_tile(cell):
		return false
	return _has_connected_neighbor(cell)


## 只读查询：该位置能否删除（矿石不挡删除，会随地块一起移除）
func can_remove_tile(cell: Vector2i) -> bool:
	if not _has_tile(cell):
		return false
	if cell == CENTER_CELL:
		return false
	var cell_data := cells[cell] as CellData
	if cell_data.above_block != null:
		return false
	return is_tile_group_connected(cell)


## cell 是否紧邻地块群：要求邻居是与中心连通的地块。
## 孤立块（本就不连中心）不算，防止挂到错误的分支上。
func _has_connected_neighbor(cell: Vector2i) -> bool:
	var connected := _center_connected_tiles()
	for dir in CARDINALS:
		if connected.has(cell + dir):
			return true
	return false


## 从中心沿 CARDINALS 洪水填充，返回与中心连通的地块集合（不含 excluded）。
func _center_connected_tiles(excluded: Vector2i = Vector2i(999999, 999999)) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {}
	if not _has_tile(CENTER_CELL) or CENTER_CELL == excluded:
		return seen
	seen[CENTER_CELL] = true
	var stack: Array[Vector2i] = [CENTER_CELL]
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		for dir in CARDINALS:
			var neighbor := current + dir
			if neighbor == excluded or seen.has(neighbor):
				continue
			if _has_tile(neighbor):
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


# ==================== 地面行为（地皮阶段） ====================
## 周期性行为由 GameManager 每帧调用 tick(delta) 驱动。
## 水/火山是"危险格"：矿石无法停留（落上即消失，自动落矿与位移目标也排除）。

func tick(delta: float) -> void:
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


## 结算价值（stone 地皮倍率）——GameManager 发金币时用
func settle_value(ore: OreBlock) -> int:
	var tile := get_tile_at(ore.cell)
	var multiplier := tile.value_multiplier if tile != null else 1.0
	return int(roundf(ore.get_value() * multiplier))


## 挖矿伤害（grass 地皮倍率）——GameManager 攻击时用
func hit_damage(ore: OreBlock, base_damage: int) -> int:
	var tile := get_tile_at(ore.cell)
	var multiplier := tile.damage_multiplier if tile != null else 1.0
	return int(roundf(base_damage * multiplier))


func _advance_behavior(cell: Vector2i, tile: TileDef, delta: float) -> void:
	if tile.tick_interval <= 0.0:
		return
	_tile_timers[cell] = _tile_timers.get(cell, 0.0) + delta
	if _tile_timers[cell] < tile.tick_interval:
		return
	_tile_timers[cell] = 0.0
	match tile.behavior:
		TileDef.Behavior.VOLCANO:
			_volcano_tick(cell, tile)
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


## 火山：攻击四邻已落地的矿，打死的给金币
func _volcano_tick(cell: Vector2i, tile: TileDef) -> void:
	for dir in CARDINALS:
		var target := cell + dir
		var ore := ores.get(target) as OreBlock
		if ore == null or not ore.has_landed:
			continue
		if ore.take_damage(int(tile.damage)):
			remove_ore(target)


## 升级台：给上方已落地的矿升一级（small -> large -> huge）
func _upgrade_tick(cell: Vector2i) -> void:
	var ore := ores.get(cell) as OreBlock
	if ore != null and ore.has_landed:
		ore.upgrade_level()


## 水晶矿脉：自身空着时请求生成矿石（实例化交给视图层）
func _spawn_tick(cell: Vector2i, tile: TileDef) -> void:
	if ores.has(cell):
		return
	tile_request_spawn.emit(cell, tile.spawn_ore_id)


## 传送带：把上方已落地的矿随机推向四邻；水也算目标（推进水里会沉没），
## 火山与没有地块的位置不算；四个方向都动不了就不推
func _push_tick(cell: Vector2i) -> void:
	var ore := ores.get(cell) as OreBlock
	if ore == null or not ore.has_landed:
		return
	var targets: Array[Vector2i] = []
	for dir in CARDINALS:
		var target := cell + dir
		if ores.has(target):
			continue
		var tile := get_tile_at(target)
		if tile == null or tile.behavior == TileDef.Behavior.VOLCANO:
			continue
		targets.append(target)
	if targets.is_empty():
		return
	var chosen: Vector2i = targets.pick_random()
	if _is_hazard_cell(chosen):
		remove_ore(cell)  # 推入水：沉没消失（算作地皮打掉的矿，给金币）
	else:
		try_move_ore(cell, chosen)


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
	if ore.take_damage(int(tile.damage)):
		remove_ore(cell)


func _is_periodic(behavior: TileDef.Behavior) -> bool:
	return behavior in [
		TileDef.Behavior.VOLCANO, TileDef.Behavior.UPGRADE, TileDef.Behavior.SPAWN,
		TileDef.Behavior.PUSH, TileDef.Behavior.PULL, TileDef.Behavior.FIRE,
	]


## 水/火山：矿石无法停留的格子（没有地块也算）
func _is_hazard_cell(cell: Vector2i) -> bool:
	var tile := get_tile_at(cell)
	if tile == null:
		return true
	return tile.behavior == TileDef.Behavior.WATER or tile.behavior == TileDef.Behavior.VOLCANO


func print_data() -> void:
	for position in cells.keys():
		var cell: CellData = cells[position]
		print("position", position)
		cell.print_data()
		print("--------------------")
