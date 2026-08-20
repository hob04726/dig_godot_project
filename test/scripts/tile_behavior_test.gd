extends SceneTree

## 地皮行为测试（数据层，无渲染）
## 运行：godot --headless --script res://test/scripts/tile_behavior_test.gd

var _failures := 0


func _init() -> void:
	var dirt := load("res://defs/tiles/dirt.tres") as TileDef
	var water := load("res://defs/tiles/water.tres") as TileDef
	var upgrade := load("res://defs/tiles/upgrade.tres") as TileDef
	var stone := load("res://defs/tiles/stone.tres") as TileDef
	var grass := load("res://defs/tiles/grass.tres") as TileDef
	var spawn := load("res://defs/tiles/spawn.tres") as TileDef
	var push := load("res://defs/tiles/push.tres") as TileDef
	var pull := load("res://defs/tiles/pull.tres") as TileDef
	var fire := load("res://defs/tiles/fire.tres") as TileDef
	var conveyor_ld := load("res://defs/tiles/conveyor_belt_leftdown.tres") as TileDef
	var conveyor_lu := load("res://defs/tiles/conveyor_belt_leftup.tres") as TileDef
	var conveyor_rd := load("res://defs/tiles/conveyor_belt_rightdown.tres") as TileDef
	var conveyor_ru := load("res://defs/tiles/conveyor_belt_rightup.tres") as TileDef
	var tnt_spawn := load("res://defs/tiles/tnt_spawn.tres") as TileDef
	var tnt_tile := load("res://defs/tiles/tnt.tres") as TileDef
	var gold := load("res://defs/ores/gold.tres") as OreDef
	var tnt_ore := load("res://defs/ores/tnt.tres") as OreDef

	# --- 定义行为已配置 ---
	_check(water.behavior == TileDef.Behavior.WATER, "water 行为配置")
	_check(spawn.behavior == TileDef.Behavior.SPAWN and spawn.spawn_ore_id == &"crystal", "spawn 行为配置")
	_check(pull.behavior == TileDef.Behavior.PULL, "pull 行为配置")
	_check(fire.behavior == TileDef.Behavior.FIRE, "fire 行为配置")
	_check(upgrade.behavior == TileDef.Behavior.UPGRADE, "upgrade 行为配置")
	_check(conveyor_ld.behavior == TileDef.Behavior.CONVEYOR_BELT_LEFTDOWN, "conveyor_leftdown 行为配置")
	_check(conveyor_ru.behavior == TileDef.Behavior.CONVEYOR_BELT_RIGHTUP, "conveyor_rightup 行为配置")
	_check(tnt_spawn.behavior == TileDef.Behavior.TNT_SPAWN and tnt_spawn.spawn_ore_id == &"tnt", "tnt_spawn 行为配置")
	_check(tnt_tile.behavior == TileDef.Behavior.TNT and tnt_tile.spawn_ore_id == &"tnt", "tnt 地皮行为配置")

	# --- 水：默认落地即沉没，不给金币 ---
	var grid := _base_grid(dirt)
	_set_tile(grid, Vector2i(0, 2), water)
	var sink_ore := _make_gold_ore(gold, Vector2i(0, 2))
	_check(grid.try_spawn_ore(Vector2i(0, 2), sink_ore).is_ok(), "水格能生成矿（落地才沉没）")
	var counts := {"discarded": 0, "rewarded": 0, "ratio": 1.0}
	grid.ore_discarded.connect(func(_o: OreBlock, _c: Vector2i) -> void: counts["discarded"] += 1)
	grid.ore_removed.connect(func(_o: OreBlock, _c: Vector2i, r: float) -> void:
		counts["rewarded"] += 1
		counts["ratio"] = r)
	grid.notify_ore_landed(sink_ore)
	_check(not grid.ores.has(Vector2i(0, 2)), "水格矿落地后沉没")
	_check(counts["rewarded"] == 0 and counts["discarded"] == 1, "默认沉没走 ore_discarded（不给金币）")

	# --- 水：解锁 sink refund 后按 10% 返还 ---
	grid = _base_grid(dirt)
	_set_tile(grid, Vector2i(0, 2), water)
	grid.water_sink_refund_ratio = 0.1
	var sink_ore2 := _make_gold_ore(gold, Vector2i(0, 2))
	grid.try_spawn_ore(Vector2i(0, 2), sink_ore2)
	counts = {"discarded": 0, "rewarded": 0, "ratio": 1.0}
	grid.ore_discarded.connect(func(_o: OreBlock, _c: Vector2i) -> void: counts["discarded"] += 1)
	grid.ore_removed.connect(func(_o: OreBlock, _c: Vector2i, r: float) -> void:
		counts["rewarded"] += 1
		counts["ratio"] = r)
	grid.notify_ore_landed(sink_ore2)
	_check(counts["rewarded"] == 1 and counts["discarded"] == 0, "解锁后沉没走 ore_removed（给金币）")
	_check(counts["ratio"] == 0.1, "水沉没只返还价值 10%")

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

	# --- grass 影响邻接格：邻接 dirt 上的矿也受伤害更高 ---
	grid = _base_grid(dirt)
	_set_tile(grid, Vector2i(0, 1), grass)
	var adjacent_grass_ore := _make_gold_ore(gold, Vector2i.ZERO)
	grid.try_spawn_ore(Vector2i.ZERO, adjacent_grass_ore)
	var base_dmg := grid.hit_damage(adjacent_grass_ore, 10)
	_check(base_dmg > 10, "草地影响邻接 dirt 格，矿受到伤害更高")

	# --- stone 影响邻接格：邻接 dirt 上的矿结算价值更高 ---
	grid = _base_grid(dirt)
	_set_tile(grid, Vector2i(0, 1), stone)
	var adjacent_stone_ore := _make_gold_ore(gold, Vector2i.ZERO)
	grid.try_spawn_ore(Vector2i.ZERO, adjacent_stone_ore)
	_check(grid.settle_value(adjacent_stone_ore) > adjacent_stone_ore.get_value(), "石头影响邻接 dirt 格，矿结算价值更高")

	# --- upgrade 影响邻接格：邻接 dirt 上的矿也被升级 ---
	grid = _base_grid(dirt)
	_set_tile(grid, Vector2i(0, 1), upgrade)
	var adjacent_up_ore := _make_gold_ore(gold, Vector2i.ZERO)
	grid.try_spawn_ore(Vector2i.ZERO, adjacent_up_ore)
	grid.tick(upgrade.tick_interval)
	_check(adjacent_up_ore.level == 2, "升级台影响邻接 dirt 格，矿升到 2 级")

	# --- spawn：自身及邻接空地块请求生成水晶，有矿时不发 ---
	grid = _base_grid(dirt)
	var spawn_cell := Vector2i(0, 1)
	_set_tile(grid, spawn_cell, spawn)
	var requests: Array = []
	grid.tile_request_spawn.connect(func(c: Vector2i, id: StringName) -> void: requests.append([c, id]))
	grid.tick(spawn.tick_interval)
	# (0,1) 自身 + (0,0) 邻接 dirt 共 2 格空着
	_check(requests.size() == 2, "spawn 空时请求自身及邻接格（共 2 个）")
	for r in requests:
		_check(r[1] == &"crystal", "spawn 请求矿石为 crystal")
	var spawn_ore := _make_gold_ore(gold, spawn_cell)
	grid.try_spawn_ore(spawn_cell, spawn_ore)
	requests.clear()
	grid.tick(spawn.tick_interval)
	_check(requests.size() == 1 and requests[0][0] == Vector2i(0, 0), "spawn 有矿时只请求剩余空邻接格")

	# --- push：把相邻矿向外推一格 ---
	grid = _base_grid(dirt)
	var push_cell := Vector2i(0, 1)
	_set_tile(grid, push_cell, push)
	_set_tile(grid, Vector2i(0, 2), dirt)
	_set_tile(grid, Vector2i(0, 3), dirt)
	var push_ore := _make_gold_ore(gold, Vector2i(0, 2))
	grid.try_spawn_ore(Vector2i(0, 2), push_ore)
	grid.tick(push.tick_interval)
	_check(not grid.ores.has(Vector2i(0, 2)) and grid.ores.has(Vector2i(0, 3)), "push 把相邻矿向外推一格")

	# --- push：目标被堵住时不推 ---
	grid = _base_grid(dirt)
	push_cell = Vector2i(0, 1)
	_set_tile(grid, push_cell, push)
	_set_tile(grid, Vector2i(0, 2), dirt)
	_set_tile(grid, Vector2i(0, 3), dirt)
	grid.try_spawn_ore(Vector2i(0, 3), _make_gold_ore(gold, Vector2i(0, 3)))
	var blocked_ore := _make_gold_ore(gold, Vector2i(0, 2))
	grid.try_spawn_ore(Vector2i(0, 2), blocked_ore)
	grid.tick(push.tick_interval)
	_check(grid.ores.has(Vector2i(0, 2)), "push 目标被堵住时不推")

	# --- push 推入水：相邻矿沉没 ---
	grid = _base_grid(dirt)
	push_cell = Vector2i(0, 1)
	_set_tile(grid, push_cell, push)
	_set_tile(grid, Vector2i(0, 2), dirt)
	_set_tile(grid, Vector2i(0, 3), water)
	var sink_push_ore := _make_gold_ore(gold, Vector2i(0, 2))
	grid.try_spawn_ore(Vector2i(0, 2), sink_push_ore)
	grid.tick(push.tick_interval)
	_check(not grid.ores.has(Vector2i(0, 2)), "push 把相邻矿推入水中沉没")

	# --- 定向传送带：按指定方向推动矿石 ---
	grid = _base_grid(dirt)
	var conv_cell := Vector2i(0, 1)
	_set_tile(grid, conv_cell, conveyor_ru)  # rightup = grid (0, -1)
	_set_tile(grid, Vector2i(0, 0), dirt)
	var conv_ore := _make_gold_ore(gold, conv_cell)
	grid.try_spawn_ore(conv_cell, conv_ore)
	grid.tick(conveyor_ru.tick_interval)
	_check(not grid.ores.has(conv_cell) and grid.ores.has(Vector2i(0, 0)), "定向传送带把矿推向右上")

	# --- 定向传送带：目标被堵住时不推 ---
	grid = _base_grid(dirt)
	conv_cell = Vector2i(0, 1)
	_set_tile(grid, conv_cell, conveyor_ru)
	grid.try_spawn_ore(Vector2i(0, 0), _make_gold_ore(gold, Vector2i(0, 0)))
	var blocked_conv_ore := _make_gold_ore(gold, conv_cell)
	grid.try_spawn_ore(conv_cell, blocked_conv_ore)
	grid.tick(conveyor_ru.tick_interval)
	_check(grid.ores.has(conv_cell), "目标被堵住时传送带不推")

	# --- tnt_spawn：自身及邻接空地块请求生成 TNT，有矿时只发剩余空邻接格 ---
	grid = _base_grid(dirt)
	var tnt_spawn_cell := Vector2i(0, 1)
	_set_tile(grid, tnt_spawn_cell, tnt_spawn)
	var tnt_requests: Array = []
	grid.tile_request_spawn.connect(func(c: Vector2i, id: StringName) -> void: tnt_requests.append([c, id]))
	grid.tick(tnt_spawn.tick_interval)
	_check(tnt_requests.size() == 2, "tnt_spawn 空时请求自身及邻接格（共 2 个）")
	for r in tnt_requests:
		_check(r[1] == &"tnt", "tnt_spawn 请求矿石为 tnt")
	var tnt_ore_inst := OreBlock.new()
	tnt_ore_inst.setup_ore(tnt_ore, 1, tnt_spawn_cell)
	tnt_ore_inst.has_landed = true
	grid.try_spawn_ore(tnt_spawn_cell, tnt_ore_inst)
	tnt_requests.clear()
	grid.tick(tnt_spawn.tick_interval)
	_check(tnt_requests.size() == 1 and tnt_requests[0][0] == Vector2i(0, 0), "tnt_spawn 有矿时只请求剩余空邻接格")

	# --- tnt 地皮：不会主动生成 TNT；只承载 TNT 矿 ---
	grid = _base_grid(dirt)
	var tnt_tile_cell := Vector2i(0, 1)
	_set_tile(grid, tnt_tile_cell, tnt_tile)
	var tnt_tile_requests: Array = []
	grid.tile_request_spawn.connect(func(c: Vector2i, id: StringName) -> void: tnt_tile_requests.append([c, id]))
	grid.tick(tnt_tile.tick_interval)
	_check(tnt_tile_requests.is_empty(), "tnt 地皮不主动生成 TNT")
	var tnt_on_tile := OreBlock.new()
	tnt_on_tile.setup_ore(tnt_ore, 1, tnt_tile_cell)
	tnt_on_tile.has_landed = true
	_check(grid.try_spawn_ore(tnt_tile_cell, tnt_on_tile).is_ok(), "TNT 地皮可承载 TNT 矿")
	var normal_ore := _make_gold_ore(gold, tnt_tile_cell)
	_check(not grid.try_spawn_ore(tnt_tile_cell, normal_ore).is_ok(), "TNT 地皮不能承载普通矿")

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
	grid.ore_removed.connect(func(_o: OreBlock, _c: Vector2i, _r: float) -> void: fire_counts["rewarded"] += 1)
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
