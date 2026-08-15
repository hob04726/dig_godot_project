class_name TalentNode
extends Node2D

## 天赋节点（世界空间）：图标 + 名字 + 价格，悬停/可购买高亮。
## 点击由控制器手动命中测试（本节点只提供 contains_point 判定）。

enum State { LOCKED, AVAILABLE, PURCHASED }

const HIT_SIZE := Vector2(90, 90)

var talent_id: StringName
var cost: int = 0
## 前置天赋 id：前置购买后本节点才显示
var prerequisite_id: StringName = &""
var state: State = State.LOCKED

var _hovered := false

@onready var icon_sprite: Sprite2D = $Icon
@onready var name_label: Label = $Name
@onready var cost_label: Label = $Cost


func setup(def: TalentDef) -> void:
	talent_id = def.id
	cost = def.cost
	prerequisite_id = def.prerequisite_id
	# setup 在 add_child 之前调用，@onready 还没赋值，直接用 get_node 解析
	name_label = $Name as Label
	cost_label = $Cost as Label
	icon_sprite = $Icon as Sprite2D
	name_label.text = def.display_name
	cost_label.text = _fmt(cost)
	if def.icon != null:
		icon_sprite.texture = def.icon


func set_state(s: State) -> void:
	state = s
	_apply_visual()


func set_hovered(h: bool) -> void:
	_hovered = h
	_apply_visual()


## 世界坐标是否落在本节点的命中矩形内（控制器点击/悬停用）
func contains_point(world_pos: Vector2) -> bool:
	return Rect2(global_position - HIT_SIZE * 0.5, HIT_SIZE).has_point(world_pos)


func _apply_visual() -> void:
	match state:
		State.PURCHASED:
			modulate = Color.WHITE
			cost_label.visible = false
		State.AVAILABLE:
			cost_label.visible = true
			modulate = Color(1.15, 1.15, 0.8) if _hovered else Color.WHITE
		State.LOCKED:
			cost_label.visible = true
			modulate = Color(0.6, 0.6, 0.6, 0.85)


## 金币缩写：1K / 1M / 1B / 1T / 1Qa / 1Qi
func _fmt(v: int) -> String:
	if v >= 1_000_000_000_000_000_000:
		return "%.1fQi" % (v / 1e18)
	if v >= 1_000_000_000_000_000:
		return "%.1fQa" % (v / 1e15)
	if v >= 1_000_000_000_000:
		return "%.1fT" % (v / 1e12)
	if v >= 1_000_000_000:
		return "%.1fB" % (v / 1e9)
	if v >= 1_000_000:
		return "%.1fM" % (v / 1e6)
	if v >= 1_000:
		return "%.1fK" % (v / 1e3)
	return str(v)
