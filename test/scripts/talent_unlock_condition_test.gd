extends SceneTree

## 验证 unlock_coal 的前置门控：必须先购买左边的 unlock_dirt。
## 运行：godot --headless --path . --script res://test/scripts/talent_unlock_condition_test.gd

var _failures := 0


func _init() -> void:
	var state := GameState.new()
	state.add_coins(BigNumber.from_int(100))   # 足够买 unlock_coal（50 金币）

	var scene: Node = load("res://scenes/talent.tscn").instantiate()
	var grid := _find_talent_grid(scene)
	if grid == null:
		_fail("找不到 TalentGrid")
		quit(1)
		return

	# 进程内注入 state，让 _ready 使用这个状态而不是从存档自载
	grid.setup_state(state)
	root.add_child(scene)
	for i in 3:
		await process_frame

	var coal_node := _find_node_by_id(grid, &"unlock_coal")
	if coal_node == null:
		_fail("找不到 unlock_coal 节点")
		quit(1)
		return

	# 未购买前置 unlock_dirt：煤炭节点应隐藏
	_check(not coal_node.visible,
		"未购买 unlock_dirt 时 unlock_coal 应隐藏")

	# 购买前置 unlock_dirt（0 金币），不需要挖泥土，煤矿节点应立即可买
	state.record_talent_purchase(&"unlock_dirt")
	grid.setup_state(state)
	for i in 3:
		await process_frame

	coal_node = _find_node_by_id(grid, &"unlock_coal")
	_check(coal_node != null and coal_node.visible,
		"购买 unlock_dirt 后 unlock_coal 应显示")
	if coal_node != null:
		_check(coal_node.state == TalentNode.State.AVAILABLE,
			"购买 unlock_dirt 后 unlock_coal 应为 AVAILABLE（无需挖土）")

	print("=== talent_unlock_condition_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _find_talent_grid(node: Node) -> Node:
	if node.get_script() != null and "talent_grid" in str(node.get_script().resource_path):
		return node
	for child in node.get_children():
		var found := _find_talent_grid(child)
		if found != null:
			return found
	return null


func _find_node_by_id(grid: Node, id: StringName) -> TalentNode:
	for child in grid.get_children():
		if child is TalentNode and child.talent_id == id:
			return child
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] %s" % message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	print("[失败] %s" % message)
