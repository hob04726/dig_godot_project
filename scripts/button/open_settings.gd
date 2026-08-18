extends Button

## 主场景右上角设置按钮：开关设置覆盖层。
## settings.tscn 实例化进一个高 layer 的 CanvasLayer（盖住 HUD/抽屉，挡住对世界的点击），
## 界面内 Back 在 Home 页发出 closed 信号 → 这里销毁覆盖层。

const SETTINGS_SCENE := "res://scenes/ui/settings.tscn"
const OVERLAY_LAYER := 40   # 转场 100 / 控制台 150 之下，主 CanvasLayer(1) 之上

var _overlay: CanvasLayer = null


func _ready() -> void:
	pressed.connect(_toggle)


func _toggle() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	if sm != null:
		sm.play_sfx(&"menu_selection_click")
	if _overlay != null:
		_close()
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = OVERLAY_LAYER
	var panel := (load(SETTINGS_SCENE) as PackedScene).instantiate()
	_overlay.add_child(panel)
	panel.closed.connect(_close)
	var scene := get_tree().current_scene
	(scene if scene != null else get_tree().root).add_child(_overlay)


func _close() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
