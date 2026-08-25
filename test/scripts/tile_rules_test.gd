extends SceneTree

## 地皮放置/删除规则测试（纯数据层 GridModel，无渲染）
## 新规则：放置只要求目标格是水域/空地，不需要连通；中心地块也可删除。
## 运行：godot --headless --script res://test/scripts/tile_rules_test.gd

var _failures := 0


func _init() -> void:
	var grid := GridModel.new()
	var grass := load("res://defs/tiles/grass.tres") as TileDef
	var water := load("res://defs/tiles/water.tres") as TileDef
	_check(grass != null, "加载 grass 定义")
	_check(water != null, "加载 water 定义")

	# 初始：中心一块草地，旁边一块水域
	grid.set_cell(Vector2i.ZERO, CellData.new(null, grass))
	grid.set_cell(Vector2i(1, 0), CellData.new(null, water))

	# --- 放置规则 ---
	_check(grid.try_place_tile(Vector2i(1, 0), grass).is_ok(), "替换水域可放置")
	_check(grid.try_place_tile(Vector2i(5, 5), grass).is_ok(), "空地不需要连通也可放置")
	_check(not grid.try_place_tile(Vector2i.ZERO, grass).is_ok(), "已有非水域地块处不可重复放置")
	_check(grid.try_place_tile(Vector2i(0, -1), grass).is_ok(), "另一块空地可放置")
	_check(grid.can_place_tile(Vector2i(9, 9)), "can_place_tile 查询：空地为真")
	_check(not grid.can_place_tile(Vector2i.ZERO), "can_place_tile 查询：已有非水域地块为假")

	# --- 删除规则 ---
	_check(grid.can_remove_tile(Vector2i.ZERO), "can_remove_tile 查询：中心为真")
	_check(grid.try_remove_tile(Vector2i.ZERO).is_ok(), "中心地块现在可删除")
	_check(not grid.try_remove_tile(Vector2i(9, 9)).is_ok(), "空位置删除失败")
	# (1,0) 是 grass，可删除
	_check(grid.try_remove_tile(Vector2i(1, 0)).is_ok(), "删除普通地块可以")
	# (0,-1) 是 grass，可删除
	_check(grid.try_remove_tile(Vector2i(0, -1)).is_ok(), "删除另一块普通地块可以")

	# --- 删除带矿石的地块：矿石随地块一起移除，不给金币奖励 ---
	grid.set_cell(Vector2i(2, 0), CellData.new(null, grass))
	var ore := OreBlock.new()
	_check(grid.try_spawn_ore(Vector2i(2, 0), ore).is_ok(), "目标格生成矿石")
	_check(grid.has_ore(Vector2i(2, 0)), "矿石已注册")
	var counts := {"discarded": 0, "rewarded": 0}
	grid.ore_discarded.connect(func(_removed: OreBlock, _cell: Vector2i) -> void: counts["discarded"] += 1)
	grid.ore_removed.connect(func(_removed: OreBlock, _cell: Vector2i, _ratio: float) -> void: counts["rewarded"] += 1)
	_check(grid.can_remove_tile(Vector2i(2, 0)), "带矿石的地块可删除")
	_check(grid.try_remove_tile(Vector2i(2, 0)).is_ok(), "带矿石的地块删除成功")
	_check(not grid.has_ore(Vector2i(2, 0)), "矿石随地块一起移除")
	_check(not grid.has_cell(Vector2i(2, 0)), "地块已删除")
	_check(counts["discarded"] == 1 and counts["rewarded"] == 0, "走 ore_discarded（无奖励），不发 ore_removed")

	# --- 水域格不可删除 ---
	grid.set_cell(Vector2i(3, 0), CellData.new(null, water))
	_check(not grid.can_remove_tile(Vector2i(3, 0)), "水域格不可删除")
	_check(not grid.try_remove_tile(Vector2i(3, 0)).is_ok(), "删除水域失败")

	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
