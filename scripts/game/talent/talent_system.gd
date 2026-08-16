class_name TalentSystem
extends RefCounted

## 天赋效果引擎（数据层）：聚合已购天赋（GameState）的定义（TalentDb），
## 对外提供语义化只读查询。不持有 GridModel——地块协同依赖的放置计数由调用方传参，
## 保持数据层解耦、可无头测试。
##
## 聚合规则（统一判定 _is_purchased）：
##   加 bucket：PICKAXE_DAMAGE_FLAT / PICKAXE_CRIT_CHANCE / PICKAXE_CRIT_DAMAGE /
##             GLOBAL_COIN_MULT / GLOBAL_ORE_VALUE_MULT / PERMANENT_SLOT
##   乘 bucket（per ore）：ORE_VALUE_MULT
##   SET（取已购最大值，per tile）：TILE_BEHAVIOR_UP
##   集合：UNLOCK_ORE / UNLOCK_TILE
##   运行时现算：TERRAIN_ORE_SYNERGY（依赖 placed_counts）
## 缓存固定部分，invalidate() 后重算（天赋购买/升华后调用）。

const CRYSTAL := &"crystal"

## TILE_BEHAVIOR_UP 的 tile -> 覆盖参数名（与 TileDef 字段一致）
const TILE_PARAM_MAP := {
	&"dirt": &"damage_multiplier",
	&"grass": &"damage_multiplier",
	&"stone": &"value_multiplier",
	&"water": &"sink_refund_ratio",
	&"fire": &"damage",
	&"volcano_stable": &"damage",
	&"push": &"tick_interval",
	&"pull": &"tick_interval",
	&"upgrade": &"tick_interval",
	&"spawn": &"tick_interval",
	&"rarity": &"min_rarity",
}

var _state: GameState
var _db: TalentDb
var _cache_dirty := true

# 缓存（_rebuild 填充）
var _pickaxe_flat := 0
var _crit_chance := 0.0
var _crit_damage := 0.0
var _aoe_radius := 0
var _global_coin_sum := 0.0
var _global_ore_value_sum := 0.0
var _permanent_slots := 0
var _ore_value_mult: Dictionary[StringName, float] = {}
var _tile_overrides: Dictionary[StringName, Dictionary] = {}
var _unlocked_ores: Dictionary[StringName, bool] = {}
var _unlocked_tiles: Dictionary[StringName, bool] = {}
var _terrain_defs: Array[TalentDef] = []


func _init(state: GameState, db: TalentDb) -> void:
	_state = state
	_db = db


## 购买/升华后调用：缓存失效，下次查询重建
func invalidate() -> void:
	_cache_dirty = true


# ==================== 稿子 ====================

func get_pickaxe_damage_flat() -> int:
	_ensure()
	return _pickaxe_flat


## 暴击概率（0..1）
func get_pickaxe_crit_chance() -> float:
	_ensure()
	return _crit_chance


## 暴击伤害加值：暴击倍率 = 2.0 + 此值
func get_pickaxe_crit_damage() -> float:
	_ensure()
	return _crit_damage


## 稿子作用范围（AOE；本次只暴露数据，范围命中后续实现）
func get_pickaxe_aoe_radius() -> int:
	_ensure()
	return _aoe_radius


# ==================== 全局收益 ====================

## 全局金币获取倍率 = 1 + Σ(GLOBAL_COIN_MULT)
func get_global_coin_multiplier() -> float:
	_ensure()
	return 1.0 + _global_coin_sum


## 全局矿石价值倍率 = 1 + Σ(GLOBAL_ORE_VALUE_MULT)
func get_global_ore_value_multiplier() -> float:
	_ensure()
	return 1.0 + _global_ore_value_sum


# ==================== 矿石价值 ====================

## 该矿结算价值倍率 = Π(ORE_VALUE_MULT)（同矿连乘，gold_council 另乘 4）
func get_ore_value_multiplier(ore_id: StringName) -> float:
	_ensure()
	return _ore_value_mult.get(ore_id, 1.0)


