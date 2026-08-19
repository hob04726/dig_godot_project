extends SceneTree

## TNT 引信闪烁验证：左边 TNT 挂上闪烁 shader 并定格在高强度，右边正常对照。
## 运行：godot --path . --script res://test/scripts/tnt_blink_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var ore_scene := load("res://scenes/ore_block.tscn") as PackedScene
	var tnt_def := load("res://defs/ores/tnt.tres") as OreDef
	var shader := load("res://scripts/shaders/tnt_blink.gdshader") as Shader

	var blink_ore := ore_scene.instantiate() as OreBlock
	blink_ore.setup_from_def(tnt_def, Vector2i.ZERO)
	blink_ore.node_name = "tnt_blink"
	blink_ore.starts_falling = false
	blink_ore.position = Vector2(300, 320)
	root.add_child(blink_ore)

	var normal_ore := ore_scene.instantiate() as OreBlock
	normal_ore.setup_from_def(tnt_def, Vector2i(1, 0))
	normal_ore.node_name = "tnt_normal"
	normal_ore.starts_falling = false
	normal_ore.position = Vector2(500, 320)
	root.add_child(normal_ore)

	await process_frame
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("time", 2.5)
	mat.set_shader_parameter("intensity", 1.0)
	blink_ore.base_material = mat
	blink_ore._refresh_sprite_material()
	await process_frame
	await process_frame
	print("截图前: base_material=%s material=%s shader=%s" % [
		blink_ore.base_material != null,
		blink_ore.sprite.material != null,
		(blink_ore.sprite.material as ShaderMaterial).shader.resource_path])
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_tnt_blink.png")
	print("已保存 res://test/capture_tnt_blink.png")
	quit()
