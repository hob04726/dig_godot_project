class_name TalentSystem
extends RefCounted

## 天赋效果引擎（数据层）：聚合已购天赋（GameState）的定义（TalentDb），
## 对外提供语义化只读查询。不持有 GridModel——地块协同依赖的放置计数由调用方传参，
## 保持数据层解耦、可无头测试。
##
## 聚合规则（统一判定 _is_purchased）：
##   加 bucket：PICKAXE_DAMAGE_FLAT / PICKAXE_CRIT_CHANCE / PICKAXE_CRIT_DAMAGE /
##             GLOBAL_COIN_MULT / GLOBAL_ORE_VALUE_MULT
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
	&"push": &"tick_interval",
	&"pull": &"tick_interval",
	&"upgrade": &"tick_interval",
	&"spawn": &"tick_interval",
	&"rarity": &"min_rarity",
	&"conveyor_belt_leftdown": &"tick_interval",
	&"conveyor_belt_leftup": &"tick_interval",
	&"conveyor_belt_rightdown": &"tick_interval",
	&"conveyor_belt_rightup": &"tick_interval",
	&"tnt_spawn": &"tick_interval",
	&"tnt": &"tick_interval",
}

var _state: GameState
var _db: TalentDb
var _tile_db: DefDb = null
var _cache_dirty := true

# 缓存（_rebuild 填充）
var _pickaxe_flat := 0
var _crit_chance := 0.0
var _crit_damage := 0.0
var _aoe_radius := 0
var _extra_hit_chance := 0.0
var _global_coin_sum := 0.0
var _global_ore_value_sum := 0.0
var _ore_value_mult: Dictionary[StringName, float] = {}
var _tile_overrides: Dictionary[StringName, Dictionary] = {}
var _unlocked_ores: Dictionary[StringName, bool] = {}
var _unlocked_tiles: Dictionary[StringName, bool] = {}
var _terrain_defs: Array[TalentDef] = []
var _synergy_per_tile_defs: Array[TalentDef] = []
var _special_value_buff_chance := 0.0
var _special_high_value_chance := 0.0
var _special_fragile_chance := 0.0


func _init(state: GameState, db: TalentDb, tile_db: DefDb = null) -> void:
	_state = state
	_db = db
	_tile_db = tile_db


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


## 稿子额外攻击几率（0..1）
func get_pickaxe_extra_hit_chance() -> float:
	_ensure()
	return _extra_hit_chance


## 特殊矿出现概率（0..1），三者按累计阈值判定：value_buff < high_value < fragile
func get_special_value_buff_chance() -> float:
	_ensure()
	return _special_value_buff_chance


func get_special_high_value_chance() -> float:
	_ensure()
	return _special_high_value_chance


func get_special_fragile_chance() -> float:
	_ensure()
	return _special_fragile_chance


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


## 每放置一个目标地块即获得全局/指定矿产值加成（无上限，由数值设计控制）
func get_per_tile_synergy_bonus(placed_counts: Dictionary) -> float:
	_ensure()
	var bonus := 0.0
	for def in _synergy_per_tile_defs:
		var per_tile := _eval_value(def, 0.0)
		for tile_id in def.target_ids:
			var placed: int = placed_counts.get(tile_id, 0)
			bonus += per_tile * placed
	return 1.0 + bonus


# ==================== 升华 ====================

## 声望倍率（基于已领取升华点；委托 GameState）
func get_permanent_multiplier() -> BigNumber:
	return _state.permanent_multiplier()


## 是否已解锁"水域沉没矿返还金币"机制
func has_water_sink_refund() -> bool:
	return _state.has_ascension(&"meta_water_sink")


## 新一轮开局可探索区域边长（3/5/7/9）
func get_starting_area_size() -> int:
	if _state.has_ascension(&"meta_area_9x9"): return 9
	if _state.has_ascension(&"meta_area_7x7"): return 7
	if _state.has_ascension(&"meta_area_5x5"): return 5
	return 3


## 是否已解锁无限放置（不受水域/区域限制）
func has_unlimited_placement() -> bool:
	return _state.has_ascension(&"meta_unlimited_placement")


# ==================== 结算 / 挖矿管线 ====================

## 完整金币结算：base(已含 tile 倍率) × 矿价值 × 地块协同 × 全局矿石价值 × reward_ratio × 全局金币 × 声望倍率
func compute_coin_gain(base_value: int, ore_id: StringName,
		placed_counts: Dictionary, reward_ratio: float = 1.0) -> BigNumber:
	_ensure()
	var mult := get_ore_value_multiplier(ore_id)
	mult *= get_terrain_synergy(ore_id, placed_counts)
	mult *= get_per_tile_synergy_bonus(placed_counts)
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


## 根据当前等级计算 def.value 的实际数值。
## 支持："2*level" / "0.15*level" / "2^(level-1)" / 直接数值（兼容旧版单级）
func _eval_value(def: TalentDef, default: float = 0.0) -> float:
	var expr := def.value.strip_edges()
	if expr.is_empty():
		return default
	var rank := _state.get_talent_rank(def.id)
	if rank <= 0:
		return default
	# X*level
	if expr.ends_with("*level"):
		var base_str := expr.substr(0, expr.length() - 6).strip_edges()
		if base_str.is_valid_float():
			return base_str.to_float() * rank
	# X^(level-Y)
	var caret_idx := expr.find("^(level")
	if caret_idx != -1:
		var base_str := expr.substr(0, caret_idx).strip_edges()
		var rest := expr.substr(caret_idx + 2)  # "level-Y)" 或 "level)"
		var offset := 0
		var minus_idx := rest.find("-")
		if minus_idx != -1:
			var num_str := rest.substr(minus_idx + 1).strip_edges().replace(")", "")
			if num_str.is_valid_int():
				offset = num_str.to_int()
		if base_str.is_valid_float():
			return pow(base_str.to_float(), maxi(rank - offset, 0))
	# 直接数值（旧版单级）
	if expr.is_valid_float():
		return expr.to_float()
	return default


