extends SceneTree

## 把整屏截图裁出金币面板区域并放大，另存 JPG 便于查看。

func _init() -> void:
	var img := Image.load_from_file("res://test/capture_amount6.png")
	if img == null:
		print("载入失败")
		quit()
		return
	print("原图尺寸: ", img.get_size(), "  格式: ", img.get_format())
	var crop := img.get_region(Rect2i(20, 10, 150, 90))
	print("裁剪区尺寸: ", crop.get_size(), "  格式: ", crop.get_format())
	crop.resize(750, 450, Image.INTERPOLATE_NEAREST)
	var jpg := crop.save_jpg("res://test/capture_panel.jpg", 0.92)
	print("保存 JPG 结果: ", jpg)
	# 也存一份 PNG 对照
	var png := crop.save_png("res://test/capture_panel.png")
	print("保存 PNG 结果: ", png)
	quit()
