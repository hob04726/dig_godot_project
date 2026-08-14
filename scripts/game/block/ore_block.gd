extends Block
class_name OreBlock

var level: int = 1
var hp: int
var progress: float = 0.0   # 第 7 种地皮（渐进破坏）的进度 0~1



func setup_ore(ore_def: OreDef, start_level: int, c: Vector2i) -> void:
	setup_from_def(ore_def, c)
	level = clampi(start_level, 1, ore_def.max_level)
	hp = get_max_hp()
	size_scale = get_size_scale()


func get_def() -> OreDef: return def as OreDef
func get_value() -> int: return get_def().get_value(level)
func get_max_hp() -> int: return get_def().get_max_hp(level)
func get_size_scale() -> float: return get_def().get_size_scale(level)


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
	return true
