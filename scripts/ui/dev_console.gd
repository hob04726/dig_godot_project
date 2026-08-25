class_name DevConsole
extends CanvasLayer

## 开发者控制台（autoload，跨场景存活）：反引号 ` 呼出/收起。
## 命令直接操作真实 GameState，主场景（World/GameManager）与天赋场景（TalentGrid）均可用：
##   help                    — 命令列表
##   clear                   — 清空输出
##   give gold <数量>         — 加金币（如 give gold 1999999 / 1e9）
##   give lifetime <数量>     — 加累计金币（升华点按它算）
##   unlock <talent_id>      — 直接记录解锁一个天赋
## 输入回车执行，↑/↓ 翻历史。layer 150 盖在场景转场(100)之上。

const TOGGLE_KEYS := [KEY_QUOTELEFT, KEY_ASCIITILDE]   # ` 与 ~

var _panel: Control = null
var _log_label: RichTextLabel = null
var _input_edit: LineEdit = null
var _open := false
var _history: Array[String] = []
var _history_index := -1

var _num_re := RegEx.new()


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_num_re.compile("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")
	_panel = $Panel
	_log_label = $Panel/Box/Margin/VBox/Output
	_input_edit = $Panel/Box/Margin/VBox/Input
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_input_edit.text_submitted.connect(_on_submit)
	_input_edit.gui_input.connect(_on_input_gui)
	_panel.visible = false
	_log("开发者控制台就绪（按 ` 呼出）")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode in TOGGLE_KEYS or event.physical_keycode in TOGGLE_KEYS:
		set_open(not _open)
		get_viewport().set_input_as_handled()   # 吞掉该键，避免打进输入框


func set_open(open: bool) -> void:
	_open = open
	_panel.visible = open
	if open:
		_input_edit.text = ""
		_input_edit.grab_focus()
	else:
		_input_edit.release_focus()


# ==================== 输入 ====================

func _on_submit(text: String) -> void:
	var trimmed := text.strip_edges()
	if not trimmed.is_empty():
		_history.append(trimmed)
		_history_index = _history.size()
		_log("> " + trimmed)
		_run_command(trimmed)
	_input_edit.clear()


func _on_input_gui(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_UP:
		_history_index = maxi(_history_index - 1, 0)
		_input_edit.text = _history[_history_index] if _history_index < _history.size() else ""
		_input_edit.caret_column = _input_edit.text.length()
		_input_edit.accept_event()
	elif event.keycode == KEY_DOWN:
		_history_index = mini(_history_index + 1, _history.size())
		_input_edit.text = _history[_history_index] if _history_index < _history.size() else ""
		_input_edit.caret_column = _input_edit.text.length()
		_input_edit.accept_event()


# ==================== 命令 ====================

func _run_command(line: String) -> void:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	match cmd:
		"help", "?":
			_print_help()
		"clear", "cls":
			_log_label.clear()
		"give":
			_run_give(parts)
		"unlock":
			_run_unlock(parts)
		_:
			_log("未知命令：%s（输入 help 查看）" % cmd)


func _print_help() -> void:
	_log("可用命令：")
	_log("  help                    — 本列表")
	_log("  clear                   — 清空输出")
	_log("  give gold <数量>         — 加金币（如 give gold 1999999 / 1e9）")
	_log("  give lifetime <数量>     — 加累计金币（升华点按它算）")
	_log("  unlock <talent_id>      — 解锁一个天赋（如 unlock unlock_tile_fire）")


func _run_give(parts: PackedStringArray) -> void:
	if parts.size() < 3:
		_log("用法：give <gold|lifetime> <数量>，如 give gold 1999999")
		return
	var what := parts[1].to_lower()
	var amount_str := parts[2]
	if not _num_re.search(amount_str):
		_log("数量格式无效：%s（支持整数 / 小数 / 1e9）" % amount_str)
		return
	var amount := BigNumber.from_string(amount_str)
	var state := _find_state()
	if state == null:
		_log("当前场景找不到 GameState（需在主场景或天赋场景中使用）")
		return
	match what:
		"gold":
			state.add_coins(amount)
			_refresh_views()
			_log("金币 +%s → %s" % [amount.to_compact_string(), state.coins.to_compact_string()])
		"lifetime":
			state.lifetime_coins = state.lifetime_coins.add(amount)
			_refresh_views()
			_log("累计金币 → %s（升华点合计 %s）" % [state.lifetime_coins.to_compact_string(), state.ascension_points_total().to_compact_string()])
		_:
			_log("give 目标未知：%s（gold / lifetime）" % what)


func _run_unlock(parts: PackedStringArray) -> void:
	if parts.size() < 2:
		_log("用法：unlock <talent_id>")
		return
	var id := StringName(parts[1])
	var state := _find_state()
	if state == null:
		_log("当前场景找不到 GameState")
		return
	if state.has_talent(id):
		_log("该天赋已解锁：%s" % id)
		return
	state.record_talent_purchase(id)
	# 天赋场景重建树让新解锁生效；主场景失效缓存（查询均为懒读取，unlock 后即时可见）
	var scene := get_tree().current_scene
	if scene is TalentGrid:
		(scene as TalentGrid)._build_tree()
	elif scene != null and scene.has_node("World"):
		var gm := scene.get_node("World") as GameManager
		if gm != null and gm._talent_system != null:
			gm._talent_system.invalidate()
	_log("已解锁天赋：%s" % id)


# ==================== 场景接线 ====================

func _find_state() -> GameState:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	if scene.has_node("World"):
		var gm := scene.get_node("World") as GameManager
		if gm != null and gm.state != null:
			return gm.state
	if scene is TalentGrid:
		var grid := scene as TalentGrid
		if grid._state != null:
			return grid._state
	return null


## 状态变更后刷新当前场景视图（主场景金币标签 / 天赋场景可购状态与金币显示）
func _refresh_views() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.has_node("World"):
		var gm := scene.get_node("World") as GameManager
		if gm != null:
			gm._update_money_label()
	elif scene is TalentGrid:
		var grid := scene as TalentGrid
		grid._refresh_all(false)
		grid._update_gold_label()


func _log(text: String) -> void:
	if _log_label == null:
		return
	_log_label.append_text(text + "\n")
