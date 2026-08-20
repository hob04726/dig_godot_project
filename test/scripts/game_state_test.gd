extends SceneTree

## GameState 经济状态测试（数据层）
## 运行：godot --headless --script res://test/scripts/game_state_test.gd

var _failures := 0


func _init() -> void:
	var st := GameState.new()
	_check(st.coins.is_zero() and st.lifetime_coins.is_zero(), "初始金币 0")

	# --- 经济 ---
	st.add_coins(BigNumber.from_int(500))
	_check(st.coins.to_int() == 500 and st.lifetime_coins.to_int() == 500, "add_coins 同步 lifetime")
	_check(st.spend_coins(BigNumber.from_int(600)) == false and st.coins.to_int() == 500, "余额不足不扣款")
	_check(st.spend_coins(BigNumber.from_int(200)) == true and st.coins.to_int() == 300, "扣款成功")
	st.increment_ore_mined(&"coal")
	st.increment_ore_mined(&"coal")
	_check(st.get_ore_mined(&"coal") == 2, "ore_mined 计数")

	# --- 升华：总点数按累计推导，升华时领取差值（100→1, 10K→2, 1M→3, 之后每 1M→+1） ---
	st.add_coins(BigNumber.from_int(1_000_000))   # lifetime = 500 + 1e6 ≈ 1e6
	_check(st.ascension_points_total().to_int() == 3, "累计≈1e6 → 总点数 3")
	var gained := st.apply_ascension()
	_check(gained.to_int() == 3, "首次升华领取差值 3 点")
	_check(st.coins.is_zero(), "升华后金币清零")
	_check(st.permanent_multiplier().eq(BigNumber.from_float(1.03)), "已领取 3 点 → 声望倍率 1.03")
	_check(st.run_version == 1, "升华后 run_version = 1")
	_check(st.get_ore_mined(&"coal") == 0, "升华后 ore_mined 清零")

	# 继续赚到累计 2e6 → 总点数 4，第二次升华只领差值 1
	st.add_coins(BigNumber.from_int(1_000_000))
	_check(st.ascension_points_total().to_int() == 4, "累计 2e6 → 总点数 4")
	var gained2 := st.apply_ascension()
	_check(gained2.to_int() == 1, "第二次升华只领差值 1")
	_check(st.coins.is_zero(), "第二次升华后金币清零")

	# --- 下一升华点所需金币 ---
	var st6 := GameState.new()
	_check(Prestige.coins_to_next_point(st6.lifetime_coins).eq(BigNumber.from_int(100)), "0 累计时还需 100 到 1 点")
	st6.add_coins(BigNumber.from_int(50))
	_check(Prestige.coins_to_next_point(st6.lifetime_coins).eq(BigNumber.from_int(50)), "50 时还需 50")
	st6.add_coins(BigNumber.from_int(9_950))
	# 10K 时正好 2 点，下一点阈值 1M
	_check(Prestige.coins_to_next_point(st6.lifetime_coins).eq(BigNumber.from_int(990_000)), "10K 时还需 990K 到 3 点")
	st6.add_coins(BigNumber.from_int(990_000))
	# 1M 时正好 3 点，下一点阈值 2M
	_check(Prestige.coins_to_next_point(st6.lifetime_coins).eq(BigNumber.from_int(1_000_000)), "1M 时还需 1M 到 4 点")
	st6.add_coins(BigNumber.from_int(7_000_000))
	# 8M 时 10 点，下一点阈值 9M
	_check(Prestige.coins_to_next_point(st6.lifetime_coins).eq(BigNumber.from_int(1_000_000)), "8M 时还需 1M 到 11 点")

	# --- 升华点购买 ---
	_check(st.record_ascension_purchase(&"meta_legacy", 3) == true, "花 3 点买升华天赋")
	_check(st.ascension_points_available().to_int() == 1, "剩余可花 1 点")
	_check(st.record_ascension_purchase(&"meta_legacy", 0) == false, "重复购买失败")
	_check(st.record_ascension_purchase(&"meta_xxx", 9999) == false, "点数不足失败")

	# --- 普通天赋记录 ---
	st.record_talent_purchase(&"unlock_coal")
	_check(st.has_talent(&"unlock_coal"), "普通天赋已记录")
	_check(not st.has_talent(&"unlock_iron"), "未买天赋不存在")

	# --- 世界名 ---
	_check(st.world_name == "小世界", "默认世界名")
	st.set_world_name("黄金乡")
	_check(st.world_name == "黄金乡", "改名生效")
	var name_changed_count := {"v": 0}
	st.changed.connect(func() -> void: name_changed_count.v += 1)
	st.set_world_name("黄金乡")
	_check(name_changed_count.v == 0, "同名不改不触发 changed")
	st.set_world_name("水晶洞")
	_check(name_changed_count.v == 1, "改名触发 changed")

	# --- 序列化 round-trip ---
	st.add_coins(BigNumber.from_int(77))   # 升华后新一轮的金币，验证存档
	var dict := st.to_dict()
	var st2 := GameState.new()
	st2.load_from_dict(dict)
	_check(st2.coins.eq(st.coins), "存档金币一致")
	_check(st2.lifetime_coins.eq(st.lifetime_coins), "存档累计一致")
	_check(st2.ascension_points_earned.eq(st.ascension_points_earned), "存档已领取升华点一致")
	_check(st2.ascension_points_spent == st.ascension_points_spent, "存档已花升华点一致")
	_check(st2.ascension_points_total().eq(st.ascension_points_total()), "存档总点数按累计推导一致")
	_check(st2.run_version == st.run_version, "存档 run_version 一致")
	_check(st2.get_ore_mined(&"coal") == 0, "存档 ore_mined 一致（升华后已清空）")
	_check(st2.has_talent(&"unlock_coal"), "存档普通天赋一致")
	_check(st2.has_ascension(&"meta_legacy"), "存档升华天赋一致")
	_check(st2.world_name == "水晶洞", "存档世界名一致")

	# --- 升华后清空普通天赋 ---
	var st5 := GameState.new()
	st5.record_talent_purchase(&"prod_coal_01")
	st5.record_talent_purchase(&"coin_bonus")
	st5.add_coins(BigNumber.from_string("1e9"))
	st5.apply_ascension()
	_check(not st5.has_talent(&"coin_bonus"), "升华清空 coin_bonus")
	_check(not st5.has_talent(&"prod_coal_01"), "升华清空 prod_coal_01")
	_check(st5.run_version == 1, "升华后 run_version 自增")

	# --- 旧档缺 run_version 容错 ---
	var st4 := GameState.new()
	st4.load_from_dict({})
	_check(st4.run_version == 0, "旧档缺 run_version 容错为 0")

	# --- 容错：缺字段 ---
	var st3 := GameState.new()
	st3.load_from_dict({})
	_check(st3.coins.is_zero() and st3.ascension_points_spent == 0, "空存档容错")

	print("=== game_state_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
