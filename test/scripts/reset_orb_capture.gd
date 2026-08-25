extends SceneTree

## 非 headless 运行，截取 reset orb 在 50% 水位时的视觉效果。
## 运行：godot --path . --script res://test/scripts/reset_orb_capture.gd

func _init() -> void:
	var packed := load("res://scenes/vfx/reset.tscn") as PackedScene
	var reset := packed.instantiate() as ResetVfx
	root.add_child(reset)
	
	reset.setup(BigNumber.from_int(500_000), BigNumber.from_int(500_000))
	reset._set_orb_height(0.5)
	
	await process_frame
	await process_frame
	await process_frame
	
	var img := root.get_texture().get_image()
	if img == null:
		push_error("截图失败")
		quit()
		return
	
	var path := "res://test/capture_reset_orb.png"
	var err := img.save_png(path)
	if err != OK:
		push_error("保存截图失败: %d" % err)
	else:
		print("已保存截图: ", path)
	
	quit()
