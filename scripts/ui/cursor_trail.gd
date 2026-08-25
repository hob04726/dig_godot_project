extends Node2D
class_name CursorTrail

## 挖矿时鼠标光标拖尾：白色 → 后半段渐黑，起点粗、终点细。
## 调用方每帧把光标世界坐标喂进来；不挖矿时 clear() 清空。

## 拖尾最大点数（长度）
@export var trail_length := 20
## 头部（靠近光标）最大宽度
@export var head_width := 10.0
## 是否记录位置（供预览调参）
@export var preview_track_mouse := false
## 绘制层级
@export var line_z_index := 4000

var _points: Array[Vector2] = []
var _line: Line2D = null
var _gradient := Gradient.new()
var _width_curve := Curve.new()
var _enabled := false


func _ready() -> void:
	_line = get_node_or_null("Line2D") as Line2D
	if _line == null:
		_line = Line2D.new()
		_line.name = "Line2D"
		add_child(_line)
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.z_index = line_z_index
	_setup_style()


func _process(_delta: float) -> void:
	if preview_track_mouse:
		add_position(get_global_mouse_position())


## 开始/停止记录。停止时立即清空拖尾。
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		clear()


## 喂入一个头部位置（世界/屏幕坐标），追加到拖尾并裁掉旧点
func add_position(pos: Vector2) -> void:
	if not _enabled and not preview_track_mouse:
		return
	_points.append(to_local(pos))
	if _points.size() > trail_length:
		_points.pop_front()
	_update_line()


## 清空拖尾
func clear() -> void:
	_points.clear()
	_update_line()


func _setup_style() -> void:
	# 颜色：头部（offset 1）纯白；中段（0.5）仍白；尾段后半（0→0.5）渐黑
	_gradient.colors = PackedColorArray([
		Color.BLACK,
		Color.BLACK,
		Color.WHITE,
		Color.WHITE,
	])
	_gradient.offsets = PackedFloat32Array([0.0, 0.5, 0.5, 1.0])
	_line.gradient = _gradient
	_line.width = head_width
	# 宽度：尾部（offset 0）细到 0，头部（offset 1）全宽
	_width_curve.clear_points()
	_width_curve.add_point(Vector2(0.0, 0.0))
	_width_curve.add_point(Vector2(1.0, 1.0))
	_line.width_curve = _width_curve


func _update_line() -> void:
	_line.points = PackedVector2Array(_points)
