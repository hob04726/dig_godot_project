extends Node
class_name Block

@export var texture_to_show: Texture2D = null
@export var node_name: String = ""

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


func setup_properties() -> void:
	setup_name()
	setup_texture()


func setup_texture() -> void:
	self.get_node("Sprite2D").texture = texture_to_show
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
