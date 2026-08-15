class_name MutResult
extends RefCounted

## 网格写操作的显式结果：失败不静默，调用方必须处理失败分支

enum Code {
	OK,
	CELL_OCCUPIED,     # 格子已有地块 / 上方块
	NO_ORE,
	NO_CELL,
	UNKNOWN_ORE,
	NO_ADJACENT_TILE,  # 放置位置不紧邻地块群
	NO_TILE_HERE,      # 该位置没有地块可删
	CENTER_PROTECTED,  # 中心地块不可删除
	WOULD_DISCONNECT,  # 删除会导致地块群断开
	UNKNOWN_TILE,      # 无效的地皮定义
}

var code: Code
var message: String = ""


static func ok() -> MutResult:
	return MutResult.new()


static func fail(c: Code, msg: String = "") -> MutResult:
	var r := MutResult.new()
	r.code = c
	r.message = msg
	return r


func is_ok() -> bool:
	return code == Code.OK