# ==================== 地块行为 override ====================

func get_tile_behavior_overrides() -> Dictionary[StringName, Dictionary]:
	_ensure()
	return _tile_overrides


# ==================== 解锁集合 ====================

func get_unlocked_ores() -> Array[StringName]:
	_ensure()
	var result: Array[StringName] = []
	for id in _unlocked_ores.keys():
		result.append(id)
	return result


## 自然落矿池候选：已解锁矿石，但水晶永远排除——水晶只在地块（spawn 水晶矿脉）上产生。
func get_natural_spawn_ores() -> Array[StringName]:
	var result := get_unlocked_ores()
	result = result.filter(func(id: StringName) -> bool: return id != CRYSTAL)
	return result


func get_unlocked_tiles() -> Array[StringName]:
	_ensure()
	var result: Array[StringName] = []
	for id in _unlocked_tiles.keys():
		result.append(id)
	return result


func has_unlocked_ore(ore_id: StringName) -> bool:
	_ensure()
	return _unlocked_ores.get(ore_id, false)


func has_unlocked_tile(tile_id: StringName) -> bool:
	_ensure()
	return _unlocked_tiles.get(tile_id, false)


# ==================== 地块协同 ====================

## 该矿的地块协同倍率 = 1 + Σ(rate × min(⌊placed[branch]/10⌋, 10))，对 ore ∈ target_ids 求和。
## placed_counts 由调用方传（GridModel.get_placed_counts() 或测试字面量），不缓存。
func get_terrain_synergy(ore_id: StringName, placed_counts: Dictionary) -> float:
	_ensure()
	var bonus := 0.0
	for def in _terrain_defs:
		if not def.target_ids.has(ore_id):
			continue
		var placed: int = placed_counts.get(StringName(def.branch), 0)
		var groups := mini(placed / 10, 10)   # 每 10 块一组，最多 10 组
		bonus += def.value.to_float() * groups
	return 1.0 + bonus


# ==================== 升华 ====================

## 永久金币倍率（基于已领取升华点；委托 GameState）
func get_permanent_multiplier() -> BigNumber:
	return _state.permanent_multiplier()


## 永久槽数量 = Σ(PERMANENT_SLOT)
func get_permanent_slot_count() -> int:
	_ensure()
	return _permanent_slots


## 升华时保留的普通天赋：已购普通天赋中成本最高的 N 个
func select_preserved_talents(slot_count: int) -> Array[StringName]:
	_ensure()
	var purchased: Array[TalentDef] = []
	for def in _db.get_normal_defs():
		if _state.has_talent(def.id):
			purchased.append(def)
	purchased.sort_custom(func(a: TalentDef, b: TalentDef) -> bool: return a.cost.gt(b.cost))
	var result: Array[StringName] = []
	for i in mini(slot_count, purchased.size()):
		result.append(purchased[i].id)
	return result


# ==================== 结算 / 挖矿管线 ====================

## 完整金币结算：base(已含 tile 倍率) × 矿价值 × 地块协同 × 全局矿石价值 × reward_ratio × 全局金币 × 永久倍率
func compute_coin_gain(base_value: int, ore_id: StringName,
		placed_counts: Dictionary, reward_ratio: float = 1.0) -> BigNumber:
	_ensure()
	var mult := get_ore_value_multiplier(ore_id)
	mult *= get_terrain_synergy(ore_id, placed_counts)
	mult *= get_global_ore_value_multiplier()
	mult *= get_global_coin_multiplier()
	mult *= reward_ratio
	var gain := BigNumber.from_int(base_value).mul(BigNumber.from_float(mult))
	gain = gain.mul(get_permanent_multiplier())
	return gain.floor()


## 挖矿伤害：max(1, round((base + flat) × tile 倍率))；暴击概率内再 × (2.0 + 暴击加值)。
## rng 由调用方注入（GameManager 的 _mine_rng），可复现种子。兼容旧签名（只返回数值）。
func compute_hit_damage(base_damage: int, tile_multiplier: float, rng: RandomNumberGenerator) -> int:
	return hit_damage_details(base_damage, tile_multiplier, rng)["damage"]


