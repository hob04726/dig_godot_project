extends SceneTree

## 设置界面截图：Home 页 + Audio 页各一张，人工核对 back/icon 角点与页面布局。
## 运行：godot --path . --script res://test/scripts/settings_capture.gd（非 headless，会闪窗）

func _initialize() -> void:
	_run()


func _run() -> void:
	var settings := (load("res://scenes/ui/settings.tscn") as PackedScene).instantiate()
	settings.cfg_path = "user://test_settings_capture.cfg"
	root.add_child(settings)
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://test/capture_settings_home.png")
	settings._show_page(&"Audio")
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://test/capture_settings_audio.png")
	# 悬浮态：回 Home，模拟鼠标悬停 Game 按钮（平滑放大 + 白色描边）
	settings._show_page(&"Home")
	var btn := settings.get_node("Home/PanelContainer/VBoxContainer/PanelContainer/Button") as Button
	btn.mouse_entered.emit()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("res://test/capture_settings_hover.png")
	print("已保存 test/capture_settings_home.png / capture_settings_audio.png / capture_settings_hover.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings_capture.cfg"))
	quit()
