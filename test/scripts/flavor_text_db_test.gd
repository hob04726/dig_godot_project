extends SceneTree

## FlavorTextDb 最小单元测试：验证阶段划分、语句池过滤、按权重抽取。
## 运行：godot --headless --script res://test/scripts/flavor_text_db_test.gd

var _failures := 0


func _init() -> void:
	# --- 阶段判定 ---
	_check(FlavorTextDb.current_stage(BigNumber.zero()) == 0, "0 金币处于阶段 0")
	_check(FlavorTextDb.current_stage(BigNumber.from_string("9999")) == 0, "9999 金币仍处于阶段 0")
	_check(FlavorTextDb.current_stage(BigNumber.from_string("1e4")) == 1, "1e4 金币进入阶段 1")
	_check(FlavorTextDb.current_stage(BigNumber.from_string("1e8")) == 1, "1e8 金币仍处于阶段 1")
	_check(FlavorTextDb.current_stage(BigNumber.from_string("1e9")) == 2, "1e9 金币进入阶段 2")
	_check(FlavorTextDb.current_stage(BigNumber.from_string("1e14")) == 2, "1e14 金币仍处于阶段 2")
	_check(FlavorTextDb.current_stage(BigNumber.from_string("1e15")) == 3, "1e15 金币进入阶段 3")

	# --- 可用语句池：开局只有阶段 0 ---
	var stage0_pool := FlavorTextDb.get_available_lines(BigNumber.zero())
	_check(stage0_pool.size() == 5, "开局可用语句共 5 条")
	for e in stage0_pool:
		_check(e.stage == 0, "开局语句都属于阶段 0")

	# --- 可用语句池：阶段 1 包含阶段 0+1（其中一条需 lifetime ≥ 1e5）---
	var stage1_pool := FlavorTextDb.get_available_lines(BigNumber.from_string("1e4"))
	_check(stage1_pool.size() == 9, "阶段 1 解锁后（1e4）可用语句共 9 条")
	var has_stage1 := false
	for e in stage1_pool:
		_check(e.stage <= 1, "阶段 1 语句池只含阶段 0/1")
		if e.stage == 1:
			has_stage1 = true
	_check(has_stage1, "阶段 1 语句池确实包含阶段 1 语句")

	var stage1_full_pool := FlavorTextDb.get_available_lines(BigNumber.from_string("1e5"))
	_check(stage1_full_pool.size() == 10, "阶段 1 完全解锁后（1e5）可用语句共 10 条")

	# --- 按权重抽取：多次抽取不会空，且结果来自可用池 ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var rolled: Array[String] = []
	for i in 10:
		var text := FlavorTextDb.pick_line(rng, BigNumber.from_string("1e5"))
		_check(not text.is_empty(), "第 %d 次抽取非空" % i)
		var found := false
		for e in stage1_full_pool:
			if e.text == text:
				found = true
				break
		_check(found, "抽取结果属于当前可用池")
		rolled.append(text)

	# --- 高阶段解锁低阶段语句仍然可用 ---
	var stage3_pool := FlavorTextDb.get_available_lines(BigNumber.from_string("1e15"))
	_check(stage3_pool.size() == 20, "阶段 3 全部解锁后可用语句共 20 条")
	var has_stage0 := false
	for e in stage3_pool:
		if e.stage == 0:
			has_stage0 = true
			break
	_check(has_stage0, "终局阶段仍包含开局语句")

	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
