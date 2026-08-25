extends SceneTree

## TNT 引信存档恢复测试：验证 _snapshot_tnt_fuses / _restore_tnt_fuse 往返正确。
## 运行：godot --headless --script res://test/scripts/tnt_save_test.gd

var _failures := 0


func _init() -> void:
	var gm := GameManager.new()
	gm.db.load_all()

	var dirt := gm.db.get_tile(&"dirt")
	var tnt_tile := gm.db.get_tile(&"tnt")
	var tnt_ore_def := gm.db.get_ore(&"tnt")

	# 准备两个格子：一个放 TNT 矿，一个放 TNT 地皮
	gm.grid.set_cell(Vector2i.ZERO, CellData.new(null, dirt))
	gm.grid.set_cell(Vector2i(1, 0), CellData.new(null, tnt_tile))

	var tnt_ore := OreBlock.new()
	tnt_ore.setup_ore(tnt_ore_def, 1, Vector2i.ZERO)
	tnt_ore.has_landed = true
	_check(gm.grid.try_spawn_ore(Vector2i.ZERO, tnt_ore).is_ok(), "生成 TNT 矿")

	# 模拟两个被点燃的引信
	gm._active_tnts.append({"kind": &"ore", "cell": Vector2i.ZERO, "time_left": 1.5, "ore": tnt_ore})
	gm._active_tnts.append({"kind": &"tile", "cell": Vector2i(1, 0), "time_left": 0.8, "ore": null})

	# 快照
	var fuses := gm._snapshot_tnt_fuses()
	_check(fuses.size() == 2, "快照包含 2 条引信")
	if fuses.size() == 2:
		_check(fuses[0]["kind"] == "ore" and fuses[0]["time_left"] == 1.5, "TNT 矿引信数据正确")
		_check(fuses[1]["kind"] == "tile" and fuses[1]["time_left"] == 0.8, "TNT 地皮引信数据正确")

	# 清空后恢复
	gm._active_tnts.clear()
	_check(gm._active_tnts.is_empty(), "已清空")
	for entry: Dictionary in fuses:
		gm._restore_tnt_fuse(entry)
	_check(gm._active_tnts.size() == 2, "恢复后 2 条引信")
	if gm._active_tnts.size() == 2:
		_check(gm._active_tnts[0]["kind"] == &"ore" and gm._active_tnts[0]["time_left"] == 1.5
			and is_instance_valid(gm._active_tnts[0]["ore"]), "TNT 矿引信恢复正确")
		_check(gm._active_tnts[1]["kind"] == &"tile" and gm._active_tnts[1]["time_left"] == 0.8
			and gm._active_tnts[1]["ore"] == null, "TNT 地皮引信恢复正确")

	# 异常条目：坐标不对 / 类型不对应，应跳过且不崩溃
	gm._restore_tnt_fuse({"kind": "ore", "x": 99, "y": 99, "time_left": 1.0})
	gm._restore_tnt_fuse({"kind": "tile", "x": 0, "y": 0, "time_left": 1.0})
	gm._restore_tnt_fuse({"kind": "unknown", "x": 0, "y": 0, "time_left": 1.0})
	_check(gm._active_tnts.size() == 2, "异常引信被跳过")

	print("=== tnt_save_test：失败 %d 处 ===" % _failures)
	gm._active_tnts.clear()
	gm.grid.ores.clear()
	tnt_ore.free()
	gm.free()
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
