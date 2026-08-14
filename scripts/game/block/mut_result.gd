class_name MutResult
extends RefCounted

## 网格写操作的显式结果：失败不静默，调用方必须处理失败分支

enum Code { OK, CELL_OCCUPIED, NO_ORE, NO_CELL, UNKNOWN_ORE }

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
