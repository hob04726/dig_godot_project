extends Control
class_name ConfirmDialog
## 通用确认弹窗（scenes/ui/confirm.tscn）。
## 实例化到 CanvasLayer 后调用 confirm(message) 等待玩家点击 Yes/No，返回 bool。

signal finished(confirmed: bool)

const YES_TEXT := "Yes"
const NO_TEXT := "No"

var _confirmed := false


func _ready() -> void:
	var yes_btn := _find_button(YES_TEXT)
	var no_btn := _find_button(NO_TEXT)
	if yes_btn != null:
		yes_btn.pressed.connect(_on_yes)
	if no_btn != null:
		no_btn.pressed.connect(_on_no)


func _find_button(text: String) -> Button:
	var hbox := get_node_or_null("PanelContainer/VBoxContainer/HBoxContainer") as HBoxContainer
	if hbox == null:
		return null
	for wrapper in hbox.get_children():
		var btn := wrapper.get_node_or_null("Button") as Button
		if btn != null and btn.text == text:
			return btn
	return null


## 显示弹窗并等待玩家选择。返回 true = Yes，false = No。
func confirm(message: String) -> bool:
	var label := get_node_or_null("PanelContainer/VBoxContainer/RichTextLabel") as RichTextLabel
	if label != null:
		label.text = message
	visible = true
	_confirmed = false
	await finished
	return _confirmed


func _on_yes() -> void:
	_confirmed = true
	finished.emit(true)


func _on_no() -> void:
	_confirmed = false
	finished.emit(false)
