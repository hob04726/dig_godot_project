extends BlockState


func enter() -> void:
	context.animation_tree["parameters/conditions/idle"] = true


func exit() -> void:
	context.animation_tree["parameters/conditions/idle"] = false


func get_hurt() -> void:
	context.change_state(context.shake_state)


func fall() -> void:
	context.change_state(context.fall_state)


func float_block() -> void:
	context.change_state(context.float_state)
