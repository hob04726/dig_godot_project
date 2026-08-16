class_name TalentNode
extends Node2D

## 天赋节点（世界空间）：图标 + 状态视觉 + 动画。
## 状态：LOCKED（半透明 0.9）→ AVAILABLE（不透明 0.9）→ PURCHASED（1.0）。
## 悬停：平滑放大到 1.15、透明度变 1；离开回到基础。
## 购买：0.9 → 1.2 → 1（回弹）；新解锁（前置刚买）：0 → 1.2 → 0.9（弹跳出现）。

enum State { LOCKED, AVAILABLE, PURCHASED }

const HIT_SIZE := Vector2(90, 90)
const BASE_SCALE := 0.9
const HOVER_SCALE := 1.15
const PURCHASED_SCALE := 1.0
const LOCKED_ALPHA := 0.3
const AVAILABLE_ALPHA := 0.8
## 购买弹跳总时长（0.14 冲到 1.2 + 0.14 回弹），TalentGrid 用它等动画播完再揭示新节点
const PURCHASE_POP_TIME := 0.28

var talent_id: StringName
var display_name: String = ""
var description: String = ""
var currency: String = "金币"
var cost: BigNumber = null
var effect_type: String = ""
var prerequisite_ids: Array[StringName] = []
var ascension_prerequisite_id: StringName = &""
var unlock_condition: String = ""
var state: State = State.LOCKED
var revealed := false   # 前置已满足（false→true 且可购买时触发弹跳）

var _hovered := false
var _scale_tween: Tween = null
var _alpha_tween: Tween = null

@onready var icon_sprite: Sprite2D = $Icon


func setup(def: TalentDef) -> void:
	talent_id = def.id
	display_name = def.display_name
	description = def.description
	currency = def.currency
	cost = def.cost
	effect_type = def.effect_type
	prerequisite_ids = def.prerequisite_ids.duplicate()
	ascension_prerequisite_id = def.ascension_prerequisite_id
	unlock_condition = def.unlock_condition
	icon_sprite = $Icon as Sprite2D
	if def.icon != null:
		icon_sprite.texture = def.icon
	scale = Vector2.ONE * BASE_SCALE


func set_state(s: State, animated := true) -> void:
	var prev := state
	state = s
	if not _hovered:
		modulate.a = _desired_alpha()   # 非悬浮时透明度直接到位
	if animated:
		if s == State.PURCHASED and prev != State.PURCHASED:
			_play_purchase_pop()
		elif s == State.AVAILABLE and prev == State.LOCKED:
			_play_reveal_pop()
	else:
		_kill_scale_tween()
		scale = Vector2.ONE * _desired_scale()


func set_hovered(h: bool) -> void:
	if _hovered == h:
		return
	_hovered = h
	_tween_scale(_desired_scale(), 0.15)
	_tween_alpha(_desired_alpha(), 0.12)


## 世界坐标是否落在本节点的命中矩形内（控制器点击/悬停用）
func contains_point(world_pos: Vector2) -> bool:
	return Rect2(global_position - HIT_SIZE * 0.5, HIT_SIZE).has_point(world_pos)


# ==================== 视觉 ====================

func _base_scale() -> float:
	return PURCHASED_SCALE if state == State.PURCHASED else BASE_SCALE


func _desired_scale() -> float:
	return HOVER_SCALE if _hovered else _base_scale()


func _base_alpha() -> float:
	match state:
		State.LOCKED: return LOCKED_ALPHA
		State.AVAILABLE: return AVAILABLE_ALPHA
		State.PURCHASED: return 1.0
	return 1.0


func _desired_alpha() -> float:
	return 1.0 if _hovered else _base_alpha()


## 购买后：0.9 → 1.2 → 1（回弹强调）
func _play_purchase_pop() -> void:
	_kill_scale_tween()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * _desired_scale(), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 新解锁（前置刚买且可购买）：0 → 1.2 → 0.9（弹跳出现）
func _play_reveal_pop() -> void:
	_kill_scale_tween()
	scale = Vector2.ZERO
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * _desired_scale(), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _tween_scale(target: float, time := 0.15) -> void:
	_kill_scale_tween()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _tween_alpha(target: float, time := 0.12) -> void:
	if _alpha_tween and _alpha_tween.is_valid():
		_alpha_tween.kill()
	_alpha_tween = create_tween()
	_alpha_tween.tween_property(self, "modulate:a", target, time)


func _kill_scale_tween() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
