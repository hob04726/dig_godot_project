class_name SceneTransition
extends CanvasLayer

## 场景切换转场（luminance mask 虹膜开合式）：
##   盖上：扫 cutoff 1→0，径向 mask 让 display 从中心铺满屏幕（盖住旧场景）；
##   切场景；然后揭开：扫 cutoff 0→1，display 从边缘退去露出新场景。
## 挂载在 SceneTree.root 下（跨场景存活），layer 100 盖在所有画面之上。

const TRANSITION_SHADER := preload("res://scripts/shaders/scene_transition.gdshader")
const MASK_SIZE := 256
const FADE_TIME := 0.5
const DISPLAY_COLOR := Color.WHITE   # 盖上时的底色（白色过场）

static var _instance: SceneTransition = null
static var _used := false   # 进程内是否已发生过转场（区分"游戏首次启动"与"从别的场景切回来"）

## 遮罩贴图：灰度图（亮处显示 display_texture、暗处透明）。
## 在 scenes/ui/scene_transition.tscn 的 Inspector 里选；留空则用程序生成的径向渐变。
@export var mask_texture: Texture2D = null
## 盖上时显示的贴图：留空则用纯色（DISPLAY_COLOR）
@export var display_texture: Texture2D = null

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _busy := false   # 转场进行中，忽略重复触发


## 单例：确保转场层挂在 root（场景切换不会被释放）
static func get_instance() -> SceneTransition:
	if _instance == null or not is_instance_valid(_instance):
		var scene := load("res://scenes/ui/scene_transition.tscn") as PackedScene
		var t := scene.instantiate() as SceneTransition
		t.name = "SceneTransition"
		(Engine.get_main_loop() as SceneTree).root.add_child(t)
		_instance = t
	return _instance


## 对外入口：播放转场并切换到 scene_path
static func play_to(scene_path: String) -> void:
	_used = true
	get_instance().play_transition(scene_path)


## 对外入口：游戏首次启动时的开场揭开（主场景 _ready 调用）。
## 从天赋界面等经 play_to 切回主场景时，play_to 自己已经播过揭开，这里跳过。
static func play_entry() -> void:
	if _used:
		return
	_used = true
	# 主场景 _ready 期间 root 还在装子节点，直接 add_child 会失败 → 推迟到帧末
	# （deferred 在首帧绘制前执行，不会闪出未覆盖的画面）
	Callable(func() -> void: get_instance().play_reveal()).call_deferred()


func _ready() -> void:
	layer = 100                                   # 盖在所有画面之上
	process_mode = Node.PROCESS_MODE_ALWAYS   # 场景切换期间也继续动画
	_material = ShaderMaterial.new()
	_material.shader = TRANSITION_SHADER
	# 用 Inspector 里选的遮罩/显示贴图，留空则回退程序生成
	_material.set_shader_parameter("mask_texture",
		mask_texture if mask_texture != null else _make_radial_mask())
	_material.set_shader_parameter("display_texture",
		display_texture if display_texture != null else _make_solid(DISPLAY_COLOR))
	_material.set_shader_parameter("luminance_cutoff", 1.0)   # 初始全透明（场景可见）
	_rect = ColorRect.new()
	_rect.name = "TransitionOverlay"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _material
	add_child(_rect)
	_rect.visible = false


## 播放转场：盖上 → 切换 → 揭开
func play_transition(scene_path: String) -> void:
	if _busy or _material == null or _rect == null:
		return   # 转场中不重复触发（防止转场未结束又点按钮）
	_busy = true
	_rect.visible = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP   # 转场期间挡住所有点击
	_set_cutoff(1.0)
	var tween := create_tween()
	tween.tween_method(_set_cutoff, 1.0, 0.0, FADE_TIME)   # 盖上（虹膜关闭）
	await tween.finished
	get_tree().change_scene_to_file(scene_path)
	# 等新场景加载完成再揭开
	for i in 3:
		await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_method(_set_cutoff, 0.0, 1.0, FADE_TIME)      # 揭开（虹膜打开）
	await t2.finished
	_rect.visible = false
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


## 只播"揭开"：初始全盖住（cutoff 0）→ 扫到 1 露出场景。用于游戏首次启动开场。
func play_reveal() -> void:
	if _busy or _material == null or _rect == null:
		return
	_busy = true
	_rect.visible = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP   # 开场期间挡住点击
	_set_cutoff(0.0)
	var t := create_tween()
	t.tween_method(_set_cutoff, 0.0, 1.0, FADE_TIME)   # 揭开（虹膜打开）
	await t.finished
	_rect.visible = false
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _set_cutoff(v: float) -> void:
	_material.set_shader_parameter("luminance_cutoff", v)


## 径向渐变 mask：中心亮(1) → 边缘暗(0)
func _make_radial_mask() -> ImageTexture:
	var img := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGB8)
	var half := MASK_SIZE * 0.5
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			var d := Vector2(x - half, y - half).length() / half
			var lum := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(lum, lum, lum))
	return ImageTexture.create_from_image(img)


## 纯色 display 贴图（盖上时的颜色）
func _make_solid(c: Color) -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)
