class_name Prestige
extends RefCounted

## 升华点与声望结算：
##   100  → 1 点
##   10K  → 2 点
##   1M   → 3 点
##   之后每 +1M → +1 点
## 按全时间累计金币推导，永不减少；每次升华领取"新总数 − 已领取"的差值。
## 每点升华点提供 +1% 金币获取 → 声望 = 1 + 点数 × 1%
## 纯数学、无状态；状态归属 GameState。

const THRESHOLD_1 := 100
const THRESHOLD_2 := 10_000
const THRESHOLD_3 := 1_000_000
const STEP_AFTER_3 := 1_000_000
const PERCENT_PER_POINT := 0.01           # 每点 +1%


## 指定累计金币对应的"应有点数"（全时间口径，永不减少）
static func points_for(lifetime: BigNumber) -> BigNumber:
	if lifetime.lt(BigNumber.from_int(THRESHOLD_1)):
		return BigNumber.zero()
	if lifetime.lt(BigNumber.from_int(THRESHOLD_2)):
		return BigNumber.one()
	if lifetime.lt(BigNumber.from_int(THRESHOLD_3)):
		return BigNumber.from_int(2)
	# 1M 之后每 1M 一点；大数用 float 计算避免 BigNumber 相邻大数相减丢精度
	var scaled := lifetime.to_float() / float(STEP_AFTER_3)
	var points := int(floorf(scaled)) + 2
	return BigNumber.from_int(points)


## 两次升华之间可获得的点数增量 = 新总数 - 旧总数
static func points_delta(lifetime_before: BigNumber, lifetime_after: BigNumber) -> BigNumber:
	return points_for(lifetime_after).sub(points_for(lifetime_before))


## 由点数计算声望倍率：1 + 点数 × 1%
static func multiplier_from_points(points: BigNumber) -> BigNumber:
	return points.mul(BigNumber.from_float(PERCENT_PER_POINT)).add(BigNumber.one())


## 给定升华点数对应的累计金币阈值（刚好到达该点数所需的最少金币）
static func threshold_for_points(points: BigNumber) -> BigNumber:
	if points.is_zero() or points.is_negative():
		return BigNumber.zero()
	if points.eq(BigNumber.one()):
		return BigNumber.from_int(THRESHOLD_1)
	if points.eq(BigNumber.from_int(2)):
		return BigNumber.from_int(THRESHOLD_2)
	if points.eq(BigNumber.from_int(3)):
		return BigNumber.from_int(THRESHOLD_3)
	# N >= 4: threshold = (N - 2) * 1M，用 BigNumber 乘法避免 float 大整数丢精度
	var multiplier := points.sub(BigNumber.from_int(2))
	return multiplier.mul(BigNumber.from_int(STEP_AFTER_3))


## 当前 lifetime 到下一升华点阈值的进度（0~1）
static func progress_to_next_point(lifetime: BigNumber) -> float:
	var current_points := points_for(lifetime)
	var current_threshold := threshold_for_points(current_points)
	var next_threshold := threshold_for_points(current_points.add(BigNumber.one()))
	var range := next_threshold.to_float() - current_threshold.to_float()
	if range <= 0.0:
		return 0.0
	var progress := (lifetime.to_float() - current_threshold.to_float()) / range
	return clampf(progress, 0.0, 1.0)


## 距离下一个升华点还需要多少累计金币。
static func coins_to_next_point(lifetime: BigNumber) -> BigNumber:
	var current_points := points_for(lifetime)
	var next_threshold := threshold_for_points(current_points.add(BigNumber.one()))
	# 大数相邻阈值相减会丢失精度，用 float 差值（剩余金额在 0~1M 之间，float 足够）
	var diff := next_threshold.to_float() - lifetime.to_float()
	if diff < 0.0:
		diff = 0.0
	return BigNumber.from_float(diff)
