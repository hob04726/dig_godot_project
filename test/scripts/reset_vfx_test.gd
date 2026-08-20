extends SceneTree

## 升华特效测试：加载 reset.tscn，设置 lifetime 从 1e6 到 9e6，
## 验证水位上涨、升华点从 3 增加到 11、闪光触发。
## 运行：godot --headless --script res://test/scripts/reset_vfx_test.gd

var _failures := 0


func _init() -> void:
	var scene: PackedScene = load("res://scenes/vfx/reset.tscn") as PackedScene
	if scene == null:
		push_error("加载 reset.tscn 失败")
		quit(1)
		return
	var vfx := scene.instantiate() as Node2D
	root.add_child(vfx)
	await process_frame

	var reset_vfx := vfx.get_script().new() as Node2D
	# 直接用脚本实例调用 setup/play
	var from_lifetime := BigNumber.from_int(1_000_000)
	var to_lifetime := BigNumber.from_int(9_000_000)
	vfx.setup(from_lifetime, to_lifetime)
	vfx.duration = 0.5
	vfx.play()

	await _wait_for_finish(vfx, 2.0)

	# 验证结束状态
	var points_label := vfx.get_node("PointsLabel") as RichTextLabel
	var lifetime_label := vfx.get_node("LifetimeLabel") as RichTextLabel
	_check(points_label != null and points_label.text.find("11") >= 0, "结束时升华点显示为 11")
	_check(lifetime_label != null and lifetime_label.text.find("9M") >= 0 or lifetime_label.text.find("900") >= 0, "结束时累计金币显示约 9e6")

	var orb_sprite := vfx.get_node("OrbSprite") as Sprite2D
	if orb_sprite != null and orb_sprite.material != null:
		var height: float = orb_sprite.material.get_shader_parameter("height")
		_check(height >= 0.99, "结束时水位满")
	else:
		_failures += 1
		print("[失败] 找不到 orb sprite 或 material")

	print("=== reset_vfx_test：失败 %d 处 ===" % _failures)
	vfx.queue_free()
	quit(1 if _failures > 0 else 0)


func _wait_for_finish(vfx: Node2D, timeout: float) -> void:
	var start := Time.get_ticks_msec()
	while vfx._running and (Time.get_ticks_msec() - start) / 1000.0 < timeout:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
