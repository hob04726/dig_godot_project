extends SceneTree

## 挖矿进度条动效回归测试：验证切换目标/快速挖掘时进度条不会异常消失或卡住。
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

	var bar: Node2D = gm._mining_bar
	_check(bar != null, "GameManager 已创建进度条")
	if bar == null:
		_finish()
		return

	# --- 基本显示：更新进度条后应可见并放大到接近 1 ---
	gm._update_mining_bar(ore1)
	await process_frame
	_check(bar.visible, "更新进度条后可见")
	_check(bar.scale.x > 0.2, "更新后进度条已开始放大（scale=%.2f）" % bar.scale.x)
	# 等弹入动画完成
	await create_timer(0.25).timeout
	_check(bar.visible and is_equal_approx(bar.scale.x, 1.0), "弹入完成后 scale=1")

	# --- 切换目标：正在收起时切到新矿，不应消失 ---
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
		# 没有第二个矿，在 (0,1) 手动生成一个
		cell2 = Vector2i(0, 1)
		if gm.grid.has_cell(cell2) and not gm.grid.ores.has(cell2):
			var def := load("res://defs/ores/gold.tres") as OreDef
			gm.spawn_ore(cell2, def, 1)
			await process_frame
			ore2 = gm.grid.get_ore(cell2)
			if ore2 != null:
				ore2.has_landed = true

	if ore2 != null:
		gm._hide_mining_bar(ore1)   # 触发收起
		await process_frame
		gm._update_mining_bar(ore2) # 立刻切新矿（模拟快速挖掘/特效多时的切换）
		await process_frame
		_check(bar.visible, "收起过程中切新矿，进度条仍可见")
		# 等动画稳定
		await create_timer(0.25).timeout
		_check(bar.visible and is_equal_approx(bar.scale.x, 1.0), "切新矿后弹入完成 scale=1")
	else:
		push_warning("mining_bar_test: 无法找到或生成第二个矿，跳过切换目标测试")

	# --- 点空处/矿死亡：隐藏后重新显示新矿 ---
	gm._hide_mining_bar()
	await create_timer(0.25).timeout
	_check(not bar.visible, "隐藏后进度条不可见")
	gm._update_mining_bar(ore1)
	await process_frame
	_check(bar.visible, "重新显示进度条后可见")
	await create_timer(0.25).timeout
	_check(bar.visible and is_equal_approx(bar.scale.x, 1.0), "重新弹入完成 scale=1")

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
