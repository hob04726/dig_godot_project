extends SceneTree

## 爆炸缩放成长曲线测试：base 0.2 起步，对数饱和成长渐近 0.55 封顶
## 运行：godot --headless --path . --script res://test/scripts/explosion_scale_test.gd

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, name: String) -> void:
	if ok:
		print("[通过] %s" % name)
	else:
		_fail += 1
		printerr("[失败] %s" % name)


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var gm := main.get_node("World") as GameManager

	var s0 := gm._explosion_scale(0)
	var s10 := gm._explosion_scale(10)
	var s100 := gm._explosion_scale(100)
	var s1e5 := gm._explosion_scale(100000)
	var s1e12 := gm._explosion_scale(1000000000000)
	_check(absf(s0 - 0.2) < 0.01, "0 伤害 → 基础 0.2")
	_check(s10 > s0 and s100 > s10 and s1e5 > s100, "缩放随伤害增大")
	# 对数饱和：100→1e5（3 个数量级）的增量 要大于 1e5→1e12（7 个数量级）的增量
	_check(s1e5 - s100 > s1e12 - s1e5, "成长速度随数量级递减")
	_check(s1e12 <= 0.55 + 0.01, "渐近 0.55 封顶")
	_check(s1e12 < 0.6, "超大伤害不会炸满屏")

	print("=== 结果：失败 %d 处 ===" % _fail)
	quit(1 if _fail > 0 else 0)
