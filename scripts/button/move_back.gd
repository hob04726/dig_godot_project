extends Button


@export var camera: Camera2D

const FLAVOR_LABEL_SCENE := preload("res://scenes/ui/flavor_text_label.tscn")

## 悬浮在按钮下方显示的世界名标签
var _name_label: Label = null
## 世界名下方滚动显示的风味语句
var _flavor_label: FlavorTextLabel = null
var _gm: Node = null


func _ready():
	pressed.connect(on_pressed)
	_setup_tooltip()


func on_pressed():
	camera.reset_camera()


func _setup_tooltip() -> void:
	# 通过 camera 找到 GameManager（camera 的父节点就是 World/GameManager）
	if camera != null:
		_gm = camera.get_parent()

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.2, 1.0))
	_name_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 1.0))
	_name_label.add_theme_constant_override("outline_size", 4)
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.visible = false
	add_child(_name_label)

	_flavor_label = FLAVOR_LABEL_SCENE.instantiate() as FlavorTextLabel
	_flavor_label.visible = false
	add_child(_flavor_label)
	if _gm != null:
		_flavor_label.setup(_gm)

	_update_tooltip_text()
	resized.connect(_position_tooltip)
	_name_label.resized.connect(_position_tooltip)
	mouse_entered.connect(_show_tooltip)
	mouse_exited.connect(_hide_tooltip)
	if _gm != null:
		var state = _gm.state
		if state != null and state.has_signal("changed"):
			state.changed.connect(_update_tooltip_text)


func _update_tooltip_text() -> void:
	if _name_label == null or _gm == null:
		return
	var state = _gm.state
	if state == null:
		return
	_name_label.text = state.world_name
	_position_tooltip()


func _show_tooltip() -> void:
	if _name_label != null:
		_name_label.visible = true
	if _flavor_label != null:
		_flavor_label.visible = true
	_position_tooltip()


func _hide_tooltip() -> void:
	if _name_label != null:
		_name_label.visible = false
	if _flavor_label != null:
		_flavor_label.visible = false


func _position_tooltip() -> void:
	if _name_label == null:
		return
	_name_label.position = Vector2((size.x - _name_label.size.x) * 0.5, size.y + 4.0)
	if _flavor_label != null:
		_flavor_label.position = Vector2(
			(size.x - _flavor_label.size.x) * 0.5,
			_name_label.position.y + _name_label.size.y + 2.0)
