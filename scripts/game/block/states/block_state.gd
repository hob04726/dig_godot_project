extends Node
class_name BlockState

## 状态机中的行为节点：enter/exit 由 Block.change_state 驱动。
## 各状态用 Godot 内置 Tween 播放自己的视觉动画（不再使用 AnimationTree/AnimationPlayer）。

var context: Block


func enter() -> void:
	pass


func exit() -> void:
	pass
