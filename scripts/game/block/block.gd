extends Node
class_name Block

@export var texture_to_show: Texture2D = null
@export var node_name: String = ""
@export var size_scale: float = 1.0

## 方块定义引用（null = 未走注册表的临时方块）
var def: BlockDef
## 所在格子坐标
var cell: Vector2i = Vector2i.ZERO

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var states: Node = $States

@onready var idle_state: BlockState = $States/Idle
@onready var shake_state: BlockState = $States/Shake
@onready var fall_state: BlockState = $States/Fall
@onready var float_state: BlockState = $States/Float

var current_state: BlockState

var animation_playback: AnimationNodeStateMachinePlayback


func _ready() -> void:
	setup_properties()
	setup_states()
	setup_animation()
	animation_tree.animation_finished.connect(_on_animation_finished)

	change_state(fall_state)


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
	self.get_node("Sprite2D").texture = texture_to_show
	self.get_node("Sprite2D").scale = Vector2.ONE * size_scale
	var particles: GPUParticles2D = self.get_node("GPUParticles2D")
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


func setup_animation() -> void:
	animation_tree.active = true
	animation_playback = animation_tree["parameters/playback"]


func _on_animation_finished(anim_name: StringName) -> void:
	if current_state != null:
		current_state.animation_finished(anim_name)


func set_hovered(hovered: bool) -> void:
	if hovered:
		if current_state == idle_state:
			change_state(float_state)
	elif current_state == float_state:
		change_state(idle_state)
