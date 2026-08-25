extends SceneTree

## 分析整屏截图里金币面板区域 (48,33)-(134,73) 的实际像素，
## 判断 amount=6 时火焰是否真的渲染出来了。

func _init() -> void:
	var img := Image.load_from_file("res://test/capture_amount6.png")
	if img == null:
		print("载入失败")
		quit()
		return
	var panel := Rect2i(48, 33, 86, 40)
	var fire_px := 0
	var dark_px := 0
	var bg_px := 0
	var rows: Array = []
	for y in range(panel.position.y, panel.position.y + panel.size.y):
		var row := ""
		for x in range(panel.position.x, panel.position.x + panel.size.x):
			var c := img.get_pixel(x, y)
			var is_fire := c.r > 0.5 and c.g > 0.3 and c.r > c.b
			var is_bg := c.r > 0.8 and c.g > 0.8 and c.b > 0.8
			if is_fire:
				fire_px += 1
				row += "#"
			elif is_bg:
				bg_px += 1
				row += "."
			else:
				dark_px += 1
				row += "o"
		rows.append(row)
	print("面板 86x40 像素分布: fire=%d  bg(透出背景)=%d  other=%d" % [fire_px, bg_px, dark_px])
	for r in rows:
		print(r)
	quit()
