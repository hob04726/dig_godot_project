class_name Prestige
extends RefCounted

## 升华点与声望结算（Cookie Clicker / Heavenly Chips 式）：
##   总升华点 = floor(cbrt(全时间累计金币 / 基准)) —— 按累计推导，永不减少；
##   每次升华领取"新总数 − 已领取"的差值；
##   每点升华点提供 +1% 金币获取 → 声望 = 1 + 点数 × 1%
## 纯数学、无状态；状态归属 GameState。基准值调低会让前期升华更快。

const COINS_PER_POINT_BASE := 1_000_000   # 累计 1e6 金币 = 1 点
const PERCENT_PER_POINT := 0.01           # 每点 +1%


## 指定累计金币对应的"应有点数"（全时间口径，永不减少）
static func points_for(lifetime: BigNumber) -> BigNumber:
	return lifetime.div(BigNumber.from_int(COINS_PER_POINT_BASE)).cbrt().floor()


## 两次升华之间可获得的点数增量 = 新总数 - 旧总数
static func points_delta(lifetime_before: BigNumber, lifetime_after: BigNumber) -> BigNumber:
	return points_for(lifetime_after).sub(points_for(lifetime_before))


## 由点数计算声望倍率：1 + 点数 × 1%
static func multiplier_from_points(points: BigNumber) -> BigNumber:
	return points.mul(BigNumber.from_float(PERCENT_PER_POINT)).add(BigNumber.one())


## 距离下一个升华点还需要多少累计金币。
## 公式：当前总点数 = floor(cbrt(lifetime / 1e6))，下一点阈值 = (当前总点数 + 1)^3 * 1e6。
static func coins_to_next_point(lifetime: BigNumber) -> BigNumber:
	var current_points := points_for(lifetime)
	var next_points := current_points.add(BigNumber.one())
	var threshold := next_points.mul(next_points).mul(next_points).mul(BigNumber.from_int(COINS_PER_POINT_BASE))
	var remaining := threshold.sub(lifetime)
	if remaining.is_negative():
		remaining = BigNumber.zero()
	return remaining
