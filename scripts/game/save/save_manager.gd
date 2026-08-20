class_name SaveManager
extends RefCounted

## 存档 I/O：JSON 写入 user://save.json。
## 只负责 序列化/反序列化 + 版本号 + 损坏兜底；
## 存档内容（state + grid）由组合根（GameManager）组装，这里不关心结构。
## load() 失败（无档/损坏/版本不符）返回 {}，调用方走"新游戏"。

const SAVE_VERSION := 3   # v3：开局网格改为中心 1 块陆地 + 周围水域
## 存档路径（实例变量以便测试用独立路径，不污染真实存档）
var save_path := "user://save.json"


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save(payload: Dictionary) -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: 无法写入 %s（%s）" % [save_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()


## 返回 {"state": ..., "grid": ...}；无档/损坏/版本不符 → {}
func load() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_quarantine_corrupt(text)
		return {}
	if int(parsed.get("version", -1)) != SAVE_VERSION:
		push_warning("SaveManager: 存档版本 %s 不兼容（当前 %d），忽略" % [parsed.get("version", "?"), SAVE_VERSION])
		return {}
	return parsed


## 删除存档（测试/重置用）
func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## 损坏的存档改名留底，避免覆盖用户数据
func _quarantine_corrupt(text: String) -> void:
	var bak := save_path + ".corrupt"
	var f := FileAccess.open(bak, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	push_warning("SaveManager: %s 损坏，已备份到 %s，重新开始" % [save_path, bak])
