extends SceneTree
## 放置模式悬停行为验证：
## 1) 放置模式下悬停"有矿的格子"→ 地块被选中（描边）但不上浮，矿完全不响应
## 2) 悬停"空格子"→ 地块描边 + 上浮
## 3) 退出放置模式 → 矿恢复悬停响应
## 用法：godot --headless --path . --script res://test/scripts/placement_hover_test.gd

var _failures := 0


func _init() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var gm := scene.get_node("World") as GameManager
	print("tiles_by_cell 数量: %d, grid.ores: %d" % [gm.tiles_by_cell.size(), gm.grid.ores.size()])

	# 解锁 dirt 并进入放置模式
	gm._talent_system._unlocked_tiles[&"dirt"] = true
	gm.toggle_tile_selection(&"dirt")
	_check(gm.selected_tile != null, "已进入放置模式")

	# 自建测试场景（不依赖初始网格/存档内容）：(50,50) 地块+矿，(51,50) 空地块
	var dirt := gm.db.get_tile(&"dirt")
	var cell_with_ore := Vector2i(50, 50)
	var empty_cell := Vector2i(51, 50)
	for c in [cell_with_ore, empty_cell]:
		gm.grid.set_cell(c, CellData.new(null, dirt))
		gm.create_sprite(false, c, dirt)
	var ore := (load("res://scenes/ore_block.tscn") as PackedScene).instantiate() as OreBlock
	ore.setup_from_def(load("res://defs/ores/coal.tres") as OreDef, cell_with_ore)
	ore.starts_falling = false
	gm.above_grid_layer.add_child(ore)
	gm.grid.ores[cell_with_ore] = ore
	await process_frame

	# 直接把悬停格指到 (50,50)（headless 的 warp_mouse 不生效，走测试覆写口；
	# 注意：中间不能 await 帧——gm._process 会用真实鼠标位置刷掉覆写）
	gm.update_hover(cell_with_ore)
	print("悬停格: %s（期望 %s）" % [str(gm._hovered_cell), str(cell_with_ore)])

	var tile := gm.tiles_by_cell.get(cell_with_ore) as Block
	_check(gm._hovered_node == tile, "放置模式悬停有矿格 → 选中的是地块而非矿")
	_check(gm._hovered_allow_float == false, "有矿压着的地块不上浮")
	_check(tile != null and tile.sprite.material != null, "地块显示描边")
	_check(ore._hovered == false, "矿不响应悬停（无描边无上浮）")
	_check(tile.current_state != tile.float_state, "地块未进入漂浮状态")

	# 挪到没有矿的 (51,50)
	gm.update_hover(empty_cell)
	var empty_tile := gm.tiles_by_cell.get(empty_cell) as Block
	_check(gm._hovered_node == empty_tile and gm._hovered_allow_float, "空格子地块允许上浮")
	_check(empty_tile.current_state == empty_tile.float_state, "空格子地块进入漂浮状态")
	_check(tile.sprite.material == null, "挪走后原地块描边摘除")

	# 退出放置模式 → 矿恢复响应
	gm.clear_tile_selection()
	gm.update_hover(cell_with_ore)
	_check(gm._hovered_node == ore, "退出放置模式后矿恢复悬停响应")

	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
