extends BlockState

## 静止态：不播放动画；进入时复位旋转/透明度。
## 位置不在这里硬复位——各状态自己收尾（漂浮退出时会"落回"，
## 若在此瞬间复位会把动画打断）。


func enter() -> void:
	var sprite := context.sprite
	sprite.rotation = 0.0
	sprite.modulate.a = 1.0
