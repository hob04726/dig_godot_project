extends Camera2D


@export var zoom_speed := 0.15
@export var zoom_smooth := 8.0

@export var min_zoom := 0.5
@export var max_zoom := 3.0


@export var pan_smooth := 10.0
@export var pan_speed := 1.0

var start_position := Vector2.ZERO
var start_zoom := Vector2.ONE

var target_zoom := Vector2.ONE
var target_position := Vector2.ZERO


var dragging := false


func _ready():

	start_position = position
	start_zoom = zoom
	target_zoom = zoom
	target_position = position



func _process(delta):

	# 平滑缩放
	zoom = zoom.lerp(
		target_zoom,
		zoom_smooth * delta
	)


	# 平滑移动
	position = position.lerp(
		target_position,
		pan_smooth * delta
	)



func _input(event):


	# 鼠标滚轮
	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(zoom_speed)


		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-zoom_speed)



		# 中键按下
		elif event.button_index == MOUSE_BUTTON_MIDDLE:

			dragging = event.pressed



	# 鼠标移动
	if event is InputEventMouseMotion:

		if dragging:
			move_camera(event.relative)



func change_zoom(value):

	target_zoom += Vector2(value,value)

	target_zoom.x = clamp(
		target_zoom.x,
		min_zoom,
		max_zoom
	)

	target_zoom.y = target_zoom.x



func move_camera(delta):

	target_position -= (
		delta *
		pan_speed /
		target_zoom.x
	)

func reset_camera():

	target_position = start_position
	target_zoom = start_zoom