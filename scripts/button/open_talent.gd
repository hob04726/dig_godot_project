extends Button

## 主场景"天赋"按钮：先强制存档（切场景会释放 GameManager，不存档会丢进度），
## 再切换到天赋界面。

func _ready() -> void:
	pressed.connect(_open)


func _open() -> void:
	# SoundManager autoload 走节点查找（--script 测试模式无全局标识符）
	var sm := get_node_or_null("/root/SoundManager")
	if sm != null:
		sm.play_sfx(&"menu_selection_click")
	var scene := get_tree().current_scene
	var gm := scene.get_node_or_null("World") as GameManager if scene != null else null
	if gm != null:
		gm.save_now()
	SceneTransition.play_to("res://scenes/talent.tscn")   # 转场（盖住→切换→揭开）
