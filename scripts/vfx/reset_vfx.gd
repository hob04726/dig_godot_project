extends Node2D
class_name ResetVfx

## 升华（重置）特效控制器：展示金币累计到下一个升华点的过程。
## 黄色水位随 lifetime_coins 增加而上升，每跨过一个升华点阈值时闪烁一次，
## 同时更新升华点计数。

## 球体精灵（挂载 reset_orb.gdshader）
@export var orb_sprite: Sprite2D = null
## 升华点数字标签
@export var points_label: RichTextLabel = null
## 累计金币数字标签
@export var lifetime_label: RichTextLabel = null

## 动画总时长（秒）
@export var duration: float = 3.0

signal finished

const COINS_PER_POINT_BASE := 1_000_000

var _from_lifetime: BigNumber = BigNumber.zero()
var _to_lifetime: BigNumber = BigNumber.zero()
var _from_points: BigNumber = BigNumber.zero()
var _to_points: BigNumber = BigNumber.zero()
var _elapsed: float = 0.0
var _running: bool = false
var _last_points: BigNumber = BigNumber.from_int(-1)
var _light_timer: float = 0.0


func _ready() -> void:
	if orb_sprite == null:
		orb_sprite = get_node_or_null("OrbSprite") as Sprite2D
	if points_label == null:
		points_label = get_node_or_null("PointsLabel") as RichTextLabel
	if lifetime_label == null:
		lifetime_label = get_node_or_null("LifetimeLabel") as RichTextLabel
	_ensure_orb_texture()


## 准备数据：从升华前的累计金币到升华后的累计金币
func setup(from_lifetime: BigNumber, to_lifetime: BigNumber) -> void:
	_from_lifetime = from_lifetime
	_to_lifetime = to_lifetime
	_from_points = Prestige.points_for(from_lifetime)
	_to_points = Prestige.points_for(to_lifetime)
	_last_points = _from_points
	_update_labels(_from_lifetime, _from_points)


## 开始播放动画
func play() -> void:
	_elapsed = 0.0
	_running = true
	_light_timer = 0.0
	_update_labels(_from_lifetime, _from_points)


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	var t := clampf(_elapsed / duration, 0.0, 1.0)
	var current_lifetime := _lerp_big(_from_lifetime, _to_lifetime, t)
	var current_points := Prestige.points_for(current_lifetime)
	var root := _cbrt_lifetime(current_lifetime)
	var progress := clampf(root - floor(root), 0.0, 1.0)

	_set_orb_height(progress)

	# 跨越升华点阈值时触发闪光
	if current_points.gt(_last_points):
		_trigger_point_flash()
	_last_points = current_points

	# 闪光衰减
	if _light_timer > 0.0:
		_light_timer -= delta
		_set_light_effect(_light_timer > 0.0)

	_update_labels(current_lifetime, current_points)

	if t >= 1.0:
		_running = false
		_set_orb_height(1.0)
		_set_light_effect(false)
		_update_labels(_to_lifetime, _to_points)
		finished.emit()


func _set_orb_height(value: float) -> void:
	if orb_sprite == null or orb_sprite.material == null:
		return
	var mat := orb_sprite.material as ShaderMaterial
	mat.set_shader_parameter("height", value)
	mat.set_shader_parameter("oheight", value)


func _set_light_effect(active: bool) -> void:
	if orb_sprite == null or orb_sprite.material == null:
		return
	var mat := orb_sprite.material as ShaderMaterial
	mat.set_shader_parameter("light_effect", active)


func _trigger_point_flash() -> void:
	_light_timer = 0.35
	_set_light_effect(true)


func _update_labels(lifetime: BigNumber, points: BigNumber) -> void:
	if points_label != null:
		points_label.text = "[center]升华点：%s[/center]" % points.to_full_string()
	if lifetime_label != null:
		lifetime_label.text = "[center]累计金币：%s$[/center]" % lifetime.to_compact_string()


## 计算 cbrt(lifetime / 1e6)，返回 float（0~N，N 为当前升华点数）
func _cbrt_lifetime(lifetime: BigNumber) -> float:
	var base := BigNumber.from_int(COINS_PER_POINT_BASE)
	var ratio := lifetime.div(base)
	var root := ratio.cbrt()
	return root.to_float()


## BigNumber 线性插值：a + (b - a) * t
func _lerp_big(a: BigNumber, b: BigNumber, t: float) -> BigNumber:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	return a.add(b.sub(a).mul(BigNumber.from_float(t)))


## 如果 orb 没有贴图，创建一个纯白方块作为绘制载体
func _ensure_orb_texture() -> void:
	if orb_sprite == null:
		return
	if orb_sprite.texture != null:
		return
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	orb_sprite.texture = ImageTexture.create_from_image(img)
