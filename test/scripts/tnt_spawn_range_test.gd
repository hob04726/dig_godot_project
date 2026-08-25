extends SceneTree

## 验证 TNT 生成器只在自身所在格请求生成 TNT。
## 运行：godot --headless --path . --script res://test/scripts/tnt_spawn_range_test.gd

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

	# 3x3 陆地，中心放 TNT 生成器
	for x in range(-1, 2):
		for y in range(-1, 2):
			var cell := Vector2i(x, y)
			var tile := tnt_spawn_tile if cell == Vector2i.ZERO else dirt
			gm.grid.set_cell(cell, CellData.new(null, tile))

	# 触发一次 TNT 生成器 tick
	gm.grid._tile_timers[Vector2i.ZERO] = tnt_spawn_tile.tick_interval
	gm.grid.tick(tnt_spawn_tile.tick_interval)

	var spawned_cells: Array[Vector2i] = []
	for target in gm.grid._spawned_this_tick.keys():
		spawned_cells.append(target)

	print("请求生成 TNT 的格子: ", spawned_cells)
	_check(spawned_cells.size() == 1, "TNT 生成器只请求 1 个格子")
	_check(spawned_cells.has(Vector2i.ZERO), "只请求自身所在格")
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x == 0 and y == 0:
				continue
			_check(not spawned_cells.has(Vector2i(x, y)),
				"不请求周围格子 (%d, %d)" % [x, y])

	print("=== tnt_spawn_range_test：失败 %d 处 ===" % _failures)

	layer.free()
	gm.free()
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
