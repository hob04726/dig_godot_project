extends SceneTree

## 天赋 V4 实装回归测试：验证可升级节点、cost_mult 成本、新 effect_type、shader 挂载。

var _failures := 0

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)

func _run() -> void:
	var db := TalentDb.new()
	db.load_all()

	# --- 数据层 ---
	var pickaxe_dmg := _find(db.get_normal_defs(), &"pickaxe_dmg")
	_check(pickaxe_dmg != null, "pickaxe_dmg 节点存在")
	if pickaxe_dmg != null:
		_check(pickaxe_dmg.max_rank == 5, "pickaxe_dmg max_rank = 5")
		_check(pickaxe_dmg.cost_mult == 5, "pickaxe_dmg cost_mult = 5")
		_check(pickaxe_dmg.value == "2*level", "pickaxe_dmg value = '2*level'")

	var ore_coal := _find(db.get_normal_defs(), &"ore_coal")
	_check(ore_coal != null, "ore_coal 节点存在")
	if ore_coal != null:
		_check(ore_coal.max_rank == 5, "ore_coal max_rank = 5")
		_check(ore_coal.effect_type == "UNLOCK_ORE_VALUE_MULT", "ore_coal effect_type 正确")

	var tile_stone := _find(db.get_normal_defs(), &"tile_stone")
	_check(tile_stone != null, "tile_stone 节点存在")
	if tile_stone != null:
		_check(tile_stone.effect_type == "UNLOCK_TILE_BEHAVIOR", "tile_stone effect_type 正确")

	# --- GameState rank ---
	var state := GameState.new()
	state.coins = BigNumber.from_int(1000000)
	_check(state.get_talent_rank(&"pickaxe_dmg") == 0, "初始 rank = 0")
	var r1 := state.record_talent_purchase(&"pickaxe_dmg")
	_check(r1 == 1, "第一次购买后 rank = 1")
	var r2 := state.record_talent_purchase(&"pickaxe_dmg")
	_check(r2 == 2, "第二次购买后 rank = 2")
	_check(state.has_talent(&"pickaxe_dmg"), "has_talent 返回 true")

	# --- TalentSystem 数值计算 ---
	var ts := TalentSystem.new(state, db)
	ts.invalidate()
	var flat := ts.get_pickaxe_damage_flat()
	_check(flat == 4, "Lv.2 锋利提供 +4 伤害（2*level）")

	# ore_coal L3: 解锁 + ×4 价值
	state.record_talent_purchase(&"ore_coal")
	state.record_talent_purchase(&"ore_coal")
	state.record_talent_purchase(&"ore_coal")
	ts.invalidate()
	_check(ts.has_unlocked_ore(&"coal"), "ore_coal L3 解锁 coal")
	_check(ts.get_ore_value_multiplier(&"coal") == 4.0, "ore_coal L3 提供 ×4 价值")

	# --- 稿子范围 ---
	var pickaxe_range := _find(db.get_normal_defs(), &"pickaxe_range")
	_check(pickaxe_range != null, "pickaxe_range 节点存在")
	if pickaxe_range != null:
		_check(pickaxe_range.value == "2*level", "pickaxe_range value = '2*level'（像素）")
	state.record_talent_purchase(&"pickaxe_range")
	state.record_talent_purchase(&"pickaxe_range")
	ts.invalidate()
	_check(ts.get_pickaxe_aoe_radius() == 4, "Lv.2 稿子范围 +4 像素")

	# --- 特殊矿概率 ---
	var special_value_buff := _find(db.get_normal_defs(), &"special_value_buff")
	var special_high_value := _find(db.get_normal_defs(), &"special_high_value")
	var special_fragile := _find(db.get_normal_defs(), &"special_fragile")
	_check(special_value_buff != null, "special_value_buff 节点存在")
	_check(special_high_value != null, "special_high_value 节点存在")
	_check(special_fragile != null, "special_fragile 节点存在")
	_check(ts.get_special_value_buff_chance() == 0.0, "无天赋时彩虹矿概率为 0")
	state.record_talent_purchase(&"special_value_buff")
	state.record_talent_purchase(&"special_value_buff")
	state.record_talent_purchase(&"special_high_value")
	state.record_talent_purchase(&"special_high_value")
	state.record_talent_purchase(&"special_fragile")
	ts.invalidate()
	_check(ts.get_special_value_buff_chance() == 0.04, "Lv.2 彩虹矿概率 4%")
	_check(ts.get_special_high_value_chance() == 0.12, "Lv.2 富矿累计概率 4%+8%=12%")
	_check(ts.get_special_fragile_chance() == 0.19, "Lv.1 脆矿累计概率 4%+8%+7%=19%")

	# --- 存档兼容 ---
	var d := state.to_dict()
	_check(d["talents"].has("pickaxe_dmg"), "to_dict 包含 pickaxe_dmg")
	_check(d["talents"]["pickaxe_dmg"] == 2, "to_dict 保存 rank = 2")

	var state2 := GameState.new()
	state2.load_from_dict(d)
	_check(state2.get_talent_rank(&"pickaxe_dmg") == 2, "读档后 rank = 2")

	# 旧档 bool 兼容
	var old_save := {"talents": {"coin_bonus": true, "missing": false}}
	var state3 := GameState.new()
	state3.load_from_dict(old_save)
	_check(state3.get_talent_rank(&"coin_bonus") == 1, "旧档 true 转 rank 1")
	_check(state3.get_talent_rank(&"missing") == 0, "旧档 false 转 rank 0")

	_finish()

func _find(defs: Array[TalentDef], id: StringName) -> TalentDef:
	for def in defs:
		if def.id == id:
			return def
	return null

func _finish() -> void:
	print("=== talent_v4_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
