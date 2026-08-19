extends SceneTree

## 每格独立落矿验证：加载主场景，采样矿石数量随时间增长，且落矿时间错开（非整批同帧）。
## 运行：godot --headless --path . --script res://test/scripts/per_cell_spawn_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var gm := scene.get_node("World") as GameManager
	gm._save_manager.save_path = "user://test_per_cell_spawn.json"   # 不碰真实存档
	var sm := SaveManager.new()
	sm.save_path = gm._save_manager.save_path
	sm.clear_save()
	root.add_child(scene)
	await process_frame
	await process_frame

	var initial := gm.grid.ores.size()
	var free_count := 0
	for cell: Vector2i in gm.grid.cells.keys():
		if not gm.grid.ores.has(cell) and gm.grid.get_tile_at(cell) != null:
			free_count += 1
	print("初始: 矿 %d 空格 %d 间隔 %.1fs" % [initial, free_count, gm.spawn_interval])
	_check(free_count > 0, "存在空闲格子（实测 %d）" % free_count)
	_check(gm._cell_spawn_timers.size() > 0, "独立计时器表非空（%d 个）" % gm._cell_spawn_timers.size())

	# 解锁煤矿，让自然落矿池非空（否则 reset 后门控会阻止所有落矿）
	gm.state.record_talent_purchase(&"unlock_coal")
	gm._talent_system.invalidate()

	# 初始间隔都在 ±jitter 区间内（大体一致但有快慢差异，不再是 0.2~1.0× 的大散布）
	# 必须在采样前检查：采样后计时器已衰减/清零
	var lo := gm.spawn_interval * (1.0 - gm.spawn_interval_jitter)
	var hi := gm.spawn_interval * (1.0 + gm.spawn_interval_jitter)
	var in_range := true
	for t: float in gm._cell_spawn_timers.values():
		if t < lo - 0.2 or t > hi:   # 减 0.2s 容差：登记后已跑了几帧
			in_range = false
	_check(in_range, "初始落矿间隔都在 %.1f~%.1fs 区间内" % [lo, hi])

	# headless 下 delta 是真实时间（180 帧 ≈ 1 秒），2s 级间隔采不到落矿 →
	# 缩短间隔并清空计时器重新登记，验证落矿发生且错开
	gm.spawn_interval = 0.3
	gm._cell_spawn_timers.clear()
	await process_frame

	# 采样 3 秒（约 1.5 倍间隔）：矿应陆续增加，且不是同一帧齐刷刷出现
	var counts: Array[int] = []
	for i in range(180):   # 3s @60fps
		await process_frame
		counts.append(gm.grid.ores.size())
	_check(counts[-1] > initial, "3 秒后有新矿落下（%d → %d）" % [initial, counts[-1]])
	var change_frames := 0
	for i in range(1, counts.size()):
		if counts[i] != counts[i - 1]:
			change_frames += 1
	_check(change_frames >= 2, "落矿时间错开（%d 个不同帧落矿）" % change_frames)
	# 上限：不超过格子数
	_check(counts[-1] <= gm.grid.cells.size(), "不超过格子数上限（%d ≤ %d）" % [counts[-1], gm.grid.cells.size()])

	sm.clear_save()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)


func _finish() -> void:
	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
