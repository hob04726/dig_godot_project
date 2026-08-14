extends Node2D

@onready var game_manager: GameManager = $World

## 测试用候选点：初始 3x3 中除 (1,1)（初始金矿）外的格子
const SPAWN_CANDIDATES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(0, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1),
]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_C and event.pressed:
			print("开始创建一个矿物")
			var ore_def := game_manager.db.roll_ore()
			if ore_def == null:
				return
			for cell in SPAWN_CANDIDATES:
				if game_manager.is_above_free(cell):
					game_manager.spawn_ore(cell, ore_def, 1)
					print("生成 %s 于 %s" % [ore_def.display_name, cell])
					return
			print("没有空闲格子了")
