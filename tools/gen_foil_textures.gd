extends SceneTree

## 一次性工具：生成箔膜/全息 shader 所需的占位贴图
## 运行：godot --headless --path . --script res://tools/gen_foil_textures.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	var dirs := ["res://assets/gradients", "res://assets/noise", "res://assets/normal"]
	for d in dirs:
		DirAccess.make_dir_recursive_absolute(d)

	# 彩虹渐变
	_save_gradient("res://assets/gradients/gradient_rainbow.png", func(x: float) -> Color:
		return Color.from_hsv(fmod(x + 0.1, 1.0), 0.9, 1.0))

	# 金橙渐变
	_save_gradient("res://assets/gradients/gradient_gold.png", func(x: float) -> Color:
		return Color(1.0, 0.5 + 0.5 * x, 0.1 + 0.2 * x).lerp(Color.WHITE, 0.15))

	# 火红渐变（易碎矿）
	_save_gradient("res://assets/gradients/gradient_fire.png", func(x: float) -> Color:
		return Color(1.0, 0.2 + 0.5 * x, 0.05 + 0.1 * x))

	# 细密 noise（灰度）
	_save_noise("res://assets/noise/noise_fine.png", 128)

	# 中性 normal 贴图（偏蓝）
	_save_normal_flat("res://assets/normal/normal_flat.png", 128)

	# 纯白 foil mask
	_save_white("res://assets/masks/foil_mask.png", 128)

	print("箔膜贴图生成完成")
	quit(0)


func _save_gradient(path: String, color_func: Callable) -> void:
	var img := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	for x in 256:
		img.set_pixel(x, 0, color_func.call(float(x) / 255.0))
	img.save_png(path)


func _save_noise(path: String, size: int) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for y in size:
		for x in size:
			var v := rng.randf_range(0.35, 0.65)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	img.save_png(path)


func _save_normal_flat(path: String, size: int) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var neutral := Color(0.5, 0.5, 1.0, 1.0)
	for y in size:
		for x in size:
			img.set_pixel(x, y, neutral)
	img.save_png(path)


func _save_white(path: String, size: int) -> void:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.save_png(path)
