extends BlockState

## 受击摇晃：左右摆动几下再回正，播完回到 idle


var _tween: Tween


func enter() -> void:
	var sprite := context.sprite
	_tween = context.create_tween()
	_tween.tween_property(sprite, "rotation", deg_to_rad(5.0), 0.06)
	_tween.parallel().tween_property(sprite, "position:x", 1.0, 0.06)
	_tween.tween_property(sprite, "rotation", deg_to_rad(-5.0), 0.12)
	_tween.parallel().tween_property(sprite, "position:x", -1.0, 0.12)
	_tween.tween_property(sprite, "rotation", 0.0, 0.08)
	_tween.parallel().tween_property(sprite, "position:x", 0.0, 0.08)
	_tween.tween_callback(_shake_done)


func exit() -> void:
	if _tween:
		_tween.kill()


func _shake_done() -> void:
	context.change_state(context.idle_state)
