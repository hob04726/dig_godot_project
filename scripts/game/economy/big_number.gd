class_name BigNumber
extends RefCounted

## 大数经济类型：尾数(mantissa) + 指数(exponent)，仿 break_infinity.js（Cookie Clicker 用的经济库）。
## 可表示 ±1e308（double 上限），约 15 位有效数字精度——对 idle 游戏足够。
## 注意：这不是任意精度整数。小于 2^53 的整数加减是精确的；大数加减时小数被大数吸收
## （与 break_infinity 一致）。不要用它做需要精确整数的记账（那种场景用 int）。
## 运算都返回新实例，不改动自身（不可变风格），避免共享引用串改。

const LOG10 := 2.302585092994046   # ln(10)，const 不能调用函数所以硬编码
const INT64_MAX := 9_223_372_036_854_775_807
## 精确整数上限：超过后 double 无法精确表示每个整数
const EXACT_INT_LIMIT := 9_007_199_254_740_992  # 2^53
## 加减时尾数对齐后，指数差超过该值则小数项直接忽略
const PRECISION_GAP := 15
## 比较容差（相对）：吸收浮点对齐噪声（~1e-15），但保留真实差异（如 7 vs 7.0001）
const CMP_EPS := 1e-9

var mantissa: float = 0.0   # 归一化后 ∈ [1,10) 或 0
var exponent: int = 0       # 10 的幂


# ==================== 工厂 ====================

static func zero() -> BigNumber:
	return from_float(0.0)


static func one() -> BigNumber:
	return from_float(1.0)


static func from_int(value: int) -> BigNumber:
	return from_float(float(value))


static func from_float(value: float) -> BigNumber:
	var bn := BigNumber.new()
	bn.mantissa = value
	bn.normalize()
	return bn


static func from_mantissa_exp(m: float, e: int) -> BigNumber:
	var bn := BigNumber.new()
	bn.mantissa = m
	bn.exponent = e
	bn.normalize()
	return bn


## 解析 "750" / "1.23e+45" / "-0.5" / "Infinity" / "NaN"
static func from_string(text: String) -> BigNumber:
	var s := text.strip_edges()
	if s.is_empty():
		return zero()
	var lower := s.to_lower()
	if lower == "inf" or lower == "+inf" or lower == "infinity" or lower == "+infinity":
		return from_float(INF)
	if lower == "-inf" or lower == "-infinity":
		return from_float(-INF)
	if lower == "nan":
		return from_float(NAN)
	var parts := s.split("e", false)
	if parts.size() > 2:
		return zero()   # 非法格式
	var exponent_part := 0
	if parts.size() == 2:
		exponent_part = parts[1].to_int()
	var bn := from_float(parts[0].to_float())
	if exponent_part != 0:
		bn.exponent += exponent_part
		bn.normalize()
	return bn


# ==================== 内部 ====================

## 把 mantissa 归一化到 [1,10)（绝对值），指数合并进 exponent。
func normalize() -> void:
	if mantissa == 0.0 or not is_finite(mantissa):
		return
	# 小整数（< 2^53）内先吸收浮点对齐噪声：接近整数就直接吸附成精确整数
	# （如 6.999999999999999 → 7），保证整币经济不漂移
	if exponent >= 0 and exponent <= 15:
		var raw := to_float()
		if absf(raw) < float(EXACT_INT_LIMIT):
			var rnd := roundf(raw)
			if absf(raw - rnd) <= CMP_EPS * maxf(1.0, absf(raw)):
				mantissa = rnd
				exponent = 0
				# 吸附成 0 时直接结束，避免后续 log(0) 崩溃；
				# 吸附成非零整数时继续走下方归一化，保证 mantissa 回到 [1,10)。
				if mantissa == 0.0:
					return
	var sign := signf(mantissa)
	var a := absf(mantissa)
	var e := int(floorf(log(a) / LOG10))
	a /= pow(10.0, e)
	# 浮点舍入可能把归一化值顶到 10 或压到 1 以下，再修一次
	if a >= 10.0:
		a /= 10.0
		e += 1
	elif a < 1.0:
		a *= 10.0
		e -= 1
	mantissa = sign * a
	exponent += e


# ==================== 查询 ====================

func is_zero() -> bool:
	return mantissa == 0.0


func is_negative() -> bool:
	return mantissa < 0.0


func is_finite_number() -> bool:
	return is_finite(mantissa)


func duplicate() -> BigNumber:
	var bn := BigNumber.new()
	bn.mantissa = mantissa
	bn.exponent = exponent
	return bn


