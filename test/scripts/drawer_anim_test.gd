extends SceneTree
## 验证抽屉按钮选中/取消的动画是否真实播放：
## 解锁 dirt → toggle_tile_selection 选中 → 每帧采样按钮 scale/position.y → 再取消 → 再采样。
## 用法：godot --path . --script res://test/scripts/drawer_anim_test.gd

var _samples: Array[String] = []


func _init() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var gm := scene.get_node("World") as GameManager
	if gm == null:
		print("FAIL: 找不到 World")
		quit(1)
		return
	# 等 GameManager 初始化完成
	for i in 60:
		if gm.state != null:
			break
		await process_frame

	var drawer := _find_drawer(scene)
	if drawer == null:
		print("FAIL: 找不到抽屉")
		quit(1)
		return

	# 直接解锁 dirt（绕过天赋购买 UI，测动画路径）
	gm._talent_system._unlocked_tiles[&"dirt"] = true
	drawer._refresh_visible()
	await process_frame
	print("drawer visible=%s, dirt unlocked=%s" % [drawer.visible, gm.is_tile_unlocked(&"dirt")])

	var btn: Button = drawer._tile_buttons[0]
	print("按钮 size=%s pivot=%s 初始 scale=%s pos.y=%.2f base_y=%.2f" % [
		btn.size, btn.pivot_offset, btn.scale, btn.position.y, drawer._btn_base_y[0]])

	# 模拟悬停（真实点击前鼠标一定在按钮上）
	drawer._on_btn_hover(0, true)
	await _sample(drawer, btn, 0.3, "悬停")

	# 点击选中
	gm.toggle_tile_selection(&"dirt")
	await _sample(drawer, btn, 0.6, "选中")

	# 再点一次取消
	gm.toggle_tile_selection(&"dirt")
	await _sample(drawer, btn, 0.4, "取消(仍悬停)")

	drawer._on_btn_hover(0, false)
	await _sample(drawer, btn, 0.4, "离开")

	for s in _samples:
		print(s)
	quit(0)


func _sample(drawer: PanelContainer, btn: Button, duration: float, tag: String) -> void:
	var steps := int(duration / 0.033) + 1
	var line := "[%s] " % tag
	for i in steps:
		line += "%.3f/%.1f " % [btn.scale.x, btn.position.y]
		await process_frame
	_samples.append(line + " | _btn_scale=%.3f _btn_lift=%.2f" % [drawer._btn_scale[0], drawer._btn_lift[0]])


func _find_drawer(node: Node) -> PanelContainer:
	if node is PanelContainer and node.get_script() != null \
			and "tile_drawer" in str(node.get_script().resource_path):
		return node
	for child in node.get_children():
		var found := _find_drawer(child)
		if found != null:
			return found
	return null
