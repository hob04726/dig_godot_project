extends Node2D
class_name GameManager

const ABOVE_LAYER_OFFSET := Vector2(0, -8)
const INITIAL_GRID_SIZE := 1   # 初始 3x3 草地（半径 1）

## 数据层：网格（唯一写入口 + 唯一事件源）
var grid := GridModel.new()
## 定义数据库：启动时扫描 defs/ 目录
var db := DefDb.new()

## 运行时地皮节点（渲染/交互用；矿石节点权威来源在 grid.ores）
var tiles_by_cell: Dictionary[Vector2i, Block] = {}
var _hovered_cell := Vector2i(999999, 999999)

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

	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	_spawn_timer.start()

	_update_money_label()


func _process(_delta: float) -> void:
	show_target()
	update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_mine_at(world_to_grid(get_global_mouse_position()))


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
	var ore_def := db.roll_ore()
	if ore_def == null:
		return
	var cell: Vector2i = free_cells.pick_random()
	spawn_ore(cell, ore_def, 1)


## 矿石上限：max_ores <= 0 时填满所有格子
func _effective_max_ores() -> int:
	return grid.cells.size() if max_ores <= 0 else max_ores


## 手动生成一个随机矿石（测试用，C 键）
func spawn_random_ore() -> void:
	var free_cells := _free_cells()
	if free_cells.is_empty():
		print("没有空闲格子了")
		return
	var ore_def := db.roll_ore()
	if ore_def == null:
		return
	var cell: Vector2i = free_cells.pick_random()
	spawn_ore(cell, ore_def, 1)


func _free_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in grid.cells.keys():
		if not grid.ores.has(cell):
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
	ore.hit()
	if ore.take_damage(pickaxe_damage):
		ore.burst_particles()
		grid.remove_ore(cell)
		# 稍后释放节点，让破碎粒子播完
		var tween := create_tween()
		tween.tween_interval(1.0)
		tween.tween_callback(ore.queue_free)


## 金币结算：订阅网格事件（经济 = 纯订阅者，不写回模型）
func _on_ore_removed(ore: OreBlock, _cell: Vector2i) -> void:
	coins += ore.get_value()
	_update_money_label()
	print("+%d 金币（总计 %d）" % [ore.get_value(), coins])


func _update_money_label() -> void:
	if money_label:
		money_label.text = "%d" % coins


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
