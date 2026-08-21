class_name WhiteFade
extends CanvasLayer

## 全屏白场淡入淡出转场：淡入 → 切换场景 → 淡出。
## 实例挂到 root，场景切换不会销毁它。

const WHITE_FADE_SCENE_PATH := "res://scenes/ui/white_fade.tscn"

@onready var _rect: ColorRect = $ColorRect


## 对外入口：淡入 -> 切换场景(可选) -> 淡出，结束后自动释放。
## duration_in: 淡入时长；hold: 白场停留；duration_out: 淡出时长；next_scene: 空字符串则不切场景。
static func play(duration_in: float = 0.5, hold: float = 0.0,
		duration_out: float = 0.5, next_scene: String = "") -> void:
	var scene := load(WHITE_FADE_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("WhiteFade: 无法加载场景 %s" % WHITE_FADE_SCENE_PATH)
		return
	var inst := scene.instantiate() as WhiteFade
	(Engine.get_main_loop() as SceneTree).root.add_child(inst)
	inst._run(duration_in, hold, duration_out, next_scene)


func _run(duration_in: float, hold: float, duration_out: float, next_scene: String) -> void:
	layer = 101                      # 盖在 SceneTransition (100) 之上
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP   # 转场期间挡住点击

	var tween_in := create_tween()
	tween_in.tween_property(_rect, "modulate:a", 1.0, duration_in)
	await tween_in.finished

	if hold > 0.0:
		await get_tree().create_timer(hold).timeout

	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)
		for i in 3:
			await get_tree().process_frame

	var tween_out := create_tween()
	tween_out.tween_property(_rect, "modulate:a", 0.0, duration_out)
	await tween_out.finished

	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_free()
