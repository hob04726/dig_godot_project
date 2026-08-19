extends SceneTree

## DefDb.roll_ore 落矿池过滤测试
## 运行：godot --headless --script res://test/scripts/def_db_pool_test.gd

var _failures := 0


func _init() -> void:
	var db := DefDb.new()
	db.load_all()

	# 无 allowed_ore_ids 表示没有解锁任何矿石，不应抽到矿
	var any := db.roll_ore(1, _rng(1))
	_check(any == null, "无 allowed 时 roll_ore 返回 null")

	# allowed 过滤：只允许 coal → 恒 coal（种子无关）
	for s in 10:
		var ore := db.roll_ore(1, _rng(s), [&"coal"])
		_check(ore != null and ore.id == &"coal", "allowed=[coal] 恒抽 coal（种子 %d）" % s)

	# 空池（allowed 不含任何符合稀有度的矿）→ null
	var none := db.roll_ore(1, _rng(1), [&"不存在的矿"])
	_check(none == null, "allowed 不匹配 → null")

	# rarity 过滤与 allowed 叠加：coal 稀有度 1，min_rarity=4 时被排除
	var high := db.roll_ore(4, _rng(1), [&"coal"])
	_check(high == null, "min_rarity=4 时 coal 被排除 → null")

	print("=== def_db_pool_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
