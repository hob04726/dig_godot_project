extends SceneTree

## 验证：运行主场景几秒后，没有矿落在水域上

func _init() -> void:
	var inst := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var gm := inst.get_node("World") as GameManager
	if gm == null:
		push_error("找不到 GameManager")
		quit(1)
		return

	# 等待 3 秒，让自然落矿跑几轮
	await create_timer(3.0).timeout

	var failed := false
	for cell: Vector2i in gm.grid.ores.keys():
		var tile := gm.grid.get_tile_at(cell)
		if tile != null and tile.behavior == TileDef.Behavior.WATER:
			print("[失败] 矿落在水域上: ", cell)
			failed = true

	if not failed:
		print("[通过] 没有矿落在水域上")
	quit(1 if failed else 0)
