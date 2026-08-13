extends Button


@export var camera: Camera2D


func _ready():
	pressed.connect(on_pressed)



func on_pressed():

	camera.reset_camera()
