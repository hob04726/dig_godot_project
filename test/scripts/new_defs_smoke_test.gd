extends SceneTree

## 临时冒烟测试：新增矿石/地块定义与天赋解锁链路。

var _failures := 0

func _initialize() -> void:
	_run()

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("[通过] ", msg)
	else:
		_failures += 1
		print("[失败] ", msg)

func _run() -> void:
	var defs := DefDb.new()
	defs.load_all()
	_check(defs.get_ore(&"stone") != null and defs.get_ore(&"stone").base_value == 5, "stone 矿定义加载")
	_check(defs.get_ore(&"emerald") != null and defs.get_ore(&"emerald").rarity == 2, "emerald 矿定义加载")
	for id in [&"stone", &"emerald", &"obsidian", &"diamond", &"cat"]:
		_check(defs.get_ore(id) != null and defs.get_ore(id).get_texture(0) != null, "%s 矿有贴图" % id)

	var db := TalentDb.new()
	db.load_all()
	var state := GameState.new()
	state.coins = BigNumber.from_float(1e12)
	var ts := TalentSystem.new(state, db, defs)

	# 矿解锁链：ore_coal → ore_stone
	_check(not ts.has_unlocked_ore(&"stone"), "初始未解锁 stone")
	state.record_talent_purchase(&"ore_coal")
	state.record_talent_purchase(&"ore_stone")
	ts.invalidate()
	_check(ts.has_unlocked_ore(&"stone"), "购买 ore_stone 后解锁 stone")
	state.record_talent_purchase(&"ore_stone")
	ts.invalidate()
	_check(ts.get_ore_value_multiplier(&"stone") == 2.0, "ore_stone L2 → 价值 ×2")

	# 地块解锁链：tile_conveyor → tile_pull → tile_rarity → tile_spawn → tile_tnt_spawn
	_check(not ts.has_unlocked_tile(&"pull"), "初始未解锁 pull")
	for id in [&"tile_conveyor", &"tile_pull", &"tile_rarity", &"tile_spawn", &"tile_tnt_spawn"]:
		state.record_talent_purchase(id)
	ts.invalidate()
	for tid in [&"push", &"pull", &"rarity", &"spawn", &"tnt_spawn"]:
		_check(ts.has_unlocked_tile(tid), "购买后解锁地块 %s" % tid)
	state.record_talent_purchase(&"tile_pull")
	ts.invalidate()
	var ov := ts.get_tile_behavior_overrides()
	_check(ov.has(&"pull"), "tile_pull L2 产生行为 override")

	# 图集图标：新增 9 条天赋都分到了图标（图集 6 列，细胞 27..35）
	for id in [&"ore_stone", &"ore_emerald", &"ore_obsidian", &"ore_diamond", &"ore_cat",
			&"tile_pull", &"tile_rarity", &"tile_spawn", &"tile_tnt_spawn"]:
		var d: TalentDef = null
		for x in db.get_normal_defs():
			if x.id == id:
				d = x
		_check(d != null and d.icon != null, "%s 分到图集图标" % id)

	print("=== 失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
