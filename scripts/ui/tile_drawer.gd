extends PanelContainer
## 右下角"抽屉"：点击把手按钮上拉面板（开关），
## 点击地皮按钮进入对应地块的放置模式（再点一次取消）。
## 地皮按钮静态预置在 main.tscn 的 HBoxContainer 里，这里按顺序连线。
## 挂载在 main.tscn 的 CanvasLayer/BlowContainer 上。
## 交互细节：
## - 没有任何已解锁地块可放时，整个抽屉隐藏（有解锁后再出现）
## - 地皮按钮 flat（无背景框）
## - 悬停/选中：按钮以底边中心为支点平滑上移 + 微放大（1.05）；选中瞬间"压→冲→落"弹跳（0.94→1.15→1.05），再点一次平滑缩回默认
## - 选中瞬间在按钮中心随机播放 scenes/vfx/impact.tscn 的一种冲击动画

const OPEN_DURATION := 0.22
## 与 main.tscn 中 HBoxContainer 里的地皮按钮一一对应
const TILE_IDS: Array[StringName] = [
	&"dirt", &"grass", &"stone", &"fire", &"water",
	&"volcano_stable", &"upgrade", &"rarity",
	&"spawn", &"push", &"pull",
]
const IMPACT_SCENE := preload("res://scenes/vfx/impact.tscn")
## 按钮悬停/选中时的目标缩放与上移像素（只大一点点，别喧宾夺主）
const BTN_ACTIVE_SCALE := 1.05
const BTN_ACTIVE_LIFT := 6.0
const BTN_ANIM_TIME := 0.15
## 缩小（取消选中/离开）的时长：比放大长，和选中弹跳的收回节奏一致
const BTN_REVERT_TIME := 0.3
## 选中瞬间的弹跳：先小幅下压再冲过目标、最后回落（squash & stretch，
## 悬停已把按钮抬到 1.05，单纯再放大 7% 几乎看不见，所以用"压→冲→落"让点击有反馈）
const BTN_POP_DIP := 0.94
const BTN_POP_DIP_TIME := 0.07
const BTN_POP_SCALE := 1.15
const BTN_POP_UP_TIME := 0.11
const BTN_POP_DOWN_TIME := 0.16
## impact 特效相对天赋树用法缩小一点，适配 36px 按钮
const IMPACT_SCALE := 0.5
## 选中按钮的描边材质（全体按钮共享一份；thickness 单位是贴图像素，
## 地块贴图 256×352 缩到 36px 按钮 → 8 ≈ 1 屏幕像素）
const OUTLINE_SHADER := preload("res://scripts/shaders/outline.gdshader")
const BTN_OUTLINE_THICKNESS := 8.0

var _game_manager: GameManager
var _tile_buttons: Array[Button] = []
var _btn_outlines: Array[TextureRect] = []   # 选中态描边覆盖层（与按钮同序）
var _outline_material: ShaderMaterial = null
## 每个按钮的动画状态（平行数组，与 _tile_buttons 同序）
var _btn_scale: Array[float] = []
var _btn_lift: Array[float] = []
var _btn_base_y: Array[float] = []   # HBox 排版赋予的基准 position.y（排序时重记）
var _btn_hovered: Array[bool] = []
var _btn_selected: Array[bool] = []
var _btn_tweens: Array[Tween] = []
var _open := false
var _closed_top := -20.0
var _closed_bottom := 27.0
var _tween: Tween


