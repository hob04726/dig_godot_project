class_name FlavorTextDb
extends RefCounted

## 风味语句数据库（NamePanel 下方滚动的小字）。
## 按“阶段”分桶，每 10 秒从当前阶段已解锁的语句中随机抽取一条。
## 条件目前以 lifetime_coins 为主，也可以扩展为按天赋、地块、开采数等解锁特定语句。

class Entry:
	var stage: int
	var text: String
	var weight: int
	var min_lifetime_coins: BigNumber

	func _init(p_stage: int, p_text: String, p_weight: int = 1,
			p_min_lifetime: BigNumber = BigNumber.zero()) -> void:
		stage = p_stage
		text = p_text
		weight = p_weight
		min_lifetime_coins = p_min_lifetime


static var _entries: Array[Entry] = []

static func _static_init() -> void:
	_entries = [
		# ===== 阶段 0：开局 =====
		Entry.new(0, "小世界里的第一粒尘埃开始发光。"),
		Entry.new(0, "泥土块们还不太敢相信自己会被挖走。"),
		Entry.new(0, "你听到了镐子敲击的回响。"),
		Entry.new(0, "远处的矿脉正在低声交谈。"),
		Entry.new(0, "这里的一切都还很小，但已经充满可能。"),

		# ===== 阶段 1：小有起色（lifetime ≥ 1e4） =====
		Entry.new(1, "煤矿们决定不再睡懒觉。", 1, BigNumber.from_string("1e4")),
		Entry.new(1, "草地的风带来了金币的味道。", 1, BigNumber.from_string("1e4")),
		Entry.new(1, "有人传说金矿已经在深处沉睡。", 1, BigNumber.from_string("1e4")),
		Entry.new(1, "你的小世界开始变得热闹起来。", 1, BigNumber.from_string("1e4")),
		Entry.new(1, "路过的商人看了一眼，决定过几天再来。", 1, BigNumber.from_string("1e5")),

		# ===== 阶段 2：中期（lifetime ≥ 1e9） =====
		Entry.new(2, "水晶的光芒照亮了洞穴。", 1, BigNumber.from_string("1e9")),
		Entry.new(2, "TNT 的轰鸣让世界颤抖。", 1, BigNumber.from_string("1e9")),
		Entry.new(2, "稀有矿脉吸引了外地商人的注意。", 1, BigNumber.from_string("1e9")),
		Entry.new(2, "你的矿石已经销往隔壁位面。", 1, BigNumber.from_string("1e9")),
		Entry.new(2, "矿工协会给你寄来了一封表扬信。", 1, BigNumber.from_string("1e9")),

		# ===== 阶段 3：大数/终局（lifetime ≥ 1e15） =====
		Entry.new(3, "猫矿睁开眼睛，审视着一切。", 1, BigNumber.from_string("1e15")),
		Entry.new(3, "升华点像星星一样在天空中闪烁。", 1, BigNumber.from_string("1e15")),
		Entry.new(3, "你的声望已经传遍所有维度。", 1, BigNumber.from_string("1e15")),
		Entry.new(3, "整个世界都在为你的镐子让路。", 1, BigNumber.from_string("1e15")),
		Entry.new(3, "传说这里曾是一片空地，直到你出现。", 1, BigNumber.from_string("1e15")),
	]


## 根据当前累计金币判断所处阶段。
static func current_stage(lifetime: BigNumber) -> int:
	if lifetime.gte(BigNumber.from_string("1e15")):
		return 3
	if lifetime.gte(BigNumber.from_string("1e9")):
		return 2
	if lifetime.gte(BigNumber.from_string("1e4")):
		return 1
	return 0


## 获取当前阶段所有已解锁的语句（含更低阶段，保证早期语句后期仍可出现）。
static func get_available_lines(lifetime: BigNumber) -> Array[Entry]:
	var stage := current_stage(lifetime)
	var result: Array[Entry] = []
	for e in _entries:
		if e.stage <= stage and lifetime.gte(e.min_lifetime_coins):
			result.append(e)
	return result


## 按权重随机选一条；没有可用时返回空字符串。
static func pick_line(rng: RandomNumberGenerator, lifetime: BigNumber) -> String:
	var pool := get_available_lines(lifetime)
	if pool.is_empty():
		return ""
	var total_weight := 0
	for e in pool:
		total_weight += e.weight
	var roll := rng.randi_range(1, total_weight)
	for e in pool:
		roll -= e.weight
		if roll <= 0:
			return e.text
	return pool[-1].text
