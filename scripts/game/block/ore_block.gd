extends Block
class_name OreBlock

var level: int = 1
var hp: int
var progress: float = 0.0   # 第 7 种地皮（渐进破坏）的进度 0~1
var has_landed := false     # 下落动画播完才为 true（落地前不可挖）
## 最后一次受击的伤害（GameManager 用来决定破坏后飞出的力度）
var kill_damage := 0

## 落地事件：fall 动画结束进入 idle 时发出（经 GameManager 转报 GridModel）
signal landed



func setup_ore(ore_def: OreDef, start_level: int, c: Vector2i) -> void:
	setup_from_def(ore_def, c)
	level = clampi(start_level, 1, ore_def.max_level)
	hp = get_max_hp()
	_refresh_visuals()


func get_def() -> OreDef: return def as OreDef
func get_value() -> int: return get_def().get_value(level)
func get_max_hp() -> int: return get_def().get_max_hp(level)
func get_size_scale() -> float: return get_def().get_size_scale(level)


## 按当前 level 同步贴图与缩放（级别贴图来自 def.textures[level-1]）
func _refresh_visuals() -> void:
	texture_to_show = get_def().get_texture(level - 1)
	size_scale = get_size_scale()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.texture = texture_to_show
		sprite.scale = Vector2.ONE * size_scale * TEXTURE_BASE_SCALE


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
