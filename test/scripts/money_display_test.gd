extends SceneTree

## 金币紧凑显示的边界测试。

const CASES: Array = [
	[0, "0"],
	[999, "999"],
	[1000, "1K"],
	[1234, "1.23K"],
	[9999, "10K"],
	[12_345, "12.3K"],
	[123_456, "123K"],
	[999_499, "999K"],
	[999_500, "1M"],
	[999_999, "1M"],
	[1_234_567, "1.23M"],
	[999_500_000, "1B"],
	[1_000_000_000_000, "1T"],
	[1_000_000_000_000_000, "1Qa"],
	[1_000_000_000_000_000_000, "1Qi"],
	[9_223_372_036_854_775_807, "9.22Qi"],
	[-1234, "-1.23K"],
]


func _init() -> void:
	var failures := 0
	for test_case: Array in CASES:
		var value: int = test_case[0]
		var expected: String = test_case[1]
		var actual := GameManager.format_compact_coins(BigNumber.from_int(value))
		if actual != expected:
			failures += 1
			push_error("format_compact_coins(%d): 期望 %s，实际 %s" % [value, expected, actual])
	if failures == 0:
		print("money_display_test: %d 项全部通过" % CASES.size())
	quit(failures)
