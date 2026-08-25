extends SceneTree

## 放置预览虚影验证：主场景中注入选中地块（绕开天赋解锁门控），
## 把鼠标移到一个可放置格子上，截图确认虚影出现在正确位置。
## 运行：godot --path . --script res://test/scripts/ghost_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var inst := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var gm := inst.get_node("World") as GameManager
	gm.selected_tile = gm.db.get_tile(&"stone")   # 仅验证显示，直接注入
	gm.state.add_coins(BigNumber.from_int(100000))   # 先保证买得起 → 绿

	# 找一个可放置的格子
	var target := Vector2i(999, 999)
	for x in range(-4, 5):
		for y in range(-4, 5):
			if gm.grid.can_place_tile(Vector2i(x, y)):
				target = Vector2i(x, y)
				break
		if target.x != 999:
			break
	if target.x == 999:
		push_error("没有找到可放置格子")
		quit(1)
		return

	# 世界坐标 → 屏幕坐标，把鼠标移过去（update_hover 每帧跑，虚影随即出现）
	var screen := root.canvas_transform * gm.grid_to_world(target)
	Input.warp_mouse(screen)
	print("目标格子 ", target, "，屏幕坐标 ", screen)
	await process_frame
	await process_frame
	await process_frame

	print("虚影可见: ", gm._ghost != null and gm._ghost.visible, " 颜色: ", gm._ghost.modulate if gm._ghost else "n/a")
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_ghost.png")
	print("已保存 res://test/capture_ghost.png")

	# 金币清零 → 虚影应变红（可放但买不起）
	gm.state.coins = BigNumber.zero()
	await process_frame
	await process_frame
	print("清零后虚影可见: ", gm._ghost != null and gm._ghost.visible, " 颜色: ", gm._ghost.modulate if gm._ghost else "n/a")
	var img2 := root.get_texture().get_image()
	img2.save_png("res://test/capture_ghost_red.png")
	print("已保存 res://test/capture_ghost_red.png")
	quit()
