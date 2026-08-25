extends SceneTree
## 测试天赋场景顶部「完成升华」按钮可见性：普通树隐藏，升华树显示。

const TALENT_SCENE := "res://scenes/talent.tscn"
const ASCENSION_SCENE := "res://scenes/talent_ascension.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	await _test_normal_hidden()
	await _test_ascension_visible()
	print("=== talent_finish_button_test：失败 %d 处 ===" % _fail)
	quit()


func _test_normal_hidden() -> void:
	var scene := (load(TALENT_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	# 等待一帧让按钮 _ready 执行
	await create_timer(0.05).timeout
	var finish := scene.get_node_or_null("UI/FinishAscension") as Button
	if finish == null:
		_fail += 1
		print("[失败] 普通树找不到 FinishAscension 按钮")
		scene.queue_free()
		return
	if not finish.visible:
		_pass += 1
		print("[通过] 普通树 FinishAscension 按钮隐藏")
	else:
		_fail += 1
		print("[失败] 普通树 FinishAscension 按钮应隐藏")

	var back := scene.get_node_or_null("UI/PanelContainer/Back") as Button
	if back == null:
		_fail += 1
		print("[失败] 普通树找不到 Back 按钮")
	elif back.visible:
		_pass += 1
		print("[通过] 普通树 Back 按钮显示")
	else:
		_fail += 1
		print("[失败] 普通树 Back 按钮应显示")
	scene.queue_free()


func _test_ascension_visible() -> void:
	var scene := (load(ASCENSION_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(0.05).timeout
	var finish := scene.get_node_or_null("UI/FinishAscension") as Button
	if finish == null:
		_fail += 1
		print("[失败] 升华树找不到 FinishAscension 按钮")
		scene.queue_free()
		return
	if finish.visible:
		_pass += 1
		print("[通过] 升华树 FinishAscension 按钮显示")
	else:
		_fail += 1
		print("[失败] 升华树 FinishAscension 按钮应显示")

	var back := scene.get_node_or_null("UI/PanelContainer/Back") as Button
	if back == null:
		_fail += 1
		print("[失败] 升华树找不到 Back 按钮")
	elif not back.visible:
		_pass += 1
		print("[通过] 升华树 Back 按钮隐藏")
	else:
		_fail += 1
		print("[失败] 升华树 Back 按钮应隐藏")
	scene.queue_free()
