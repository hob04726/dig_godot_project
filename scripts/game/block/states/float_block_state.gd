extends BlockState

## 悬停浮动：上下轻晃（循环），退出时复位


var _tween: Tween


func enter() -> void:
	var sprite := context.sprite
	_tween = context.create_tween().set_loops()
	_tween.tween_property(sprite, "position:y", -3.0, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(sprite, "position:y", 0.0, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func exit() -> void:
	if _tween:
		_tween.kill()
	context.sprite.position.y = 0.0
