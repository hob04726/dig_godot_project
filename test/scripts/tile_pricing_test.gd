extends SceneTree

## 地块放置/卖出计价测试（纯静态）
## 运行：godot --headless --script res://test/scripts/tile_pricing_test.gd

var _failures := 0


func _init() -> void:
	var dirt := load("res://defs/tiles/dirt.tres") as TileDef
	var spawn := load("res://defs/tiles/spawn.tres") as TileDef
	var grass := load("res://defs/tiles/grass.tres") as TileDef
	_check(dirt.base_cost == 1, "dirt 基准价 1")
	_check(spawn.base_cost == 1000000, "spawn 基准价 1M")
	_check(grass.base_cost == 10, "grass 基准价 10")

	# 泥土（base_cost=1）价格序列
	var dirt_expect := [0, 1, 10, 100, 1000, 1_000_000]
	for n in dirt_expect.size():
		var got := TilePricing.placement_cost(dirt, n).to_int()
		_check(got == dirt_expect[n], "dirt 已放 %d 块时下一块价 %d（实际 %d）" % [n, dirt_expect[n], got])

	# 第 6 块后增速放缓：dirt 6->~2M, 7->~4M
	var dirt_6 := TilePricing.placement_cost(dirt, 6).to_int()
	var dirt_7 := TilePricing.placement_cost(dirt, 7).to_int()
	_check(dirt_6 == 1_995_262, "dirt 已放 6 块时下一块价 ~2M（实际 %d）" % dirt_6)
	_check(dirt_7 > 3_900_000 and dirt_7 < 4_100_000, "dirt 已放 7 块时下一块价 ~4M（实际 %d）" % dirt_7)

	# 通用曲线也作用于其他地块（grass base_cost=10）
	_check(TilePricing.placement_cost(grass, 0).to_int() == 0, "grass 第 1 块免费")
	_check(TilePricing.placement_cost(grass, 1).to_int() == 10, "grass 第 2 块 10")
	_check(TilePricing.placement_cost(grass, 2).to_int() == 100, "grass 第 3 块 100")
	_check(TilePricing.placement_cost(grass, 5).to_int() == 10_000_000, "grass 第 6 块 10M")

	# spawn（base_cost=1M）第 6 块 = 1M × 10^6 = 1T
	var spawn_5 := TilePricing.placement_cost(spawn, 5)
	_check(spawn_5.eq(BigNumber.from_string("1e12")), "spawn 第 6 块 1T")

	# 卖出返还 = 被移除那块买入价的 25%
	_check(TilePricing.refund_value(dirt, 1).to_int() == 0, "dirt 移除第 1 块返 0")
	_check(TilePricing.refund_value(dirt, 2).to_int() == 0, "dirt 移除第 2 块返 0（1×25% floor）")
	_check(TilePricing.refund_value(dirt, 3).to_int() == 2, "dirt 移除第 3 块返 2（10×25% floor）")
	_check(TilePricing.refund_value(dirt, 6).to_int() == 250_000, "dirt 移除第 6 块返 250K")
	_check(TilePricing.refund_value(dirt, 0).is_zero(), "0 块不返")
	_check(TilePricing.refund_value(spawn, 2).to_int() == 250_000, "spawn 第 2 块返 250K")

	# 大 n 不溢出（BigNumber）
	var big := TilePricing.placement_cost(dirt, 200)
	_check(big.gt(BigNumber.from_int(1000000)), "dirt 200 块价 > 1M（大数不溢出）")

	print("=== tile_pricing_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)
