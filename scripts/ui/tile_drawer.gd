extends PanelContainer
## 右下角"抽屉"：点击把手按钮上拉面板（开关），
## 点击地皮按钮进入对应地块的放置模式（再点一次取消）。
## 地皮按钮静态预置在 main.tscn 的 HBoxContainer 里，这里按顺序连线。
## 挂载在 main.tscn 的 CanvasLayer/BlowContainer 上。

const OPEN_DURATION := 0.22
## 与 main.tscn 中 HBoxContainer 里的地皮按钮一一对应
const TILE_IDS: Array[StringName] = [
	&"dirt", &"grass", &"stone", &"fire", &"water",
	&"volcano_stable", &"upgrade", &"rarity",
	&"spawn", &"push", &"pull",
]

var _game_manager: GameManager
var _tile_buttons: Array[Button] = []
var _open := false
var _closed_top := -20.0
var _closed_bottom := 27.0
var _tween: Tween


func _ready() -> void:
	_game_manager = get_tree().current_scene.get_node_or_null("World") as GameManager
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
	for child in hbox.get_children():
		if child is Button:
			# 不用 toggle_mode：按钮按下态完全由 _on_selection_changed 同步，
			# 避免原生 toggle 与 pressed 信号的触发顺序造成状态不一致
			var index := _tile_buttons.size()
			_tile_buttons.append(child)
			child.pressed.connect(_on_tile_button_pressed.bind(index))
	if _tile_buttons.size() != TILE_IDS.size():
		push_warning("tile_drawer: 地皮按钮 %d 个与 TILE_IDS %d 个不匹配"
			% [_tile_buttons.size(), TILE_IDS.size()])

	if _game_manager:
		_game_manager.tile_selection_changed.connect(_on_selection_changed)


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


## 单选同步：当前选中的按钮按下，其余抬起
func _on_selection_changed(tile: TileDef) -> void:
	for i in _tile_buttons.size():
		_tile_buttons[i].button_pressed = tile != null and TILE_IDS[i] == tile.id
