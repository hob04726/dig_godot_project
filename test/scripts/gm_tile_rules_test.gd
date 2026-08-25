extends SceneTree
## GameManager 层级地皮放置/删除规则回归测试（新规则）
## 验证：1) 中心土块可删除；2) 不需要连通，只要是区域内水域即可放置；3) 区域外不可放置（未解锁无限）。
## 用法：godot --headless --path . --script res://test/scripts/gm_tile_rules_test.gd

var _failures := 0


func _init() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame

	var gm := scene.get_node("World") as GameManager
	if gm == null:
		_check(false, "获取 GameManager")
		_finish()
		return

	# 清空现有网格并重新初始化，避免测试受外部存档/运行时状态污染
	gm.grid.cells.clear()
	gm.grid.ores.clear()
	gm.tiles_by_cell.clear()
	gm.grid_init()

	# 确保未解锁无限放置/大面积，避免天赋影响规则判定
	_check(not gm._talent_system.has_unlimited_placement(), "当前未解锁无限放置")
	_check(gm._talent_system.get_starting_area_size() == 3, "当前开局区域 3x3")

	# 解锁 dirt 并进入放置模式
	gm._talent_system._unlocked_tiles[&"dirt"] = true
	gm.toggle_tile_selection(&"dirt")
	_check(gm.selected_tile != null, "已进入 dirt 放置模式")

	# 初始网格应为 3x3：中心 dirt，其余 water
	_check(gm.grid.get_tile_at(Vector2i.ZERO).behavior == TileDef.Behavior.NONE, "中心是 dirt")
	_check(gm.grid.get_tile_at(Vector2i(1, 0)).behavior == TileDef.Behavior.WATER, "(1,0) 是 water")
	_check(gm.grid.get_tile_at(Vector2i(1, 1)).behavior == TileDef.Behavior.WATER, "(1,1) 是 water")

	# --- 中心可删除 ---
	var center_removable := gm.grid.can_remove_tile(Vector2i.ZERO)
	_check(center_removable, "grid 报告中心可删除")
	var can_place_center := gm._can_place_selected_at(Vector2i.ZERO)
	_check(not can_place_center, "放置模式下中心不可放置（已有 dirt）")

	# --- 不需要连通，只要是区域内水域都能放置 ---
	_check(gm._can_place_selected_at(Vector2i(1, 1)), "(1,1) 不需要连通，区域内水域可放置")
	_check(not gm._can_place_selected_at(Vector2i(2, 0)), "(2,0) 超出 3x3 区域，不可放置")

	# --- 与中心相邻/不相邻的水域都可放置 ---
	_check(gm._can_place_selected_at(Vector2i(1, 0)), "(1,0) 可放置")
	_check(gm._can_place_selected_at(Vector2i(0, 1)), "(0,1) 可放置")
	_check(gm._can_place_selected_at(Vector2i(-1, -1)), "(-1,-1) 可放置")

	# 实际放置 (1,0)：先给足够金币
	gm.state.coins = BigNumber.from_int(100)
	var before_coins := gm.state.coins.duplicate()
	gm._place_selected(Vector2i(1, 0))
	_check(gm.grid.get_tile_at(Vector2i(1, 0)).behavior == TileDef.Behavior.NONE, "(1,0) 放置后变成 dirt")
	_check(gm.state.coins.lt(before_coins), "放置花费了金币")

	# 放置 (1,0) 后，(1,1) 仍然可放置（不需要连通）
	_check(gm._can_place_selected_at(Vector2i(1, 1)), "(1,0) 放置后 (1,1) 仍可放置")

	# 但 (2,0) 仍然不在 3x3 区域内，不可放置
	_check(not gm._can_place_selected_at(Vector2i(2, 0)), "(2,0) 仍在区域外，不可放置")

	# --- 删除测试 ---
	# 删除刚放的 (1,0) 应该成功
	gm._remove_tile_at(Vector2i(1, 0))
	_check(gm.grid.get_tile_at(Vector2i(1, 0)).behavior == TileDef.Behavior.WATER, "(1,0) 删除后变回 water")

	# 中心现在也可删除
	var center_result := gm.grid.try_remove_tile(Vector2i.ZERO, gm.db.get_tile(&"water"))
	_check(center_result.is_ok(), "try_remove_tile 中心现在被允许")
	_check(gm.grid.get_tile_at(Vector2i.ZERO).behavior == TileDef.Behavior.WATER, "中心删除后变回 water")

	_finish()


func _finish() -> void:
	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
