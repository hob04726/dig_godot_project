extends SceneTree

## TalentDb CSV 加载测试（数据层）
## 运行：godot --headless --script res://test/scripts/talent_db_test.gd

var _failures := 0


func _init() -> void:
	var db := TalentDb.new()
	db.load_all()
	var normal := db.get_normal_defs()
	var ascension := db.get_ascension_defs()
	_check(normal.size() == 260, "普通天赋 260 条（实际 %d）" % normal.size())
	_check(ascension.size() == 11, "升华天赋 11 条（实际 %d）" % ascension.size())

	# 表头名映射：关键字段
	var reset := _find(normal, &"talent_reset")
	_check(reset != null and reset.currency == "金币" and reset.effect_type == "PRESTIGE_RESET"
		and reset.col == 0 and reset.row == 0, "talent_reset 字段映射")
	var coal10 := _find(normal, &"prod_coal_10")
	_check(coal10 != null and coal10.ascension_prerequisite_id == &"meta_endless_mining", "prod_coal_10 升华前置")
	_check(coal10 != null and coal10.cost.gt(BigNumber.from_string("1e22")), "prod_coal_10 成本是大数（>1e22）")
	_check(coal10 != null and coal10.cost.to_compact_string() != "", "大数成本可紧凑显示")

	# 多前置解析 + target_ids 内嵌逗号
	var grass := _find(normal, &"terrain_grass_1")
	_check(grass != null and grass.prerequisite_ids.size() == 2, "terrain_grass_1 双前置")
	var fire := _find(normal, &"terrain_fire_1")
	_check(fire != null and fire.target_ids.size() == 9, "terrain_fire_1 目标 9 矿（内嵌逗号解析）")

	# 升华表
	var legacy := _find(ascension, &"meta_legacy")
	_check(legacy != null and legacy.currency == "升华点" and legacy.cost.is_zero(), "meta_legacy 升华点 / 0 成本")
	var endless := _find(ascension, &"meta_endless_mining")
	_check(endless != null and endless.prerequisite_ids.has(&"meta_abyssal_mining"), "meta_endless 前置")

	# 引用完整性：所有前置/升华前置都在全集里
	var all_ids := {}
	for def in db.get_all_defs():
		all_ids[def.id] = true
	var broken := 0
	for def in db.get_all_defs():
		for pid in def.prerequisite_ids:
			if not all_ids.has(pid):
				broken += 1
		if def.ascension_prerequisite_id != &"" and not all_ids.has(def.ascension_prerequisite_id):
			broken += 1
	_check(broken == 0, "前置引用全部可解析（坏引用 %d）" % broken)

	# 名称映射跨树
	var names := db.get_name_map()
	_check(names.has(&"meta_deep_mining") and names.has(&"prod_coal_01"), "名称映射跨两棵树")

	print("=== talent_db_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _find(defs: Array[TalentDef], id: StringName) -> TalentDef:
	for def in defs:
		if def.id == id:
			return def
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
