extends SceneTree

## SaveManager + GridModel 快照/计数测试（数据层；不实例化场景）
## 运行：godot --headless --script res://test/scripts/save_test.gd

var _failures := 0


func _init() -> void:
	var save := SaveManager.new()
	save.save_path = "user://save_test.json"   # 独立路径，不碰真实存档
	save.clear_save()
	_check(not save.has_save(), "初始无存档")

	# --- 组装 payload：真实 state + 网格快照 ---
	var state := GameState.new()
	state.add_coins(BigNumber.from_string("1.25e22"))
	state.apply_ascension()   # 拿到大量升华点
	state.add_coins(BigNumber.from_int(777))
	state.increment_ore_mined(&"gold")
	_check(state.record_ascension_purchase(&"meta_legacy", 10) == true, "升华点充足可购买")
	state.record_talent_purchase(&"unlock_coal")   # 普通天赋也进存档

	var dirt := load("res://defs/tiles/dirt.tres") as TileDef
	var gold := load("res://defs/ores/gold.tres") as OreDef
	var grid := GridModel.new()
	grid.set_cell(Vector2i.ZERO, CellData.new(null, dirt))
	grid.set_cell(Vector2i(1, 0), CellData.new(null, dirt))
	var ore := OreBlock.new()
	ore.setup_ore(gold, 2, Vector2i(1, 0))
	ore.hp = 3
	ore.has_landed = true
	_check(grid.try_spawn_ore(Vector2i(1, 0), ore).is_ok(), "测试网格生成矿")
	_check(grid.get_placed_count(&"dirt") == 2, "placed 计数 2")
	_check(grid.get_placed_count(&"grass") == 0, "未放置类型计数 0")

	var payload := {
		"version": SaveManager.SAVE_VERSION,
		"state": state.to_dict(),
		"grid": {"cells": grid.snapshot_cells(), "ores": grid.snapshot_ores()},
	}
	save.save(payload)
	_check(save.has_save(), "写盘成功")

	# --- 读档 ---
	var loaded := save.load()
	_check(loaded.has("state") and loaded.has("grid"), "读档结构完整")
	var state2 := GameState.new()
	state2.load_from_dict(loaded["state"])
	_check(state2.coins.eq(BigNumber.from_int(777)), "读档金币一致")
	_check(state2.lifetime_coins.eq(state.lifetime_coins), "读档累计一致")
	_check(state2.ascension_points_earned.eq(state.ascension_points_earned), "读档已领取升华点一致")
	_check(state2.ascension_points_total().gt(BigNumber.zero()), "读档总点数按累计推导")
	_check(state2.get_ore_mined(&"gold") == 1, "读档 ore_mined 一致")
	_check(state2.has_ascension(&"meta_legacy"), "读档升华购买一致")
	_check(state2.has_talent(&"unlock_coal"), "读档普通天赋购买一致")
	var cells: Array = loaded["grid"]["cells"]
	_check(cells.size() == 2, "读档格子数一致")
	var ores: Array = loaded["grid"]["ores"]
	_check(ores.size() == 1, "读档矿石数一致")
	if ores.size() == 1:
		_check(ores[0]["ore"] == "gold" and ores[0]["level"] == 2 and ores[0]["hp"] == 3, "读档矿石数据一致")

	# --- 用快照重建网格（数据层）并核对 placed 计数 ---
	var grid2 := GridModel.new()
	for entry: Dictionary in cells:
		var tile := dirt if entry["below"] == "dirt" else null
		grid2.set_cell(Vector2i(int(entry["x"]), int(entry["y"])), CellData.new(null, tile))
	for entry: Dictionary in ores:
		var ore2 := OreBlock.new()
		ore2.setup_ore(gold, int(entry["level"]), Vector2i(int(entry["x"]), int(entry["y"])))
		ore2.hp = int(entry["hp"])
		grid2.try_spawn_ore(Vector2i(int(entry["x"]), int(entry["y"])), ore2)
	_check(grid2.get_placed_count(&"dirt") == 2, "重建后 placed 计数一致")
	_check(grid2.ores.size() == 1 and grid2.ores[Vector2i(1, 0)].hp == 3, "重建后矿石一致")

	# --- 损坏文件 → load 返回 {} ---
	var f := FileAccess.open(save.save_path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	_check(save.load().is_empty(), "损坏存档返回空")

	save.clear_save()
	# 清理损坏隔离文件（测试产物）
	if FileAccess.file_exists(save.save_path + ".corrupt"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save.save_path + ".corrupt"))
	_check(not save.has_save(), "清理存档")

	print("=== save_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
