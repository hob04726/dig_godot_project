extends Node2D
class_name GameManager

const ABOVE_LAYER_OFFSET := Vector2(0, -8)
const INITIAL_GRID_SIZE := 1   # 初始 3x3 草地（半径 1）

## 数据层：网格
var grid: GridData = GridData.new()
## 定义数据库：启动时扫描 defs/ 目录
var db := DefDb.new()

## 运行时节点：cell -> 上方块（优先）或下方块
var blocks_by_cell: Dictionary[Vector2i, Block] = {}
var _hovered_cell: Vector2i = Vector2i(999999, 999999)

# pointer
@export var pointer: Node2D = null

# 方块原型：普通方块（地皮/装置）
@export var block_prototype: PackedScene = null
# 矿石原型：根脚本为 OreBlock 的场景
@export var ore_prototype: PackedScene = null

@export var above_grid_layer: Node2D = null
@export var below_grid_layer: Node2D = null


func _ready() -> void:
	db.load_all()
	grid_init()
	spawn_ore(Vector2i.ONE, db.get_ore(&"gold"), 1)


func _process(delta: float) -> void:
	show_target()
	update_hover()


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
			var position := Vector2i(x, y)
			grid.set_cell(position, CellData.new(null, grass))
			create_sprite(false, position, grass)


## 该格是否存在（并且上方为空）—— 供放置/测试判断落点
func is_above_free(cell: Vector2i) -> bool:
	var cell_data := grid.get_cell(cell)
	return cell_data != null and cell_data.get_block(true) == null


## 生成矿石：数据(定义) + 运行时(OreBlock) 一次完成。
## 这里是矿石的工厂（场景在这里，定义在 DefDb）
func spawn_ore(cell: Vector2i, ore_def: OreDef, level: int = 1) -> void:
	if ore_def == null:
		push_warning("spawn_ore: 无效定义")
		return
	if not is_above_free(cell):
		push_warning("spawn_ore: %s 上方已有方块" % cell)
		return

	grid.set_block(true, cell, ore_def)

	var ore := ore_prototype.instantiate() as OreBlock
	ore.setup_ore(ore_def, level, cell)
	ore.node_name = "ore,%d,%d" % [cell.x, cell.y]
	ore.position = grid_to_world(cell) + ABOVE_LAYER_OFFSET
	ore.z_index = cell.x + cell.y + 1 + ore_def.z_bias
	above_grid_layer.add_child(ore)
	blocks_by_cell[cell] = ore


## 通用入口：改数据 + 建渲染（普通方块，如地皮/装置）
func set_block(is_above: bool, position: Vector2i, block_def: BlockDef) -> void:
	grid.set_block(is_above, position, block_def)
	create_sprite(is_above, position, block_def)


func create_sprite(is_above: bool, cell: Vector2i, block_def: BlockDef) -> void:
	var block_instance := block_prototype.instantiate() as Block
	block_instance.setup_from_def(block_def, cell)
	block_instance.node_name = "%s,%d,%d" % [is_above, cell.x, cell.y]

	block_instance.position = grid_to_world(cell) + (ABOVE_LAYER_OFFSET if is_above else Vector2.ZERO)
	block_instance.z_index = cell.x + cell.y + (1 if is_above else 0) + block_def.z_bias

	if is_above:
		above_grid_layer.add_child(block_instance)
	else:
		below_grid_layer.add_child(block_instance)

	if is_above or not blocks_by_cell.has(cell):
		blocks_by_cell[cell] = block_instance


func update_hover() -> void:
	var hovered_cell := world_to_grid(get_global_mouse_position())

	if hovered_cell == _hovered_cell:
		return

	if blocks_by_cell.has(_hovered_cell):
		blocks_by_cell[_hovered_cell].set_hovered(false)

	_hovered_cell = hovered_cell

	if blocks_by_cell.has(_hovered_cell):
		blocks_by_cell[_hovered_cell].set_hovered(true)


func grid_to_world(position: Vector2i) -> Vector2:
	var tile_width := 32.0
	var tile_height := 16.0

	return Vector2(
		(position.x - position.y) * tile_width / 2.0,
		(position.x + position.y) * tile_height / 2.0
	)

func world_to_grid(world_position: Vector2) -> Vector2i:
	var d := world_position.x / 16.0
	var s := world_position.y / 8.0

	return Vector2i(
		roundi((s + d) / 2.0),
		roundi((s - d) / 2.0)
	)
