extends Resource
class_name GridData

## 稀疏网格：数据层的唯一容器。
## 初始地图的搭建已从 _init 移到 GameManager（组合根），
## 这样数据容器不依赖注册表，保持纯容器身份。

var cells: Dictionary[Vector2i, CellData] = {}


func has_cell(position: Vector2i) -> bool:
	return cells.has(position)


func get_cell(position: Vector2i) -> CellData:
	return cells.get(position)


func set_cell(position: Vector2i, cell: CellData) -> void:
	cells[position] = cell


## 修改格子的上/下方块定义；格子不存在时自动创建
func set_block(is_above: bool, position: Vector2i, block_def: BlockDef) -> void:
	var cell := get_cell(position)
	if cell == null:
		cell = CellData.new()
		set_cell(position, cell)
	cell.set_block(is_above, block_def)


func create_cell(position: Vector2i, cell_data: CellData) -> void:
	cells[position] = cell_data


func print_data() -> void:
	for position in cells.keys():
		var cell: CellData = cells[position]

		print("position", position)
		cell.print_data()

		print("--------------------")
