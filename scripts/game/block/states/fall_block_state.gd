extends BlockState

## 从天而降：淡入 + 从上方落下，落地时左右晃动一下，播完回到 idle 并回调 on_landed


var _tween: Tween


func enter() -> void:
	var sprite := context.sprite
	sprite.rotation = 0.0
	sprite.modulate.a = 0.0

	_tween = context.create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(sprite, "position", Vector2.ZERO, 1.0) \
		.from(Vector2(0, -50)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(sprite, "modulate:a", 1.0, 0.96)
	_tween.set_parallel(false)
	# 落地：左右晃两下（不旋转）
	_tween.tween_property(sprite, "position:x", -1.0, 0.1)
	_tween.tween_property(sprite, "position:x", 1.0, 0.1)
	_tween.tween_property(sprite, "position:x", 0.0, 0.1)
	_tween.tween_callback(_fall_done)


func exit() -> void:
	if _tween:
		_tween.kill()


func _fall_done() -> void:
	context.change_state(context.idle_state)
	context.on_landed()
