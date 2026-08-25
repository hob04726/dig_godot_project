class_name TilePricing
extends RefCounted

## 地块放置/卖出计价（纯静态、无状态，可无头测试）。
## 统一成长曲线：第一块免费，第二块 = base_cost，随后数量级快速爬升，
## 第 6 块后增速放缓，避免 9 块后继续跳数量级。
##
## 价格公式（placed_count = 已放置数，求下一块价格）：
##   placed_count == 0          -> 0
##   placed_count in [1..4]     -> round(base_cost × 10^(placed_count-1))
##                                 即 1x, 10x, 100x, 1000x base_cost
##   placed_count == 5          -> round(base_cost × 10^6)
##   placed_count >= 6          -> round(base_cost × 10^(6 + (placed_count-5) × 0.3))
##
## 卖出返还 = floor(被移除那块买入价 × 25%)。

const SELL_RATIO := 0.25


## 放置第 n+1 块的价格（n = 已放置数）
static func placement_cost(tile: TileDef, placed_count: int) -> BigNumber:
	if tile == null or tile.base_cost <= 0:
		return BigNumber.zero()
	if placed_count == 0:
		return BigNumber.zero()

	var exponent := _growth_exponent(placed_count)
	var price := float(tile.base_cost) * pow(10.0, exponent)
	return BigNumber.from_float(price)


static func _growth_exponent(placed_count: int) -> float:
	if placed_count <= 1:
		return 0.0
	if placed_count <= 4:
		return placed_count - 1.0
	# 第 6 块起增速放缓：5->6, 6->6.3, 7->6.6, ...
	return 6.0 + (placed_count - 5) * 0.3


## 卖出返还：移除前已放置 n 块，返还被移除那块的 25% 买入价
static func refund_value(tile: TileDef, placed_count: int) -> BigNumber:
	if tile == null or placed_count <= 0:
		return BigNumber.zero()
	var buy_price := placement_cost(tile, placed_count - 1)
	return buy_price.mul(BigNumber.from_float(SELL_RATIO)).floor()
