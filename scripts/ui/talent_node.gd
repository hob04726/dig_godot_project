class_name TalentNode
extends Node2D

## 天赋节点（世界空间）：图标 + 状态视觉 + 动画。
## 状态：LOCKED（0.3 透明度 0.7）→ AVAILABLE（0.6 透明度 0.8）→ PURCHASED（1.0）。
## 悬停：平滑放大到 1.15、透明度变 1、图标挂白色描边（outline.gdshader，共享材质）。
## 购买：0.75 下蹲 → 1.4 爆发（+瞬间提亮）→ 弹性回稳（squash & stretch）；新揭示（前置刚买，可买/买不起都算）：0 → base+0.3 → base（弹跳出现）+ 透明度淡入。
## 买不起 → 买得起（节点本就在屏上）：尺寸/透明度平滑过渡，不弹跳。
## AVAILABLE 期间每隔 2~4.5 秒轻轻摇晃一下（吸引注意；「重置·升华」除外）。

enum State { LOCKED, AVAILABLE, PURCHASED }

const HIT_SIZE := Vector2(90, 90)
const BASE_SCALE := 0.8        # AVAILABLE 的基础尺寸
const LOCKED_SCALE := 0.7      # LOCKED 的基础尺寸（更小，凸显未解锁）
const HOVER_SCALE := 1.15
const PURCHASED_SCALE := 1.0
const LOCKED_ALPHA := 0.3
const AVAILABLE_ALPHA := 0.6
## 购买弹跳（squash & stretch）：下蹲蓄力 → 爆发过冲+提亮 → 弹性回稳。
## REVEAL_DELAY：从点击到揭示新节点的延迟（卡在爆发高点，节奏最爽）；
## PURCHASE_POP_TIME：总时长（下蹲 0.08 + 爆发 0.16 + 回稳 0.45）。
const PURCHASE_SQUASH := 0.75
const PURCHASE_SQUASH_TIME := 0.08
const PURCHASE_BURST := 1.4
const PURCHASE_BURST_TIME := 0.16
const PURCHASE_SETTLE_TIME := 0.45
const PURCHASE_FLASH := 1.8    # 爆发瞬间提亮倍数（modulate > 1 增亮）
const PURCHASE_WOBBLE := 0.18  # 爆发时左右摇晃幅度（弧度）
const REVEAL_DELAY := 0.28
const PURCHASE_POP_TIME := PURCHASE_SQUASH_TIME + PURCHASE_BURST_TIME + PURCHASE_SETTLE_TIME
## AVAILABLE 待机摇晃：间隔随机区间（秒）+ 单次摇晃时长
const WIGGLE_INTERVAL_MIN := 2.0
const WIGGLE_INTERVAL_MAX := 4.5
const WIGGLE_TIME := 0.36
## 悬停描边（outline.gdshader）：同款描边 shader，但天赋场景背景是浅粉色
## （Color(1, 0.867, 1)）+ 图标本身是白色系，白色描边会完全隐形，
## 所以用金黄色描边（在粉底上对比强烈、也契合"天赋=珍贵"的语义）。
## thickness 单位是贴图像素：图标 10×12 × 精灵缩放 4 → 0.5 ≈ 1.6 屏幕像素
const OUTLINE_SHADER := preload("res://scripts/shaders/outline.gdshader")
const OUTLINE_THICKNESS := 0.5
const OUTLINE_RING_COUNT := 16
const OUTLINE_COLOR := Color(1.0, 0.82, 0.15)

## 全体节点共享的描边材质（懒加载）；烘焙贴图缓存：源贴图 → ImageTexture
static var _outline_material: ShaderMaterial = null
static var _baked_icon_cache: Dictionary = {}

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
var _wiggle_timer: Timer = null

@onready var icon_sprite: Sprite2D = $Icon


func _ready() -> void:
	# AVAILABLE 待机摇晃计时器（每次超时后摇晃一次并按随机间隔重新计时）
	_wiggle_timer = Timer.new()
	_wiggle_timer.one_shot = true
	add_child(_wiggle_timer)
	_wiggle_timer.timeout.connect(_on_wiggle_timeout)
	_bake_icon()   # 兜底：setup() 未被调用时场景默认贴图也烘焙


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
	_bake_icon()
	scale = Vector2.ONE * _base_scale()   # 初始 state=LOCKED → 0.7


## 悬停描边前置：outline.gdshader 的 border_clipping_fix 假定 UV∈[0,1]，
## AtlasTexture 的区域 UV 不满足（顶点外扩方向会错），所以把图标烘焙成独立
## ImageTexture；同一源贴图（204 个节点共用同一张图集区域）只烘一次。
func _bake_icon() -> void:
	var tex := icon_sprite.texture
	if tex == null or tex is ImageTexture:
		return
	if _baked_icon_cache.has(tex):
		icon_sprite.texture = _baked_icon_cache[tex]
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	var baked := ImageTexture.create_from_image(img)
	_baked_icon_cache[tex] = baked
	icon_sprite.texture = baked


static func _get_outline_material() -> ShaderMaterial:
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter("thickness", OUTLINE_THICKNESS)
		_outline_material.set_shader_parameter("ring_count", OUTLINE_RING_COUNT)
		_outline_material.set_shader_parameter("outline_color", OUTLINE_COLOR)
	return _outline_material


