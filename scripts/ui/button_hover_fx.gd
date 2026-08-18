extends Node
class_name ButtonHoverFX

## 挂到 BaseButton 或 PanelContainer（如金币计数板、设置菜单的按钮面板）之下：
##   悬浮 → 目标平滑放大；离开 → 平滑恢复；按下 → 目标左右摇晃一下。
## 两种挂法：
##   父节点是 PanelContainer → 效果直接做在面板本体上，只缩放/摇晃，
##     不克隆 stylebox、不挂材质、不加任何额外东西（面板内按钮的 pressed 也会触发摇晃）；
##   父节点是 BaseButton → 按钮被单个 PanelContainer 包着 → 效果作用于那个面板
##     （克隆 StyleBox 挂描边材质，白色描边淡入）；纯图标按钮 → 作用于按钮自身
##     （描边画在烘焙后的 icon 上）；否则只缩放/摇晃。
## 描边为了让 outline shader 的 UV∈[0,1] 假设成立：
##   AtlasTexture 烘焙成独立 ImageTexture；面板的 StyleBox 克隆一份并把
##   texture_margin 清零（9-patch 会拆成 9 个绘制命令，逐块 UV 会让顶点外扩算错）。

const OUTLINE_SHADER := preload("res://scripts/shaders/outline.gdshader")   # 画本体+外沿（材质直接挂在目标上）

@export var hover_scale := 1.08
## 指数跟随速率（帧率无关）：值越大越跟手。放大快、回放慢，手感更「沉」
@export var grow_speed := 14.0
@export var revert_speed := 8.0
@export var outline_thickness := 2.0
@export var outline_ring_count := 8
@export var outline_color := Color.WHITE
@export var wiggle_angle := 5.0    # 按下摇晃的最大摆角（度）

var _target: Control = null        # 被做效果的控件（面板或按钮自身）
var _material: ShaderMaterial = null
var _hover01 := 0.0                # 悬浮程度 0..1，每帧指数平滑逼近目标，方向反转零突变
var _wiggle_tween: Tween = null
static var _bake_cache: Dictionary = {}   # 源贴图 instance_id → 烘焙 ImageTexture


func _ready() -> void:
	# 场景搭建期间不能动父链资源（克隆 stylebox / 替换 icon），推迟到搭建完成
	_setup.call_deferred()


func _setup() -> void:
	var parent := get_parent()
	if parent is BaseButton:
		var btn := parent as BaseButton
		btn.mouse_entered.connect(_set_hovered.bind(true))
		btn.mouse_exited.connect(_set_hovered.bind(false))
		btn.pressed.connect(_play_wiggle)
		var wrapper := btn.get_parent() as PanelContainer
		if wrapper != null and wrapper.get_child_count() == 1:
			_target = wrapper
			_attach_panel_outline(wrapper)
		elif btn is Button and (btn as Button).icon != null:
			_target = btn
			(btn as Button).icon = _bake((btn as Button).icon)
			_attach_material(btn)
		else:
			_target = btn   # 无图标无面板：只缩放/摇晃
	elif parent is PanelContainer:
		# 面板直连：只做缩放/摇晃，不动 stylebox、不加材质（用户要求不加额外东西）
		var panel := parent as PanelContainer
		_target = panel
		panel.mouse_entered.connect(_hover_delta.bind(1))
		panel.mouse_exited.connect(_hover_delta.bind(-1))
		panel.gui_input.connect(_on_panel_gui_input)
		for child in panel.get_children():
			# mouse_entered 只发给最上层控件：悬浮到面板内的按钮上时面板收不到，
			# 把子按钮的悬浮/按下也并进来（计数器防止 面板→按钮 移动时闪烁）
			if child is BaseButton:
				(child as BaseButton).mouse_entered.connect(_hover_delta.bind(1))
				(child as BaseButton).mouse_exited.connect(_hover_delta.bind(-1))
				(child as BaseButton).pressed.connect(_play_wiggle)
	else:
		push_warning("ButtonHoverFX: 父节点不是按钮或面板")
		queue_free()
		return
	_target.resized.connect(_on_target_resized)
	_on_target_resized()


