class_name Prestige
extends RefCounted

## 升华点结算（Cookie Clicker / Heavenly Chips 式）：
##   总升华点 = floor(cbrt(全时间累计金币 / 基准)) —— 按累计推导，永不减少；
##   每次升华领取"新总数 − 已领取"的差值；
##   每点永久 +1% 金币获取 → 永久倍率 = 1 + 点数 × 1%
## 纯数学、无状态；状态归属 GameState。基准值调低会让前期升华更快。

const COINS_PER_POINT_BASE := 1_000_000   # 累计 1e6 金币 = 1 点
const PERCENT_PER_POINT := 0.01           # 每点 +1%


## 指定累计金币对应的"应有点数"（全时间口径，永不减少）
static func points_for(lifetime: BigNumber) -> BigNumber:
	return lifetime.div(BigNumber.from_int(COINS_PER_POINT_BASE)).cbrt().floor()


## 两次升华之间可获得的点数增量 = 新总数 - 旧总数
static func points_delta(lifetime_before: BigNumber, lifetime_after: BigNumber) -> BigNumber:
	return points_for(lifetime_after).sub(points_for(lifetime_before))


## 由点数计算永久金币倍率：1 + 点数 × 1%
static func multiplier_from_points(points: BigNumber) -> BigNumber:
	return points.mul(BigNumber.from_float(PERCENT_PER_POINT)).add(BigNumber.one())
