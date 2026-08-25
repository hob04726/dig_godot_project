extends SceneTree

## 天赋存档回归：购买记录必须跨"退出界面 → 重新打开"恢复为 PURCHASED，
## 且已购节点不可重复购买扣钱。用独立测试存档路径，不污染真实 user://save.json。
## 运行：godot --headless --path . --script res://test/scripts/talent_save_test.gd

var _failures := 0
const SAVE_PATH := "user://test_talent_save.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	# 准备：落一份含已购 pickaxe_root 的存档（模拟上次购买后的写盘）
	var sm := SaveManager.new()
	sm.save_path = SAVE_PATH
	sm.clear_save()
	var seed_state := GameState.new()
	seed_state.add_coins(BigNumber.from_int(100000))
	seed_state.record_talent_purchase(&"pickaxe_root")
	sm.save({"version": SaveManager.SAVE_VERSION, "state": seed_state.to_dict()})

	# 第一次打开天赋界面（独立模式：自己从存档读）
	var grid := (load("res://scenes/talent.tscn") as PackedScene).instantiate() as TalentGrid
	grid._save.save_path = SAVE_PATH
	root.add_child(grid)
	await process_frame
	await process_frame

	var root_node := grid._nodes_by_id[&"pickaxe_root"] as TalentNode
	_check(root_node.state == TalentNode.State.PURCHASED,
		"重进后已购天赋恢复 PURCHASED（实测 state=%d）" % root_node.state)

	# 已购节点再点：不扣钱、不重复记录
	var coins_before := grid._state.coins.to_float()
	grid._click(root_node)
	await process_frame
	_check(is_equal_approx(grid._state.coins.to_float(), coins_before), "重复点击已购天赋不扣钱")

	# 前置已购 → 子节点 pickaxe_dmg_1 揭示且可买
	var dmg := grid._nodes_by_id[&"pickaxe_dmg_1"] as TalentNode
	_check(dmg.visible, "前置已购 → pickaxe_dmg_1 已揭示")
	_check(dmg.state == TalentNode.State.AVAILABLE, "pickaxe_dmg_1 可购买（实测 state=%d）" % dmg.state)

	# 购买 → 等 _click 内的揭示延迟走完（_persist 在 await 之后）→ 验证落盘
	grid._click(dmg)
	await create_timer(TalentNode.REVEAL_DELAY + 0.3).timeout
	_check(dmg.state == TalentNode.State.PURCHASED, "购买 pickaxe_dmg_1 成功")
	var talents: Dictionary = sm.load().get("state", {}).get("talents", {})
	_check(talents.has("pickaxe_root") and talents.has("pickaxe_dmg_1"),
		"存档含两条购买记录（实测 %s）" % str(talents.keys()))

	# 关掉重开（模拟退出界面再进），新购天赋必须还是 PURCHASED
	grid.queue_free()
	await process_frame
	var grid2 := (load("res://scenes/talent.tscn") as PackedScene).instantiate() as TalentGrid
	grid2._save.save_path = SAVE_PATH
	root.add_child(grid2)
	await process_frame
	await process_frame
	_check((grid2._nodes_by_id[&"pickaxe_root"] as TalentNode).state == TalentNode.State.PURCHASED,
		"二次重进 pickaxe_root 仍 PURCHASED")
	_check((grid2._nodes_by_id[&"pickaxe_dmg_1"] as TalentNode).state == TalentNode.State.PURCHASED,
		"二次重进 pickaxe_dmg_1 仍 PURCHASED")

	grid2.queue_free()
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
