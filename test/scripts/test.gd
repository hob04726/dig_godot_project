extends Node2D

@onready var game_manager: GameManager = $World


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_C and event.pressed:
			print("手动生成一个随机矿石")
			game_manager.spawn_random_ore()
