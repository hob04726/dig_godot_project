extends SceneTree

## 天赋界面金币面板悬浮态截图：悬浮 → 面板平滑放大（无描边）。
## 运行：godot --path . --script res://test/scripts/talent_money_hover_capture.gd（非 headless，会闪窗）

func _initialize() -> void:
	_run()


func _run() -> void:
	var talent := (load("res://scenes/talent.tscn") as PackedScene).instantiate()
	root.add_child(talent)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png("res://test/capture_talent_money_normal.png")
	var panel := talent.get_node("UI/PanelContainer") as PanelContainer
	panel.mouse_entered.emit()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("res://test/capture_talent_money_hover.png")
	print("已保存 test/capture_talent_money_normal.png / capture_talent_money_hover.png")
	quit()
