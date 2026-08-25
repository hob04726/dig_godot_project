extends SceneTree

## 受击闪色验证：左边矿 hit() 闪色（下一帧截图，仍在 0.08s 窗口内），右边正常对照。
## 运行：godot --path . --script res://test/scripts/hit_flash_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var ore_scene := load("res://scenes/ore_block.tscn") as PackedScene
	var coal := load("res://defs/ores/coal.tres") as OreDef

	var hit_ore := ore_scene.instantiate() as OreBlock
	hit_ore.setup_from_def(coal, Vector2i.ZERO)
	hit_ore.starts_falling = false
	hit_ore.position = Vector2(300, 320)
	root.add_child(hit_ore)

	var normal_ore := ore_scene.instantiate() as OreBlock
	normal_ore.setup_from_def(coal, Vector2i(1, 0))
	normal_ore.starts_falling = false
	normal_ore.position = Vector2(500, 320)
	root.add_child(normal_ore)

	await process_frame
	hit_ore.hit()
	hit_ore._flash_tween.kill()   # 冻结闪白状态，排除截图时序问题
	await process_frame
	await process_frame
	print("截图前: flash_on=%s material=%s active=%s shader=%s" % [
		hit_ore._flash_on, hit_ore.sprite.material != null,
		(hit_ore.sprite.material as ShaderMaterial).get_shader_parameter("active"),
		(hit_ore.sprite.material as ShaderMaterial).shader.resource_path])
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_hit_flash.png")
	print("已保存 res://test/capture_hit_flash.png")
	quit()
