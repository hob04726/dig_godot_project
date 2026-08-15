class_name GameState
extends RefCounted

## 可持久化的游戏经济状态（数据层，全游戏唯一写入口之一，与 GridModel 平级）。
## 规则（沿用 GridModel 的纪律）：
##   1. 所有写入走方法，成功后发 changed 信号；
##   2. 视图（GameManager/HUD/天赋树）只读订阅，禁止反向写回；
##   3. 读写分离：to_dict() 给存档，load_from_dict() 恢复。
## 升华点语义（Cookie Clicker / Heavenly Chips 式，用户确认）：
##   总升华点 = floor(cbrt(累计金币 / 1e6))，按全时间累计推导，永不减少；
##   每次升华领取"新总数 − 已领取"的差值，累进已领取数；
##   每点永久 +1% 金币获取（按已领取点数；花掉的不降低永久等级）。

signal changed

## 当前金币（本轮）
var coins := BigNumber.zero()
## 全时间累计金币（单调不减；升华点按它推导）
var lifetime_coins := BigNumber.zero()
## 已通过升华领取的升华点（跨轮累加；每次升华只领取差值）
var ascension_points_earned := BigNumber.zero()
## 已花掉的升华点（购买升华天赋用）
var ascension_points_spent: int = 0
## 每矿累计开采数：ore_id -> int（矿石被玩家挖死时 +1，跨轮保留）
var ore_mined: Dictionary[StringName, int] = {}
## 普通天赋购买（本轮）：id -> true
var talent_purchases: Dictionary[StringName, bool] = {}
## 升华天赋购买（永久）：id -> true
var ascension_purchases: Dictionary[StringName, bool] = {}


# ==================== 经济 ====================

## 获得金币：coins 与 lifetime_coins 同时增加
func add_coins(amount: BigNumber) -> void:
	if amount.is_zero():
		return
	coins = coins.add(amount)
	lifetime_coins = lifetime_coins.add(amount)
	changed.emit()


## 花金币：余额不足返回 false，不扣款
func spend_coins(amount: BigNumber) -> bool:
	if coins.lt(amount):
		return false
	coins = coins.sub(amount)
	changed.emit()
	return true


## 记录一次矿石开采（玩家挖死才 +1；水沉没/火山/熔岩击杀不计）
func increment_ore_mined(ore_id: StringName) -> void:
	ore_mined[ore_id] = ore_mined.get(ore_id, 0) + 1
	changed.emit()


func get_ore_mined(ore_id: StringName) -> int:
	return ore_mined.get(ore_id, 0)


# ==================== 升华 ====================

## 应有点数 = floor(cbrt(累计金币 / 1e6))（按全时间累计推导，永不减少）
func ascension_points_total() -> BigNumber:
	return Prestige.points_for(lifetime_coins)


## 升华结算：领取"新总数 − 已领取"的差值，清空本轮金币与普通天赋，进入新一轮。
## 返回本次领取的升华点；网格/初始地块由调用方（未来的重置流程）负责重建。
func apply_ascension() -> BigNumber:
	var gain := ascension_points_total().sub(ascension_points_earned)
	if gain.is_negative():
		gain = BigNumber.zero()
	ascension_points_earned = ascension_points_earned.add(gain)
	coins = BigNumber.zero()
	talent_purchases.clear()
	changed.emit()
	return gain


## 当前可花费点数 = 已领取 − 已花
func ascension_points_available() -> BigNumber:
	return ascension_points_earned.sub(BigNumber.from_int(ascension_points_spent))


## 永久金币倍率：基于已领取点数（花掉的不降低永久等级）
func permanent_multiplier() -> BigNumber:
	return Prestige.multiplier_from_points(ascension_points_earned)


# ==================== 天赋购买 ====================

func has_talent(id: StringName) -> bool:
	return talent_purchases.get(id, false)


func has_ascension(id: StringName) -> bool:
	return ascension_purchases.get(id, false)


## 记录普通天赋购买（金币扣款由调用方先走 spend_coins）
func record_talent_purchase(id: StringName) -> void:
	talent_purchases[id] = true
	changed.emit()


## 购买升华天赋：检查升华点余额，扣点并记录。返回是否成功。
func record_ascension_purchase(id: StringName, cost: int) -> bool:
	if has_ascension(id):
		return false
	if ascension_points_available().lt(BigNumber.from_int(cost)):
		return false
	ascension_points_spent += cost
	ascension_purchases[id] = true
	changed.emit()
	return true


# ==================== 存档 ====================

## 序列化（键转 String，保证 JSON 安全）
func to_dict() -> Dictionary:
	var om := {}
	for k: StringName in ore_mined:
		om[String(k)] = ore_mined[k]
	var tp := {}
	for k: StringName in talent_purchases:
		tp[String(k)] = true
	var ap := {}
	for k: StringName in ascension_purchases:
		ap[String(k)] = true
	return {
		"coins": coins.to_save_string(),
		"lifetime_coins": lifetime_coins.to_save_string(),
		"ascension_points_earned": ascension_points_earned.to_save_string(),
		"ascension_points_spent": ascension_points_spent,
		"ore_mined": om,
		"talents": tp,
		"ascension_talents": ap,
	}


## 反序列化（容忍缺字段/未知字段；键回转为 StringName）
func load_from_dict(data: Dictionary) -> void:
	coins = BigNumber.from_string(str(data.get("coins", "0")))
	lifetime_coins = BigNumber.from_string(str(data.get("lifetime_coins", "0")))
	ascension_points_earned = BigNumber.from_string(str(data.get("ascension_points_earned", "0")))
	ascension_points_spent = int(data.get("ascension_points_spent", 0))
	ore_mined.clear()
	for key in data.get("ore_mined", {}):
		ore_mined[StringName(key)] = int(data["ore_mined"][key])
	talent_purchases.clear()
	for key in data.get("talents", {}):
		talent_purchases[StringName(key)] = true
	ascension_purchases.clear()
	for key in data.get("ascension_talents", {}):
		ascension_purchases[StringName(key)] = true
	changed.emit()
