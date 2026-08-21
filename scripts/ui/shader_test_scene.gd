extends Node2D
## ShaderTest 场景驱动：给 5 个等级示例节点挂上与天赋节点一致的 rank 外观，
## 每帧同步鼠标位置，让 card.gdshader 的透视 tilt 和 foil shimmer 跟随光标。

const CARD_SHADER := preload("res://scripts/shaders/card.gdshader")
const FOIL_MASK := preload("res://assets/masks/foil_mask.png")
const NOISE_TEX := preload("res://assets/noise/noise_fine.png")
const NORMAL_CIRCLES := preload("res://assets/Cards/Normals/normal_circles.jpg")
const NORMAL_7813 := preload("res://assets/Cards/Normals/7813-normal.jpg")
const NORMAL_GROOVY := preload("res://assets/Cards/Normals/groovy normal.png")
const NORMAL_12551 := preload("res://assets/Cards/Normals/12551-normal.jpg")
const GRADIENT_RAINBOW := preload("res://assets/gradients/gradient_rainbow.png")

const TARGET_PATHS: Array[String] = ["level1", "level2", "level3", "level4", "level5"]

static var _rank_gradient_cache: Dictionary = {}


func _ready() -> void:
	for i in TARGET_PATHS.size():
		var sprite := get_node_or_null(TARGET_PATHS[i]) as Sprite2D
		if sprite == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = CARD_SHADER
		mat.set_shader_parameter("foil_mask", FOIL_MASK)
		mat.set_shader_parameter("noise", NOISE_TEX)
		mat.set_shader_parameter("foilcolor", Color(0, 0, 0))
		mat.set_shader_parameter("enable_tilt", false)   # 取消鼠标位置导致的倾斜
		_apply_rank_style(mat, i + 1)
		sprite.material = mat


func _process(_delta: float) -> void:
	var mouse_pos := get_global_mouse_position()
	for path in TARGET_PATHS:
		var sprite := get_node_or_null(path) as Sprite2D
		if sprite == null or sprite.material == null:
			continue
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("mouse_position", mouse_pos)
		mat.set_shader_parameter("sprite_position", sprite.global_position)


func _apply_rank_style(mat: ShaderMaterial, rank: int) -> void:
	var r := clampi(rank, 1, 5)
	var grad: Texture2D = null
	var normal: Texture2D = null
	var threshold := 0.1
	var normal_strength := 0.1
	var effect_alpha := 1.0

	match r:
		2:
			grad = _ensure_rank_gradient(2)
			normal = NORMAL_CIRCLES
			threshold = 2.0
			normal_strength = 3.0
			effect_alpha = 0.1
		3:
			grad = _ensure_rank_gradient(3)
			normal = NORMAL_7813
			threshold = 2.0
			normal_strength = 3.0
			effect_alpha = 0.1
		4:
			grad = _ensure_rank_gradient(4)
			normal = NORMAL_GROOVY
			threshold = 2.0
			normal_strength = 3.0
			effect_alpha = 0.1
		5:
			grad = GRADIENT_RAINBOW
			normal = NORMAL_12551
			threshold = 2.0
			normal_strength = 3.0
			effect_alpha = 0.1

	mat.set_shader_parameter("gradient", grad)
	mat.set_shader_parameter("normal_map", normal)
	mat.set_shader_parameter("threshold", threshold)
	mat.set_shader_parameter("normal_strength", normal_strength)
	mat.set_shader_parameter("effect_alpha_mult", effect_alpha)


func _ensure_rank_gradient(rank: int) -> Texture2D:
	if _rank_gradient_cache.has(rank):
		return _rank_gradient_cache[rank]
	var grad := Gradient.new()
	match rank:
		2:
			grad.add_point(0.0, Color(0.0, 1.0, 1.0))
			grad.add_point(0.5, Color(0.0, 0.0, 1.0))
			grad.add_point(1.0, Color(0.0, 1.0, 1.0))
		3:
			grad.add_point(0.0, Color(0.0, 1.0, 0.0))
			grad.add_point(0.44, Color(0.0, 0.376, 0.0))
			grad.add_point(1.0, Color(0.0, 1.0, 0.0))
		4:
			grad.add_point(0.0, Color(0.0, 0.0, 0.0))
			grad.add_point(0.57, Color(1.0, 1.0, 1.0))
			grad.add_point(1.0, Color(0.0, 0.0, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	_rank_gradient_cache[rank] = tex
	return tex
