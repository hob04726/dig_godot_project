extends Button
## 天赋界面左上角"返回"按钮：普通天赋树中显示并返回主场景；升华树中隐藏。

func _ready() -> void:
	pressed.connect(_back)
	_update_visibility()
	call_deferred("_update_visibility")


func _process(_delta: float) -> void:
	_update_visibility()


func _update_visibility() -> void:
	var grid := _talent_grid()
	if grid == null:
		visible = false
		return
	# TreeMode.NORMAL = 0，只在普通树显示
	visible = grid.get("tree_mode") == 0


func _back() -> void:
	# 升华树不应触发（按钮已隐藏），防御性兜底
	var grid := _talent_grid()
	if grid != null and grid.get("tree_mode") != 0:
		return

	# SoundManager autoload 走节点查找（--script 测试模式无全局标识符）
	var sm := get_node_or_null("/root/SoundManager")
	if sm != null:
		sm.play_sfx(&"menu_selection_click")
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("persist"):
		scene.call("persist")   # TalentGrid 写档
	SceneTransition.play_to("res://scenes/main.tscn")   # 转场（盖住→切换→揭开）


func _talent_grid() -> Node:
	# 按钮路径：Talent/UI/PanelContainer/Back
	var panel := get_parent() as PanelContainer
	if panel == null:
		return null
	var ui := panel.get_parent() as CanvasLayer
	if ui == null:
		return null
	return ui.get_parent()
