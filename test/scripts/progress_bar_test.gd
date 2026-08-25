extends SceneTree
## 进度条帧数测试：默认使用 15 帧，最后有效帧对应进度接近 1.0 但不越界。

const PROGRESS_SCENE := "res://scenes/vfx/progress_bar.tscn"

var _failures := 0


func _initialize() -> void:
	var bar := (load(PROGRESS_SCENE) as PackedScene).instantiate()
	root.add_child(bar)
	await create_timer(0.05).timeout

	# 反射访问私有数组长度
	var textures: Array = bar.get("_frame_textures")
	var frame_count := textures.size()
	if frame_count == 15:
		print("[通过] 进度条帧数 = 15")
	else:
		_failures += 1
		print("[失败] 进度条帧数 = %d，期望 15" % frame_count)

	# 进度 1.0 不应越界
	bar.set_progress(1.0)
	var tex: AtlasTexture = bar.get_node_or_null("TextureRect").texture
	if tex != null:
		var region_x := int(tex.region.position.x)
		var last_frame_x := (frame_count - 1) * 16
		if region_x == last_frame_x:
			print("[通过] 进度 1.0 对应最后一帧 (%d)" % region_x)
		else:
			_failures += 1
			print("[失败] 进度 1.0 对应帧 x=%d，期望 %d" % [region_x, last_frame_x])
	else:
		_failures += 1
		print("[失败] 获取不到进度条当前帧贴图")

	bar.queue_free()
	print("=== progress_bar_test：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
