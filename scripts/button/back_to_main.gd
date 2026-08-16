extends Button

## 天赋界面"返回"按钮：写档后回到主场景。

func _ready() -> void:
	pressed.connect(_back)


func _back() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("persist"):
		scene.call("persist")   # TalentGrid 写档
	SceneTransition.play_to("res://scenes/main.tscn")   # 转场（盖住→切换→揭开）
