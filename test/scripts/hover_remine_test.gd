extends SceneTree

## 长按左键滑入滑出矿即可再次挖掘的回归测试：
## 1) 按住左键悬停矿上 → 触发一次挖掘
## 2) 悬停不动不会重复挖
## 3) 离开矿后再划回同一矿 → 再次触发挖掘
## 运行：godot --headless --path . --script res://test/scripts/hover_remine_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)


func _press_left() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	Input.parse_input_event(e)


func _release_left() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	Input.parse_input_event(e)


## 把鼠标挪到远离 UI 的屏幕角落，避免 gui_get_hovered_control() 返回按钮/面板
func _move_mouse_screen(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	# 等待 SceneTransition 开场揭开结束（其 ColorRect 会挡住 gui_get_hovered_control）
	await create_timer(0.7).timeout

	var gm := scene.get_node("World") as GameManager
	# 关闭 _process，避免自动调用 _batch_mine_if_held 干扰手动测试步骤
	gm.set_process(false)

	var dirt := gm.db.get_tile(&"dirt")
	var cell_with_ore := Vector2i(50, 50)
	var empty_cell := Vector2i(51, 50)

	gm.grid.set_cell(cell_with_ore, CellData.new(null, dirt))
	gm.create_sprite(false, cell_with_ore, dirt)
	gm.grid.set_cell(empty_cell, CellData.new(null, dirt))
	gm.create_sprite(false, empty_cell, dirt)

	var coal := gm.db.get_ore(&"coal") as OreDef
	gm.spawn_ore(cell_with_ore, coal, 1)
	var ore := gm.grid.get_ore(cell_with_ore)
	_check(ore != null, "测试矿已生成")
	if ore == null:
		_finish()
		return
	ore.has_landed = true
	await process_frame

	# 鼠标移到屏幕右下角空白处，确保不在任何 UI 控件上
	_move_mouse_screen(Vector2(2000, 2000))
	await process_frame

	# 按住左键（此时鼠标在空白处，无矿）
	_press_left()
	await process_frame

	# 先悬停到空格，把拖动挖矿记录清空
	gm.update_hover(empty_cell)
	gm._batch_mine_if_held()

	# 滑入矿：应触发一次挖掘
	var hp_before := ore.hp
	gm.update_hover(cell_with_ore)
	gm._batch_mine_if_held()
	var hp_after_first := ore.hp
	_check(hp_after_first == hp_before - 1, "滑入矿时触发挖掘（hp %d -> %d）" % [hp_before, hp_after_first])

	# 悬停不动：不应重复挖掘
	gm._batch_mine_if_held()
	gm._batch_mine_if_held()
	_check(ore.hp == hp_after_first, "停在同一矿上不重复挖掘")

	# 滑出到空格：记录清空，矿未受伤
	gm.update_hover(empty_cell)
	gm._batch_mine_if_held()
	_check(ore.hp == hp_after_first, "滑出到空格不挖掘")

	# 再次滑回同一矿：应再次触发挖掘
	gm.update_hover(cell_with_ore)
	gm._batch_mine_if_held()
	_check(ore.hp == hp_after_first - 1, "离开后再划回同一矿可再次挖掘（hp %d -> %d）" % [hp_after_first, ore.hp])

	_release_left()
	_finish()


func _finish() -> void:
	print("=== hover_remine_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
