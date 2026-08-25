extends SceneTree

## 计数器悬浮精确数值提示截图：把鼠标 warp 到金币面板上，应显示完整数字（白字黑描边）。
## 运行：godot --path . --script res://test/scripts/money_tooltip_capture.gd（非 headless，会闪窗）

func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var gm := main.get_node("World") as GameManager
	gm.state.coins = BigNumber.from_float(12345678.0)   # 给个能看出千分位的数值
	var panel := main.get_node("CanvasLayer/PanelContainer") as PanelContainer
	root.warp_mouse(panel.get_global_rect().get_center())   # 真实悬浮到计数器上
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("res://test/capture_money_tooltip.png")

	# 边界场景：超长数字 + 鼠标甩到面板内最右缘 → 数字（含描边）不能出屏幕
	gm.state.coins = BigNumber.from_float(987654321987654.0)
	root.warp_mouse(Vector2(panel.get_global_rect().end.x - 2.0, panel.get_global_rect().get_center().y))
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("res://test/capture_money_tooltip_edge.png")
	print("已保存 test/capture_money_tooltip.png / capture_money_tooltip_edge.png")
	quit()
