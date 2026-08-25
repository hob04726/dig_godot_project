extends SceneTree

## 天赋节点动效测试：新揭示弹跳（0 → 1.1 → 0.8）、买得起↔买不起平滑过渡、待机摇晃
## 运行：godot --headless --script res://test/scripts/talent_reveal_pop_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var node_scene := load("res://scenes/talent_node.tscn") as PackedScene
	var node := node_scene.instantiate() as TalentNode
	root.add_child(node)
	await process_frame   # 等 _ready 建好摇晃计时器

	node.set_state(TalentNode.State.LOCKED, false)
	_check(absf(node.scale.x - 0.7) < 0.001, "LOCKED 基础尺寸为 0.7（实测 %.3f）" % node.scale.x)
	_check(absf(node.modulate.a - 0.3) < 0.001, "LOCKED 透明度为 0.3（实测 %.2f）" % node.modulate.a)

	# --- 新揭示：just_revealed=true → 弹跳 0 → 1.1 → 0.8 ---
	node.set_state(TalentNode.State.AVAILABLE, true, true)
	_check(node.scale.x < 0.05, "弹跳从 scale 0 开始（实测 %.5f）" % node.scale.x)
	var max_scale := 0.0
	for i in range(40):   # 约 0.67s，覆盖 0.18s 冲到 1.1 + 0.14s 回落
		await process_frame
		max_scale = maxf(max_scale, node.scale.x)
	_check(max_scale > 1.0 and max_scale <= 1.11, "弹跳过冲到 1.1（实测峰值 %.3f）" % max_scale)
	_check(absf(node.scale.x - 0.8) < 0.02, "弹跳结束稳定在 0.8（实测 %.3f）" % node.scale.x)
	_check(absf(node.modulate.a - 0.6) < 0.02, "AVAILABLE 透明度为 0.6（实测 %.2f）" % node.modulate.a)

	# --- 买得起 → 买不起 → 买得起：平滑过渡，不缩到 0 ---
	node.set_state(TalentNode.State.LOCKED, true)
	for i in range(25):   # 0.25s 过渡播完
		await process_frame
	_check(absf(node.scale.x - 0.7) < 0.02, "回到 LOCKED 0.7（实测 %.3f）" % node.scale.x)
	node.set_state(TalentNode.State.AVAILABLE, true, false)   # 非新揭示 → 平滑
	var min_scale := 1.0
	for i in range(10):
		await process_frame
		min_scale = minf(min_scale, node.scale.x)
	_check(min_scale > 0.5, "平滑过渡不缩到 0（过程最小 %.3f）" % min_scale)
	await create_timer(0.4).timeout   # 按真实时间等过渡播完（headless 帧率≠真实时间）
	_check(absf(node.scale.x - 0.8) < 0.02, "平滑过渡到 0.8（实测 %.3f）" % node.scale.x)
	_check(absf(node.modulate.a - 0.6) < 0.02, "透明度平滑到 0.6（实测 %.2f）" % node.modulate.a)

	# --- 待机摇晃：AVAILABLE 计时器在跑，购买后停止并回正 ---
	_check(node._wiggle_timer != null and node._wiggle_timer.time_left > 0.0, "AVAILABLE 摇晃计时器运行中")
	node.set_state(TalentNode.State.PURCHASED, true)
	_check(node._wiggle_timer.is_stopped(), "PURCHASED 后摇晃停止")
	# 购买弹跳曲线：先下蹲到 0.75 以下，再爆发过冲到 1.3 以上，期间左右摇晃
	var squash_min := 1.0
	var burst_max := 0.0
	var wobble_max := 0.0
	for i in range(25):
		await process_frame
		squash_min = minf(squash_min, node.scale.x)
		burst_max = maxf(burst_max, node.scale.x)
		wobble_max = maxf(wobble_max, absf(node.rotation))
	_check(squash_min < 0.8, "购买弹跳先下蹲蓄力（实测谷底 %.3f）" % squash_min)
	_check(burst_max > 1.3, "购买弹跳爆发过冲到 1.4（实测峰值 %.3f）" % burst_max)
	_check(wobble_max > 0.1, "购买弹跳伴随左右摇晃（实测最大摆幅 %.3f）" % wobble_max)
	await create_timer(0.8).timeout   # 等弹性回稳播完
	_check(absf(node.scale.x - 1.0) < 0.02, "购买弹跳回稳到 1.0（实测 %.3f）" % node.scale.x)
	_check(absf(node.rotation) < 0.001, "摇晃结束旋转回正（实测 %.3f）" % node.rotation)
	_check(absf(node.modulate.r - 1.0) < 0.05, "提亮回落到 1.0（实测 %.2f）" % node.modulate.r)

	# --- 悬停放大不受影响 ---
	node.set_hovered(true)
	await create_timer(0.3).timeout
	_check(absf(node.scale.x - TalentNode.HOVER_SCALE) < 0.02, "悬停后放大到 %.2f" % TalentNode.HOVER_SCALE)

	# --- 新揭示但买不起（LOCKED）：也要弹跳出现，不能凭空显示 ---
	var locked_node := node_scene.instantiate() as TalentNode
	root.add_child(locked_node)
	await process_frame
	locked_node.set_state(TalentNode.State.LOCKED, true, true)   # just_revealed + LOCKED
	_check(locked_node.scale.x < 0.05, "LOCKED 揭示弹跳从 scale 0 开始（实测 %.5f）" % locked_node.scale.x)
	_check(locked_node.modulate.a < 0.05, "LOCKED 揭示透明度从 0 淡入（实测 %.2f）" % locked_node.modulate.a)
	var locked_max := 0.0
	for i in range(40):
		await process_frame
		locked_max = maxf(locked_max, locked_node.scale.x)
	_check(locked_max > 0.9 and locked_max <= 1.01, "LOCKED 揭示过冲到 1.0（实测峰值 %.3f）" % locked_max)
	await create_timer(0.4).timeout
	_check(absf(locked_node.scale.x - 0.7) < 0.02, "LOCKED 揭示结束稳定在 0.7（实测 %.3f）" % locked_node.scale.x)
	_check(absf(locked_node.modulate.a - 0.3) < 0.02, "LOCKED 揭示结束透明度 0.3（实测 %.2f）" % locked_node.modulate.a)
	locked_node.queue_free()

	# --- 重置·升华（PRESTIGE_RESET）节点不摇晃 ---
	var reset_node := node_scene.instantiate() as TalentNode
	root.add_child(reset_node)
	await process_frame
	reset_node.effect_type = "PRESTIGE_RESET"
	reset_node.set_state(TalentNode.State.AVAILABLE, false)
	_check(reset_node._wiggle_timer.is_stopped(), "重置·升华节点不启动摇晃")
	reset_node.queue_free()

	print("=== 结果：失败 %d 处 ===" % _failures)
	node.queue_free()
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
