extends BlockDef
class_name TileDef

## 地皮行为（"地皮阶段"）。
## 周期性行为由 GridModel.tick 驱动；事件行为（落矿/结算/受击）由对应钩子触发。
## 数值写在 defs/tiles/*.tres 里。枚举值是稳定的整数，写进 .tres 时保持一致。

enum Behavior {
	NONE = 0,                 # 普通地皮，无行为（dirt）
	WATER = 1,                # 落上去的矿直接沉没消失
	DEPRECATED_VOLCANO = 2,   # 已删除：火山（保留数值保证旧档/枚举稳定）
	UPGRADE = 3,              # 周期性给上方矿升一级
	STONE = 4,                # 上方矿结算价值更高
	SPAWN = 5,                # 周期性在自身生成矿石
	RARITY = 6,               # 自动落矿时提高稀有度下限
	PUSH = 7,                 # 周期性把上方矿随机推向四邻
	PULL = 8,                 # 周期性把邻格的矿吸到自身
	GRASS = 9,                # 上方矿受到的挖矿伤害更高
	FIRE = 10,                # 周期性给上方矿伤害
	CONVEYOR_BELT_LEFTDOWN = 11,  # 传送带：把上方矿推向左下（grid +0,+1）
	CONVEYOR_BELT_LEFTUP = 12,    # 传送带：把上方矿推向左上（grid -1, 0）
	CONVEYOR_BELT_RIGHTDOWN = 13, # 传送带：把上方矿推向右下（grid +1, 0）
	CONVEYOR_BELT_RIGHTUP = 14,   # 传送带：把上方矿推向右上（grid 0,-1）
	TNT_SPAWN = 15,           # 周期性在自身生成 TNT 矿
	TNT = 16,                 # TNT 地皮：放置后生成 TNT 矿，倒计时后引爆
}

## 该地皮的行为类型
@export var behavior: Behavior = Behavior.NONE

## 周期性行为的触发间隔（秒）：upgrade/spawn/push/pull/fire/conveyor/tnt_spawn
@export var tick_interval: float = 2.0
## 每次造成伤害：fire（对上方）
@export var damage: float = 0.0
## 结算价值倍率：stone
@export var value_multiplier: float = 1.0
## 受到的伤害倍率：grass（挖矿时）
@export var damage_multiplier: float = 1.0
## 落矿稀有度下限：rarity
@export var min_rarity: int = 1
## spawn 生成的矿石 id
@export var spawn_ore_id: StringName = &"crystal"
## 放置基准价：放置计价 = base × 1.15^已放置数；卖出返 25%
@export var base_cost: int = 0
## 水格沉没返还比例（TILE_BEHAVIOR_UP 的 water 升级覆盖它）
@export var sink_refund_ratio: float = 0.1
