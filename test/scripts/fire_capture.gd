extends SceneTree

## 用真实渲染器实例化 main.tscn，把 amount 拉满，截一张 PNG 看火焰实际长什么样。
## 运行：godot --path . --script res://test/scripts/fire_capture.gd（非 headless，会闪一个窗口）

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame   # 等 _ready + 布局

	var gm := inst.get_node("World")
	var mat = gm.get("money_fire_material")
	mat.set_shader_parameter("amount", 6.0)
	print("已把 amount 设为 6.0，等待几帧渲染…")
	await process_frame
	await process_frame
	await process_frame

	var img := root.get_texture().get_image()
	var out := "res://test/capture_amount6.png"
	img.save_png(out)
	print("已保存截图: ", out)
	quit()
