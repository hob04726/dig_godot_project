extends SceneTree

## 购买跳数（unlock!/upgrade!）截图：真实场景直接触发 _spawn_rank_text，播到中段截图。
## 运行：godot --path . --script res://test/scripts/rank_text_capture.gd（非 headless，会闪窗）

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

	var nodes: Array[TalentNode] = []
	for child in grid.get_children():
		if child is TalentNode and child.effect_type != "PRESTIGE_RESET":
			nodes.append(child)
	if nodes.size() < 2:
		print("FAIL: 天赋节点不足")
		quit(1)
		return

	var unlock_node := nodes[7]   # coin_bonus
	var upgrade_node := nodes[8]
	var cam := scene.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		var mid: Vector2 = (unlock_node.global_position + upgrade_node.global_position) * 0.5
		cam.global_position = mid
		cam.target_position = mid
		cam.zoom = Vector2.ONE * 2.5
		cam.target_zoom = Vector2.ONE * 2.5

	grid._spawn_rank_text(unlock_node, false)   # 灰色 unlock!
	grid._spawn_rank_text(upgrade_node, true)   # 黄色 upgrade!
	print("跳数已触发")
	await create_timer(0.25).timeout   # 弹入完成、上飘中段截图
	root.get_texture().get_image().save_png("res://test/capture_rank_text.png")
	await create_timer(0.18).timeout   # 第二帧：对比 [wave] 波形是否随时间变化
	root.get_texture().get_image().save_png("res://test/capture_rank_text_b.png")
	print("已保存 res://test/capture_rank_text.png / _b.png")
	quit()


func _find_talent_grid(node: Node) -> Node:
	if node.get_script() != null and "talent_grid" in str(node.get_script().resource_path):
		return node
	for child in node.get_children():
		var found := _find_talent_grid(child)
		if found != null:
			return found
	return null
