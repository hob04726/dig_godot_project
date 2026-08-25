extends SceneTree

## 设置界面自检：页面切换、back/icon 角点跟随、音量写总线+落盘、全屏写档、关闭信号。
## 运行：godot --headless --path . --script res://test/scripts/settings_test.gd

var _failures := 0
const CFG := "user://test_settings.cfg"


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	var settings := (load("res://scenes/ui/settings.tscn") as PackedScene).instantiate()
	settings.cfg_path = CFG
	root.add_child(settings)
	await process_frame
	await process_frame

	# 初始：只有 Home 可见，图标是 Home
	_check((settings.get_node("Home") as Control).visible, "初始 Home 页可见")
	_check(not (settings.get_node("Audio") as Control).visible, "初始 Audio 页隐藏")
	_check(settings._icon_btn.icon != null \
		and settings._icon_btn.icon.resource_path.ends_with("Home.png"), "初始图标为 Home.png")

	# back / icon 锚点面板骑在可视面板的右上 / 左上角
	var home_panel := settings.get_node("Home/PanelContainer") as PanelContainer
	var r := home_panel.get_global_rect()
	var back: PanelContainer = settings._back_panel
	var expect_back := r.position + Vector2(r.size.x - back.size.x * 0.5, -back.size.y * 0.5)
	_check(back.global_position.distance_to(expect_back) < 1.0,
		"Back 面板骑在 Home 面板右上角（实测 %s 期望 %s）" % [back.global_position, expect_back])
	var icon: PanelContainer = settings._icon_panel
	var expect_icon := r.position - icon.size * 0.5
	_check(icon.global_position.distance_to(expect_icon) < 1.0,
		"Icon 面板骑在 Home 面板左上角（实测 %s 期望 %s）" % [icon.global_position, expect_icon])

	# 切到 Audio 页：只显示 Audio，back/icon 跟到 Audio 面板
	settings._show_page(&"Audio")
	await process_frame
	_check(not (settings.get_node("Home") as Control).visible \
		and (settings.get_node("Audio") as Control).visible, "切页后只有 Audio 可见")
	_check(settings._icon_btn.icon.resource_path.ends_with("Audio.png"), "切页后图标为 Audio.png")
	var audio_panel := settings.get_node("Audio/PanelContainer") as PanelContainer
	var ra := audio_panel.get_global_rect()
	expect_back = ra.position + Vector2(ra.size.x - back.size.x * 0.5, -back.size.y * 0.5)
	_check(back.global_position.distance_to(expect_back) < 1.0, "Back 面板跟随到 Audio 面板右上角")

	# 音量滑条 → 总线线性值 + 配置落盘
	var sm := root.get_node_or_null("SoundManager")
	_check(sm != null, "SoundManager 在树中")
	if sm != null:
		var music_slider := settings.get_node("Audio/PanelContainer/HBoxContainer/VBoxContainer2/HSlider2") as HSlider
		music_slider.value = 50.0
		await process_frame
		_check(absf(sm.get_bus_linear(&"Music") - 0.5) < 0.05,
			"音乐滑条 50 → Music 总线 ≈0.5（实测 %.2f）" % sm.get_bus_linear(&"Music"))
		var cfg := ConfigFile.new()
		_check(cfg.load(CFG) == OK and absf(float(cfg.get_value("audio", "music", -1.0)) - 0.5) < 0.05,
			"音量已写入配置文件")

	# 全屏勾选 → 配置落盘（headless 下窗口模式本身不断言）
	var check := settings.get_node("Display/PanelContainer/HBoxContainer/VBoxContainer2/CheckButton") as CheckButton
	settings._show_page(&"Display")
	check.button_pressed = true
	await process_frame
	var cfg2 := ConfigFile.new()
	_check(cfg2.load(CFG) == OK and bool(cfg2.get_value("display", "fullscreen", false)),
		"全屏勾选已写入配置文件")
	check.button_pressed = false

	# Back：子页面 → Home；Home → closed
	settings._show_page(&"Audio")
	settings._on_back()
	_check(settings._page == &"Home" and (settings.get_node("Home") as Control).visible,
		"子页面 Back 返回 Home")
	var closed_emitted := [false]
	settings.closed.connect(func() -> void: closed_emitted[0] = true)
	settings._on_back()
	_check(closed_emitted[0], "Home 页 Back 发出 closed")

	settings.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)


func _finish() -> void:
	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
