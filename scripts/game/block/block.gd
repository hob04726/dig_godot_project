extends Node2D
class_name Block

@export var texture_to_show: Texture2D = null
@export var node_name: String = ""
@export var size_scale: float = 1.0

## 贴图基础缩放：新贴图 256x352 太大，统一乘这个系数
const TEXTURE_BASE_SCALE := 0.13

## 方块定义引用（null = 未走注册表的临时方块）
var def: BlockDef
## 所在格子坐标
var cell: Vector2i = Vector2i.ZERO
## 是否为"从天而降"生成（地皮为 false，直接 idle）
var starts_falling := true

@onready var sprite: Sprite2D = $Sprite2D
@onready var states: Node = $States

@onready var idle_state: BlockState = $States/Idle
@onready var shake_state: BlockState = $States/Shake
@onready var fall_state: BlockState = $States/Fall
@onready var float_state: BlockState = $States/Float

var current_state: BlockState


func _ready() -> void:
	setup_properties()
	setup_states()
	change_state(fall_state if starts_falling else idle_state)


## 由注册表定义初始化（在 add_child 之前调用，_ready 时才会用到贴图）
func setup_from_def(d: BlockDef, c: Vector2i) -> void:
	def = d
	cell = c
	if d != null:
		texture_to_show = d.get_texture(0)


func setup_properties() -> void:
	setup_name()
	setup_texture()


func setup_texture() -> void:
	sprite.texture = texture_to_show
	sprite.scale = Vector2.ONE * size_scale * TEXTURE_BASE_SCALE
	var particles: GPUParticles2D = $GPUParticles2D
	var atlas_texture := particles.texture as AtlasTexture

	if atlas_texture:
		atlas_texture = atlas_texture.duplicate()
		atlas_texture.atlas = texture_to_show
		particles.texture = atlas_texture


func setup_name() -> void:
	self.name = node_name


func setup_states() -> void:
	for child in states.get_children():
		if child is BlockState:
			child.context = self


func change_state(new_state: BlockState) -> void:
	if current_state == new_state:
		return

	if current_state != null:
		current_state.exit()

	current_state = new_state
	current_state.enter()


## 落地钩子：fall 动画结束进入 idle 时由状态机回调，子类可覆写
func on_landed() -> void:
	pass


## 受击反馈：空闲时进入 shake 状态（挖矿/被摧毁时用）
func hit() -> void:
	if current_state == idle_state:
		change_state(shake_state)


func set_hovered(hovered: bool) -> void:
	if hovered:
		if current_state == idle_state:
			change_state(float_state)
	elif current_state == float_state:
		change_state(idle_state)
