extends Resource
class_name TalentDef

## 天赋定义（数据层）：由 TalentDb 从 defs/talents/*.csv 解析填充。
## 两种 CSV 列结构不同（普通 24 列 / 升华 13 列），缺的字段落到默认值。
## cost 用 BigNumber——CSV 最高成本到 e+49，int 会溢出。

@export var id: StringName
@export var display_name: String = ""
## 描述（含 BBCode 颜色标签，RichTextLabel 直接渲染）
@export var description: String = ""
## 货币：普通天赋 = 金币；升华天赋 = 升华点
@export var currency: String = "金币"
## 成本（大数；BigNumber 非 Resource 不支持 @export，由 TalentDb 运行时填充）
var cost: BigNumber = null
## 成本紧凑显示（直接来自 CSV 的 cost_display 列，或由 cost 格式化）
@export var cost_display: String = ""
## 网格坐标：col 右正左负、row 下正上负，中心(0,0)是重置节点
@export var col: int = 0
@export var row: int = 0
## 前置天赋 id 列表（可能多个，全部购买后才显示/可解锁）
@export var prerequisite_ids: Array[StringName] = []
## 前置天赋所需等级，与 prerequisite_ids 一一对应；0 或空表示只需购买（>=1）
@export var prerequisite_ranks: Array[int] = []
## 普通天赋的升华前置（普通树节点还受升华天赋门控；空 = 无）
@export var ascension_prerequisite_id: StringName = &""
## 解锁条件（自由文本，如 "coal_mined ≥ 50"）
@export var unlock_condition: String = ""
## 效果类型（如 UNLOCK_ORE / ORE_VALUE_MULT / TILE_BEHAVIOR_UP …），机制阶段消费
@export var effect_type: String = ""
@export var target_ids: Array[StringName] = []
@export var operation: String = ""
## 效果数值（原始字符串：可能是 "2" / "0.1" / "5% / 0.1%" 等）
@export var value: String = ""
@export var max_rank: int = 1
@export var cost_mult: int = 5
@export var group: String = ""
@export var branch: String = ""
@export var level: String = ""
@export var stage: String = ""
@export var requires_big_number: bool = false
## 图标（.tres 阶段再分配，现在留空）
@export var icon: Texture2D = null
