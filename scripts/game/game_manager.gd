extends Node2D
class_name GameManager

const ABOVE_LAYER_OFFSET := Vector2(0, -8)
const INITIAL_GRID_SIZE := 1   # 初始 3x3 草地（半径 1）

# 放置模式下指针颜色：绿=可放 / 橙=可删 / 红=都不行
const POINTER_PLACE_COLOR := Color(0.4, 1, 0.4)
const POINTER_REMOVE_COLOR := Color(1, 0.72, 0.25)
const POINTER_BLOCKED_COLOR := Color(1, 0.35, 0.35)

## 数据层：网格（唯一写入口 + 唯一事件源）
var grid := GridModel.new()
## 定义数据库：启动时扫描 defs/ 目录
var db := DefDb.new()

## 运行时地皮节点（渲染/交互用；矿石节点权威来源在 grid.ores）
var tiles_by_cell: Dictionary[Vector2i, Block] = {}
var _hovered_cell := Vector2i(999999, 999999)
## 批量放置时记录上一次放置的格子，避免同一格重复放
var _last_placed_cell := Vector2i(999999, 999999)
## 批量删除时记录上一次删除的格子，避免同一格重复删
var _last_removed_cell := Vector2i(999999, 999999)

## 金币
var coins := 0

## 稿子伤害（PickaxeData 阶段再替换成资源）
@export var pickaxe_damage := 10

## 自动落矿参数
@export var spawn_interval := 2.0
## 矿石上限；<= 0 表示填满所有格子（动态取 grid.cells.size()）
@export var max_ores := 0

# pointer
@export var pointer: Node2D = null

# 方块原型：普通方块（地皮/装置）与矿石
@export var block_prototype: PackedScene = null
@export var ore_prototype: PackedScene = null

@export var above_grid_layer: Node2D = null
@export var below_grid_layer: Node2D = null

## 金币 HUD（main.tscn 里的 RichTextLabel）
@export var money_label: RichTextLabel = null

var _spawn_timer: Timer


func _ready() -> void:
	db.load_all()
	grid_init()
	spawn_ore(Vector2i.ONE, db.get_ore(&"gold"), 1)
	spawn_random_ore()
	spawn_random_ore()

	grid.ore_removed.connect(_on_ore_removed)
	grid.ore_discarded.connect(_on_ore_discarded)
	grid.ore_moved.connect(_on_ore_moved)
	grid.tile_request_spawn.connect(_on_tile_request_spawn)

	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	_spawn_timer.start()

	_update_money_label()


func _process(delta: float) -> void:
	show_target()
	update_hover()
	_batch_place_if_held()
	_batch_remove_if_held()
	grid.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell := world_to_grid(get_global_mouse_position())
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# 放置模式：左键放置选中地皮；普通模式：左键挖矿
				if selected_tile != null:
					_place_selected(cell)
				else:
					_mine_at(cell)
			MOUSE_BUTTON_RIGHT:
				# 放置模式下右键删除光标处地块
				if selected_tile != null:
					_remove_tile_at(cell)


func show_target() -> void:
	pointer.position = grid_to_world(_hovered_cell)


## 初始 3x3 草地：先写数据（CellData），再建渲染（Sprite）
func grid_init() -> void:
	var grass := db.get_tile(&"grass")
	if grass == null:
		push_error("game_manager: 缺少 grass 地皮定义，请检查 res://defs/tiles")
		return

	for x in range(-INITIAL_GRID_SIZE, INITIAL_GRID_SIZE + 1):
		for y in range(-INITIAL_GRID_SIZE, INITIAL_GRID_SIZE + 1):
			var cell := Vector2i(x, y)
			grid.set_cell(cell, CellData.new(null, grass))
			create_sprite(false, cell, grass)


# ==================== 落矿 ====================

func _on_spawn_tick() -> void:
	if grid.ores.size() >= _effective_max_ores():
		return
	var free_cells := _free_cells()
	if free_cells.is_empty():
		return
	_spawn_ore_on(free_cells.pick_random())


## 矿石上限：max_ores <= 0 时填满所有格子
func _effective_max_ores() -> int:
	return grid.cells.size() if max_ores <= 0 else max_ores


## 手动生成一个随机矿石（测试用，C 键）
func spawn_random_ore() -> void:
	var free_cells := _free_cells()
	if free_cells.is_empty():
		print("没有空闲格子了")
		return
	_spawn_ore_on(free_cells.pick_random())


## 抽取矿石并生成；rarity 地皮会提高稀有度门槛
func _spawn_ore_on(cell: Vector2i) -> void:
	var tile := grid.get_tile_at(cell)
	var min_rarity := tile.min_rarity if tile != null else 1
	var ore_def := db.roll_ore(min_rarity)
	if ore_def == null:
		return
	spawn_ore(cell, ore_def, 1)


