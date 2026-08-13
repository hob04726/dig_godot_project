extends Node2D

@onready var game_manager: Node2D = $World


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_C and event.pressed:
			print("开始创建一个矿物")
			game_manager.grid.get_cell(game_manager.selected_block).set_block(true, BlockData.new(Vector2i(2, 1), 1))
