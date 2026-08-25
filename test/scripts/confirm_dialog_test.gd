extends SceneTree
## 确认弹窗基础功能测试：实例化 confirm.tscn，调用 confirm(message) 等待选择，
## 从外部触发 Yes/No 按钮，验证返回结果。

const CONFIRM_SCENE := "res://scenes/ui/confirm.tscn"

var _pass := 0
var _fail := 0


func _init() -> void:
	# 同步等待confirm返回需要真正的SceneTree，所以在 _initialize 里跑
	pass


func _initialize() -> void:
	await _test_yes()
	await _test_no()
	print("=== confirm_dialog_test：失败 %d 处 ===" % _fail)
	quit()


func _test_yes() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 90
	var dialog := (load(CONFIRM_SCENE) as PackedScene).instantiate()
	overlay.add_child(dialog)
	root.add_child(overlay)

	# 找到 Yes 按钮并延迟触发
	var yes_btn := _find_button(dialog, "Yes")
	if yes_btn == null:
		_fail += 1
		print("[失败] 找不到 Yes 按钮")
		overlay.queue_free()
		return

	# confirm() 会等待 finished 信号；我们在一帧后触发按钮
	var t := create_timer(0.05)
	t.timeout.connect(func(): yes_btn.pressed.emit())
	var result: bool = await dialog.confirm("测试 Yes")
	if result:
		_pass += 1
		print("[通过] Yes 返回 true")
	else:
		_fail += 1
		print("[失败] Yes 应返回 true，实际 %s" % result)
	overlay.queue_free()


func _test_no() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 90
	var dialog := (load(CONFIRM_SCENE) as PackedScene).instantiate()
	overlay.add_child(dialog)
	root.add_child(overlay)

	var no_btn := _find_button(dialog, "No")
	if no_btn == null:
		_fail += 1
		print("[失败] 找不到 No 按钮")
		overlay.queue_free()
		return

	var t := create_timer(0.05)
	t.timeout.connect(func(): no_btn.pressed.emit())
	var result: bool = await dialog.confirm("测试 No")
	if not result:
		_pass += 1
		print("[通过] No 返回 false")
	else:
		_fail += 1
		print("[失败] No 应返回 false，实际 %s" % result)
	overlay.queue_free()


func _find_button(dialog: Node, text: String) -> Button:
	var hbox := dialog.get_node_or_null("PanelContainer/VBoxContainer/HBoxContainer") as HBoxContainer
	if hbox == null:
		return null
	for wrapper in hbox.get_children():
		var btn := wrapper.get_node_or_null("Button") as Button
		if btn != null and btn.text == text:
			return btn
	return null
