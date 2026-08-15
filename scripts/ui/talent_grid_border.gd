class_name TalentGridBorder
extends Node2D

## 天赋网格边框叠加层：随鼠标距离淡出的格子边框（"若隐若现，只在鼠标周围"）。
## 由 TalentGrid 创建并作为最后一个子节点挂上——子节点绘制在父节点之上，
## 所以边框画在所有天赋节点之上。坐标 = 世界坐标（受相机缩放/平移影响）。
## 原版是 Control + GridContainer 时代（commit 53672c6），已适配当前 Node2D 世界。

@export var cell_size := Vector2(100, 100)
## 网格包围盒（col/row 矩形），由 TalentGrid 每次建树后同步
@export var grid_bounds := Rect2i()
@export var reveal_radius := 300.0     # 鼠标影响半径（世界单位）
@export var max_alpha := 0.9           # 鼠标紧贴格子时边框透明度
@export var border_color := Color(0.8, 0.9, 1.0)
@export var border_width := 1.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if grid_bounds.size == Vector2i.ZERO:
		return
	var mouse := get_local_mouse_position()
	for c in grid_bounds.size.x:
		for r in grid_bounds.size.y:
			var cell := Vector2i(grid_bounds.position.x + c, grid_bounds.position.y + r)
			var center := Vector2(cell) * cell_size
			var dist := mouse.distance_to(center)
			if dist > reveal_radius:
				continue              # 半径外：不画 = 透明 0
			var t := clampf(1.0 - dist / reveal_radius, 0.0, 1.0)
			var color := border_color
			color.a = lerpf(0.0, max_alpha, t)
			draw_rect(Rect2(center - cell_size * 0.5, cell_size), color, false, border_width)
