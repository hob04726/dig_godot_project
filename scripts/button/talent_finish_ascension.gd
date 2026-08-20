extends Button
## 天赋界面顶部中央「完成升华」按钮：弹出确认后保存并返回主场景。
## 仅在升华树中显示（普通天赋树隐藏）。

const CONFIRM_SCENE := "res://scenes/ui/confirm.tscn"

func _ready() -> void:
	pressed.connect(_on_pressed)
	_update_visibility()
	# 等待 TalentGrid 初始化完成后再刷新一次可见性
	call_deferred("_update_visibility")


func _process(_delta: float) -> void:
	_update_visibility()


func _update_visibility() -> void:
	var grid := _talent_grid()
	if grid == null:
		visible = false
		return
	# TreeMode.ASCENSION = 1
	visible = grid.get("tree_mode") == 1


func _on_pressed() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	if sm != null:
		sm.play_sfx(&"menu_selection_click")

	var overlay := CanvasLayer.new()
	overlay.layer = 90
	var dialog := (load(CONFIRM_SCENE) as PackedScene).instantiate()
	overlay.add_child(dialog)
	get_tree().root.add_child(overlay)
	var confirmed: bool = await dialog.confirm("是否保存天赋并开启下一轮？")
	overlay.queue_free()
	if not confirmed:
		return

	# 确认后：写档并返回主场景
	var grid := _talent_grid()
	if grid != null and grid.has_method("persist"):
		grid.call("persist")
	SceneTransition.play_to("res://scenes/main.tscn")


func _talent_grid() -> Node:
	# 按钮路径：Talent/UI/FinishAscension
	var ui := get_parent() as CanvasLayer
	if ui == null:
		return null
	return ui.get_parent()
