extends BlockState


func enter() -> void:
	context.animation_tree["parameters/conditions/float"] = true


func exit() -> void:
	context.animation_tree["parameters/conditions/float"] = false


func stop_float() -> void:
	context.change_state(context.idle_state)


func fall() -> void:
	context.change_state(context.fall_state)
