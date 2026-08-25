extends SceneTree

## 测试普通天赋树中央的 reset 节点（PRESTIGE_RESET）在不同 lifetime 下的水位显示。
## 非 headless 运行：godot --path . --script res://test/scripts/talent_reset_orb_capture.gd

func _init() -> void:
	# 模拟升华天赋场景的暗紫背景
	var bg := ColorRect.new()
	bg.color = Color(0.356, 0.0, 0.373, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	
	var packed := load("res://scenes/talent_node.tscn") as PackedScene
	var node := packed.instantiate() as TalentNode
	node.position = Vector2(576, 324)   # 屏幕中心
	root.add_child(node)
	
	var def := TalentDef.new()
	def.id = &"talent_reset"
	def.display_name = "重置·升华"
	def.effect_type = "PRESTIGE_RESET"
	def.cost = BigNumber.zero()
	def.currency = "金币"
	node.setup(def)
	node.set_state(TalentNode.State.AVAILABLE, false)
	
	var lifetimes := [0, 50, 5_000, 500_000, 1_500_000, 5_500_000]
	for lifetime in lifetimes:
		node.set_orb_progress(BigNumber.from_int(lifetime))
		await process_frame
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		var path := "res://test/capture_reset_node_%d.png" % lifetime
		img.save_png(path)
		var mat := node.orb_sprite.material as ShaderMaterial
		var height: float = mat.get_shader_parameter("height") if mat != null else -1.0
		print("lifetime=%d -> actual_height=%.3f, 截图: %s" % [lifetime, height, path])
	
	quit()
