extends SceneTree

## 天赋效果引擎测试（数据层，无渲染）
## 运行：godot --headless --script res://test/scripts/talent_system_test.gd

var _failures := 0


func _init() -> void:
	var db := TalentDb.new()
	db.load_all()
	var state := GameState.new()
	var ts := TalentSystem.new(state, db)

	# --- 开局默认解锁 dirt 矿；coal/dirt 地块仍需手动购买；水晶永远排除出自然落矿池 ---
	_check(not ts.has_unlocked_ore(&"coal"), "coal 开局未解锁（需手动购买）")
	_check(ts.has_unlocked_ore(&"dirt"), "dirt 开局默认解锁")
	_check(not ts.has_unlocked_tile(&"dirt"), "dirt 地块开局未解锁（需手动购买）")
	var natural := ts.get_natural_spawn_ores()
	_check(natural.has(&"dirt") and natural.size() == 1, "开局自然落矿池只含 dirt")
	state.record_talent_purchase(&"unlock_coal")
	state.record_talent_purchase(&"unlock_tile_dirt")
	ts.invalidate()
	natural = ts.get_natural_spawn_ores()
	_check(natural.has(&"coal") and natural.has(&"dirt"), "购买 unlock_coal 后自然落矿池含 coal/dirt")
	_check(not natural.has(&"crystal"), "自然落矿池排除水晶")
	state.record_talent_purchase(&"unlock_crystal")
	ts.invalidate()
	natural = ts.get_natural_spawn_ores()
	_check(not natural.has(&"crystal"), "解锁水晶后自然落矿池仍排除水晶")

	# --- 矿石价值倍率（连乘） ---
	state.record_talent_purchase(&"prod_coal_01")
	state.record_talent_purchase(&"prod_coal_02")
	state.record_talent_purchase(&"prod_coal_03")
	ts.invalidate()
	_check(_close(ts.get_ore_value_multiplier(&"coal"), 8.0), "coal 3 级 ×2 → 8")
	state.record_talent_purchase(&"gold_council")
	ts.invalidate()
	_check(_close(ts.get_ore_value_multiplier(&"gold"), 4.0), "gold_council → gold ×4")

	# --- 全局金币收益（加法 bucket） ---
	state.record_talent_purchase(&"coin_bonus")
	state.record_talent_purchase(&"coin_bonus_2")
	state.record_talent_purchase(&"coin_bonus_3")
	ts.invalidate()
	_check(_close(ts.get_global_coin_multiplier(), 1.3), "3 级金币收益 → 1.3")

	# --- 地块协同（per 10 块，最多 10 组） ---
	state.record_talent_purchase(&"terrain_dirt_1")
	state.record_talent_purchase(&"terrain_dirt_2")
	ts.invalidate()
	_check(_close(ts.get_terrain_synergy(&"coal", {&"dirt": 25}), 1.5), "25 块泥土 2 组 → 1+(0.1+0.15)×2=1.5")
	_check(_close(ts.get_terrain_synergy(&"iron", {&"dirt": 25}), 1.0), "协同不影响非目标矿")
	_check(_close(ts.get_terrain_synergy(&"coal", {&"dirt": 999}), 1.0 + 2.5), "协同最多 10 组封顶")

	# --- 地块行为 override（SET 取最大） ---
	state.record_talent_purchase(&"tile_up_grass_1")   # 2.0
	state.record_talent_purchase(&"tile_up_grass_2")   # 2.5
	state.record_talent_purchase(&"tile_up_water_3")   # 0.25
	ts.invalidate()
	var ov := ts.get_tile_behavior_overrides()
	_check(_close(float(ov[&"grass"][&"damage_multiplier"]), 2.5), "grass override 取最大 2.5")
	_check(_close(float(ov[&"water"][&"sink_refund_ratio"]), 0.25), "water 沉没返还 0.25")

	# --- 稿子 ---
	state.record_talent_purchase(&"pickaxe_root")
	state.record_talent_purchase(&"pickaxe_dmg_1")    # +5
	state.record_talent_purchase(&"pickaxe_crit_1")   # +2%
	state.record_talent_purchase(&"pickaxe_crit_2")   # +3%
	state.record_talent_purchase(&"pickaxe_critdmg")  # +0.5
	ts.invalidate()
	_check(ts.get_pickaxe_damage_flat() == 5, "稿子 flat +5")
	_check(_close(ts.get_pickaxe_crit_chance(), 0.05), "暴击率 5%")
	_check(_close(ts.get_pickaxe_crit_damage(), 0.5), "暴击加值 0.5")
	_check(ts.get_pickaxe_aoe_radius() == 0, "未买 AOE → 0")
	state.record_talent_purchase(&"pickaxe_aoe")
	ts.invalidate()
	_check(ts.get_pickaxe_aoe_radius() == 1, "AOE → 1")

	# --- 结算管线 ---
	var state0 := GameState.new()
	var ts0 := TalentSystem.new(state0, db)
	_check(ts0.compute_coin_gain(100, &"coal", {}, 1.0).to_int() == 100, "无天赋结算 = base")
	state0.add_coins(BigNumber.from_string("1e9"))
	state0.apply_ascension()
	_check(ts0.compute_coin_gain(100, &"coal", {}, 1.0).to_int() == 110, "10 升华点 → ×1.1")
	_check(ts0.compute_coin_gain(100, &"coal", {}, 0.1).to_int() == 11, "reward_ratio 0.1 → 11")

	# --- 挖矿伤害 ---
	var state2 := GameState.new()
	var ts2 := TalentSystem.new(state2, db)
	_check(ts2.compute_hit_damage(10, 1.0, _rng(1)) == 10, "无天赋伤害 10")
	state2.record_talent_purchase(&"pickaxe_dmg_1")
	state2.record_talent_purchase(&"pickaxe_dmg_2")
	ts2.invalidate()
	_check(ts2.compute_hit_damage(10, 1.0, _rng(1)) == 20, "flat +10 → 20（无暴击）")
	state2.record_talent_purchase(&"pickaxe_crit_1")
	state2.record_talent_purchase(&"pickaxe_crit_2")
	state2.record_talent_purchase(&"pickaxe_critdmg")
	ts2.invalidate()
	var crit_seed := _find_seed_under(ts2.get_pickaxe_crit_chance())
	var crit_dmg := ts2.compute_hit_damage(10, 1.0, _rng(crit_seed))
	_check(crit_dmg == 50, "暴击 (10+10)×2.5 → 50（实际 %d）" % crit_dmg)
	# 详情接口：视图据 crit 标记显示暴击特效
	var details := ts2.hit_damage_details(10, 1.0, _rng(crit_seed))
	_check(details["crit"] == true and details["damage"] == 50, "hit_damage_details 返回暴击标记")
	var normal_seed := _find_seed_over(ts2.get_pickaxe_crit_chance())
	var normal := ts2.hit_damage_details(10, 1.0, _rng(normal_seed))
	_check(normal["crit"] == false and normal["damage"] == 20, "hit_damage_details 非暴击标记")

	# --- 永久槽选择（按成本取顶 N） ---
	var state3 := GameState.new()
	var ts3 := TalentSystem.new(state3, db)
	state3.record_talent_purchase(&"prod_coal_01")   # 750
	state3.record_talent_purchase(&"coin_bonus")     # 500
	state3.record_talent_purchase(&"pickaxe_root")   # 1000
	ts3.invalidate()
	var keep := ts3.select_preserved_talents(2)
	_check(keep.size() == 2 and keep.has(&"pickaxe_root") and keep.has(&"prod_coal_01"),
		"保留成本最高 2 个")

	print("=== talent_system_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


## 找一个首个 randf() < chance 的种子（Godot RNG 确定性，用于强制暴击）
func _find_seed_under(chance: float) -> int:
	var rng := RandomNumberGenerator.new()
	for s in 5000:
		rng.seed = s
		if rng.randf() < chance:
			return s
	return 0


## 找一个首个 randf() >= chance 的种子（用于强制非暴击）
func _find_seed_over(chance: float) -> int:
	var rng := RandomNumberGenerator.new()
	for s in 5000:
		rng.seed = s
		if rng.randf() >= chance:
			return s
	return 0


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _close(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
