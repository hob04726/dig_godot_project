extends SceneTree

## 天赋购买 unlock 特效截图：真实场景触发 _play_purchase_unlock，播到一半截图。
## 运行：godot --path . --script res://test/scripts/talent_unlock_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var scene: Node = load("res://scenes/talent.tscn").instantiate()
	root.add_child(scene)
	for i in 10:
		await process_frame

	var grid := _find_talent_grid(scene)
	if grid == null:
		print("FAIL: 找不到 TalentGrid")
		quit(1)
		return
	if grid.unlock_prototype == null:
		print("FAIL: unlock_prototype 未在 talent.tscn 配置")
		quit(1)
		return

	var target: TalentNode = null
	for child in grid.get_children():
		if child is TalentNode:
			target = child
			break
	if target == null:
		print("FAIL: 没有天赋节点")
		quit(1)
		return

	var cam := scene.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.global_position = target.global_position
		cam.zoom = Vector2.ONE * 2.0
		cam.reset_camera()
	target.set_state(TalentNode.State.PURCHASED, false)

	grid._play_purchase_unlock(target)
	print("特效已触发 @ %s" % target.global_position)
	await create_timer(0.25).timeout   # 播到中段截图
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_talent_unlock.png")
	print("已保存 res://test/capture_talent_unlock.png")
	quit()


func _find_talent_grid(node: Node) -> Node:
	if node.get_script() != null and "talent_grid" in str(node.get_script().resource_path):
		return node
	for child in node.get_children():
		var found := _find_talent_grid(child)
		if found != null:
			return found
	return null
