extends SceneTree

## 实例化 main.tscn，检查金币面板尺寸、材质参数和 tween 属性路径是否生效。

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame

	var label := inst.get_node_or_null("CanvasLayer/PanelContainer/HBoxContainer/Money") as Control
	if label == null:
		print("Money label 找不到")
		quit()
		return
	var panel := label.get_parent().get_parent() as Control
	print("panel.size = ", panel.size)
	print("panel.get_global_rect() = ", panel.get_global_rect())

	var gm := inst.get_node_or_null("World")
	var mat = gm.get("money_fire_material")
	print("money_fire_material = ", mat)
	if mat != null:
		print("  image_details   = ", mat.get_shader_parameter("image_details"))
		print("  texture_details = ", mat.get_shader_parameter("texture_details"))
		print("  amount          = ", mat.get_shader_parameter("amount"))

	# 验证 tween 能否驱动 shader_parameter/amount（破纪录触发路径）
	var mat_node := inst.get_node("CanvasLayer/PanelContainer") as Control
	print("panel.material == gm.money_fire_material ? ", mat_node.material == mat)
	mat.set_shader_parameter("amount", 6.0)
	print("set_shader_parameter amount=6 -> ", mat.get_shader_parameter("amount"))
	var t := inst.create_tween()
	t.tween_property(mat, "shader_parameter/amount", 0.0, 0.1)
	await create_timer(0.15).timeout
	print("tween 后 amount = ", mat.get_shader_parameter("amount"))
	quit()
