extends SceneTree

## TNT 爆炸特效验证：在画面中央播放一次 TNT 爆炸并截图。
## 运行：godot --path . --script res://test/scripts/tnt_explosion_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var layer := Node2D.new()
	root.add_child(layer)

	var gm := GameManager.new()
	gm.above_grid_layer = layer
	gm._play_tnt_explosion(Vector2(576, 324), 50)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_tnt_explosion.png")
	print("已保存 res://test/capture_tnt_explosion.png")
	gm.free()
	layer.free()
	quit()
