extends BlockState

## 悬停浮动：进入时上移几个单位，退出时落回原处（不再循环晃动）


var _tween: Tween


func enter() -> void:
	var sprite := context.sprite
	if _tween:
		_tween.kill()
	_tween = context.create_tween()
	_tween.tween_property(sprite, "position:y", -6.0, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func exit() -> void:
	if _tween:
		_tween.kill()
	# 落回原位：tween 挂在 sprite 上，即使进入 idle 也不会被瞬间复位
	_tween = context.create_tween()
	_tween.tween_property(context.sprite, "position:y", 0.0, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
