class_name TalentNode
extends Node2D

## 天赋节点（世界空间）：图标 + 名字 + 价格，悬停/可购买高亮。
## 点击由控制器手动命中测试（本节点只提供 contains_point 判定）。
## 数据来自 TalentDef（TalentDb 从 CSV 解析）。

enum State { LOCKED, AVAILABLE, PURCHASED }

const HIT_SIZE := Vector2(90, 90)

var talent_id: StringName
var display_name: String = ""
var description: String = ""
var currency: String = "金币"
var cost: BigNumber = null
var prerequisite_ids: Array[StringName] = []
var ascension_prerequisite_id: StringName = &""
var unlock_condition: String = ""
var state: State = State.LOCKED

var _hovered := false

@onready var icon_sprite: Sprite2D = $Icon
@onready var name_label: Label = $Name


func setup(def: TalentDef) -> void:
	talent_id = def.id
	display_name = def.display_name
	description = def.description
	currency = def.currency
	cost = def.cost
	prerequisite_ids = def.prerequisite_ids.duplicate()
	ascension_prerequisite_id = def.ascension_prerequisite_id
	unlock_condition = def.unlock_condition
	# setup 在 add_child 之前调用，@onready 还没赋值，直接用 get_node 解析
	name_label = $Name as Label
	icon_sprite = $Icon as Sprite2D
	name_label.text = def.display_name
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
		State.AVAILABLE:
			modulate = Color(1.15, 1.15, 0.8) if _hovered else Color.WHITE
		State.LOCKED:
			modulate = Color(0.6, 0.6, 0.6, 0.85)
