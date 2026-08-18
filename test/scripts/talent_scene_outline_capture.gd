extends SceneTree

## 真实天赋场景悬停描边验证：强制悬停一个可见节点并截图（含浅粉背景）。
## 运行：godot --path . --script res://test/scripts/talent_scene_outline_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var scene: Node = load("res://scenes/talent.tscn").instantiate()
	root.add_child(scene)
	for i in 10:
		await process_frame   # 等 TalentGrid 初始化、存档加载、节点生成

	var grid := _find_talent_grid(scene)
	if grid == null:
		print("FAIL: 找不到 TalentGrid")
		quit(1)
		return

	# 找一个在屏上且已揭示的节点强制悬停
	var target: TalentNode = null
	for child in grid.get_children():
		if child is TalentNode and child.revealed:
			target = child
			break
	if target == null:
		for child in grid.get_children():
			if child is TalentNode:
				target = child
				break
	if target == null:
		print("FAIL: 没有任何天赋节点")
		quit(1)
		return

	# 把相机对准目标节点，确保在画面里
	var cam := scene.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.global_position = target.global_position
		cam.zoom = Vector2.ONE * 2.0   # 放大看清楚描边
		cam.reset_camera()
	target.set_state(TalentNode.State.PURCHASED, false)
	target.set_hovered(true)
	print("悬停节点: %s @ %s, material=%s" % [target.talent_id, target.global_position, target.icon_sprite.material])

	await create_timer(0.6).timeout
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_talent_scene_outline.png")
	print("已保存 res://test/capture_talent_scene_outline.png")
	quit()


func _find_talent_grid(node: Node) -> Node:
	if node.get_script() != null and "talent_grid" in str(node.get_script().resource_path):
		return node
	for child in node.get_children():
		var found := _find_talent_grid(child)
		if found != null:
			return found
	return null
