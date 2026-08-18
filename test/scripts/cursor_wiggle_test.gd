extends SceneTree
## 挖矿光标摇晃验证：旋转帧有差异、悬停矿时角度状态机按序列推进、离开后复位。
## 用法：godot --headless --path . --script res://test/scripts/cursor_wiggle_test.gd

func _init() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var gm := scene.get_node("World") as GameManager
	if gm == null or gm._cursor_mine == null:
		print("FAIL: GameManager 或光标未就绪")
		quit(1)
		return

	# 旋转帧与原图应有明显差异
	var base := gm._cursor_mine.get_image()
	var diff_count := 0
	for y in 16:
		for x in 16:
			if base.get_pixel(x, y) != gm._cursor_mine_left.get_pixel(x, y):
				diff_count += 1
	print("左旋帧与原图差异像素: %d/256（应 > 10）" % diff_count)

	# 找一个真实存在的矿来悬停（没有就用煤矿造一个）
	var ore: OreBlock = null
	for cell in gm.grid.ores:
		ore = gm.grid.ores[cell] as OreBlock
		if ore != null:
			break
	if ore == null:
		ore = (load("res://scenes/ore_block.tscn") as PackedScene).instantiate() as OreBlock
		ore.setup_from_def(load("res://defs/ores/coal.tres") as OreDef, Vector2i.ZERO)
		root.add_child(ore)
	gm._hovered_node = ore

	# 推进状态机（最长 1.2~2.8s 等待 → 摇晃序列）
	var angles_seen := {}
	for i in 240:   # 240 × 1/60 = 4s
		gm._update_cursor_wiggle(1.0 / 60.0)
		angles_seen[gm._cursor_wiggle_angle] = true
	print("摇晃过程中出现的角度: %s（应含 20.0 和 -20.0）" % str(angles_seen.keys()))

	# 移开悬停 → 立即复位
	gm._hovered_node = null
	gm._update_cursor_wiggle(1.0 / 60.0)
	print("离开悬停后角度: %.1f（应为 0）" % gm._cursor_wiggle_angle)
	quit(0)
