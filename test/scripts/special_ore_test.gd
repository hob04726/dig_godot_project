extends SceneTree

## 特殊矿机制回归测试
## 运行：godot --headless --path . --script res://test/scripts/special_ore_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var gm := scene.get_node("World") as GameManager
	gm._save_manager.save_path = "user://test_special_ore.json"
	var sm := SaveManager.new()
	sm.save_path = gm._save_manager.save_path
	sm.clear_save()
	root.add_child(scene)
	for i in 5:
		await process_frame
	await create_timer(0.7).timeout

	gm.set_process(false)

	var dirt := gm.db.get_tile(&"dirt")
	var cell := Vector2i(50, 50)
	gm.grid.set_cell(cell, CellData.new(null, dirt))
	gm.create_sprite(false, cell, dirt)

	# --- 1. 价值 buff 矿 ---
	var coal := gm.db.get_ore(&"coal") as OreDef
	gm.spawn_ore(cell, coal, 1)
	var buff_ore := gm.grid.get_ore(cell)
	_prepare_ore(buff_ore)
	buff_ore.make_special(OreBlock.SpecialType.VALUE_BUFF)
	_check(buff_ore.special_type == OreBlock.SpecialType.VALUE_BUFF, "buff 矿标记正确")
	_check(state_value_buff(gm) <= 0.0, "挖掘前无全局 buff")

	# 把 buff 矿血量设为 1 方便一次挖掉，测试只关心触发 buff
	buff_ore.hp = 1
	gm._mine_at(cell)
	await process_frame
	_check(state_value_buff(gm) > 0.0, "挖掉 buff 矿后触发全局价值 buff")
	_check(not gm.grid.ores.has(cell), "buff 矿已被移除")

	# --- 2. 高价值坦克矿 ---
	cell = Vector2i(51, 50)
	gm.grid.set_cell(cell, CellData.new(null, dirt))
	gm.create_sprite(false, cell, dirt)
	var gold := gm.db.get_ore(&"gold") as OreDef
	gm.spawn_ore(cell, gold, 1)
	var tank_ore := gm.grid.get_ore(cell)
	_prepare_ore(tank_ore)
	var base_hp := tank_ore.get_def().get_max_hp(1)
	var base_value := tank_ore.get_def().get_value(1)
	tank_ore.make_special(OreBlock.SpecialType.HIGH_VALUE_TANK, 5.0, 3.0)
	_check(tank_ore.get_max_hp() == base_hp * 3, "坦克矿血量是基础 3 倍（%d vs %d）" % [tank_ore.get_max_hp(), base_hp * 3])
	_check(tank_ore.get_value() == base_value * 5, "坦克矿价值是基础 5 倍（%d vs %d）" % [tank_ore.get_value(), base_value * 5])

	# 把坦克矿血量设为 1 方便一次挖掉，测试只关心价值倍数
	tank_ore.hp = 1
	var coins_before := gm.state.coins.duplicate()
	gm._mine_at(cell)
	await process_frame
	_check(gm.state.coins.gt(coins_before), "坦克矿挖掉后金币增加")

	# --- 3. 一击即碎矿 ---
	cell = Vector2i(52, 50)
	gm.grid.set_cell(cell, CellData.new(null, dirt))
	gm.create_sprite(false, cell, dirt)
	var iron := gm.db.get_ore(&"iron") as OreDef
	gm.spawn_ore(cell, iron, 1)
	var fragile_ore := gm.grid.get_ore(cell)
	_prepare_ore(fragile_ore)
	fragile_ore.make_special(OreBlock.SpecialType.FRAGILE)
	_check(fragile_ore.hp == 1, "易碎矿血量为 1")
	gm._mine_at(cell)
	_check(not gm.grid.ores.has(cell), "易碎矿一锤即碎")

	sm.clear_save()
	_finish()


func state_value_buff(gm: GameManager) -> float:
	return gm.state.value_buff_time_left


func _prepare_ore(ore: OreBlock) -> void:
	ore.change_state(ore.idle_state)
	ore.has_landed = true
	ore.sprite.position = Vector2.ZERO
	await process_frame


func _finish() -> void:
	print("=== special_ore_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