## 空闲且能承载矿石的格子（水/火山是危险格，自动落矿不投进去；
## 想让矿落进水里沉没，用传送带把矿推进去）
func _free_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in grid.cells.keys():
		if grid.can_hold_ore(cell):
			result.append(cell)
	return result


## 矿石工厂：实例化场景 → 注册进网格 → 挂到渲染层。
## 工厂在这里（场景在这里，定义在 DefDb）
func spawn_ore(cell: Vector2i, ore_def: OreDef, level: int = 1) -> void:
	if ore_def == null:
		push_warning("spawn_ore: 无效定义")
		return

	var ore := ore_prototype.instantiate() as OreBlock
	ore.setup_ore(ore_def, level, cell)
	ore.node_name = "ore,%d,%d" % [cell.x, cell.y]
	ore.position = grid_to_world(cell) + ABOVE_LAYER_OFFSET
	ore.z_index = cell.x + cell.y + 1 + ore_def.z_bias
	above_grid_layer.add_child(ore)

	var result := grid.try_spawn_ore(cell, ore)
	if not result.is_ok():
		ore.queue_free()
		push_warning("spawn_ore 失败: %s" % result.message)
		return

	ore.landed.connect(_on_ore_landed.bind(ore), CONNECT_REFERENCE_COUNTED)


func _on_ore_landed(ore: OreBlock) -> void:
	grid.notify_ore_landed(ore)


# ==================== 挖矿 ====================

func _mine_at(cell: Vector2i) -> void:
	var ore := grid.get_ore(cell)
	if ore == null or not ore.has_landed:
		return
	# grass 地皮会放大受到的挖矿伤害
	var damage := grid.hit_damage(ore, pickaxe_damage)
	ore.hit()
	if ore.take_damage(damage):
		grid.remove_ore(cell)  # 发 ore_removed → 结算金币 + 播粒子释放节点


## 金币结算：订阅网格事件（经济 = 纯订阅者，不写回模型）。
## 挖矿与地皮打掉的矿都走这里；stone 地皮会让价值倍率更高。
## 节点释放也统一在这里做：播粒子后稍等播完再 queue_free。
func _on_ore_removed(ore: OreBlock, _cell: Vector2i) -> void:
	var gained := grid.settle_value(ore)
	coins += gained
	_update_money_label()
	print("+%d 金币（总计 %d）" % [gained, coins])
	ore.burst_particles()
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_callback(ore.queue_free)


## 删除地块时连带移除的矿（不给金币）：播粒子后释放节点
func _on_ore_discarded(ore: OreBlock, _cell: Vector2i) -> void:
	ore.burst_particles()
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(ore.queue_free)