## 挖矿伤害详情：{"damage": int, "crit": bool}——视图据此显示跳数/暴击特效。
func hit_damage_details(base_damage: int, tile_multiplier: float, rng: RandomNumberGenerator) -> Dictionary:
	_ensure()
	var dmg := float(base_damage + _pickaxe_flat) * tile_multiplier
	var crit := _crit_chance > 0.0 and rng.randf() < _crit_chance
	if crit:
		dmg *= 2.0 + _crit_damage
	return {"damage": maxi(1, int(round(dmg))), "crit": crit}


# ==================== 内部 ====================

func _ensure() -> void:
	if _cache_dirty:
		_rebuild()


## 已购判定：本轮普通 / 永久升华 / CSV 标"开局已购买"
func _is_purchased(def: TalentDef) -> bool:
	if def == null:
		return false
	if _state.has_talent(def.id) or _state.has_ascension(def.id):
		return true
	return def.unlock_condition == "开局已购买"


func _rebuild() -> void:
	_cache_dirty = false
	_pickaxe_flat = 0
	_crit_chance = 0.0
	_crit_damage = 0.0
	_aoe_radius = 0
	_global_coin_sum = 0.0
	_global_ore_value_sum = 0.0
	_permanent_slots = 0
	_ore_value_mult.clear()
	_tile_overrides.clear()
	_unlocked_ores.clear()
	_unlocked_tiles.clear()
	_terrain_defs.clear()

	for def in _db.get_all_defs():
		if not _is_purchased(def):
			continue
		match def.effect_type:
			"PICKAXE_DAMAGE_FLAT":
				_pickaxe_flat += int(def.value.to_float()) if def.value != "" else 0
			"PICKAXE_CRIT_CHANCE":
				_crit_chance += def.value.to_float() if def.value != "" else 0.0
			"PICKAXE_CRIT_DAMAGE":
				_crit_damage += def.value.to_float() if def.value != "" else 0.0
			"PICKAXE_AOE":
				_aoe_radius = maxi(_aoe_radius, int(def.value.to_float()) if def.value != "" else 0)
			"GLOBAL_COIN_MULT":
				_global_coin_sum += def.value.to_float() if def.value != "" else 0.0
			"GLOBAL_ORE_VALUE_MULT":
				_global_ore_value_sum += def.value.to_float() if def.value != "" else 0.0
			"PERMANENT_SLOT":
				_permanent_slots += int(def.value.to_float()) if def.value != "" else 0
			"ORE_VALUE_MULT":
				var v := def.value.to_float() if def.value != "" else 1.0
				for ore in def.target_ids:
					_ore_value_mult[ore] = _ore_value_mult.get(ore, 1.0) * v
			"TILE_BEHAVIOR_UP":
				if not def.target_ids.is_empty():
					_apply_tile_override(def.target_ids[0], def.value.to_float())
			"UNLOCK_ORE":
				for ore in def.target_ids:
					_unlocked_ores[ore] = true
			"UNLOCK_TILE":
				for tile in def.target_ids:
					_unlocked_tiles[tile] = true
			"TERRAIN_ORE_SYNERGY":
				_terrain_defs.append(def)
			_:
				pass   # PRESTIGE_RESET / UNLOCK_META / UNLOCK_TIER_RANGE 等由树/流程处理


## TILE_BEHAVIOR_UP：按 tile 映射参数，SET 取已购最大值
func _apply_tile_override(tile_id: StringName, value: float) -> void:
	var param: StringName = TILE_PARAM_MAP.get(tile_id, &"")
	if param == &"":
		return
	var ov: Dictionary = _tile_overrides.get(tile_id, {})
	if not ov.has(param) or value > float(ov[param]):
		ov[param] = value
	_tile_overrides[tile_id] = ov
