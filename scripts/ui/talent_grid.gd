extends Control
## 天赋网格边框：填充 GridContainer 的占位格子 + 绘制随鼠标距离淡出的格子边框。
## 挂在一个"叠加层"节点上：它必须排在 ColorRect / GridContainer 之后（树里靠后），
## 这样边框才会画在背景之上（Godot 里子节点绘制在父节点之上）。

@export var grid: GridContainer = null     # 拖入 GridContainer
@export var columns := 10
@export var cell_count := 100              # 占位格子数量（预览用）
@export var cell_min_size := Vector2(40, 40)
@export var reveal_radius := 300.0         # 鼠标影响半径（像素）
@export var max_alpha := 0.9               # 鼠标紧贴格子时边框透明度
@export var border_color := Color(1, 1, 1)
@export var border_width := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 别挡鼠标
	# 兜底：导出没解析到就从父节点（Talent）找 GridContainer
	if grid == null:
		grid = get_parent().get_node_or_null("GridContainer") as GridContainer
	if grid == null:
		push_warning("talent_grid: 找不到 GridContainer")
		return
	grid.columns = columns
	for i in cell_count:
		var cell := Control.new()
		cell.custom_minimum_size = cell_min_size
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	var mouse := get_global_mouse_position()
	var my_pos := get_global_rect().position
	for child in grid.get_children():
		if child is not Control:
			continue
		var cell := child as Control
		var cell_rect := cell.get_global_rect()
		cell_rect.position -= my_pos          # 转成叠加层局部坐标
		var dist := mouse.distance_to(cell.get_global_rect().get_center())
		if dist > reveal_radius:
			continue                          # 半径外：不画 = 透明 0
		var t := clampf(1.0 - dist / reveal_radius, 0.0, 1.0)
		var color := border_color
		color.a = lerpf(0.0, max_alpha, t)
		draw_rect(cell_rect, color, false, border_width)
