extends Control
## 设置界面（scenes/ui/settings.tscn）。
## 页面：Home（菜单）/ Game / Audio / Display，同一时刻只显示一个。
## Back 按钮固定在「当前可视面板」的右上角、页面图标固定在左上角（每帧跟随面板矩形，
## 换页/改分辨率都不脱锚）。Back 在子页面返回 Home，在 Home 关闭整个设置界面。
## 音量（Master/Music/SFX 三条总线）与全屏写入 user://settings.cfg，
## 启动时由 SoundManager._apply_saved_settings 应用。

signal closed   # 请求关闭（由打开方 open_settings.gd 负责销毁覆盖层）

const ICON_DIR := "res://assets/UI/setting/"
const CORNER_ORDER: Array[StringName] = [&"Home", &"Game", &"Audio", &"Display"]

## 设置文件路径（测试可改成独立路径，不污染真实配置）
var cfg_path := "user://settings.cfg"

var _pages: Dictionary = {}        # StringName → Control
var _panels: Dictionary = {}       # StringName → PanelContainer（back/icon 的锚点）
var _page := &"Home"
## 场景里预置的两个透明锚点面板：Back 骑可视面板右上角、Icon 骑左上角，
## 里面的 flat Button 分别显示 Back.png / 当前页图标
var _back_panel: PanelContainer = null
var _icon_panel: PanelContainer = null
var _icon_btn: Button = null
var _save_btn: Button = null
var _sliders: Dictionary = {}      # StringName 总线名 → HSlider（&"" = Master）
var _fullscreen_check: CheckButton = null
var _world_name_edit: LineEdit = null


## SoundManager autoload 访问器（--script 测试模式下全局标识符不可编译，走节点查找）
func _sm():
	return get_node_or_null("/root/SoundManager")


## 当前场景下的 GameManager（世界名等游戏状态来源）
func _game_manager() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("World")


func _ready() -> void:
	for page_name in CORNER_ORDER:
		var page := get_node_or_null(NodePath(page_name)) as Control
		if page == null:
			push_warning("settings: 缺页面 %s" % page_name)
			continue
		_pages[page_name] = page
		_panels[page_name] = page.get_node_or_null("PanelContainer") as PanelContainer
	_wire_corner_panels()
	_wire_home()
	_wire_game()
	_wire_audio()
	_wire_display()
	_load_cfg_into_controls()
	_show_page(&"Home")


## Back / Icon 锚点面板每帧骑到当前可视面板的右上 / 左上角（尺寸 40×40，半跨 20px）
func _process(_delta: float) -> void:
	var panel := _panels.get(_page) as PanelContainer
	if panel == null or not panel.visible:
		return
	var r := panel.get_global_rect()
	if _back_panel != null:
		_back_panel.global_position = r.position + Vector2(r.size.x - _back_panel.size.x * 0.5, -_back_panel.size.y * 0.5)
	if _icon_panel != null:
		_icon_panel.global_position = r.position - _icon_panel.size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


# ==================== 页面切换 ====================

func _show_page(page_name: StringName) -> void:
	_page = page_name
	for key in _pages:
		(_pages[key] as Control).visible = (key == page_name)
	if _icon_btn != null:
		_icon_btn.icon = load(ICON_DIR + String(page_name) + ".png")


func _on_back() -> void:
	var sm = _sm()
	if sm != null:
		sm.play_sfx(&"menu_selection_click")
	if _page != &"Home":
		_show_page(&"Home")
	else:
		closed.emit()


## 接管场景里预置的 Back / Icon 锚点面板：
## Back 里的按钮显示 Back.png、点击 = _on_back；Icon 里的按钮只展示当前页图标（不吃鼠标）
func _wire_corner_panels() -> void:
	_back_panel = get_node_or_null("Back") as PanelContainer
	_icon_panel = get_node_or_null("Icon") as PanelContainer
	if _back_panel == null or _icon_panel == null:
		push_warning("settings: 缺 Back/Icon 锚点面板")
		return
	var back_btn := _back_panel.get_node_or_null("Button") as Button
	if back_btn != null:
		back_btn.icon = load(ICON_DIR + "Back.png")
		back_btn.expand_icon = true
		back_btn.pressed.connect(_on_back)
	_icon_btn = _icon_panel.get_node_or_null("Button") as Button
	if _icon_btn != null:
		_icon_btn.icon = load(ICON_DIR + "Home.png")
		_icon_btn.expand_icon = true
		_icon_btn.mouse_filter = MOUSE_FILTER_IGNORE


# ==================== Home 菜单 ====================

func _wire_home() -> void:
	var vbox := get_node_or_null("Home/PanelContainer/VBoxContainer")
	if vbox == null:
		return
	_bind_menu_button(vbox, "PanelContainer/Button", &"Game")
	_bind_menu_button(vbox, "PanelContainer2/Button", &"Audio")
	_bind_menu_button(vbox, "PanelContainer3/Button", &"Display")
	_save_btn = vbox.get_node_or_null("PanelContainer4/Button") as Button
	if _save_btn != null:
		_save_btn.pressed.connect(_on_save_pressed)
	var exit_btn := vbox.get_node_or_null("PanelContainer5/Button") as Button
	if exit_btn != null:
		exit_btn.pressed.connect(_on_exit_pressed)


