extends SceneTree

## 地皮放置/删除规则测试（纯数据层 GridModel，无渲染）
## 运行：godot --headless --script res://test/scripts/tile_rules_test.gd

var _failures := 0


func _init() -> void:
	var grid := GridModel.new()
	var grass := load("res://defs/tiles/grass.tres") as TileDef
	_check(grass != null, "加载 grass 定义")

	# 初始：中心一块草地
	grid.set_cell(Vector2i.ZERO, CellData.new(null, grass))

	# --- 放置规则 ---
	_check(grid.try_place_tile(Vector2i(1, 0), grass).is_ok(), "中心旁可放置")
	_check(grid.try_place_tile(Vector2i(0, -1), grass).is_ok(), "中心另一侧可放置")
	_check(not grid.try_place_tile(Vector2i(5, 5), grass).is_ok(), "远离地块群不可放置")
	_check(not grid.try_place_tile(Vector2i(1, 0), grass).is_ok(), "已有地块处不可重复放置")
	_check(grid.try_place_tile(Vector2i(2, 0), grass).is_ok(), "紧邻地块旁可放置")
	_check(not grid.try_place_tile(Vector2i.ZERO, grass).is_ok(), "中心已有地块不可放置")
	_check(grid.can_place_tile(Vector2i(3, 0)), "can_place_tile 查询：连块旁为真")

	# --- 删除规则 ---
	_check(not grid.try_remove_tile(Vector2i.ZERO).is_ok(), "中心地块不可删除")
	_check(not grid.try_remove_tile(Vector2i(9, 9)).is_ok(), "空位置删除失败")
	_check(not grid.can_remove_tile(Vector2i.ZERO), "can_remove_tile 查询：中心为假")
	# 删 (1,0) 会让 (2,0) 脱离中心 → 断开，禁止
	_check(not grid.try_remove_tile(Vector2i(1, 0)).is_ok(), "删除桥地块不可（会断开）")
	_check(not grid.can_remove_tile(Vector2i(1, 0)), "can_remove_tile 查询：桥为假")
	# 删叶子 (2,0) 可以
	_check(grid.try_remove_tile(Vector2i(2, 0)).is_ok(), "删除叶子地块可以")

	# --- 删除带矿石的地块：矿石随地块一起移除，不给金币奖励 ---
	var ore := OreBlock.new()
	_check(grid.try_spawn_ore(Vector2i(0, -1), ore).is_ok(), "中心上方生成矿石")
	_check(grid.has_ore(Vector2i(0, -1)), "矿石已注册")
	var counts := {"discarded": 0, "rewarded": 0}
	grid.ore_discarded.connect(func(_removed: OreBlock, _cell: Vector2i) -> void: counts["discarded"] += 1)
	grid.ore_removed.connect(func(_removed: OreBlock, _cell: Vector2i) -> void: counts["rewarded"] += 1)
	_check(grid.can_remove_tile(Vector2i(0, -1)), "带矿石的地块可删除")
	_check(grid.try_remove_tile(Vector2i(0, -1)).is_ok(), "带矿石的地块删除成功")
	_check(not grid.has_ore(Vector2i(0, -1)), "矿石随地块一起移除")
	_check(not grid.has_cell(Vector2i(0, -1)), "地块已删除")
	_check(counts["discarded"] == 1 and counts["rewarded"] == 0, "走 ore_discarded（无奖励），不发 ore_removed")

	# --- 孤儿地块（绕过 try_* 的历史写入）不锁死其余删除 ---
	grid.set_block(false, Vector2i(9, 9), grass)
	_check(not grid.try_place_tile(Vector2i(10, 9), grass).is_ok(), "孤儿旁不可放置（不与中心连通）")
	_check(grid.try_remove_tile(Vector2i(1, 0)).is_ok(), "有孤儿时其余叶子仍可删")
	_check(grid.try_remove_tile(Vector2i(9, 9)).is_ok(), "孤儿地块本身可删")

	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
