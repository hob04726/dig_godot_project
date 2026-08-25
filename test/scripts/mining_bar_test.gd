extends SceneTree

## 挖矿进度条动效回归测试：验证每个受伤的矿石都有独立进度条，
## 切换目标、隐藏/重新显示时行为正确。
## 运行：godot --headless --path . --script res://test/scripts/mining_bar_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var gm := scene.get_node("World") as GameManager
	gm._save_manager.save_path = "user://test_mining_bar.json"
	var sm := SaveManager.new()
	sm.save_path = gm._save_manager.save_path
	sm.clear_save()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 解锁煤炭落矿池，等自然落矿后找一个已落地矿
	var ore1: OreBlock = null
	var cell1 := Vector2i.ZERO
	gm.state.record_talent_purchase(&"unlock_coal")
	gm._talent_system.invalidate()
	for i in range(180):   # 等最多 3 秒
		await process_frame
		for cell: Vector2i in gm.grid.cells.keys():
			var ore := gm.grid.get_ore(cell)
			if ore != null and ore.has_landed:
				ore1 = ore
				cell1 = cell
				break
		if ore1 != null:
			break
	_check(ore1 != null, "初始场景存在已落地矿")
	if ore1 == null:
		_finish()
		return

	# --- 基本显示：更新进度条后应可见并放大到接近 1 ---
	gm._update_mining_bar(ore1)
	var bar1: Node2D = gm._mining_bars.get(cell1) as Node2D
	_check(bar1 != null, "矿石 1 已创建进度条")
	if bar1 == null:
		_finish()
		return

	await process_frame
	_check(bar1.visible, "更新进度条后可见")
	_check(bar1.scale.x > 0.2, "更新后进度条已开始放大（scale=%.2f）" % bar1.scale.x)
	# 等弹入动画完成
	await create_timer(0.25).timeout
	_check(bar1.visible and is_equal_approx(bar1.scale.x, 1.0), "弹入完成后 scale=1")

	# --- 切换目标：给第二个矿也创建进度条，两者互不干扰 ---
	var ore2: OreBlock = null
	var cell2 := Vector2i.ZERO
	for cell: Vector2i in gm.grid.cells.keys():
		if cell == cell1:
			continue
		var ore := gm.grid.get_ore(cell)
		if ore != null and ore.has_landed:
			ore2 = ore
			cell2 = cell
			break

	if ore2 == null:
		# 没有第二个矿，在 (0, 1) 手动生成一个
		cell2 = Vector2i(0, 1)
		if gm.grid.has_cell(cell2) and not gm.grid.ores.has(cell2):
			var def := load("res://defs/ores/gold.tres") as OreDef
			gm.spawn_ore(cell2, def, 1)
			await process_frame
			ore2 = gm.grid.get_ore(cell2)
			if ore2 != null:
				ore2.change_state(ore2.idle_state)
				ore2.has_landed = true
				ore2.sprite.position = Vector2.ZERO

	if ore2 != null:
		gm._update_mining_bar(ore2)
		var bar2: Node2D = gm._mining_bars.get(cell2) as Node2D
		_check(bar2 != null and bar2 != bar1, "矿石 2 有独立进度条")
		await create_timer(0.25).timeout
		_check(bar1.visible and is_equal_approx(bar1.scale.x, 1.0), "切到新矿后矿石 1 进度条仍可见")
		_check(bar2.visible and is_equal_approx(bar2.scale.x, 1.0), "矿石 2 进度条弹入完成 scale=1")
	else:
		push_warning("mining_bar_test: 无法找到或生成第二个矿，跳过切换目标测试")

	# --- 隐藏指定矿的进度条，不影响另一个 ---
	gm._hide_mining_bar(cell1)
	await create_timer(0.25).timeout
	# 隐藏动画完成后旧 bar 已被释放，要重新从字典取
	bar1 = gm._mining_bars.get(cell1) as Node2D
	_check(bar1 == null or not bar1.visible, "隐藏后矿石 1 进度条不可见")
	gm._update_mining_bar(ore1)
	await process_frame
	bar1 = gm._mining_bars.get(cell1) as Node2D
	_check(bar1 != null and bar1.visible, "重新显示进度条后可见")
	await create_timer(0.25).timeout
	bar1 = gm._mining_bars.get(cell1) as Node2D
	_check(bar1 != null and bar1.visible and is_equal_approx(bar1.scale.x, 1.0), "重新弹入完成 scale=1")

	# --- 超时隐藏：超过 MINING_BAR_HIDE_DELAY 没再受伤，进度条自动收起 ---
	var delay := GameManager.MINING_BAR_HIDE_DELAY + 0.5
	await create_timer(delay).timeout
	# _process 每帧会检查并触发 pop_out，等动画完成
	await create_timer(0.2).timeout
	bar1 = gm._mining_bars.get(cell1) as Node2D
	_check(bar1 == null or not bar1.visible, "超时未受伤后进度条自动隐藏")

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