func _on_target_resized() -> void:
	_target.pivot_offset = _target.size * 0.5   # 中心支点，四向均匀放大/摇晃


## 面板被点击（PanelContainer 没有 pressed 信号，走 gui_input）
func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_wiggle()


# ==================== 悬浮：缩放 + 描边（指数平滑跟随，不用 tween） ====================
## 为什么不用 tween：悬浮状态被鼠标快速切换时，「杀 tween 重启」会让初速度突变，
## 看起来一顿一顿；指数跟随每帧只按当前差距补速度，方向怎么反转都丝滑。

var _hover_count := 0    # 面板模式下：自身 + 子按钮的悬浮计数
var _hovered := false

func _hover_delta(d: int) -> void:
	_hover_count = maxi(0, _hover_count + d)
	_set_hovered(_hover_count > 0)


func _set_hovered(h: bool) -> void:
	_hovered = h


func _process(delta: float) -> void:
	if _target == null:
		return
	var goal := 1.0 if _hovered else 0.0
	if is_equal_approx(_hover01, goal):
		if _hover01 != goal:   # 吸附到端点，避免永远差一丝
			_apply_hover(goal)
		return
	var speed := grow_speed if _hovered else revert_speed
	_apply_hover(lerpf(_hover01, goal, 1.0 - exp(-speed * delta)))


func _apply_hover(v: float) -> void:
	_hover01 = clampf(v, 0.0, 1.0)
	_target.scale = Vector2.ONE * lerpf(1.0, hover_scale, _hover01)
	if _material != null:
		var c := outline_color
		c.a = _hover01
		_material.set_shader_parameter("outline_color", c)


# ==================== 按下：左右摇晃 ====================

func _play_wiggle() -> void:
	if _wiggle_tween and _wiggle_tween.is_valid():
		_wiggle_tween.kill()
		_target.rotation = 0.0
	var a := deg_to_rad(wiggle_angle)
	_wiggle_tween = create_tween()
	_wiggle_tween.tween_property(_target, "rotation", -a, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_wiggle_tween.tween_property(_target, "rotation", a * 0.7, 0.08)
	_wiggle_tween.tween_property(_target, "rotation", -a * 0.4, 0.07)
	_wiggle_tween.tween_property(_target, "rotation", 0.0, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ==================== 描边挂载 ====================

## 面板描边：克隆 StyleBox，烘焙贴图 + 清 texture_margin，再挂描边材质
func _attach_panel_outline(panel: PanelContainer) -> void:
	var sb := panel.get_theme_stylebox("panel") as StyleBoxTexture
	if sb == null or sb.texture == null:
		return
	var clone := sb.duplicate() as StyleBoxTexture
	clone.texture = _bake(sb.texture)
	clone.texture_margin_left = 0.0
	clone.texture_margin_top = 0.0
	clone.texture_margin_right = 0.0
	clone.texture_margin_bottom = 0.0
	panel.add_theme_stylebox_override("panel", clone)
	_attach_material(panel)


## 描边材质常驻，用 outline_color.a 做淡入淡出（0 = 完全无描边）
func _attach_material(ctrl: Control) -> void:
	_material = ShaderMaterial.new()
	_material.shader = OUTLINE_SHADER
	_material.set_shader_parameter("thickness", outline_thickness)
	_material.set_shader_parameter("ring_count", outline_ring_count)
	var c := outline_color
	c.a = 0.0
	_material.set_shader_parameter("outline_color", c)
	ctrl.material = _material


## AtlasTexture → 独立 ImageTexture（outline shader 的 UV 假设 0..1）
static func _bake(tex: Texture2D) -> Texture2D:
	if not (tex is AtlasTexture):
		return tex
	var key := tex.get_instance_id()
	if _bake_cache.has(key):
		return _bake_cache[key]
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	var baked := ImageTexture.create_from_image(img)
	_bake_cache[key] = baked
	return baked
