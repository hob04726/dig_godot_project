extends Control
class_name FlavorTextLabel

## 屏幕底部风味语句滚动标签（从 NamePanel 拆分出来的纯文本版）。
## 调用 setup(game_manager) 后开始每 10 秒随机切换一句。

## 显示风味语句的富文本标签
@export var label: RichTextLabel
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
	if label != null:
		label.modulate.a = 0.0
		label.text = ""
	_flavor_rng.randomize()


## 传入 GameManager，绑定状态变化并立即显示第一条语句。
func setup(gm: GameManager) -> void:
	_game_manager = gm
	if gm != null:
		gm.state.changed.connect(_maybe_refresh_on_state_change)
	_timer = rotation_interval * 0.5   # 初次稍快出现
	call_deferred("_show_next_line")


func _process(delta: float) -> void:
	if _game_manager == null or label == null:
		return
	_timer += delta
	if _timer >= rotation_interval:
		_timer = 0.0
		_show_next_line()


## 进入新阶段且当前文本不属于新阶段时立即刷新。
func _maybe_refresh_on_state_change() -> void:
	if _game_manager == null or label == null:
		return
	var stage := FlavorTextDb.current_stage(_game_manager.state.lifetime_coins)
	var text := FlavorTextDb.pick_line(_flavor_rng, _game_manager.state.lifetime_coins)
	if not text.is_empty() and not _is_text_in_stage(text, stage):
		_current_text = ""
		_show_next_line()


func _is_text_in_stage(text: String, stage: int) -> bool:
	for e in FlavorTextDb.get_available_lines(_game_manager.state.lifetime_coins):
		if e.text == text and e.stage == stage:
			return true
	return false


func _show_next_line() -> void:
	if _game_manager == null or label == null:
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
	_flavor_tween.tween_property(label, "modulate:a", 0.0, fade_duration)
	_flavor_tween.tween_callback(func() -> void:
		label.text = "[center]%s[/center]" % text
	)
	_flavor_tween.tween_property(label, "modulate:a", 1.0, fade_duration)
