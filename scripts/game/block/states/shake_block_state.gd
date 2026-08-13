extends BlockState


func enter() -> void:
	context.animation_tree["parameters/conditions/shake"] = true


func exit() -> void:
	context.animation_tree["parameters/conditions/shake"] = false


func animation_finished(anim_name: StringName) -> void:
	context.change_state(context.idle_state)


func fall() -> void:
	context.change_state(context.fall_state)
