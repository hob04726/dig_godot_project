extends SceneTree

## 描边 shader 验证：左边悬停中的煤矿（Block.set_hovered 挂材质），
## 右边模拟抽屉选中按钮（TextureRect + outline 材质，36px）。
## 运行：godot --path . --script res://test/scripts/outline_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var ore_scene := load("res://scenes/ore_block.tscn") as PackedScene
	var coal := load("res://defs/ores/coal.tres") as OreDef
	var ore := ore_scene.instantiate() as OreBlock
	ore.setup_from_def(coal, Vector2i.ZERO)
	ore.starts_falling = false
	ore.position = Vector2(300, 320)
	root.add_child(ore)
	await process_frame
	ore.set_hovered(true)   # 触发描边材质（+ float 状态）

	# 模拟抽屉按钮选中：36px TextureRect + outline 材质
	var dirt := load("res://defs/tiles/dirt.tres") as TileDef
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/outline.gdshader")
	mat.set_shader_parameter("thickness", 8.0)
	var tr := TextureRect.new()
	tr.texture = dirt.get_texture(0)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # 取消"最小尺寸=贴图尺寸"的钳制
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	var tex_size := tr.texture.get_size()
	tr.size = tex_size                                 # 贴图原始尺寸（让 shader 顶点外扩与 UV 补偿匹配）
	tr.scale = Vector2(36.0 / tex_size.x, 36.0 / tex_size.y)   # 再缩放到 36px
	tr.position = Vector2(500, 300)
	tr.material = mat
	root.add_child(tr)

	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_outline.png")
	print("已保存 res://test/capture_outline.png")
	quit()
