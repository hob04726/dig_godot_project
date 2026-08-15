extends BlockDef
class_name TileDef

## 地皮行为（"地皮阶段"）。
## 周期性行为由 GridModel.tick 驱动；事件行为（落矿/结算/受击）由对应钩子触发。
## 数值写在 defs/tiles/*.tres 里。枚举值是稳定的整数，写进 .tres 时保持一致。

enum Behavior {
	NONE = 0,      # 普通地皮，无行为（dirt）
	WATER = 1,     # 落上去的矿直接沉没消失
	VOLCANO = 2,   # 周期性攻击四邻的矿；自身不能承载矿
	UPGRADE = 3,   # 周期性给上方矿升一级
	STONE = 4,     # 上方矿结算价值更高
	SPAWN = 5,     # 周期性在自身生成矿石
	RARITY = 6,    # 自动落矿时提高稀有度下限
	PUSH = 7,      # 周期性把上方矿随机推向四邻
	PULL = 8,      # 周期性把邻格的矿吸到自身
	GRASS = 9,     # 上方矿受到的挖矿伤害更高
	FIRE = 10,     # 周期性给上方矿伤害
}

## 该地皮的行为类型
@export var behavior: Behavior = Behavior.NONE

## 周期性行为的触发间隔（秒）：volcano/upgrade/spawn/push/pull/fire
@export var tick_interval: float = 2.0
## 每次造成伤害：volcano（对四邻）/ fire（对上方）
@export var damage: float = 0.0
## 结算价值倍率：stone
@export var value_multiplier: float = 1.0
## 受到的伤害倍率：grass（挖矿时）
@export var damage_multiplier: float = 1.0
## 落矿稀有度下限：rarity
@export var min_rarity: int = 1
## spawn 生成的矿石 id
@export var spawn_ore_id: StringName = &"crystal"