## 已购判定：本轮普通 / 永久升华（以 GameState 记录为准，购买才会进存档）
func _is_purchased(def: TalentDef) -> bool:
	if def == null:
		return false
	return _state.has_talent(def.id) or _state.has_ascension(def.id)


func _rebuild() -> void:
	_cache_dirty = false
	_pickaxe_flat = 0
	_crit_chance = 0.0
	_crit_damage = 0.0
	_aoe_radius = 0
	_extra_hit_chance = 0.0
	_global_coin_sum = 0.0
	_global_ore_value_sum = 0.0
	_ore_value_mult.clear()
	_tile_overrides.clear()
	_unlocked_ores.clear()
	_unlocked_tiles.clear()
	_terrain_defs.clear()
	_synergy_per_tile_defs.clear()
	_special_value_buff_chance = 0.0
	_special_high_value_chance = 0.0
	_special_fragile_chance = 0.0

	# 泥土矿为开局默认解锁，无需天赋
	_unlocked_ores[&"dirt"] = true

	for def in _db.get_all_defs():
		if not _is_purchased(def):
			continue
		match def.effect_type:
			"PICKAXE_DAMAGE_FLAT":
				_pickaxe_flat += int(_eval_value(def))
			"PICKAXE_CRIT_CHANCE":
				_crit_chance += _eval_value(def)
			"PICKAXE_CRIT_DAMAGE":
				_crit_damage += _eval_value(def)
			"PICKAXE_AOE":
				_aoe_radius = maxi(_aoe_radius, int(_eval_value(def)))
			"PICKAXE_EXTRA_HIT":
				_extra_hit_chance += _eval_value(def)
			"SPECIAL_VALUE_BUFF_CHANCE":
				_special_value_buff_chance += _eval_value(def)
			"SPECIAL_HIGH_VALUE_CHANCE":
				_special_high_value_chance += _eval_value(def)
			"SPECIAL_FRAGILE_CHANCE":
				_special_fragile_chance += _eval_value(def)
			"GLOBAL_COIN_MULT":
				_global_coin_sum += _eval_value(def)
			"GLOBAL_ORE_VALUE_MULT":
				_global_ore_value_sum += _eval_value(def)
			"ORE_VALUE_MULT":
				var v := _eval_value(def, 1.0)
				for ore in def.target_ids:
					_ore_value_mult[ore] = _ore_value_mult.get(ore, 1.0) * v
			"TILE_BEHAVIOR_UP":
				if not def.target_ids.is_empty():
					_apply_tile_override(def.target_ids[0], _eval_value(def))
			"UNLOCK_ORE":
				for ore in def.target_ids:
					_unlocked_ores[ore] = true
			"UNLOCK_TILE":
				for tile in def.target_ids:
					_unlocked_tiles[tile] = true
			"UNLOCK_ORE_VALUE_MULT":
				var rank := _state.get_talent_rank(def.id)
				if rank >= 1:
					for ore in def.target_ids:
						_unlocked_ores[ore] = true
				if rank >= 2:
					var v := _eval_value(def, 2.0)
					for ore in def.target_ids:
						_ore_value_mult[ore] = _ore_value_mult.get(ore, 1.0) * v
			"UNLOCK_TILE_BEHAVIOR":
				var rank := _state.get_talent_rank(def.id)
				if rank >= 1:
					for tile in def.target_ids:
						_unlocked_tiles[tile] = true
				if rank >= 2 and _tile_db != null:
					var v := _eval_value(def, 2.0)
					for tile in def.target_ids:
						_apply_tile_override_from_base(tile, v)
			"TERRAIN_ORE_SYNERGY":
				_terrain_defs.append(def)
			"SYNERGY_PER_TILE":
				_synergy_per_tile_defs.append(def)
			_:
				pass   # PRESTIGE_RESET / UNLOCK_META / UNLOCK_TIER_RANGE 等由树/流程处理

	# 特殊矿概率按累计阈值归一：value_buff < high_value < fragile
	_special_high_value_chance += _special_value_buff_chance
	_special_fragile_chance += _special_high_value_chance


## TILE_BEHAVIOR_UP：按 tile 映射参数，SET 取已购最大值
func _apply_tile_override(tile_id: StringName, value: float) -> void:
	var param: StringName = TILE_PARAM_MAP.get(tile_id, &"")
	if param == &"":
		return
	var ov: Dictionary = _tile_overrides.get(tile_id, {})
	if not ov.has(param) or value > float(ov[param]):
		ov[param] = value
	_tile_overrides[tile_id] = ov


## 地块解锁+升级：根据 tile 默认值乘以倍率写入 override
func _apply_tile_override_from_base(tile_id: StringName, multiplier: float) -> void:
	var param: StringName = TILE_PARAM_MAP.get(tile_id, &"")
	if param == &"" or _tile_db == null:
		return
	var tile_def := _tile_db.get_tile(tile_id)
	if tile_def == null:
		return
	var base: float = 0.0
	match param:
		&"damage_multiplier":
			base = tile_def.damage_multiplier
		&"value_multiplier":
			base = tile_def.value_multiplier
		&"sink_refund_ratio":
			base = tile_def.sink_refund_ratio
		&"damage":
			base = tile_def.damage
		&"tick_interval":
			base = tile_def.tick_interval
		&"min_rarity":
			base = float(tile_def.min_rarity)
	if base == 0.0:
		return
	_apply_tile_override(tile_id, base * multiplier)
