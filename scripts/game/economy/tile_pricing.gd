class_name TilePricing
extends RefCounted

## 地块放置/卖出计价（纯静态、无状态，可无头测试）。
## Cookie Clicker 式：放置价 = round(base × 1.15^n)，n = 该地块已放置数（含初始免费块）；
## 卖出返还 = round(25% × base × 1.15^(n-1))，n = 移除前已放置数（近似"被移除那块"的买入价）。

const PRICE_GROWTH := 1.15
const SELL_RATIO := 0.25


## 放置第 n+1 块的价格（n = 已放置数）
static func placement_cost(tile: TileDef, placed_count: int) -> BigNumber:
	if tile == null or tile.base_cost <= 0:
		return BigNumber.zero()
	var price := float(tile.base_cost) * pow(PRICE_GROWTH, placed_count)
	return BigNumber.from_int(int(round(price)))


## 卖出返还：移除前已放置 n 块，返还被移除那块的 25% 买入价
static func refund_value(tile: TileDef, placed_count: int) -> BigNumber:
	if tile == null or tile.base_cost <= 0 or placed_count <= 0:
		return BigNumber.zero()
	# 移除前 n 块，第 n 块（最后一块）的买入价 = base × 1.15^(n-1)
	var price := float(tile.base_cost) * pow(PRICE_GROWTH, placed_count - 1)
	return BigNumber.from_int(int(round(price * SELL_RATIO)))