func absolute() -> BigNumber:
	var bn := duplicate()
	bn.mantissa = absf(bn.mantissa)
	return bn


func negate() -> BigNumber:
	var bn := duplicate()
	bn.mantissa = -bn.mantissa
	return bn


func to_float() -> float:
	return mantissa * pow(10.0, float(exponent))


func to_int() -> int:
	if is_zero():
		return 0
	var v := to_float()
	if v >= float(INT64_MAX):
		return INT64_MAX
	if v <= -float(INT64_MAX):
		return -INT64_MAX
	return int(v)


## 以 10 为底的对数（零返回 -INF，调用方自行处理）
func to_log10() -> float:
	if is_zero():
		return -INF
	return log(absf(mantissa)) / LOG10 + float(exponent)


# ==================== 算术 ====================

func add(other: BigNumber) -> BigNumber:
	if other.is_zero():
		return duplicate()
	if is_zero():
		return other.duplicate()
	var diff := exponent - other.exponent
	if diff > PRECISION_GAP:
		return duplicate()          # other 太小，被忽略
	if diff < -PRECISION_GAP:
		return other.duplicate()
	# 对齐到 self 的指数：m 表示 mantissa×10^self.exponent
	# 必须携带 self.exponent 一起归一化，否则整数吸附会在缩放后的尾数上发生，
	# 后续再把 exponent 加回去会把吸附误差放大 10^exponent 倍（如 1e11+1 → 1e11）。
	var bn := from_mantissa_exp(mantissa + other.mantissa * pow(10.0, -float(diff)), exponent)
	return bn


func sub(other: BigNumber) -> BigNumber:
	return add(other.negate())


func mul(other: BigNumber) -> BigNumber:
	if is_zero() or other.is_zero():
		return zero()
	# 与 add 同理：携带真实指数归一化，防止整数吸附在缩放尾数上发生。
	var bn := from_mantissa_exp(mantissa * other.mantissa, exponent + other.exponent)
	return bn


func div(other: BigNumber) -> BigNumber:
	if other.is_zero():
		if is_zero():
			return from_float(NAN)
		return from_float(INF) if not is_negative() else from_float(-INF)
	if is_zero():
		return zero()
	var bn := from_mantissa_exp(mantissa / other.mantissa, exponent - other.exponent)
	return bn


## 立方根（升华点公式用）
func cbrt() -> BigNumber:
	if is_zero():
		return zero()
	var neg := is_negative()
	var m := absf(mantissa)
	var e := exponent
	# 把指数凑成 3 的倍数，让 m 进入 [1,1000) 便于开立方
	while e % 3 != 0:
		m *= 10.0
		e -= 1
	var bn := from_float(pow(m, 1.0 / 3.0))
	bn.exponent += e / 3
	bn.normalize()
	if neg:
		bn.mantissa = -bn.mantissa
	return bn


func floor() -> BigNumber:
	if is_zero():
		return zero()
	# 指数 ≥ 16 时数值 ≥ 1e16，远超 2^53，double 内已无小数部分
	if exponent >= 16:
		return duplicate()
	if exponent < 0:
		return from_int(-1) if is_negative() else zero()
	return from_int(floorf(to_float()))


# ==================== 比较 ====================

func cmp(other: BigNumber) -> int:
	if is_zero() and other.is_zero():
		return 0
	if is_zero():
		return -1 if not other.is_negative() else 1
	if other.is_zero():
		return 1 if not is_negative() else -1
	if is_negative() != other.is_negative():
		return -1 if is_negative() else 1
	# 同号：把绝对值对齐到同一量级比较，用相对容差吸收浮点噪声
	var sign := -1 if is_negative() else 1
	var diff := exponent - other.exponent
	if diff > 2:
		return sign      # 指数差 ≥3 → 至少 1000 倍，直接定序
	if diff < -2:
		return -sign
	var scale := mini(exponent, other.exponent)
	var vm := absf(mantissa) * pow(10.0, float(exponent - scale))
	var om := absf(other.mantissa) * pow(10.0, float(other.exponent - scale))
	var tol := CMP_EPS * maxf(1.0, maxf(vm, om))
	if vm - om > tol:
		return sign
	if om - vm > tol:
		return -sign
	return 0


func eq(other: BigNumber) -> bool: return cmp(other) == 0
func neq(other: BigNumber) -> bool: return cmp(other) != 0
func lt(other: BigNumber) -> bool: return cmp(other) < 0
func lte(other: BigNumber) -> bool: return cmp(other) <= 0
func gt(other: BigNumber) -> bool: return cmp(other) > 0
func gte(other: BigNumber) -> bool: return cmp(other) >= 0


