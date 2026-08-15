extends SceneTree

## BigNumber 大数类型测试（数据层，纯数学）
## 运行：godot --headless --script res://test/scripts/big_number_test.gd

var _failures := 0


func _init() -> void:
	# --- 归一化 ---
	_check(BigNumber.from_int(0).is_zero(), "0 是零")
	_check(BigNumber.from_int(750).mantissa == 7.5 and BigNumber.from_int(750).exponent == 2, "750 归一化 7.5e2")
	_check(BigNumber.from_float(0.5).mantissa == 5.0 and BigNumber.from_float(0.5).exponent == -1, "0.5 归一化 5e-1")
	_check(BigNumber.from_float(1000000.0).mantissa == 1.0 and BigNumber.from_float(1000000.0).exponent == 6, "1e6 归一化 1e6")

	# --- 加减乘除 ---
	_check(_bn("5").add(_bn("7")).eq(_bn("12")), "5+7=12")
	_check(_bn("10").sub(_bn("3")).eq(_bn("7")), "10-3=7")
	_check(_bn("3").sub(_bn("10")).eq(_bn("-7")), "3-10=-7")
	_check(_bn("1e20").add(_bn("1e20")).eq(_bn("2e20")), "1e20+1e20=2e20")
	_check(_bn("1e20").add(_bn("1")).eq(_bn("1e20")), "1e20+1 被吸收（指数差>15）")
	_check(_bn("2").mul(_bn("3")).eq(_bn("6")), "2×3=6")
	_check(_bn("1e10").mul(_bn("1e10")).eq(_bn("1e20")), "1e10×1e10=1e20")
	_check(_bn("6").div(_bn("3")).eq(_bn("2")), "6÷3=2")
	_check(_bn("1e20").div(_bn("1e10")).eq(_bn("1e10")), "1e20÷1e10=1e10")
	_check(is_equal_approx(_bn("1").div(_bn("3")).to_float(), 1.0 / 3.0), "1÷3≈0.333")

	# --- 比较（含 0 与小数） ---
	_check(_bn("1e20").gt(_bn("1e19")), "1e20 > 1e19")
	_check(_bn("0").lt(_bn("0.5")), "0 < 0.5")
	_check(_bn("-1").lt(_bn("1")), "-1 < 1")
	_check(_bn("0").eq(_bn("0")), "0 == 0")
	_check(_bn("-5").lt(_bn("-3")), "-5 < -3")
	_check(_bn("5").gt(_bn("-3")), "5 > -3")

	# --- 立方根 / 取整 ---
	_check(_bn("27").cbrt().eq(_bn("3")), "cbrt(27)=3")
	_check(_bn("8").cbrt().eq(_bn("2")), "cbrt(8)=2")
	_check(_bn("1e30").cbrt().eq(_bn("1e10")), "cbrt(1e30)=1e10")
	_check(BigNumber.from_float(3.7).floor().eq(_bn("3")), "floor(3.7)=3")
	_check(BigNumber.from_float(-0.5).floor().eq(_bn("-1")), "floor(-0.5)=-1")
	_check(BigNumber.from_float(0.5).floor().eq(_bn("0")), "floor(0.5)=0")
	_check(_bn("1e16").floor().eq(_bn("1e16")), "floor(1e16)=1e16")

	# --- 升华公式（Prestige 集成） ---
	_check(Prestige.points_for(_bn("1e6")).eq(_bn("1")), "1e6 → 1 点")
	_check(Prestige.points_for(_bn("1e9")).eq(_bn("10")), "1e9 → 10 点")
	_check(Prestige.points_for(_bn("1e12")).eq(_bn("100")), "1e12 → 100 点")
	_check(Prestige.multiplier_from_points(_bn("10")).eq(BigNumber.from_float(1.1)), "10 点 → 倍率 1.1")

	# --- 序列化 round-trip ---
	var round_trip_cases: Array[BigNumber] = [
		_bn("0"), _bn("750"), _bn("-1234"), _bn("123.456"), _bn("-0.5"),
		_bn("1e22"), _bn("3.75e+22"), _bn("1e40"), _bn("9.007199254740991e15"),
		_bn("1.25e300"), _bn("2"),
	]
	for value: BigNumber in round_trip_cases:
		_check(BigNumber.from_string(value.to_save_string()).eq(value), "round-trip: %s" % value.to_save_string())

	# --- 插值（金币跳数） ---
	_check(BigNumber.lerp(_bn("0"), _bn("10"), 0.5).eq(_bn("5")), "lerp(0,10,.5)=5")
	_check(BigNumber.lerp(_bn("1e20"), _bn("1e21"), 0.0).eq(_bn("1e20")), "lerp 端点 0")
	_check(BigNumber.lerp(_bn("1e20"), _bn("1e21"), 1.0).eq(_bn("1e21")), "lerp 端点 1")
	var mid := BigNumber.lerp(_bn("1e20"), _bn("1e21"), 0.5)
	_check(mid.gt(_bn("1e20")) and mid.lt(_bn("1e21")), "大数 lerp 在区间内")

	print("=== big_number_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _bn(s: String) -> BigNumber:
	return BigNumber.from_string(s)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
