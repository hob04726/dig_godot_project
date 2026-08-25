extends Block
class_name OreBlock

## 特殊矿类型：正常 / 价值 buff / 高价值坦克 / 一击即碎
enum SpecialType { NONE, VALUE_BUFF, HIGH_VALUE_TANK, FRAGILE }

## 箔膜/全息 shader
const ORE_FOIL_SHADER := preload("res://scripts/shaders/ore_foil.gdshader")

## 运行时生成的 foil 贴图缓存（避免外部 PNG 导入问题）
static var _foil_mask_tex: Texture2D
static var _foil_noise_tex: Texture2D
static var _foil_normal_tex: Texture2D
static var _gradient_buff_tex: Texture2D
static var _gradient_tank_tex: Texture2D
static var _gradient_fragile_tex: Texture2D

var level: int = 1
var hp: int
var progress: float = 0.0   # 第 7 种地皮（渐进破坏）的进度 0~1
var has_landed := false     # 下落动画播完才为 true（落地前不可挖）
## 最后一次受击的伤害（GameManager 用来决定破坏后飞出的力度）
var kill_damage := 0
## 最后一次受伤的时间戳（秒，用于进度条超时隐藏）
var last_damage_time: float = -1.0

## 特殊矿运行时属性
var special_type: SpecialType = SpecialType.NONE
var special_value_mult: float = 1.0
var special_hp_mult: float = 1.0

## 落地事件：fall 动画结束进入 idle 时发出（经 GameManager 转报 GridModel）
signal landed


func _process(_delta: float) -> void:
	# 特殊矿的 foil shader 需要每帧同步鼠标与精灵位置
	if base_material != null and base_material is ShaderMaterial:
		var mat := base_material as ShaderMaterial
		if mat.shader == ORE_FOIL_SHADER:
			mat.set_shader_parameter("mouse_position", get_global_mouse_position())
			mat.set_shader_parameter("sprite_position", global_position)



func setup_ore(ore_def: OreDef, start_level: int, c: Vector2i) -> void:
	setup_from_def(ore_def, c)
	level = clampi(start_level, 1, ore_def.max_level)
	hp = get_max_hp()
	_refresh_visuals()


func get_def() -> OreDef: return def as OreDef

func get_value() -> int:
	return roundi(get_def().get_value(level) * special_value_mult)

func get_max_hp() -> int:
	if special_type == SpecialType.FRAGILE:
		return 1
	return roundi(get_def().get_max_hp(level) * special_hp_mult)

func get_size_scale() -> float: return get_def().get_size_scale(level)


## 标记为特殊矿，并同步数值/血量倍数
func make_special(type: SpecialType, value_mult: float = 1.0, hp_mult: float = 1.0) -> void:
	special_type = type
	special_value_mult = value_mult
	special_hp_mult = hp_mult
	# 重新按特殊规则设置血量
	hp = get_max_hp()
	_tint_by_special_type()


## 按当前 level 同步贴图与缩放（级别贴图来自 def.textures[level-1]）
func _refresh_visuals() -> void:
	texture_to_show = get_def().get_texture(level - 1)
	size_scale = get_size_scale()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.texture = texture_to_show
		sprite.scale = Vector2.ONE * size_scale * TEXTURE_BASE_SCALE


## 根据特殊类型给精灵染色并挂上对应 foil shader 材质
func _tint_by_special_type() -> void:
	if sprite == null:
		return
	_ensure_foil_textures()
	match special_type:
		SpecialType.VALUE_BUFF:
			sprite.modulate = Color(1.2, 0.7, 1.3)   # 粉紫光晕
			base_material = _create_foil_material(_gradient_buff_tex, 0.6, 0.5)
		SpecialType.HIGH_VALUE_TANK:
			sprite.modulate = Color(1.3, 1.1, 0.6)   # 金黄
			base_material = _create_foil_material(_gradient_tank_tex, 0.55, 0.0)
		SpecialType.FRAGILE:
			sprite.modulate = Color(0.85, 0.85, 0.85)   # 灰白
			base_material = _create_foil_material(_gradient_fragile_tex, 0.5, 0.3)
		_:
			sprite.modulate = Color.WHITE
			base_material = null
	_refresh_sprite_material()


## 延迟初始化 foil 贴图缓存
static func _ensure_foil_textures() -> void:
	if _foil_mask_tex != null:
		return

	var mask_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	mask_img.fill(Color.WHITE)
	_foil_mask_tex = ImageTexture.create_from_image(mask_img)

	var noise_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for y in 128:
		for x in 128:
			var v := rng.randf_range(0.35, 0.65)
			noise_img.set_pixel(x, y, Color(v, v, v, 1.0))
	_foil_noise_tex = ImageTexture.create_from_image(noise_img)

	var normal_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	normal_img.fill(Color(0.5, 0.5, 1.0, 1.0))
	_foil_normal_tex = ImageTexture.create_from_image(normal_img)

	_gradient_buff_tex = _make_gradient_texture(func(x: float) -> Color:
		return Color.from_hsv(fmod(x + 0.1, 1.0), 0.9, 1.0))
	_gradient_tank_tex = _make_gradient_texture(func(x: float) -> Color:
		return Color(1.0, 0.82 + 0.12 * x, 0.15 + 0.35 * x))  # 金黄色单色 shimmer
	_gradient_fragile_tex = _make_gradient_texture(func(x: float) -> Color:
		return Color(0.75 + 0.2 * x, 0.75 + 0.2 * x, 0.75 + 0.2 * x))  # 灰白色单色 shimmer


static func _make_gradient_texture(color_func: Callable) -> Texture2D:
	var img := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	for x in 256:
		img.set_pixel(x, 0, color_func.call(float(x) / 255.0))
	return ImageTexture.create_from_image(img)


## 为特殊矿创建一份箔膜 shader 材质实例
func _create_foil_material(gradient: Texture2D, effect_alpha: float, dir: float) -> ShaderMaterial:
	_ensure_foil_textures()
	var mat := ShaderMaterial.new()
	mat.shader = ORE_FOIL_SHADER
	mat.set_shader_parameter("foilcolor", Color.WHITE)
	mat.set_shader_parameter("threshold", 1.0)
	mat.set_shader_parameter("fuzziness", 0.1)
	mat.set_shader_parameter("period", 1.0)
	mat.set_shader_parameter("scroll", 1.0)
	mat.set_shader_parameter("normal_strength", 0.1)
	mat.set_shader_parameter("effect_alpha_mult", effect_alpha)
	mat.set_shader_parameter("direction", dir)
	mat.set_shader_parameter("foil_mask", _foil_mask_tex)
	mat.set_shader_parameter("gradient", gradient)
	mat.set_shader_parameter("noise", _foil_noise_tex)
	mat.set_shader_parameter("normal_map", _foil_normal_tex)
	return mat


func on_landed() -> void:
	has_landed = true
	landed.emit()


## 受击/破碎粒子反馈
func burst_particles() -> void:
	var particles := get_node_or_null("GPUParticles2D") as GPUParticles2D
	if particles:
		particles.restart()


## 返回 true = 碎了。破碎后的网格移除由调用方走 grid.remove_ore()，
## OreBlock 自己不碰网格 —— 这是保住鲁棒性的核心纪律
func take_damage(amount: int) -> bool:
	hp -= amount
	last_damage_time = Time.get_ticks_msec() / 1000.0
	return hp <= 0


func add_progress(amount: float) -> bool:
	progress += amount
	return progress >= 1.0


func upgrade_level() -> bool:
	if not get_def().can_upgrade(level):
		return false
	level += 1
	hp = get_max_hp()
	_refresh_visuals()
	return true
