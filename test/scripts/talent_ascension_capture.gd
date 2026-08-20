extends SceneTree

## 截取升华天赋场景，查看中央 reset 节点在真实背景下的显示。
## 非 headless 运行：godot --path . --script res://test/scripts/talent_ascension_capture.gd

func _init() -> void:
	var packed := load("res://scenes/talent_ascension.tscn") as PackedScene
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	
	# 伪造一个带 lifetime_coins 的 state，让中央球显示约 50% 水位
	var state := GameState.new()
	state.load_from_dict({
		"coins": "0",
		"lifetime_coins": "5000000",
		"ascension_points_earned": "0",
		"ascension_points_spent": 0,
		"run_version": 1,
		"ore_mined": {},
		"talents": {},
		"ascension_talents": {},
		"world_name": "小世界",
	})
	
	var grid := scene.get_node("TalentAscension") as TalentGrid
	grid.setup(state)
	
	await process_frame
	await process_frame
	await process_frame
	
	var img := root.get_texture().get_image()
	var path := "res://test/capture_talent_ascension_orb.png"
	img.save_png(path)
	print("已保存截图: ", path)
	
	quit()
