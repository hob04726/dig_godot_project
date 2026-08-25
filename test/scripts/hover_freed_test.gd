extends SceneTree
## 悬停矿被销毁后的失效引用验证：悬停 → 销毁矿 → 跑 update_hover/_update_cursor，
## 全程不应出现 "previously freed instance" 报错。
## 用法：godot --headless --path . --script res://test/scripts/hover_freed_test.gd

func _init() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var gm := scene.get_node("World") as GameManager

	var ore: OreBlock = null
	for cell in gm.grid.ores:
		ore = gm.grid.ores[cell] as OreBlock
		if ore != null:
			break
	if ore == null:
		print("没有矿可测（不影响结论：直接构造一个）")
		ore = (load("res://scenes/ore_block.tscn") as PackedScene).instantiate() as OreBlock
		ore.setup_from_def(load("res://defs/ores/coal.tres") as OreDef, Vector2i(99, 99))
		gm.add_child(ore)

	gm._hovered_node = ore
	ore.queue_free()
	await process_frame   # 真正释放

	# 这些路径之前会对已释放实例做 is 判断
	gm.update_hover()
	gm._update_cursor_wiggle(1.0 / 60.0)
	gm._update_cursor()
	await process_frame
	gm.update_hover()
	print("悬停矿销毁后所有路径跑完，无 freed instance 报错即通过")
	quit(0)