func _bind_menu_button(vbox: Node, path: NodePath, page_name: StringName) -> void:
	var btn := vbox.get_node_or_null(path) as Button
	if btn != null:
		btn.pressed.connect(_show_page.bind(page_name))
		btn.pressed.connect(_play_click)


# ==================== Game ====================

func _wire_game() -> void:
	_world_name_edit = get_node_or_null("Game/PanelContainer/HBoxContainer/LineEdit") as LineEdit
	if _world_name_edit == null:
		push_warning("settings: 缺世界名输入框")
		return
	_sync_world_name_from_state()
	_world_name_edit.text_changed.connect(_on_world_name_changed)
	var gm := _game_manager()
	if gm != null:
		gm.state.changed.connect(_sync_world_name_from_state)


func _sync_world_name_from_state() -> void:
	if _world_name_edit == null:
		return
	var gm := _game_manager()
	if gm == null:
		return
	var state_name: String = gm.state.world_name
	if _world_name_edit.text != state_name:
		_world_name_edit.text = state_name


func _on_world_name_changed(new_text: String) -> void:
	var gm := _game_manager()
	if gm == null:
		return
	if gm.state.world_name != new_text:
		gm.state.set_world_name(new_text)


func _play_click() -> void:
	var sm = _sm()
	if sm != null:
		sm.play_sfx(&"menu_selection_click")


# ==================== Audio ====================

func _wire_audio() -> void:
	var base := "Audio/PanelContainer/HBoxContainer/VBoxContainer2/"
	_sliders[&""] = get_node_or_null(base + "HSlider") as HSlider        # 主音量
	_sliders[&"Music"] = get_node_or_null(base + "HSlider2") as HSlider  # 音乐
	_sliders[&"SFX"] = get_node_or_null(base + "HSlider3") as HSlider    # 音效
	for bus_name in _sliders:
		var slider := _sliders[bus_name] as HSlider
		if slider == null:
			continue
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		slider.value_changed.connect(_on_volume_changed.bind(bus_name))
	var sfx_slider := _sliders.get(&"SFX") as HSlider
	if sfx_slider != null:
		sfx_slider.drag_ended.connect(func(_changed: bool) -> void:
			var sm = _sm()
			if sm != null:
				sm.play_sfx(&"menu_selection_click")   # 拖完预览一声当前音效音量
		)


func _on_volume_changed(value: float, bus_name: StringName) -> void:
	var sm = _sm()
	if sm != null:
		sm.set_bus_linear(bus_name, value / 100.0)
	_save_cfg()


# ==================== Display ====================

func _wire_display() -> void:
	_fullscreen_check = get_node_or_null("Display/PanelContainer/HBoxContainer/VBoxContainer2/CheckButton") as CheckButton
	if _fullscreen_check != null:
		_fullscreen_check.toggled.connect(_on_fullscreen_toggled)


func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_cfg()


# ==================== Save / Exit ====================

func _on_save_pressed() -> void:
	_save_game()
	# 按钮文字短暂反馈
	if _save_btn != null:
		_save_btn.text = "Saved!"
		var btn := _save_btn
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if is_instance_valid(btn):
				btn.text = "Save"
		)


func _on_exit_pressed() -> void:
	_save_game()
	get_tree().quit()


## 主场景找 GameManager 强制写档（防御：不在主场景时找 TalentGrid.persist）
func _save_game() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var gm := scene.get_node_or_null("World")
	if gm != null and gm.has_method("save_now"):
		gm.save_now()
	elif scene.has_method("persist"):
		scene.persist()


# ==================== 配置持久化 ====================

func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)   # 保留其他键
	var sm = _sm()
	if sm != null:
		cfg.set_value("audio", "master", sm.get_bus_linear(&""))
		cfg.set_value("audio", "music", sm.get_bus_linear(&"Music"))
		cfg.set_value("audio", "sfx", sm.get_bus_linear(&"SFX"))
	if _fullscreen_check != null:
		cfg.set_value("display", "fullscreen", _fullscreen_check.button_pressed)
	cfg.save(cfg_path)


## 打开界面时把配置灌回控件（不回触发信号）
func _load_cfg_into_controls() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		# 无配置文件：控件显示当前总线实际值
		var sm0 = _sm()
		if sm0 != null:
			for bus_name in _sliders:
				var s := _sliders[bus_name] as HSlider
				if s != null:
					s.set_value_no_signal(sm0.get_bus_linear(bus_name) * 100.0)
		return
	var sm = _sm()
	if sm != null:
		# 以配置为准应用一遍（可能和启动时应用之间被改过）
		sm.set_bus_linear(&"", float(cfg.get_value("audio", "master", 1.0)))
		sm.set_bus_linear(&"Music", float(cfg.get_value("audio", "music", 1.0)))
		sm.set_bus_linear(&"SFX", float(cfg.get_value("audio", "sfx", 1.0)))
		for bus_name in _sliders:
			var slider := _sliders[bus_name] as HSlider
			if slider != null:
				slider.set_value_no_signal(sm.get_bus_linear(bus_name) * 100.0)
	if _fullscreen_check != null:
		_fullscreen_check.set_pressed_no_signal(bool(cfg.get_value("display", "fullscreen", false)))
