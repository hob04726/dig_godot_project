extends SceneTree

## 天赋节点悬停描边验证：左 = 悬停（应显示白色外边框），右 = 未悬停对照。
## 同时断言：图标贴图已烘焙为 ImageTexture、悬停挂上共享描边材质。
## 运行：godot --path . --script res://test/scripts/talent_outline_capture.gd（非 headless，会闪窗）

func _init() -> void:
	var node_scene := load("res://scenes/talent_node.tscn") as PackedScene

	var hovered_node := node_scene.instantiate() as TalentNode
	hovered_node.position = Vector2(280, 320)
	root.add_child(hovered_node)
	var normal_node := node_scene.instantiate() as TalentNode
	normal_node.position = Vector2(520, 320)
	root.add_child(normal_node)
	await process_frame   # 等 _ready

	for n in [hovered_node, normal_node]:
		n.set_state(TalentNode.State.PURCHASED, false)   # 满透明度，看得最清楚

	# 功能断言
	assert(hovered_node.icon_sprite.texture is ImageTexture, "图标应烘焙为 ImageTexture")
	hovered_node.set_hovered(true)
	assert(hovered_node.icon_sprite.material is ShaderMaterial, "悬停应挂描边材质")
	assert(normal_node.icon_sprite.material == null, "未悬停不应有材质")
	normal_node.set_hovered(false)
	print("断言通过：ImageTexture 烘焙 + 悬停挂材质 + 未悬停无材质")

	# 等悬停放大 tween 播完再截图
	await create_timer(0.5).timeout
	var img := root.get_texture().get_image()
	img.save_png("res://test/capture_talent_outline.png")
	print("已保存 res://test/capture_talent_outline.png")
	quit()
