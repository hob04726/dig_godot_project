extends SceneTree

## 旋转支点验证：左边矿不转（参照），右边矿应用 alpha 包围盒支点修正后转 60°。
## 修正正确 → 右边的矿石绕自身视觉中心转，矿石中心与左边参照在同一水平线上。
## 运行：godot --path . --script res://test/scripts/ore_pivot_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var scene := load("res://scenes/ore_block.tscn") as PackedScene
	var coal := load("res://defs/ores/coal.tres") as OreDef

	var ore1 := scene.instantiate() as OreBlock   # 参照：不转
	ore1.setup_from_def(coal, Vector2i.ZERO)
	ore1.starts_falling = false
	ore1.position = Vector2(400, 300)
	root.add_child(ore1)

	var ore2 := scene.instantiate() as OreBlock   # 支点修正 + 转 60°
	ore2.setup_from_def(coal, Vector2i.ZERO)
	ore2.starts_falling = false
	ore2.position = Vector2(700, 300)
	root.add_child(ore2)
	await process_frame

	# 复现 GameManager._center_ore_pivot 的逻辑
	var sprite := ore2.sprite
	var tex := sprite.texture
	var used := tex.get_image().get_used_rect()
	var vis := Vector2(used.get_center())
	var tex_center := tex.get_size() * 0.5
	sprite.offset = tex_center - vis
	ore2.position += (vis - tex_center) * sprite.scale
	sprite.rotation = deg_to_rad(60.0)
	print("贴图尺寸 ", tex.get_size(), "，内容包围盒 ", used, "，视觉中心 ", vis)

	# 两个节点原点画红十字标记
	for p in [Vector2(400, 300), Vector2(700, 300)]:
		var m := ColorRect.new()
		m.color = Color.RED
		m.size = Vector2(6, 6)
		m.position = p - Vector2(3, 3)
		root.add_child(m)

	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_pivot.png")
	print("已保存 res://test/capture_pivot.png")
	quit()
