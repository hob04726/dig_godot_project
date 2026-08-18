extends SceneTree

## 金币火焰位置验证：强制 amount=6 截图，人工核对火焰不再从计数板下边缘冒出。
## 运行：godot --path . --script res://test/scripts/money_fire_capture.gd（非 headless，会闪窗）

func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var gm := main.get_node("World") as GameManager
	# 模拟底边 10 秒窗口收入 2e6 → 底边 2 档蓝火
	gm._record_income(BigNumber.from_float(2e6), &"bottom")
	await create_timer(0.15).timeout   # 燃起中段：火焰应只长到一半高
	root.get_texture().get_image().save_png("res://test/capture_money_fire.png")
	await create_timer(1.0).timeout    # 燃起完成：火焰长满
	root.get_texture().get_image().save_png("res://test/capture_money_fire_full.png")
	print("已保存 test/capture_money_fire.png / capture_money_fire_full.png")
	quit()
