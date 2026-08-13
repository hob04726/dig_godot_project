extends Resource
class_name GridData


var cells: Dictionary[Vector2i, CellData] = {}


func _init() -> void:
	cells.clear()
	cells = {

		# 初始3*3草地
		Vector2i( 1,  1): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i( 0,  1): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i(-1,  1): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i( 1,  0): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i( 0,  0): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i(-1,  0): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i( 1, -1): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i( 0, -1): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),
		Vector2i(-1, -1): CellData.new(Vector2i(0, 0), 0, Vector2i(3, 1), 1),

		# # 石头边界
		# Vector2i( 2,  2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i( 1,  2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i( 0,  2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i(-1,  2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i(-2,  2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),

		# Vector2i( 2,  1): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i( 2,  0): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i( 2, -1): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),

		# Vector2i(-2,  1): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i(-2,  0): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i(-2, -1): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),

		# Vector2i( 2, -2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i( 1, -2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i( 0, -2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i(-1, -2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
		# Vector2i(-2, -2): CellData.new(Vector2i(3, 3), 1, Vector2i(0, 0), 0),
	}


func has_cell(position: Vector2i) -> bool:
	return cells.has(position)


func get_cell(position: Vector2i) -> CellData:
	return cells.get(position)


func set_cell(position: Vector2i, cell: CellData) -> void:
	cells[position] = cell

func set_block(is_above: bool, position: Vector2i, block: BlockData) -> void:
	var cell := get_cell(position)
	if cell == null:
		cell = CellData.new()
		set_cell(position, cell)
	cell.set_block(is_above, block)

func print_data() -> void:
	for position in cells.keys():
		var cell: CellData = cells[position]

		print("position", position)
		cell.print_data()


		print("--------------------")



func create_cell(position: Vector2i, cell_data: CellData) -> void:
	cells[position] = cell_data
