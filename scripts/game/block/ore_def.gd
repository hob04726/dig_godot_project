extends BlockDef
class_name OreDef

@export_range(1, 4) var rarity: int = 1
@export var spawn_weight: float = 10.0
@export var base_value: int = 1
@export var base_hp: int = 10
@export var max_level: int = 3
@export var value_growth: float = 2.0
@export var hp_growth: float = 1.5
@export var size_growth: float = 0.25

func get_value(level: int) -> int: return roundi(base_value * pow(value_growth, level - 1))
func get_max_hp(level: int) -> int: return roundi(base_hp * pow(hp_growth, level - 1))
func get_size_scale(level: int) -> float: return 1.0 + size_growth * (level - 1)
func can_upgrade(level: int) -> bool: return level < max_level
