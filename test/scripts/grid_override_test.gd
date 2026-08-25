extends SceneTree

## 地块行为 override 测试：set_tile_overrides 后各读参生效，且不改共享 .tres
## 运行：godot --headless --script res://test/scripts/grid_override_test.gd

var _failures := 0


func _init() -> void:
	var dirt := load("res://defs/tiles/dirt.tres") as TileDef
	var grass := load("res://defs/tiles/grass.tres") as TileDef
	var water := load("res://defs/tiles/water.tres") as TileDef
	var fire := load("res://defs/tiles/fire.tres") as TileDef
	var rarity := load("res://defs/tiles/rarity.tres") as TileDef
	var gold := load("res://defs/ores/gold.tres") as OreDef

	var grid := GridModel.new()
	grid.set_cell(Vector2i.ZERO, CellData.new(null, dirt))
	grid.set_cell(Vector2i(0, 1), CellData.new(null, grass))
	grid.set_cell(Vector2i(0, 2), CellData.new(null, water))
	grid.set_cell(Vector2i(0, 3), CellData.new(null, fire))
	grid.set_cell(Vector2i(0, 4), CellData.new(null, rarity))

	var changed := {"n": 0}
	grid.overrides_changed.connect(func() -> void: changed["n"] += 1)
	grid.set_tile_overrides({
		&"grass": {&"damage_multiplier": 2.5},
		&"water": {&"sink_refund_ratio": 0.15},
		&"fire": {&"damage": 25.0},
		&"rarity": {&"min_rarity": 4.0},
	})
	_check(changed["n"] == 1, "overrides_changed 发一次")

	# grass：伤害倍率 override 生效；.tres 未被改写
	var ore := _make_ore(gold, Vector2i(0, 1))
	_check(grid.hit_damage(ore, 10) == 25, "grass override ×2.5 → 伤害 25")
	_check(grass.damage_multiplier == 1.5, "grass .tres 原值 1.5 未改写")

	# water：沉没返还 override
	var sink_ore := _make_ore(gold, Vector2i(0, 2))
	var sink := {"ratio": -1.0}
	grid.ore_removed.connect(func(_o: OreBlock, _c: Vector2i, r: float) -> void: sink["ratio"] = r)
	grid.try_spawn_ore(Vector2i(0, 2), sink_ore)
	grid.notify_ore_landed(sink_ore)
	_check(sink["ratio"] == 0.15, "water 沉没返还 override 0.15")
	_check(water.sink_refund_ratio == 0.1, "water .tres 默认 0.1 未改写")

	# fire：周期伤害 override
	var fire_ore := _make_ore(gold, Vector2i(0, 3))
	grid.try_spawn_ore(Vector2i(0, 3), fire_ore)
	fire_ore.has_landed = true
	var hp_before := fire_ore.hp
	grid.tick(fire.tick_interval)
	_check(fire_ore.hp == hp_before - 25, "fire 伤害 override 25/周期")
	_check(fire.damage == 10, "fire .tres 原伤害 10 未改写")

	# rarity：min_rarity override
	_check(grid.effective_min_rarity(Vector2i(0, 4)) == 4, "rarity override min_rarity 4")
	_check(rarity.min_rarity == 3, "rarity .tres 原值 3 未改写")

	# 未 override 的地块回落 .tres
	_check(grid.effective_value_multiplier(Vector2i.ZERO) == 1.0, "dirt 无 override 回落 1.0")

	print("=== grid_override_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _make_ore(def: OreDef, cell: Vector2i) -> OreBlock:
	var ore := OreBlock.new()
	ore.setup_ore(def, 1, cell)
	return ore


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