## 位移（push/pull）：移动节点位置并更新叠放顺序
func _on_ore_moved(ore: OreBlock, _from_cell: Vector2i, to_cell: Vector2i) -> void:
	var tween := create_tween()
	tween.tween_property(ore, "position", grid_to_world(to_cell) + ABOVE_LAYER_OFFSET, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ore.z_index = to_cell.x + to_cell.y + 1 + ore.get_def().z_bias


## spawn 地皮请求生成矿石：实例化场景并走网格写入口。
## 尊重全局矿石上限（与其他落矿路径一致）。
func _on_tile_request_spawn(cell: Vector2i, ore_id: StringName) -> void:
	if grid.ores.size() >= _effective_max_ores():
		return
	var ore_def := db.get_ore(ore_id)
	if ore_def == null:
		push_warning("tile_request_spawn: 未知矿石 %s" % ore_id)
		return
	spawn_ore(cell, ore_def, 1)


func _update_money_label() -> void:
	if money_label:
		money_label.text = "%d" % coins


# ==================== 地皮放置 / 删除 ====================

## 当前选中的放置地皮（null = 未进入放置模式）
var selected_tile: TileDef = null

## 放置模式切换信号：视图订阅它来同步抽屉按钮状态
signal tile_selection_changed(tile: TileDef)


## 抽屉按钮调用：切换某地皮为当前放置目标；再点一次取消选择
func toggle_tile_selection(id: StringName) -> void:
	var def := db.get_tile(id)
	if def == null:
		push_warning("toggle_tile_selection: 未知地皮 %s" % id)
		return
	selected_tile = null if selected_tile == def else def
	tile_selection_changed.emit(selected_tile)
	_update_pointer_tint()


func _place_selected(cell: Vector2i) -> void:
	if selected_tile == null:
		return
	var result := grid.try_place_tile(cell, selected_tile)
	if not result.is_ok():
		print("放置失败: %s" % result.message)
		return
	create_sprite(false, cell, selected_tile)
	_last_placed_cell = cell
	# 写入后立刻刷新指针颜色（鼠标没动时 update_hover 会提前返回）
	_update_pointer_tint()


## 长按左键批量放置：按住左键拖动，经过可放的格子就连续放置
func _batch_place_if_held() -> void:
	if selected_tile == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_last_placed_cell = Vector2i(999999, 999999)
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return  # 右键批量删除优先，避免同一格上互相打架
	# 鼠标悬停在 UI 控件上时不批量放（避免隔着抽屉按钮放块）
	if get_viewport().gui_get_hovered_control() != null:
		return
	if _hovered_cell == _last_placed_cell:
		return
	if not grid.can_place_tile(_hovered_cell):
		return
	_place_selected(_hovered_cell)


func _remove_tile_at(cell: Vector2i) -> void:
	var result := grid.try_remove_tile(cell)
	if not result.is_ok():
		print("删除失败: %s" % result.message)
		return
	var node := tiles_by_cell.get(cell) as Block
	if node != null:
		tiles_by_cell.erase(cell)
		node.queue_free()
	# 刚删掉的格不立刻被批量放置补回来（长按左键 + 右键删除的组合操作）
	_last_placed_cell = cell
	_last_removed_cell = cell
	# 地块上的矿石由 ore_discarded 处理器统一释放（不给金币）
	_update_pointer_tint()


## 长按右键批量删除：按住右键拖动，经过可删的格子就连续删除
func _batch_remove_if_held() -> void:
	if selected_tile == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_last_removed_cell = Vector2i(999999, 999999)
		return
	# 鼠标悬停在 UI 控件上时不批量删
	if get_viewport().gui_get_hovered_control() != null:
		return
	if _hovered_cell == _last_removed_cell:
		return
	if not grid.can_remove_tile(_hovered_cell):
		return
	_remove_tile_at(_hovered_cell)


## 放置模式下给鼠标指针染色：绿=可放、橙=可删（矿石会随地块一起删）、红=都不行（中心/桥/太远）
func _update_pointer_tint() -> void:
	if pointer == null:
		return
	if selected_tile == null:
		pointer.modulate = Color.WHITE
		return
	if grid.can_place_tile(_hovered_cell):
		pointer.modulate = POINTER_PLACE_COLOR
	elif grid.can_remove_tile(_hovered_cell):
		pointer.modulate = POINTER_REMOVE_COLOR
	else:
		pointer.modulate = POINTER_BLOCKED_COLOR


# ==================== 通用方块（地皮等） ====================

func set_block(is_above: bool, cell: Vector2i, block_def: BlockDef) -> void:
	grid.set_block(is_above, cell, block_def)
	create_sprite(is_above, cell, block_def)


func create_sprite(is_above: bool, cell: Vector2i, block_def: BlockDef) -> void:
	var block_instance := block_prototype.instantiate() as Block
	block_instance.setup_from_def(block_def, cell)
	block_instance.starts_falling = false
	block_instance.node_name = "%s,%d,%d" % [is_above, cell.x, cell.y]

	block_instance.position = grid_to_world(cell) + (ABOVE_LAYER_OFFSET if is_above else Vector2.ZERO)
	block_instance.z_index = cell.x + cell.y + (1 if is_above else 0) + block_def.z_bias

	if is_above:
		above_grid_layer.add_child(block_instance)
	else:
		below_grid_layer.add_child(block_instance)

	if not is_above:
		tiles_by_cell[cell] = block_instance


# ==================== 悬停 / 坐标 ====================

## 交互目标：优先矿石，其次地皮
func _node_at(cell: Vector2i) -> Block:
	if grid.ores.has(cell):
		return grid.ores[cell]
	return tiles_by_cell.get(cell) as Block


func update_hover() -> void:
	var hovered_cell := world_to_grid(get_global_mouse_position())

	if hovered_cell == _hovered_cell:
		return

	_set_hover(_hovered_cell, false)
	_hovered_cell = hovered_cell
	_set_hover(_hovered_cell, true)
	_update_pointer_tint()


func _set_hover(cell: Vector2i, hovered: bool) -> void:
	var node := _node_at(cell)
	if node:
		node.set_hovered(hovered)


func grid_to_world(cell: Vector2i) -> Vector2:
	var tile_width := 32.0
	var tile_height := 16.0

	return Vector2(
		(cell.x - cell.y) * tile_width / 2.0,
		(cell.x + cell.y) * tile_height / 2.0
	)

func world_to_grid(world_position: Vector2) -> Vector2i:
	var d := world_position.x / 16.0
	var s := world_position.y / 8.0

	return Vector2i(
		roundi((s + d) / 2.0),
		roundi((s - d) / 2.0)
	)
