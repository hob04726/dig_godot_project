extends SceneTree

## 主场景金币面板悬浮态截图：悬浮 → 平滑放大 + 白色描边。
## 运行：godot --path . --script res://test/scripts/money_hover_capture.gd（非 headless，会闪窗）

func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://test/capture_money_normal.png")
	var panel := main.get_node("CanvasLayer/PanelContainer") as PanelContainer
	panel.mouse_entered.emit()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("res://test/capture_money_hover.png")
	print("已保存 test/capture_money_normal.png / capture_money_hover.png")
	quit()
