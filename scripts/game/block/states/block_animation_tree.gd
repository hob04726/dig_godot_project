extends AnimationTree


func set_condition(condition: StringName, value: bool) -> void:
	set("parameters/condition/%s" % condition, value)


func enable_condition(condition: StringName):
	set_condition(condition, true)


func disable_condition(condition: StringName):
	set_condition(condition, false)
