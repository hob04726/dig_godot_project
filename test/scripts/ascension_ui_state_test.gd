extends SceneTree
## 模拟完整升华流程后，进入普通天赋树检查 unlock_tile_stone 节点状态。

var _failures := 0


func _init() -> void:
	var db := TalentDb.new()
	db.load_all()
	var state := GameState.new()
	state.record_talent_purchase(&"unlock_tile_stone")
	state.record_talent_purchase(&"unlock_tile_dirt")
	state.add_coins(BigNumber.from_string("1e9"))
	state.apply_ascension()

	# 保存到临时存档
	var save := SaveManager.new()
	save.save_path = "user://ascension_ui_test.json"
	save.save({"version": SaveManager.SAVE_VERSION, "state": state.to_dict(), "grid": {}})

	# 加载 talent.tscn
	var scene: PackedScene = load("res://scenes/talent.tscn") as PackedScene
	var talent := scene.instantiate() as Node2D
	# 注入 state
	talent.setup_state(state)
	root.add_child(talent)
	for i in 30:
		await process_frame

	# 查找 unlock_tile_stone 节点
	var grid := talent as Object
	var nodes: Array = grid.get("_nodes")
	var target: Node = null
	for node in nodes:
		if node.get("talent_id") == &"unlock_tile_stone":
			target = node
			break

	if target == null:
		_check(false, "找到 unlock_tile_stone 节点")
	else:
		_check(true, "找到 unlock_tile_stone 节点")
		var node_state: int = target.get("state")
		print("unlock_tile_stone 节点状态: ", node_state, " (LOCKED=0, AVAILABLE=1, PURCHASED=2)")
		_check(node_state == 0, "升华后普通天赋清空，节点显示为 LOCKED")

	# 检查 stone 是否不可放置
	var ts_after := TalentSystem.new(state, db)
	_check(not ts_after.has_unlocked_tile(&"stone"), "升华后 stone 不再可放置")

	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
