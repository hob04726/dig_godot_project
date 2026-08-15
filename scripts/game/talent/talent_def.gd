extends Resource
class_name TalentDef

## 天赋定义：格子位置(col,row，中心为 0) + 名字 + 解锁金币 + 前置天赋 + 图标。
## 实际效果字段（加成类型/数值）等"天赋机制阶段"再补；现在驱动显示/前置/购买。

@export var id: StringName
@export var display_name: String = ""
@export var cost: int = 0
## 网格坐标：col 右正左负、row 下正上负，中心(0,0)是重置节点
@export var col: int = 0
@export var row: int = 0
## 前置天赋 id：必须先购买它本天赋才显示/可解锁；空 = 开局可见
@export var prerequisite_id: StringName = &""
@export var icon: Texture2D = null
