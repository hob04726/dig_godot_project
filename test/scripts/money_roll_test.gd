extends SceneTree

## 金币数字持续滚动测试（_chase_money_display）。
## 显示值每帧指数追赶真实总额：持续收入时一直滚动、收入停了能在 ~2s 内吸附到精确值。

var _failures := 0


func _initialize() -> void:
	_run()
	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(_failures)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("[通过] %s" % name)
	else:
		_failures += 1
		print("[失败] %s %s" % [name, detail])


func _run() -> void:
	var gm := GameManager.new()   # 不入树，只测纯逻辑
	gm.money_label = RichTextLabel.new()
	gm.state.coins = BigNumber.from_int(1000)
	gm._displayed_coins = BigNumber.zero()

	# 单帧后显示值开始上涨
	gm._chase_money_display(0.1)
	_check("滚动开始（显示值 > 0）", gm._displayed_coins.gt(BigNumber.zero()),
		"实测 %s" % gm._displayed_coins.to_compact_string())
	_check("滚动中标记为 true", gm._money_rolling)

	# 模拟 3 秒（60 帧 × 0.05s）：应吸附到精确 1000
	for i in 60:
		gm._chase_money_display(0.05)
	_check("3 秒内吸附到精确值", gm._displayed_coins.eq(BigNumber.from_int(1000)),
		"实测 %s" % gm._displayed_coins.to_compact_string())

	# 吸附后再调用：不再滚动
	gm._chase_money_display(0.05)
	_check("追平后停止滚动", not gm._money_rolling)

	# 持续收入：滚动途中又来了 1000，应继续滚并最终到 2000
	gm.state.coins = BigNumber.from_int(1500)
	gm._chase_money_display(0.05)
	var mid := gm._displayed_coins.to_float()
	gm.state.coins = BigNumber.from_int(2000)
	gm._chase_money_display(0.05)
	_check("滚动途中追加收入继续上涨", gm._displayed_coins.to_float() > mid,
		"%.0f → %s" % [mid, gm._displayed_coins.to_compact_string()])
	for i in 60:
		gm._chase_money_display(0.05)
	_check("持续收入后仍能追平 2000", gm._displayed_coins.eq(BigNumber.from_int(2000)),
		"实测 %s" % gm._displayed_coins.to_compact_string())

	# 大数：e+20 也能滚动并追平（不溢出）
	gm.state.coins = BigNumber.from_float(1e20)
	gm._displayed_coins = BigNumber.from_float(5e19)
	for i in 120:
		gm._chase_money_display(0.05)
	_check("大数 e+20 追平", gm._displayed_coins.eq(BigNumber.from_float(1e20)),
		"实测 %s" % gm._displayed_coins.to_compact_string())

	gm.money_label.free()
	gm.free()
