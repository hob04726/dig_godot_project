extends Node2D

const ABOVE_LAYER_OFFSET := Vector2(0, -8)

var grid: GridData = GridData.new()

# var selected_block: Vector2i = Vector2i( 0, 0 )

var blocks_by_cell: Dictionary[Vector2i, Block] = {}
var _hovered_cell: Vector2i = Vector2i(999999, 999999)

# pointer
@export var pointer: Node2D = null


# block prototype
@export var block_prototype: PackedScene = null


@export var above_grid_layer: Node2D = null
@export var below_grid_layer: Node2D = null


func _ready() -> void:
	grid_init()
	set_block(true, Vector2i.ONE, BlockData.new(Vector2i(2, 3), 0))
	pass


func _process( delta: float ) -> void:
	show_target()
	update_hover()
	pass


# 使用键盘选择方块
# func _unhandled_input( event: InputEvent ) -> void:
# 	if event.is_action_pressed( "ui_up" ):
# 		try_move( Vector2i( 0, 1 ), "up" )

# 	elif event.is_action_pressed( "ui_down" ):
# 		try_move( Vector2i( 0, -1 ), "down" )

# 	elif event.is_action_pressed( "ui_left" ):
# 		try_move( Vector2i( -1, 0 ), "left" )

# 	elif event.is_action_pressed( "ui_right" ):
# 		try_move( Vector2i( 1, 0 ), "right" )


# func try_move( direction: Vector2i, direction_name: String ) -> void:
# 	var target_block := selected_block + direction

# 	print( "==============================================" )

# 	if grid.has_cell( target_block ):
# 		print( direction_name, "moved sucessfully" )
# 		selected_block = target_block
# 	else:
# 		print( direction_name, "moved failed" )

# 	print( direction_name )

# 	var block_data: CellData = grid.get_cell( selected_block )

# 	if block_data != null:
# 		block_data.print_data()
# 	else:
# 		print( "This position do not has BlockData：", selected_block )

# 	print( "==============================================" )


func show_target() -> void:
	pointer.position = grid_to_world(_hovered_cell)


func grid_init():
	for init_position in grid.cells.keys():
		create_sprite( false, init_position, BlockData.new( Vector2i( 3,1 ), 0 ) )


func set_block(
	is_above: bool,
	position: Vector2i,
	block: BlockData
) -> void:
	grid.set_block(is_above, position, block)
	create_sprite(is_above, position, block)


func create_sprite(
	is_above: bool,
	cell: Vector2i,
	block: BlockData
) -> void:

	var block_instance := block_prototype.instantiate()

	block_instance.node_name = "%s,%d,%d" % [
		is_above,
		cell.x,
		cell.y
	]
	block_instance.texture_to_show = block.get_tex()

	block_instance.position = grid_to_world(cell) + (ABOVE_LAYER_OFFSET if is_above else Vector2.ZERO)
	block_instance.z_index = cell.x + cell.y + (1 if is_above else 0)

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
