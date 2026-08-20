class_name TalentGridBorder
extends Node2D

## 天赋网格边框叠加层：随鼠标距离淡出的格子边框（"若隐若现，只在鼠标周围"）。
## 由 TalentGrid 创建并作为最后一个子节点挂上——子节点绘制在父节点之上，
## 所以边框画在所有天赋节点之上。坐标 = 世界坐标（受相机缩放/平移影响）。
## 每个格子画成圆角矩形框线（StyleBoxFlat 描边，draw_center=false 只画框）。
## 原版是 Control + GridContainer 时代（commit 53672c6），已适配当前 Node2D 世界。

@export var cell_size := Vector2(100, 100)
## 网格包围盒（col/row 矩形），由 TalentGrid 每次建树后同步
@export var grid_bounds := Rect2i()
@export var reveal_radius := 300.0     # 鼠标影响半径（世界单位）
@export var max_alpha := 0.9           # 鼠标紧贴格子时边框透明度
@export var border_color := Color(0.8, 0.9, 1.0)
@export var border_width := 1.0
@export var corner_radius := 28.0      # 每个格子框线的圆角半径（世界单位）

## 重置节点中心的圆形遮罩：越靠近中心透明度越低，避免格子框线盖住 reset 球。
@export var center_mask_enabled := true
@export var center_mask_position := Vector2.ZERO
@export var center_mask_radius := 140.0
@export var center_mask_feather := 0.35  # 0=硬边，越大边缘过渡越宽

var _stylebox: StyleBoxFlat = null


func _ready() -> void:
	# 圆角框线用 StyleBoxFlat 画：只描边不填心；颜色在 _draw 里按格子透明度逐格改
	_stylebox = StyleBoxFlat.new()
	_stylebox.draw_center = false
	_stylebox.set_border_width_all(maxi(1, int(border_width)))
	_stylebox.set_corner_radius_all(maxi(0, int(corner_radius)))
	_stylebox.border_color = border_color
	_stylebox.anti_aliasing = true


func _process(_delta: float) -> void:
	queue_redraw()


## 把鼠标 reveal 后的基础透明度再用中心遮罩压一下：越靠近 center_mask_position 越透明。
func _apply_center_mask(alpha: float, world_pos: Vector2) -> float:
	if not center_mask_enabled or center_mask_radius <= 0.0:
		return alpha
	var d := world_pos.distance_to(center_mask_position)
	if d >= center_mask_radius:
		return alpha
	# 在遮罩半径内：中心完全透明，边缘按 feather 柔和恢复
	var inner := center_mask_radius * (1.0 - center_mask_feather)
	var factor := clampf((d - inner) / (center_mask_radius - inner), 0.0, 1.0)
	return alpha * factor


func _draw() -> void:
	if _stylebox == null:
		return
	var mouse := get_local_mouse_position()

	# 鼠标影响范围（无限延伸），再与屏幕可视范围取交集，避免极端 reveal_radius 画爆
	var mouse_min := Vector2i(floor((mouse - Vector2(reveal_radius, reveal_radius)) / cell_size))
	var mouse_max := Vector2i(ceil((mouse + Vector2(reveal_radius, reveal_radius)) / cell_size))
	var visible := _get_visible_cell_rect()
	var min_cell := Vector2i(
		maxi(mouse_min.x, visible.position.x),
		maxi(mouse_min.y, visible.position.y)
	)
	var max_cell := Vector2i(
		mini(mouse_max.x, visible.end.x),
		mini(mouse_max.y, visible.end.y)
	)
	if min_cell.x > max_cell.x or min_cell.y > max_cell.y:
		return

	for c in range(min_cell.x, max_cell.x + 1):
		for r in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(c, r)
			var center := Vector2(cell) * cell_size
			var dist := mouse.distance_to(center)
			if dist > reveal_radius:
				continue              # 半径外：不画 = 透明 0
			var t := clampf(1.0 - dist / reveal_radius, 0.0, 1.0)
			var color := border_color
			color.a = _apply_center_mask(lerpf(0.0, max_alpha, t), center)
			if color.a <= 0.0:
				continue
			_stylebox.border_color = color   # 立即绘制，逐格改透明度安全
			draw_style_box(_stylebox, Rect2(center - cell_size * 0.5, cell_size))

	# 四个圆角框交汇处的空洞：精确填充"四条圆弧围成的曲边区域"本身，
	# 而不是菱形——填充边界与框线圆弧完全重合，交汇处保持圆润、不出现直边/平角。
	# 透明度沿用同一套鼠标距离衰减（按顶点到鼠标的距离算），并同样受中心遮罩影响。
	const ARC_STEPS := 8   # 每条圆弧的采样段数
	for c in range(min_cell.x, max_cell.x):
		for r in range(min_cell.y, max_cell.y):
			var vertex := Vector2(c, r) * cell_size + cell_size * 0.5
			var dist := mouse.distance_to(vertex)
			if dist > reveal_radius:
				continue
			var t := clampf(1.0 - dist / reveal_radius, 0.0, 1.0)
			var color := border_color
			color.a = _apply_center_mask(lerpf(0.0, max_alpha, t), vertex)
			if color.a <= 0.0:
				continue
			var rad := corner_radius
			# 四条弧的圆心 = 四个相邻格子各自的圆角圆心（顶点 ±rad 处）
			var arc_defs := [
				[Vector2(rad, rad), 180.0, 270.0],
				[Vector2(rad, -rad), 90.0, 180.0],
				[Vector2(-rad, -rad), 0.0, 90.0],
				[Vector2(-rad, rad), 270.0, 360.0],
			]
			var pts := PackedVector2Array()
			for arc in arc_defs:
				for s in ARC_STEPS + 1:
					var a := deg_to_rad(lerpf(arc[1], arc[2], float(s) / ARC_STEPS))
					pts.append(vertex + arc[0] + Vector2(cos(a), sin(a)) * rad)
			draw_colored_polygon(pts, color)


## 当前视口对应的格子索引范围（本地/世界坐标），用于裁剪无限网格
func _get_visible_cell_rect() -> Rect2i:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2i()
	var rect := viewport.get_visible_rect()
	# 视口矩形是屏幕像素坐标，需先通过 canvas transform 反变换到世界/本地坐标
	var inv := viewport.get_canvas_transform().affine_inverse()
	var top_left := to_local(inv * rect.position)
	var bottom_right := to_local(inv * rect.end)
	var min_cell := Vector2i(floor(top_left / cell_size))
	var max_cell := Vector2i(ceil(bottom_right / cell_size))
	return Rect2i(min_cell, max_cell - min_cell)
