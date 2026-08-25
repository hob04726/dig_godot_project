extends Node2D

## 拖尾：静态锚点 + 喂位置。本节点不移动（停在原点），Line2D 自锚定画在节点局部
## （= 世界/屏幕坐标）。调用方每帧把"飞行头位置"喂进来 add_position(pos)，
## 画一条渐隐的半透明黄色方线。预览模式 preview_track_mouse 自动跟随鼠标。
## 粗细 = width，长度 = trail_length；参数都在 Inspector 可调。

@export var color := Color(1.0, 0.85, 0.15, 1.0)   # 黄色
@export var trail_length := 14                      # 保留点数（拖尾长度）
@export var width := 6.0                            # 线宽（粗细）
@export var max_alpha := 0.6                        # 头部最不透明（半透明黄）
@export var taper := true                           # 尾部是否收细
@export var record_interval := 1                    # 预览时每 N 帧记录一个点
@export var line_z_index := 4000                    # 线的叠放
@export var preview_track_mouse := false            # 预览调参：自动跟随鼠标记录

var _points: Array[Vector2] = []
var _line: Line2D = null
var _gradient := Gradient.new()
var _width_curve := Curve.new()
var _frame := 0


func _ready() -> void:
	# Line2D 自锚定（本节点不移动，点在局部 = 世界/屏幕坐标）。
	# 优先用场景里预置的 Line2D 子节点（编辑器里可见），缺失则运行时创建兜底。
	_line = get_node_or_null("Line2D") as Line2D
	if _line == null:
		_line = Line2D.new()
		_line.name = "Line2D"
		add_child(_line)
	# 方线：方形端点 + 尖角接头（不是圆头）
	_line.begin_cap_mode = Line2D.LINE_CAP_BOX
	_line.end_cap_mode = Line2D.LINE_CAP_BOX
	_line.joint_mode = Line2D.LINE_JOINT_SHARP
	_line.z_index = line_z_index
	_setup_style()


func _process(_delta: float) -> void:
	_frame += 1
	if preview_track_mouse and _frame % record_interval == 0:
		add_position(get_global_mouse_position())


## 喂入一个头部位置（世界/屏幕坐标），追加到拖尾并裁掉旧点
func add_position(pos: Vector2) -> void:
	_points.append(pos)
	if _points.size() > trail_length:
		_points.pop_front()
	_update_line()


## 整条线透明度（GameManager 控制汇聚到计数板后的渐隐）
func set_alpha(a: float) -> void:
	if _line != null:
		_line.modulate.a = clampf(a, 0.0, 1.0)


func get_alpha() -> float:
	return _line.modulate.a if _line != null else 1.0


## 样式：颜色大部分保持不透明，只在很末尾（offset≈0.15）才渐隐到 0；宽度同样末尾收细
func _setup_style() -> void:
	_gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, max_alpha),
		Color(color.r, color.g, color.b, max_alpha),
	])
	_gradient.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	_line.gradient = _gradient
	_line.width = width
	if taper:
		_width_curve.add_point(Vector2(0.0, 0.0))    # 尾部收细到 0
		_width_curve.add_point(Vector2(0.15, 1.0))   # 快速回到全宽
		_width_curve.add_point(Vector2(1.0, 1.0))    # 之后保持全宽
		_line.width_curve = _width_curve


func _update_line() -> void:
	_line.points = PackedVector2Array(_points)


## 清空拖尾
func clear() -> void:
	_points.clear()
	_update_line()