func _ready() -> void:
	_game_manager = _find_game_manager()
	if _game_manager == null:
		push_warning("tile_drawer: 找不到 World（GameManager）节点")

	# 面板/容器背景不拦截鼠标：点击穿透到游戏（按钮本身仍可点），
	# 递归把容器背景设 IGNORE（兼容地皮按钮被套进 PanelContainer 的嵌套结构）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$VBoxContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ignore_containers($VBoxContainer)

	# 记住"收起"时的位置（场景里初始值），开关时在它与打开位置间补间
	_closed_top = offset_top
	_closed_bottom = offset_bottom

	# 把手按钮：尺寸写在 main.tscn 场景里（custom_minimum_size），
	# 这样编辑器预览和运行时一致，不会因代码改尺寸导致重排版偏移
	var toggle := $VBoxContainer/Button as Button
	toggle.pressed.connect(_on_toggle_pressed)

	var hbox := _find_hbox($VBoxContainer)
	if hbox == null:
		push_warning("tile_drawer: 找不到地皮按钮的 HBoxContainer")
		return
	# 按钮上移/放大可能溢出排版矩形，关掉裁剪避免被切
	hbox.clip_contents = false
	(hbox.get_parent() as Control).clip_contents = false
	hbox.sort_children.connect(_on_hbox_sorted)
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("thickness", BTN_OUTLINE_THICKNESS)
	for child in hbox.get_children():
		if child is Button:
			# 不用 toggle_mode：按钮按下态完全由 _on_selection_changed 同步，
			# 避免原生 toggle 与 pressed 信号的触发顺序造成状态不一致
			var index := _tile_buttons.size()
			_tile_buttons.append(child)
			_btn_scale.append(1.0)
			_btn_lift.append(0.0)
			_btn_base_y.append(0.0)
			_btn_hovered.append(false)
			_btn_selected.append(false)
			_btn_tweens.append(null)
			child.flat = true   # 无背景框，选中态靠"保持上移+放大"表达
			child.pivot_offset = Vector2(child.size.x * 0.5, child.size.y)   # 底边中心为支点
			child.resized.connect(_on_btn_resized.bind(child))
			child.pressed.connect(_on_tile_button_pressed.bind(index))
			child.mouse_entered.connect(_on_btn_hover.bind(index, true))
			child.mouse_exited.connect(_on_btn_hover.bind(index, false))
			# 选中态描边：同图标的 TextureRect 覆盖层挂 outline 材质，默认隐藏，
			# 由 _on_selection_changed 显隐；鼠标穿透、不参与排版。
			# 注意：shader 的 border_clipping_fix 按"局部单位=贴图像素"做顶点外扩+UV 补偿，
			# 所以覆盖层必须用贴图原始尺寸（256×352）再缩放到按钮大小，
			# 直接 36×36 会让外扩（±8/36）与 UV 补偿（±8/256）不匹配，图标被放大 ~44%
			var outline := TextureRect.new()
			outline.texture = child.icon
			outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # 取消"最小尺寸=贴图尺寸"钳制
			outline.stretch_mode = TextureRect.STRETCH_SCALE      # 贴图原始尺寸铺满自身矩形
			outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			outline.material = _outline_material
			outline.visible = false
			child.add_child(outline)
			_fit_outline(outline, child)
			child.resized.connect(_fit_outline.bind(outline, child))
			_btn_outlines.append(outline)
	if _tile_buttons.size() != TILE_IDS.size():
		push_warning("tile_drawer: 地皮按钮 %d 个与 TILE_IDS %d 个不匹配"
			% [_tile_buttons.size(), TILE_IDS.size()])

	_refresh_visible()
	if _game_manager:
		_game_manager.tile_selection_changed.connect(_on_selection_changed)
		# GameManager._ready 完成后再刷一次（时序兜底：万一本节点先于它 _ready）
		_game_manager.initialized.connect(_refresh_visible)


## 可靠查找 World（GameManager）：当前场景优先，兜底从根按名找（headless 脚本等场景）
func _find_game_manager() -> GameManager:
	var scene := get_tree().current_scene
	if scene != null:
		var found := scene.get_node_or_null("World") as GameManager
		if found != null:
			return found
	return get_tree().root.find_child("World", true, false) as GameManager


## 只显示已解锁的地块按钮（UNLOCK_TILE 天赋门控）：未解锁的不出现在抽屉里。
## 隐藏不改变按钮↔TILE_IDS 的顺序映射，选中同步仍按原索引工作。
## 一个可放地块都没有时，整个抽屉隐藏。
func _refresh_visible() -> void:
	var unlocked_count := 0
	for i in _tile_buttons.size():
		var unlocked := _game_manager != null and _game_manager.is_tile_unlocked(TILE_IDS[i])
		_tile_buttons[i].visible = unlocked
		if unlocked:
			unlocked_count += 1
	visible = unlocked_count > 0


## 递归把容器背景设为 IGNORE（按钮本身保持可点）
func _ignore_containers(node: Node) -> void:
	for child in node.get_children():
		if child is Container:
			(child as Container).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ignore_containers(child)


## 在 VBox 下递归找第一个 HBoxContainer（兼容嵌套层级变化）
func _find_hbox(node: Node) -> HBoxContainer:
	for child in node.get_children():
		if child is HBoxContainer:
			return child
	for child in node.get_children():
		if child is Container:
			var found := _find_hbox(child)
			if found:
				return found
	return null


func _on_toggle_pressed() -> void:
	_open = not _open
	# 关闭抽屉时退出放置模式：不再左键放置/右键删除地块
	if not _open and _game_manager:
		_game_manager.clear_tile_selection()
	_animate_to(_open)


## 打开：整块面板抬到屏幕底边之上；收起：回到只露把手的初始位置
func _animate_to(open: bool) -> void:
	var target_top := _closed_top
	var target_bottom := _closed_bottom
	if open:
		var content_height := maxf(get_combined_minimum_size().y, offset_bottom - offset_top)
		target_top = -content_height
		target_bottom = 0.0

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "offset_top", target_top, OPEN_DURATION)
	_tween.parallel().tween_property(self, "offset_bottom", target_bottom, OPEN_DURATION)


func _on_tile_button_pressed(button_index: int) -> void:
	if _game_manager == null:
		return
	_game_manager.toggle_tile_selection(TILE_IDS[button_index])


