extends SceneTree

## 矿值分档粒子贴图测试：>0 橙砖 / >10 深砖 / >100 灰砖 / >1e3 铜币 / >1e4 银币 / >1e7 金币
## 运行：godot --headless --path . --script res://test/scripts/coin_particle_tier_test.gd

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, name: String) -> void:
	if ok:
		print("[通过] %s" % name)
	else:
		_fail += 1
		printerr("[失败] %s" % name)


func _tex_name(t: Texture2D) -> String:
	return t.resource_path.get_file().get_basename()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var gm := main.get_node("World") as GameManager

	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(1.0))) == "brick_orange", "1 → 橙砖")
	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(10.0))) == "brick_orange", "10 → 橙砖（边界不含）")
	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(11.0))) == "brick_dark", "11 → 深砖")
	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(101.0))) == "brick_gray", "101 → 灰砖")
	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(1001.0))) == "coin_bronze", "1001 → 铜币")
	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(10001.0))) == "coin_silver", "10001 → 银币")
	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(1e7 + 1.0))) == "coin_gold", "1e7+1 → 金币")
	_check(_tex_name(gm._coin_particle_texture(BigNumber.from_float(1e7))) == "coin_silver", "1e7 → 银币（边界不含）")

	# 初速度倍率：饱和曲线，加成指数级递减
	var v1 := gm._coin_velocity_mul(BigNumber.from_float(1.0))
	var v3 := gm._coin_velocity_mul(BigNumber.from_float(1e3))
	var v7 := gm._coin_velocity_mul(BigNumber.from_float(1e7))
	var v20 := gm._coin_velocity_mul(BigNumber.from_float(1e20))
	_check(absf(v1 - 1.0) < 0.01, "速度倍率 1 → 1x")
	_check(v3 > v1 and v7 > v3, "速度倍率随矿值增大")
	# 指数级递减：1e3→1e7 的增量，要大于 1e7→1e20（13 个数量级）的增量
	_check(v7 - v3 > v20 - v7, "速度加成指数级递减")
	_check(v20 <= 1.6 + 0.001, "速度倍率渐近 1.6x 封顶")

	# 大小倍率：log10 线性封顶 3x
	_check(absf(gm._coin_size_mul(BigNumber.from_float(1.0)) - 1.0) < 0.01, "大小倍率 1 → 1x")
	_check(absf(gm._coin_size_mul(BigNumber.from_float(1e49)) - 3.0) < 0.01, "大小倍率封顶 3x")

	print("=== 结果：失败 %d 处 ===" % _fail)
	quit(1 if _fail > 0 else 0)
