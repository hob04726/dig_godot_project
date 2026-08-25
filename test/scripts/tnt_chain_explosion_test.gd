extends SceneTree

## 验证两个相邻 TNT 同时到期时都会爆炸，不会有一个被重置引信导致哑火。
## 运行：godot --headless --path . --script res://test/scripts/tnt_chain_explosion_test.gd

var _failures := 0
var _removed_count := 0


func _init() -> void:
	var gm := GameManager.new()
	gm.db.load_all()

	var layer := Node2D.new()
	root.add_child(layer)
	gm.above_grid_layer = layer
	gm.ore_prototype = load("res://scenes/ore_block.tscn") as PackedScene

	var dirt := gm.db.get_tile(&"dirt")
	var tnt_ore := gm.db.get_ore(&"tnt")

	# 3x3 陆地
	for x in range(-1, 2):
		for y in range(-1, 2):
			gm.grid.set_cell(Vector2i(x, y), CellData.new(null, dirt))

	# 在 (0,0) 和 (1,0) 放置两个 TNT 矿，并点燃（引信时间相同）
	gm.spawn_ore(Vector2i(0, 0), tnt_ore, 1)
	gm.spawn_ore(Vector2i(1, 0), tnt_ore, 1)
	var ore_a := gm.grid.get_ore(Vector2i(0, 0))
	var ore_b := gm.grid.get_ore(Vector2i(1, 0))
	gm._arm_tnt_ore(ore_a)
	gm._arm_tnt_ore(ore_b)

	# 把引信直接跳到即将爆炸
	for entry in gm._active_tnts:
		entry["time_left"] = 0.01

	gm.grid.ore_removed.connect(func(_o: OreBlock, _c: Vector2i, _r: float) -> void:
		_removed_count += 1)
	gm.grid.ore_discarded.connect(func(_o: OreBlock, _c: Vector2i) -> void:
		_removed_count += 1)

	# 触发一帧更新，让两个 TNT 同时爆炸
	gm._update_active_tnts(0.02)

	_check(_removed_count == 2, "两个相邻 TNT 同时到期都应从网格移除（TNT 爆炸走 discarded）")
	_check(not gm.grid.ores.has(Vector2i(0, 0)), "TNT A 应从网格移除")
	_check(not gm.grid.ores.has(Vector2i(1, 0)), "TNT B 应从网格移除")

	print("=== tnt_chain_explosion_test：失败 %d 处 ===" % _failures)

	layer.free()
	gm.free()
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
