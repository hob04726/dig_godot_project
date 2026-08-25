extends SceneTree

## 探查导出版 exe 内嵌 PCK 里 defs 目录的实际内容。
## 运行：godot --headless --path . --script res://test/scripts/pck_probe.gd

func _initialize() -> void:
	var exe := "C:/Users/hongb0/Projects/dig_godot/release/矿从天降.exe"
	print("load_resource_pack: ", ProjectSettings.load_resource_pack(exe, false))
	for d in ["res://defs", "res://defs/ores", "res://defs/tiles", "res://defs/talents"]:
		var files := DirAccess.get_files_at(d)
		print(d, " (%d) → %s" % [files.size(), str(files).left(300)])
	quit()
