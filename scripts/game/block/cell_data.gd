extends Resource
class_name CellData

## 格子数据：上/下两个槽位各存一个"定义"。
## 运行时节点（OreBlock / Block）由 GameManager 另行管理，
## 数据层只记录"这格是什么"。

@export var above_block: BlockDef   # null = 空
@export var below_block: BlockDef   # null = 空


func _init(above: BlockDef = null, below: BlockDef = null) -> void:
	above_block = above
	below_block = below


func set_block(is_above: bool, block_def: BlockDef) -> void:
	if is_above:
		above_block = block_def
	else:
		below_block = block_def


func get_block(is_above: bool) -> BlockDef:
	return above_block if is_above else below_block


func print_data() -> void:
	print("上方块: ", above_block.display_name if above_block else "<空>")
	print("下方块: ", below_block.display_name if below_block else "<空>")
