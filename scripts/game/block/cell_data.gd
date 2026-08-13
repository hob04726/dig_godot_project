extends Resource
class_name CellData

@export var above_block: BlockData
@export var below_block: BlockData

func _init(
above_block_type: Vector2i = Vector2i.ZERO, above_block_id: int = 0,
below_block_type: Vector2i = Vector2i.ZERO, below_block_id: int = 0
) -> void:
	above_block = BlockData.new(above_block_type, above_block_id)
	below_block = BlockData.new(below_block_type, below_block_id)


func print_data() -> void:
	print("上方块信息")
	above_block.print_data()
	print("下方块信息")
	below_block.print_data()

func set_block(is_above: bool, block: BlockData) -> void:
	if is_above:
		above_block = block
		print("//////////////////")
		print("设置上方方块为")
		block.print_data()
		print("//////////////////")
	else:
		below_block = block
		print("//////////////////")
		print("设置下方方块为")
		block.print_data()
		print("//////////////////")


func get_block(is_above: bool) -> BlockData:
	if is_above:
		return above_block
	else :
		return below_block