## just_revealed：本帧刚从隐藏揭示出来（前置刚买）→ 播 0→base+0.3→base 弹跳（LOCKED/AVAILABLE 通用）；
## 否则 LOCKED↔AVAILABLE（买得起/买不起的变化）走平滑过渡。
func set_state(s: State, animated := true, just_revealed := false) -> void:
	var prev := state
	state = s
	_update_wiggle_loop()
	if not animated:
		_kill_scale_tween()
		scale = Vector2.ONE * _desired_scale()
		if not _hovered:
			modulate.a = _desired_alpha()
		return
	if s == State.PURCHASED and prev != State.PURCHASED:
		if not _hovered:
			modulate.a = _desired_alpha()
		_play_purchase_pop()
	elif just_revealed:
		# 新揭示（前置刚买）：可买 / 买不起都播弹跳出现，
		# 否则 LOCKED 节点会因 s==prev 跳过所有分支而"凭空出现"
		_play_reveal_pop()
	elif s != prev:
		# 买得起 ↔ 买不起（节点已在屏上）：尺寸/透明度平滑过渡
		if not _hovered:
			_tween_alpha(_desired_alpha(), 0.25)
		_tween_scale(_desired_scale(), 0.25)


func set_hovered(h: bool) -> void:
	if _hovered == h:
		return
	_hovered = h
	# 悬停描边：挂上共享描边材质（白色外边框），离开摘掉
	icon_sprite.material = _get_outline_material() if h else null
	_tween_scale(_desired_scale(), 0.15)
	_tween_alpha(_desired_alpha(), 0.12)


## 世界坐标是否落在本节点的命中矩形内（控制器点击/悬停用）
func contains_point(world_pos: Vector2) -> bool:
	return Rect2(global_position - HIT_SIZE * 0.5, HIT_SIZE).has_point(world_pos)


# ==================== 视觉 ====================

func _base_scale() -> float:
	match state:
		State.PURCHASED: return PURCHASED_SCALE
		State.LOCKED: return LOCKED_SCALE
	return BASE_SCALE


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


## 购买后：下蹲蓄力 → 爆发过冲到 1.4（同时瞬间提亮）→ 弹性回稳（果冻感）
func _play_purchase_pop() -> void:
	_kill_scale_tween()
	var settle := _desired_scale()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * PURCHASE_SQUASH, PURCHASE_SQUASH_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * PURCHASE_BURST, PURCHASE_BURST_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * settle, PURCHASE_SETTLE_TIME) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 爆发瞬间提亮再回落（modulate > 1 的增亮闪光，ALPHA 保持当前值）
	if _flash_bright_tween and _flash_bright_tween.is_valid():
		_flash_bright_tween.kill()
	_flash_bright_tween = create_tween()
	_flash_bright_tween.tween_interval(PURCHASE_SQUASH_TIME)
	_flash_bright_tween.tween_callback(_set_bright.bind(PURCHASE_FLASH))
	_flash_bright_tween.tween_method(_set_bright, PURCHASE_FLASH, 1.0, 0.3)
	# 爆发时左右摇晃（与缩放并行）：+ → - → + → 回正
	if _rot_tween and _rot_tween.is_valid():
		_rot_tween.kill()
	rotation = 0.0
	_rot_tween = create_tween()
	_rot_tween.tween_interval(PURCHASE_SQUASH_TIME)
	_rot_tween.tween_property(self, "rotation", PURCHASE_WOBBLE, 0.09) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_rot_tween.tween_property(self, "rotation", -PURCHASE_WOBBLE, 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_rot_tween.tween_property(self, "rotation", PURCHASE_WOBBLE * 0.5, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_rot_tween.tween_property(self, "rotation", 0.0, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


var _rot_tween: Tween = null


func _set_bright(f: float) -> void:
	modulate = Color(f, f, f, modulate.a)


var _flash_bright_tween: Tween = null


## 新揭示（前置刚买）：0 → base+0.3 → base（弹跳出现），透明度同时从 0 淡入。
## settle 用 _desired_scale()，LOCKED（0.7）和 AVAILABLE（0.8）都适配。
func _play_reveal_pop() -> void:
	_kill_scale_tween()
	scale = Vector2.ZERO
	var settle := _desired_scale()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector2.ONE * (settle + 0.3), 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * settle, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _hovered:
		modulate.a = 0.0
		_tween_alpha(_desired_alpha(), 0.2)


# ==================== 待机摇晃 ====================

func _update_wiggle_loop() -> void:
	if _wiggle_timer == null:
		return
	if state == State.AVAILABLE and effect_type != "PRESTIGE_RESET":   # 重置·升华不摇
		# 初始延迟随机化，避免同批揭示的节点齐摇
		_wiggle_timer.start(randf_range(WIGGLE_INTERVAL_MIN, WIGGLE_INTERVAL_MAX))
	else:
		_wiggle_timer.stop()
		rotation = 0.0


func _on_wiggle_timeout() -> void:
	if state != State.AVAILABLE or effect_type == "PRESTIGE_RESET":
		return
	_play_wiggle()
	_wiggle_timer.start(randf_range(WIGGLE_INTERVAL_MIN, WIGGLE_INTERVAL_MAX))


## 轻轻摇晃：右转 → 左转 → 回正（旋转与缩放 tween 互不干扰）
func _play_wiggle() -> void:
	var t := create_tween()
	t.tween_property(self, "rotation", 0.09, 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "rotation", -0.09, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "rotation", 0.04, 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "rotation", 0.0, 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
