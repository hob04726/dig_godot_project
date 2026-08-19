extends SceneTree

## 地块放置/卖出计价测试（纯静态）
## 运行：godot --headless --script res://test/scripts/tile_pricing_test.gd

var _failures := 0


func _init() -> void:
	var dirt := load("res://defs/tiles/dirt.tres") as TileDef
	var spawn := load("res://defs/tiles/spawn.tres") as TileDef
	_check(dirt.base_cost == 1, "dirt 基准价 1")
	_check(spawn.base_cost == 1000000, "spawn 基准价 1M")

	# 放置价序列：round(base × 1.15^n)
	var expect := [1, 1, 1, 2, 2, 2]
	for n in expect.size():
		var got := TilePricing.placement_cost(dirt, n).to_int()
		_check(got == expect[n], "dirt 第 %d 块价 %d（实际 %d）" % [n, expect[n], got])

	# 卖出返还 = round(25% × base × 1.15^(n-1))
	_check(TilePricing.refund_value(dirt, 5).to_int() == 0, "dirt 移除第 5 块返 0")
	_check(TilePricing.refund_value(dirt, 0).is_zero(), "0 块不返")
	_check(TilePricing.refund_value(spawn, 1).to_int() == 250000, "spawn 第 1 块返 250K")

	# 大 n 不溢出（BigNumber）
	var big := TilePricing.placement_cost(dirt, 200)
	_check(big.gt(BigNumber.from_int(1000000)), "dirt 200 块价 > 1M（大数不溢出）")

	# 起点价 = 基准价
	_check(TilePricing.placement_cost(spawn, 0).to_int() == 1000000, "spawn 起点价 1M")

	print("=== tile_pricing_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