## 单选同步：当前选中的按钮按下，其余抬起；
## 新选中的按钮播 impact 特效 + 弹跳放大（过冲后回落保持），取消选中的平滑复原
func _on_selection_changed(tile: TileDef) -> void:
	for i in _tile_buttons.size():
		var selected := tile != null and TILE_IDS[i] == tile.id
		var was := _btn_selected[i]
		_btn_selected[i] = selected
		_tile_buttons[i].button_pressed = selected
		_btn_outlines[i].visible = selected   # 选中显示描边，取消隐藏
		if selected and not was:
			_play_impact(_tile_buttons[i])
			_pop_button(i)
		else:
			_animate_button(i)


# ==================== 按钮悬停/选中动效 ====================

func _on_btn_hover(index: int, hovered: bool) -> void:
	_btn_hovered[index] = hovered
	_animate_button(index)


## 按钮尺寸确定后，把缩放支点固定在底边中心（放大即"向上长"）
func _on_btn_resized(btn: Button) -> void:
	btn.pivot_offset = Vector2(btn.size.x * 0.5, btn.size.y)


## 描边覆盖层用贴图原始尺寸 + 缩放铺满按钮（让 shader 的顶点外扩与 UV 补偿匹配），
## 按钮尺寸变化（布局/抽屉动画）时重算
func _fit_outline(outline: TextureRect, btn: Button) -> void:
	var tex_size := outline.texture.get_size()
	outline.size = tex_size
	outline.scale = Vector2(btn.size.x / tex_size.x, btn.size.y / tex_size.y)
	outline.position = Vector2.ZERO


## HBox 重排版（开关抽屉、按钮显隐）时重记每个按钮的基准 y
func _on_hbox_sorted() -> void:
	for i in _tile_buttons.size():
		# 当前 position.y = 基准 - 已施加的上移，反推基准
		_btn_base_y[i] = _tile_buttons[i].position.y + _btn_lift[i]


## 悬停或选中 → 上移+放大；都否 → 平滑复原
func _animate_button(index: int) -> void:
	var active: bool = _btn_hovered[index] or _btn_selected[index]
	var target := Vector2(BTN_ACTIVE_SCALE if active else 1.0, BTN_ACTIVE_LIFT if active else 0.0)
	var from := Vector2(_btn_scale[index], _btn_lift[index])
	if from.is_equal_approx(target):
		return
	var old := _btn_tweens[index]
	if old and old.is_valid():
		old.kill()
	# 缩小（取消选中/鼠标离开）用更长时长 + 双向缓动，
	# 与选中弹跳（0.34s）的节奏匹配，否则 0.15s 一闪就没、显得不平滑
	var shrinking: bool = target.x < from.x
	var duration := BTN_REVERT_TIME if shrinking else BTN_ANIM_TIME
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT if shrinking else Tween.EASE_OUT)
	t.tween_method(_apply_button_transform.bind(index), from, target, duration)
	_btn_tweens[index] = t


## 选中瞬间的弹跳：当前状态 → 小幅下压 → 冲过目标 → 回落保持。
## 取消选中不走这里，由 _animate_button 平滑缩回。
func _pop_button(index: int) -> void:
	var old := _btn_tweens[index]
	if old and old.is_valid():
		old.kill()
	var from := Vector2(_btn_scale[index], _btn_lift[index])
	var dip := Vector2(BTN_POP_DIP, BTN_ACTIVE_LIFT * 0.5)
	var peak := Vector2(BTN_POP_SCALE, BTN_ACTIVE_LIFT)
	var settle := Vector2(BTN_ACTIVE_SCALE, BTN_ACTIVE_LIFT)
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_method(_apply_button_transform.bind(index), from, dip, BTN_POP_DIP_TIME)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(_apply_button_transform.bind(index), dip, peak, BTN_POP_UP_TIME)
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(_apply_button_transform.bind(index), peak, settle, BTN_POP_DOWN_TIME)
	_btn_tweens[index] = t


func _apply_button_transform(v: Vector2, index: int) -> void:
	_btn_scale[index] = v.x
	_btn_lift[index] = v.y
	var btn := _tile_buttons[index]
	btn.scale = Vector2.ONE * v.x
	btn.position.y = _btn_base_y[index] - v.y


## 选中瞬间：在按钮中心随机播放 impact 的一种冲击动画，播完（或超时兜底）自毁
func _play_impact(btn: Button) -> void:
	var impact := IMPACT_SCENE.instantiate() as Node2D
	add_child(impact)
	impact.z_index = 20   # 画在按钮之上
	impact.scale = Vector2.ONE * IMPACT_SCALE
	impact.global_position = btn.get_global_rect().get_center()
	var sprite := impact.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		impact.queue_free()
		return
	var names := sprite.sprite_frames.get_animation_names()
	if names.is_empty():
		impact.queue_free()
		return
	sprite.frame = 0
	sprite.play(names[randi() % names.size()])
	sprite.animation_finished.connect(impact.queue_free)
	# 兜底：动画最长约 0.35s，超时也释放（防止意外残留）
	get_tree().create_timer(0.8).timeout.connect(impact.queue_free)
