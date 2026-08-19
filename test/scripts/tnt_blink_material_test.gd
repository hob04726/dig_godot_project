extends SceneTree

## TNT 引信闪烁材质自动刷新测试：不依赖鼠标悬停/受击，进入闪烁期后材质应立即生效。
## 运行：godot --headless --script res://test/scripts/tnt_blink_material_test.gd

var _failures := 0


func _init() -> void:
	var gm := GameManager.new()
	gm.db.load_all()

	var dirt := gm.db.get_tile(&"dirt")
	var tnt_ore_def := gm.db.get_ore(&"tnt")

	gm.grid.set_cell(Vector2i.ZERO, CellData.new(null, dirt))

	var ore_scene := load("res://scenes/ore_block.tscn") as PackedScene
	var tnt_ore := ore_scene.instantiate() as OreBlock
	tnt_ore.setup_ore(tnt_ore_def, 1, Vector2i.ZERO)
	tnt_ore.node_name = "tnt_blink_test"
	tnt_ore.starts_falling = false
	tnt_ore.has_landed = true
	root.add_child(tnt_ore)
	await process_frame   # 等 ore 的 _ready 跑完，@onready 变量生效

	_check(gm.grid.try_spawn_ore(Vector2i.ZERO, tnt_ore).is_ok(), "生成 TNT 矿")

	# 进入闪烁期：time_left 必须 <= TNT_BLINK_START
	gm._active_tnts.append({"kind": &"ore", "cell": Vector2i.ZERO, "time_left": 1.0, "ore": tnt_ore})

	# 模拟一帧，让 _update_active_tnts 给 TNT 挂上闪烁材质
	gm._update_active_tnts(0.016)

	var sprite := tnt_ore.get_node("Sprite2D") as Sprite2D
	var sprite_mat := sprite.material as ShaderMaterial
	_check(sprite_mat != null, "sprite.material 不为空")
	if sprite_mat != null:
		_check(sprite_mat.shader == load("res://scripts/shaders/tnt_blink.gdshader"), "sprite.material 是 tnt_blink shader")
		_check(sprite_mat.get_shader_parameter("intensity") != null, "intensity 参数已设置")

	print("=== tnt_blink_material_test：失败 %d 处 ===" % _failures)

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
