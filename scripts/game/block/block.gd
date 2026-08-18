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


## 受击反馈：空闲时进入 shake 状态（挖矿/被摧毁时用）+ 短暂闪白
func hit() -> void:
	if current_state == idle_state:
		change_state(shake_state)
	_flash()


## 受击闪白材质（hit_flash.gdshader，每个 Block 一份：active 参数各自独立）
const HIT_FLASH_SHADER := preload("res://scripts/shaders/hit_flash.gdshader")
const HIT_FLASH_TIME := 0.08
var _flash_material: ShaderMaterial = null
var _flash_tween: Tween = null
var _flash_on := false
var _hovered := false


func _flash() -> void:
	if _flash_material == null:
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = HIT_FLASH_SHADER
	_flash_material.set_shader_parameter("active", true)
	_flash_on = true
	_refresh_sprite_material()
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()   # 绑定本节点：方块被销毁时 tween 自动失效
	_flash_tween.tween_interval(HIT_FLASH_TIME)
	_flash_tween.tween_callback(_end_flash)


func _end_flash() -> void:
	_flash_on = false
	_flash_material.set_shader_parameter("active", false)
	_refresh_sprite_material()


## 闪白与悬停描边共用 sprite.material 槽位：闪白优先，结束后恢复描边
func _refresh_sprite_material() -> void:
	if _flash_on:
		sprite.material = _flash_material
	elif _hovered:
		sprite.material = _get_outline_material()
	else:
		sprite.material = null


## 悬停描边材质（全体 Block 共享一份；thickness 单位是贴图像素，
## 贴图 256×352 × 显示缩放 0.13 → 8 ≈ 1 屏幕像素）
const OUTLINE_SHADER := preload("res://scripts/shaders/outline.gdshader")
const OUTLINE_THICKNESS := 8.0
static var _outline_material: ShaderMaterial = null


static func _get_outline_material() -> ShaderMaterial:
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter("thickness", OUTLINE_THICKNESS)
	return _outline_material


func set_hovered(hovered: bool, allow_float := true) -> void:
	# 悬停描边：挂/摘共享 outline 材质（矿和地块统一）；
	# allow_float=false 时只描边不漂浮（放置模式下悬停"有矿压着"的地块）
	_hovered = hovered
	_refresh_sprite_material()
	if not allow_float:
		return
	if hovered:
		if current_state == idle_state:
			change_state(float_state)
	elif current_state == float_state:
		change_state(idle_state)
