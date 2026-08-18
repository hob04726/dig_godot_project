extends SceneTree

## 天赋界面左键拖动相机测试：
## 1. 空白处按住左键并移动 → 相机 target_position 跟随移动（带 6px 死区）
## 2. 松开左键 → 停止拖动
## 3. 按钮掩码丢失（释放事件被 UI 吃掉）→ 也能退出拖动
## 运行：godot --headless --path . --script res://test/scripts/talent_drag_test.gd

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, name: String) -> void:
	if ok:
		print("[通过] %s" % name)
	else:
		_fail += 1
		printerr("[失败] %s" % name)


func _press_left() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func _release_left() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	return e


func _move(rel: Vector2, hold_left := true) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	if hold_left:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func _run() -> void:
	var scene := (load("res://scenes/talent.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var grid := scene as TalentGrid
	var cam := grid.camera
	_check(cam != null, "相机已绑定")

	# 1. 空白处按下左键（默认鼠标在屏幕角落，远离天赋树原点的节点）
	grid._unhandled_input(_press_left())
	_check(grid._drag_armed, "空白处按下左键进入拖动预备")

	var start_target: Vector2 = cam.target_position
	# 第一次移动 4px：没过 6px 死区，不动
	grid._unhandled_input(_move(Vector2(4, 0)))
	_check(not grid._dragging and cam.target_position == start_target, "死区内不拖相机")
	# 再移动 30px：过阈值，开始拖（这次位移被死区吃掉）
	grid._unhandled_input(_move(Vector2(30, 20)))
	_check(grid._dragging, "超过阈值开始拖动")
	_check(cam.target_position == start_target, "过阈值的这次位移被死区吃掉")
	# 拖动中的后续位移才会移动相机
	grid._unhandled_input(_move(Vector2(30, 20)))
	_check(cam.target_position != start_target, "相机 target_position 已移动")

	# 2. 松开左键 → 停止拖动
	grid._unhandled_input(_release_left())
	_check(not grid._dragging and not grid._drag_armed, "松开左键停止拖动")
	var stop_target: Vector2 = cam.target_position
	grid._unhandled_input(_move(Vector2(50, 0), false))
	_check(cam.target_position == stop_target, "松开后移动不再影响相机")

	# 3. 按住拖动中掩码丢失 → 退出拖动
	grid._unhandled_input(_press_left())
	grid._unhandled_input(_move(Vector2(30, 0)))
	_check(grid._dragging, "再次按住拖动起来")
	grid._unhandled_input(_move(Vector2(10, 0), false))   # 掩码里没有左键
	_check(not grid._dragging and not grid._drag_armed, "掩码丢失兜底退出拖动")

	print("=== 结果：失败 %d 处 ===" % _fail)
	quit(1 if _fail > 0 else 0)
