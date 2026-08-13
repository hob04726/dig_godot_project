extends BlockState


func enter() -> void:
	context.animation_tree["parameters/conditions/fall"] = true


func exit() -> void:
	context.animation_tree["parameters/conditions/fall"] = false


func landed() -> void:
	context.change_state(context.idle_state)


func float_block() -> void:
	context.change_state(context.float_state)


func animation_finished(anim_name: StringName) -> void:
	if anim_name == "fall":
		context.change_state(context.idle_state)
