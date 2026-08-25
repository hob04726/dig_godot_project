extends SceneTree

## 验证“下一升华点所需金币”显示在重置·升华天赋节点的说明框里，而非左上角。
## 运行：godot --headless --path . --script res://test/scripts/talent_prestige_tooltip_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)


func _run() -> void:
	var scene := (load("res://scenes/talent.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame

	var grid := scene as TalentGrid
	_check(grid != null, "天赋场景已加载")
	if grid == null:
		_finish()
		return

	# 注入一个累计金币 12310 的状态
	var state := GameState.new()
	state.add_coins(BigNumber.from_int(12310))
	grid.setup_state(state)
	await process_frame

	# 左上角面板里不应再存在 NextAscension 标签
	var panel := grid.get_node_or_null("UI/PanelContainer/HBoxContainer") as HBoxContainer
	if panel != null:
		_check(panel.get_node_or_null("NextAscension") == null, "左上角已移除 NextAscension 标签")
	else:
		push_warning("talent_prestige_tooltip_test: 找不到左上角面板")

	# 找到重置·升华节点（按 id 查字典，TalentNode 没有按 id 命名）
	var reset_node: TalentNode = grid._nodes_by_id.get(&"talent_reset")
	_check(reset_node != null, "存在 talent_reset 节点")
	if reset_node == null:
		_finish()
		return

	var tooltip: String = grid._tooltip_text(reset_node)
	var expected := Prestige.coins_to_next_point(state.lifetime_coins).to_compact_string()
	var expected_points := Prestige.points_for(state.lifetime_coins).to_full_string()
	_check(tooltip.find("下一级还需") != -1, "说明框包含“下一级还需”")
	_check(tooltip.find(expected) != -1, "说明框显示正确的剩余金币 %s" % expected)
	_check(tooltip.find(expected_points) != -1, "说明框显示正确的当前升华点 %s" % expected_points)

	_finish()


func _finish() -> void:
	print("=== talent_prestige_tooltip_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
