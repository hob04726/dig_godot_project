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
signal ore_moved(ore: OreBlock, from_cell: Vector2i, to_cell: Vector2i)
signal tile_changed(cell: Vector2i)

const CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const DIAGONALS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## 地皮数据（TileInstance 阶段会替换掉 CellData 槽位）
var cells: Dictionary[Vector2i, CellData] = {}
## 矿石运行时：cell -> OreBlock（矿石占用的唯一权威来源）
var ores: Dictionary[Vector2i, OreBlock] = {}


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
	if not cells.has(cell):
		return MutResult.fail(MutResult.Code.NO_CELL, "格子 %s 没有地皮" % cell)
	if ores.has(cell):
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "格子 %s 已有矿石" % cell)
	ores[cell] = ore
	ore.cell = cell
	ore_spawned.emit(ore, cell)
	return MutResult.ok()


func try_move_ore(from_cell: Vector2i, to_cell: Vector2i) -> MutResult:
	if not ores.has(from_cell):
		return MutResult.fail(MutResult.Code.NO_ORE, "格子 %s 没有矿石" % from_cell)
	if not cells.has(to_cell):
		return MutResult.fail(MutResult.Code.NO_CELL, "格子 %s 没有地皮" % to_cell)
	if ores.has(to_cell):
		return MutResult.fail(MutResult.Code.CELL_OCCUPIED, "格子 %s 已有矿石" % to_cell)
	var ore := ores[from_cell]
	ores.erase(from_cell)
	ores[to_cell] = ore
	ore.cell = to_cell
	ore_moved.emit(ore, from_cell, to_cell)
	return MutResult.ok()


## 破坏矿石的唯一路径：返回被移除的矿石供结算
func remove_ore(cell: Vector2i) -> OreBlock:
	var ore := ores.get(cell) as OreBlock
	if ore == null:
		return null
	ores.erase(cell)
	ore_removed.emit(ore, cell)
	return ore


## 落地事件转发（非写操作）：fall 动画结束由 GameManager 上报
func notify_ore_landed(ore: OreBlock) -> void:
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


func print_data() -> void:
	for position in cells.keys():
		var cell: CellData = cells[position]
		print("position", position)
		cell.print_data()
		print("--------------------")
