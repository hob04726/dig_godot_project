extends BlockState

## 静止态：不播放动画；进入时把精灵的动画偏移复位，保证干净基态


func enter() -> void:
	var sprite := context.sprite
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.modulate.a = 1.0
