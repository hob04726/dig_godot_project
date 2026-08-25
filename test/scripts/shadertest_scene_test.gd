extends SceneTree

## 验证 shadertest 场景能正确加载，5 个 level 节点都挂上了 card.gdshader，
## 并按 rank 设置了 gradient / normal_map，同时 mouse_position / sprite_position 被驱动脚本更新。

var _failures := 0

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)

func _run() -> void:
	var scene := (load("res://scenes/vfx/shadertest.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame

	var driver := scene as Node2D
	_check(driver != null and driver.script != null, "场景根节点带有驱动脚本")

	var expected := ["level1", "level2", "level3", "level4", "level5"]
	var expected_normals := [null, "normal_circles", "7813-normal", "groovy normal", "12551-normal"]
	var expected_gradients := ["", "", "", "", "gradient_rainbow"]
	for i in expected.size():
		var sprite := scene.get_node_or_null(expected[i]) as Sprite2D
		_check(sprite != null, "%s 节点存在" % expected[i])
		if sprite == null:
			continue
		_check(sprite.material != null and sprite.material is ShaderMaterial, "%s 已挂上 ShaderMaterial" % expected[i])
		if sprite.material == null:
			continue
		var mat := sprite.material as ShaderMaterial
		_check(mat.shader != null, "%s 材质有 shader" % expected[i])
		if mat.shader == null:
			continue
		var shader_path := mat.shader.resource_path
		_check(shader_path.find("card.gdshader") != -1, "%s 使用了 card.gdshader" % expected[i])
		_check(mat.get_shader_parameter("mouse_position") is Vector2, "%s mouse_position 已设置" % expected[i])
		_check(mat.get_shader_parameter("sprite_position") is Vector2, "%s sprite_position 已设置" % expected[i])

		var threshold: float = mat.get_shader_parameter("threshold")
		var effect_alpha: float = mat.get_shader_parameter("effect_alpha_mult")
		if i == 0:
			_check(threshold < 1.0 and effect_alpha > 0.5, "%s rank 1 为默认强 foil" % expected[i])
		else:
			_check(threshold >= 1.9 and effect_alpha <= 0.2, "%s rank %d 为彩色微光" % [expected[i], i + 1])

		var normal := mat.get_shader_parameter("normal_map") as Texture2D
		var gradient := mat.get_shader_parameter("gradient") as Texture2D
		if expected_normals[i] != null:
			_check(normal != null and normal.resource_path.find(expected_normals[i]) != -1, "%s normal_map 匹配" % expected[i])
		if expected_gradients[i] != "":
			_check(gradient != null and gradient.resource_path.find(expected_gradients[i]) != -1, "%s gradient 匹配" % expected[i])

	_finish()

func _finish() -> void:
	print("=== shadertest_scene_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
