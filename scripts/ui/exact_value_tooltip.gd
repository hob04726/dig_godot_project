class_name ExactValueTooltip
extends Node

## 悬浮显示精确数值：鼠标悬浮在父面板上时，在鼠标下方跟随显示完整数字
## （白字黑描边）。标签建在面板所在的 CanvasLayer 上，不受面板布局/裁剪约束。
## 用法：ExactValueTooltip.attach(面板, func() -> String: return 数值文本)

const FONT_SIZE := 20
const OUTLINE_SIZE := 6
const OFFSET := Vector2(0, 24)   # 鼠标下方偏移
const EDGE_PAD := 4.0            # 夹取屏幕时的边距

var _panel: PanelContainer = null
var _get_text: Callable
var _label: RichTextLabel = null


static func attach(panel: PanelContainer, get_text: Callable) -> ExactValueTooltip:
	var tip := ExactValueTooltip.new()
	tip._panel = panel
	tip._get_text = get_text
	panel.add_child(tip)
	return tip


func _ready() -> void:
	if _panel == null:
		_panel = get_parent() as PanelContainer
	if _panel == null:
		push_warning("exact_value_tooltip: 父节点不是 PanelContainer")
		return
	# attach 发生在场景装配期（GameManager._ready），此时往 CanvasLayer 加子节点会失败 → 推迟
	call_deferred("_setup_label")


func _setup_label() -> void:
	_label = RichTextLabel.new()
	_label.name = "ExactValueTooltipLabel"
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.clip_contents = false   # 描边画在字形外扩区域，裁剪会吃掉最左/最右字符的描边
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 特效不挡鼠标
	_label.z_index = 4096
	_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_label.add_theme_color_override("default_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	_label.visible = false
	_panel.get_parent().add_child(_label)   # 面板的父节点（CanvasLayer），屏幕空间跟随


## 每帧轮询面板矩形是否包含鼠标——比 mouse_entered/exited 可靠
## （面板里有子按钮时 enter/exit 不会按预期成对触发）
func _process(_delta: float) -> void:
	if _panel == null or _label == null:
		return
	var hovering := _panel.get_global_rect().has_point(_panel.get_global_mouse_position())
	if hovering != _label.visible:
		_label.visible = hovering
	if hovering:
		_label.text = _get_text.call()
		_label.reset_size()   # 内容变了先重排，居中/夹取才准
		var pos := _panel.get_global_mouse_position() + OFFSET - Vector2(_label.size.x * 0.5, 0)
		var vp := _panel.get_viewport_rect().size
		# 夹取边距要算上描边外扩（clip_contents=false 后描边会画出 size 之外），
		# 且数字超长时用 maxf 兜底防止 clamp 区间反转把标签甩出屏幕
		var margin := EDGE_PAD + OUTLINE_SIZE
		pos.x = clampf(pos.x, margin, maxf(margin, vp.x - _label.size.x - margin))
		pos.y = clampf(pos.y, margin, maxf(margin, vp.y - _label.size.y - margin))
		_label.position = pos
