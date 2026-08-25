extends SceneTree

## TNT 生成器产出 TNT 矿后应立即点燃引信。
## 运行：godot --headless --script res://test/scripts/tnt_spawn_arm_test.gd

var _failures := 0


func _init() -> void:
	var gm := GameManager.new()
	gm.db.load_all()

	var layer := Node2D.new()
	root.add_child(layer)
	gm.above_grid_layer = layer
	gm.ore_prototype = load("res://scenes/ore_block.tscn") as PackedScene

	var dirt := gm.db.get_tile(&"dirt")
	var tnt_spawn_tile := gm.db.get_tile(&"tnt_spawn")
	gm.grid.set_cell(Vector2i.ZERO, CellData.new(null, dirt))
	gm.grid.set_cell(Vector2i(1, 0), CellData.new(null, tnt_spawn_tile))

	# 模拟 TNT 生成器请求生成 TNT
	gm._on_tile_request_spawn(Vector2i(1, 0), &"tnt")

	# 给 ore 一帧落地
	await process_frame
	await process_frame

	_check(gm.grid.ores.has(Vector2i(1, 0)), "TNT 矿已生成到格子")
	_check(gm._active_tnts.size() == 1, "TNT 矿已被点燃")
	if gm._active_tnts.size() == 1:
		_check(gm._active_tnts[0]["kind"] == &"ore", "引信类型是 ore")
		_check(gm._active_tnts[0]["time_left"] == GameManager.TNT_FUSE_TIME, "引信时间是 3 秒")

	print("=== tnt_spawn_arm_test：失败 %d 处 ===" % _failures)

	gm._active_tnts.clear()
	for ore in gm.grid.ores.values():
		ore.queue_free()
	gm.grid.ores.clear()
	layer.free()
	gm.free()
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
