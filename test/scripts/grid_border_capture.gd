extends SceneTree

## 实例化 talent.tscn，把 GridBorder 影响半径拉满（不依赖鼠标位置），截图验证圆角+填洞效果。
## 运行：godot --path . --script res://test/scripts/grid_border_capture.gd（非 headless，会闪一个窗口）

func _init() -> void:
	var inst := (load("res://scenes/talent.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame   # 等 _ready + 建树

	var border := inst.get_node_or_null("GridBorder") as TalentGridBorder
	if border == null:
		push_error("找不到 GridBorder")
		quit(1)
		return
	border.reveal_radius = 99999.0   # 全亮，不随鼠标衰减
	border.border_color = Color(1.0, 0.15, 0.2)   # 验证用醒目红（原色太浅看不出）
	print("GridBorder 已拉满，等待渲染…")
	await process_frame
	await process_frame
	await process_frame

	var img := root.get_texture().get_image()
	var out := "res://test/capture_grid_border.png"
	img.save_png(out)
	print("已保存截图: ", out)
	quit()
