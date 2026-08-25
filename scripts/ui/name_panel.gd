class_name NamePanel
extends PanelContainer

## 世界更名面板 + 下方风味语句滚动。
## 调用方在 _ready 后执行 setup(game_manager) 即可开始滚动。

## 世界名输入框（玩家可改名）
@export var world_name_edit: TextEdit
## 显示风味语句的富文本标签
@export var flavor_label: RichTextLabel
## 轮换间隔（秒）
@export var rotation_interval := 10.0
## 淡入淡出时长（秒）
@export var fade_duration := 0.35

var _game_manager: GameManager = null
var _timer := 0.0
var _flavor_rng := RandomNumberGenerator.new()
var _current_text := ""
var _flavor_tween: Tween = null


func _ready() -> void:
	if flavor_label != null:
		flavor_label.modulate.a = 0.0
		flavor_label.text = ""
	if world_name_edit != null:
		world_name_edit.text_changed.connect(_on_world_name_text_changed)
	_flavor_rng.randomize()


## 传入 GameManager，绑定状态变化并立即显示第一条语句。
func setup(gm: GameManager) -> void:
	_game_manager = gm
	if gm != null:
		gm.state.changed.connect(_on_state_changed)
		_sync_world_name_from_state()
	_timer = rotation_interval * 0.5   # 初次稍快出现，避免空等 10 秒
	# 防止父节点在 _ready 之前调用 setup，等本节点准备好再刷新文本
	call_deferred("_show_next_line")


func _on_state_changed() -> void:
	_maybe_refresh_on_state_change()
	_sync_world_name_from_state()


## 状态侧改名时同步输入框（避免和玩家输入冲突：值相同不写回）
func _sync_world_name_from_state() -> void:
	if _game_manager == null or world_name_edit == null:
		return
	var state_name := _game_manager.state.world_name
	if world_name_edit.text != state_name:
		world_name_edit.text = state_name


## 玩家在输入框改名时同步到 GameState
func _on_world_name_text_changed() -> void:
	if _game_manager == null or world_name_edit == null:
		return
	_game_manager.state.set_world_name(world_name_edit.text)


func _process(delta: float) -> void:
	if _game_manager == null or flavor_label == null:
		return
	_timer += delta
	if _timer >= rotation_interval:
		_timer = 0.0
		_show_next_line()


## 金币变化时偶尔触发立即刷新（每获得 10 倍 lifetime 跨越一次阶段时）。
## 主要仍靠 _process 的定时轮换，避免购买一次刷一次导致看不过来。
func _maybe_refresh_on_state_change() -> void:
	if _game_manager == null or flavor_label == null:
		return
	var stage := FlavorTextDb.current_stage(_game_manager.state.lifetime_coins)
	var text := FlavorTextDb.pick_line(_flavor_rng, _game_manager.state.lifetime_coins)
	# 进入新阶段且当前文本不再属于新阶段时立即换一条
	if not text.is_empty() and not _is_text_in_stage(text, stage):
		_current_text = ""
		_show_next_line()


func _is_text_in_stage(text: String, stage: int) -> bool:
	for e in FlavorTextDb.get_available_lines(_game_manager.state.lifetime_coins):
		if e.text == text and e.stage == stage:
			return true
	return false


func _show_next_line() -> void:
	if _game_manager == null or flavor_label == null:
		return
	var text := FlavorTextDb.pick_line(_flavor_rng, _game_manager.state.lifetime_coins)
	if text.is_empty() or text == _current_text:
		return
	_current_text = text
	_crossfade_to(text)


func _crossfade_to(text: String) -> void:
	if _flavor_tween != null:
		_flavor_tween.kill()

	_flavor_tween = create_tween()
	_flavor_tween.tween_property(flavor_label, "modulate:a", 0.0, fade_duration)
	_flavor_tween.tween_callback(func() -> void:
		flavor_label.text = "[center]%s[/center]" % text
	)
	_flavor_tween.tween_property(flavor_label, "modulate:a", 1.0, fade_duration)
