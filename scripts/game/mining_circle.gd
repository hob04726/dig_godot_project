extends Node2D

## 空心圆指示器：用 _draw 精确画出作用范围，保证视觉半径和代码逻辑半径一致。

@export var radius := 24.0
@export var circle_color := Color.WHITE
@export var line_width := 2.0


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, circle_color, line_width, true)
