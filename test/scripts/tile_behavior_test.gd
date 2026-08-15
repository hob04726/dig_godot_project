extends SceneTree

## 地皮行为测试（数据层，无渲染）
## 运行：godot --headless --script res://test/scripts/tile_behavior_test.gd

var _failures := 0


func _init() -> void:
	var dirt := load("res://defs/tiles/dirt.tres") as TileDef
	var water := load("res://defs/tiles/water.tres") as TileDef
	var volcano := load("res://defs/tiles/volcano_stable.tres") as TileDef
	var upgrade := load("res://defs/tiles/upgrade.tres") as TileDef
	var stone := load("res://defs/tiles/stone.tres") as TileDef
	var grass := load("res://defs/tiles/grass.tres") as TileDef
	var spawn := load("res://defs/tiles/spawn.tres") as TileDef
	var push := load("res://defs/tiles/push.tres") as TileDef
	var pull := load("res://defs/tiles/pull.tres") as TileDef
	var fire := load("res://defs/tiles/fire.tres") as TileDef
	var gold := load("res://defs/ores/gold.tres") as OreDef

	# --- 定义行为已配置 ---
	_check(water.behavior == TileDef.Behavior.WATER, "water 行为配置")
	_check(volcano.behavior == TileDef.Behavior.VOLCANO, "volcano 行为配置")
	_check(spawn.behavior == TileDef.Behavior.SPAWN and spawn.spawn_ore_id == &"crystal", "spawn 行为配置")
	_check(pull.behavior == TileDef.Behavior.PULL, "pull 行为配置")
	_check(fire.behavior == TileDef.Behavior.FIRE, "fire 行为配置")
	_check(upgrade.behavior == TileDef.Behavior.UPGRADE, "upgrade 行为配置")

	# --- 水：落地即沉没，不给金币 ---
	var grid := _base_grid(dirt)
	_set_tile(grid, Vector2i(0, 2), water)
	var sink_ore := _make_gold_ore(gold, Vector2i(0, 2))
	_check(grid.try_spawn_ore(Vector2i(0, 2), sink_ore).is_ok(), "水格能生成矿（落地才沉没）")
	var counts := {"discarded": 0, "rewarded": 0}
	grid.ore_discarded.connect(func(_o: OreBlock, _c: Vector2i) -> void: counts["discarded"] += 1)
	grid.ore_removed.connect(func(_o: OreBlock, _c: Vector2i) -> void: counts["rewarded"] += 1)
	grid.notify_ore_landed(sink_ore)
	_check(not grid.ores.has(Vector2i(0, 2)), "水格矿落地后沉没")
	_check(counts["rewarded"] == 1 and counts["discarded"] == 0, "沉没走 ore_removed（给金币）")

	# --- 火山：不能承载矿 + 攻击四邻 ---
	grid = _base_grid(dirt)
	_set_tile(grid, Vector2i(0, 2), volcano)
	_check(not grid.try_spawn_ore(Vector2i(0, 2), _make_gold_ore(gold, Vector2i(0, 2))).is_ok(), "火山格不能生成矿")
	var neighbor := Vector2i(1, 2)
	_set_tile(grid, neighbor, dirt)
	var victim := _make_gold_ore(gold, neighbor)
	_check(grid.try_spawn_ore(neighbor, victim).is_ok(), "火山邻格生成矿")
	var before_hp := victim.hp
	grid.tick(volcano.tick_interval)
	_check(victim.hp < before_hp and grid.ores.has(neighbor), "火山对邻矿造成伤害且未打死")

	# --- 升级台：每几秒升一级 ---
	grid = _base_grid(dirt)
	var up_cell := Vector2i(0, 1)
	_set_tile(grid, up_cell, upgrade)
	var up_ore := _make_gold_ore(gold, up_cell)
	_check(grid.try_spawn_ore(up_cell, up_ore).is_ok(), "升级台生成矿")
	grid.tick(upgrade.tick_interval)
	_check(up_ore.level == 2, "升级台把矿升到 2 级")

	# --- stone：结算价值更高 ---
	grid = _base_grid(dirt)
	var stone_cell := Vector2i(0, 1)
	_set_tile(grid, stone_cell, stone)
	var stone_ore := _make_gold_ore(gold, stone_cell)
	grid.try_spawn_ore(stone_cell, stone_ore)
	_check(grid.settle_value(stone_ore) > stone_ore.get_value(), "石头格结算价值更高")

	# --- grass：受伤害更高 ---
	grid = _base_grid(dirt)
	var grass_cell := Vector2i(0, 1)
	_set_tile(grid, grass_cell, grass)
	var grass_ore := _make_gold_ore(gold, grass_cell)
	grid.try_spawn_ore(grass_cell, grass_ore)
	_check(grid.hit_damage(grass_ore, 10) > 10, "草地格矿受到伤害更高")

	# --- spawn：空时请求生成水晶，有矿时不发 ---
	grid = _base_grid(dirt)
	var spawn_cell := Vector2i(0, 1)
	_set_tile(grid, spawn_cell, spawn)
	var requests: Array = []
	grid.tile_request_spawn.connect(func(c: Vector2i, id: StringName) -> void: requests.append([c, id]))
	grid.tick(spawn.tick_interval)
	_check(requests.size() == 1 and requests[0][1] == &"crystal", "spawn 空时请求生成水晶")
	var spawn_ore := _make_gold_ore(gold, spawn_cell)
	grid.try_spawn_ore(spawn_cell, spawn_ore)
	requests.clear()
	grid.tick(spawn.tick_interval)
	_check(requests.is_empty(), "spawn 有矿时不再请求")

	# --- push：把上方矿推到邻居 ---
	grid = _base_grid(dirt)
	var push_cell := Vector2i(0, 1)
	_set_tile(grid, push_cell, push)
	var push_ore := _make_gold_ore(gold, push_cell)
	grid.try_spawn_ore(push_cell, push_ore)
	grid.tick(push.tick_interval)
	_check(not grid.ores.has(push_cell) and grid.ores.size() == 1, "传送带把矿推到相邻格")

	# --- push：四个方向都被矿堵住时不推 ---
	grid = _base_grid(dirt)
	push_cell = Vector2i(0, 1)
	_set_tile(grid, push_cell, push)
	_set_tile(grid, Vector2i(1, 1), dirt)
	_set_tile(grid, Vector2i(-1, 1), dirt)
	_set_tile(grid, Vector2i(0, 2), dirt)
	grid.try_spawn_ore(Vector2i(1, 1), _make_gold_ore(gold, Vector2i(1, 1)))
	grid.try_spawn_ore(Vector2i(-1, 1), _make_gold_ore(gold, Vector2i(-1, 1)))
	grid.try_spawn_ore(Vector2i(0, 2), _make_gold_ore(gold, Vector2i(0, 2)))
	grid.try_spawn_ore(Vector2i(0, 0), _make_gold_ore(gold, Vector2i(0, 0)))
	var blocked_ore := _make_gold_ore(gold, push_cell)
	grid.try_spawn_ore(push_cell, blocked_ore)
	grid.tick(push.tick_interval)
	_check(grid.ores.has(push_cell), "四邻都有矿时不推")

	# --- push 推入水：沉没消失 ---
	grid = _base_grid(dirt)
	push_cell = Vector2i(0, 1)
	_set_tile(grid, push_cell, push)
	_set_tile(grid, Vector2i(0, 2), water)
	grid.try_spawn_ore(Vector2i(0, 0), _make_gold_ore(gold, Vector2i(0, 0)))  # 堵住另一方向
	var sink_push_ore := _make_gold_ore(gold, push_cell)
	grid.try_spawn_ore(push_cell, sink_push_ore)
	grid.tick(push.tick_interval)
	_check(not grid.ores.has(push_cell), "传送带把矿推入水中沉没")

	# --- pull：把邻格矿吸到自己格 ---
	grid = _base_grid(dirt)
	var pull_cell := Vector2i(0, 1)
	_set_tile(grid, pull_cell, pull)
	var source_cell := Vector2i(1, 1)
	_set_tile(grid, source_cell, dirt)
	var pull_ore := _make_gold_ore(gold, source_cell)
	grid.try_spawn_ore(source_cell, pull_ore)
	grid.tick(pull.tick_interval)
	_check(grid.ores.has(pull_cell) and not grid.ores.has(source_cell), "磁吸把邻格矿吸过来")

	# --- fire：持续伤害，打死移除（给金币）---
	grid = _base_grid(dirt)
	var fire_cell := Vector2i(0, 1)
	_set_tile(grid, fire_cell, fire)
	var fire_counts := {"rewarded": 0}
	grid.ore_removed.connect(func(_o: OreBlock, _c: Vector2i) -> void: fire_counts["rewarded"] += 1)
	var fire_ore := _make_gold_ore(gold, fire_cell)
	grid.try_spawn_ore(fire_cell, fire_ore)
	var fire_before := fire_ore.hp
	grid.tick(fire.tick_interval)
	_check(fire_ore.hp < fire_before, "熔岩持续造成伤害")
	fire_ore.hp = 1
	grid.tick(fire.tick_interval)
	_check(not grid.ores.has(fire_cell), "熔岩把矿烧没")
	_check(fire_counts["rewarded"] == 1, "熔岩打死的矿走 ore_removed（给金币）")

	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _base_grid(dirt: TileDef) -> GridModel:
	var grid := GridModel.new()
	grid.set_cell(Vector2i.ZERO, CellData.new(null, dirt))
	return grid


func _set_tile(grid: GridModel, cell: Vector2i, tile: TileDef) -> void:
	grid.set_cell(cell, CellData.new(null, tile))


func _make_gold_ore(gold: OreDef, cell: Vector2i) -> OreBlock:
	var ore := OreBlock.new()
	ore.setup_ore(gold, 1, cell)
	ore.has_landed = true
	return ore


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