func min(other: BigNumber) -> BigNumber:
	return other.duplicate() if other.lt(self) else duplicate()


func max(other: BigNumber) -> BigNumber:
	return other.duplicate() if other.gt(self) else duplicate()


## 插值：同号大数走对数空间（指数插值），否则线性。
## 用于金币跳数动画：从小值滚到大值时指数插值观感更顺滑。
static func lerp(a: BigNumber, b: BigNumber, t: float) -> BigNumber:
	if a.eq(b):
		return a.duplicate()
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0:
		return a.duplicate()
	if t >= 1.0:
		return b.duplicate()
	if a.is_negative() or b.is_negative():
		return a.add(b.sub(a).mul(from_float(t)))
	if a.is_zero():
		return b.mul(from_float(t))
	if b.is_zero():
		return a.mul(from_float(1.0 - t))
	var la := a.to_log10()
	var lb := b.to_log10()
	if absf(lb - la) < 0.5:
		return a.add(b.sub(a).mul(from_float(t)))
	return from_float(pow(10.0, la + (lb - la) * t))


# ==================== 显示 ====================

const COMPACT_SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi"]

## Cookie Clicker 式紧凑显示：约三位有效数字，避免 1000K。
## 超过 Qi（1e21）回落科学计数（如 1.25e+22）。
func to_compact_string() -> String:
	if is_zero():
		return "0"
	var sign_text := "-" if is_negative() else ""
	var v := absolute()
	var e := v.exponent
	if e < 3:
		return sign_text + str(int(roundf(v.to_float())))
	var unit := int(e / 3)
	if unit >= COMPACT_SUFFIXES.size():
		return sign_text + "%.2fe+%d" % [v.mantissa, v.exponent]
	# scaled ∈ [1, 1000)，取整前加极小相对噪声抵消尾数浮点误差（9.995×100=999.4999… → 1000）
	var scaled := v.mantissa * pow(10.0, float(e - unit * 3))
	var decimals := 2 if scaled < 10.0 else (1 if scaled < 100.0 else 0)
	var factor := pow(10.0, decimals)
	scaled = roundf(scaled * factor * 1.000000001) / factor
	if scaled >= 1000.0 and unit < COMPACT_SUFFIXES.size() - 1:
		scaled /= 1000.0
		unit += 1
		decimals = 2 if scaled < 10.0 else (1 if scaled < 100.0 else 0)
	var body: String
	if decimals == 2:
		body = "%.2f" % scaled
	elif decimals == 1:
		body = "%.1f" % scaled
	else:
		body = "%.0f" % scaled
	while body.contains(".") and body.ends_with("0"):
		body = body.substr(0, body.length() - 1)
	if body.ends_with("."):
		body = body.substr(0, body.length() - 1)
	return sign_text + body + COMPACT_SUFFIXES[unit]


## 完整数值显示（悬浮提示用）：|v| < 2^53 且为整数 → 千分位整串（如 12,345,678，精确）；
## 超出精确整数范围 → 科学计数（如 1.2345e+22）
func to_full_string() -> String:
	if is_zero():
		return "0"
	var sign_text := "-" if is_negative() else ""
	var v := absolute().to_float()
	if is_finite(v) and v < float(EXACT_INT_LIMIT) and v == floorf(v):
		var s := str(int(v))
		var out := ""
		while s.length() > 3:
			out = "," + s.right(3) + out
			s = s.left(s.length() - 3)
		return sign_text + s + out
	return sign_text + "%.4fe+%d" % [absolute().mantissa, exponent]


# ==================== 序列化 ====================
## 可 round-trip 的紧凑表示（用于存档；不重写 Object.to_string）：
##   - 绝对值 < 2^53 且为整数 → 整数串（精确）
##   - 否则 → mantissa + "e" + exponent（str(mantissa) 用最短往返表示，科学形式解析回同一 double）
func to_save_string() -> String:
	if is_zero():
		return "0"
	if not is_finite(mantissa):
		if is_nan(mantissa):
			return "NaN"
		return "Infinity" if mantissa > 0.0 else "-Infinity"
	if exponent >= 0 and exponent <= 15:
		var v := to_float()
		if v == floorf(v) and absf(v) < float(EXACT_INT_LIMIT):
			return str(int(v))
	return str(mantissa) + "e" + str(exponent)
