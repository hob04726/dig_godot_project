extends SceneTree

## 方块状态机动画测试（Tween 驱动，无渲染）
## 运行：godot --headless --script res://test/scripts/block_animation_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var ore_scene := load("res://scenes/ore_block.tscn") as PackedScene
	var ore := ore_scene.instantiate() as OreBlock
	var grass := load("res://defs/tiles/grass.tres") as TileDef
	ore.setup_from_def(grass, Vector2i.ZERO)
	root.add_child(ore)

	_check(ore.current_state == ore.fall_state, "生成后从 Fall 开始")
	await create_timer(1.8).timeout
	_check(ore.current_state == ore.idle_state, "下落动画播完进入 Idle")
	_check(ore.has_landed, "落地后 has_landed = true")

	ore.hit()
	_check(ore.current_state == ore.shake_state, "受击进入 Shake")
	await create_timer(0.4).timeout
	_check(ore.current_state == ore.idle_state, "摇晃结束回到 Idle")

	ore.set_hovered(true)
	_check(ore.current_state == ore.float_state, "悬停进入 Float")
	await create_timer(0.2).timeout
	ore.set_hovered(false)
	_check(ore.current_state == ore.idle_state, "离开悬停回到 Idle")

	print("=== 结果：失败 %d 处 ===" % _failures)
	ore.queue_free()
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
