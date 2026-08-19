extends SceneTree

## 光标拖尾冒烟测试：加载主场景，模拟按住左键移动鼠标，检查拖尾有记录点。
## 运行：godot --headless --path . --script res://test/scripts/cursor_trail_test.gd

func _init() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	# 等场景完全就绪
	for i in 3:
		await process_frame

	var gm := scene.get_node("World") as GameManager
	if gm == null or gm._cursor_trail == null:
		print("FAIL: GameManager 或 CursorTrail 未就绪")
		quit(1)
		return

	# 按住左键
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)

	# 移动鼠标（注意 CursorTrail 在 CanvasLayer，使用屏幕坐标）
	for i in 30:
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(400 + i * 8, 300 + i * 5)
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		await process_frame

	var trail := gm._cursor_trail
	print("拖尾启用: ", trail._enabled, " 记录点数: ", trail._points.size())
	if trail._enabled and trail._points.size() >= 5:
		print("PASS")
	else:
		print("FAIL")
		quit(1)
		return

	# 停止拖尾，应清空拖尾（实际游戏中由左键释放触发）
	gm.set_process(false)
	trail.set_enabled(false)
	await process_frame
	print("停止后点数: ", trail._points.size(), " (应为 0)")
	if trail._points.size() != 0:
		print("FAIL")
		quit(1)
		return

	print("PASS")
	quit(0)
