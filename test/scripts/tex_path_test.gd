extends SceneTree

## DefDb 冒烟测试（取代原 BlockData 贴图路径测试）
## 运行：godot --headless --script res://test/scripts/tex_path_test.gd


func _init() -> void:
	var db := DefDb.new()
	db.load_all()

	print("=== 矿石定义 ===")
	for ore_def in db.ores.values():
		var tex := ore_def.get_texture(0)
		print("%s | rarity=%d weight=%.1f 价值=%d 血量=%d | %s" % [
			ore_def.id, ore_def.rarity, ore_def.spawn_weight,
			ore_def.base_value, ore_def.base_hp,
			tex.resource_path if tex else "<无贴图>",
		])

	print("=== 地皮定义 ===")
	for tile_def in db.tiles.values():
		var tex := tile_def.get_texture(0)
		print("%s | %s" % [tile_def.id, tex.resource_path if tex else "<无贴图>"])

	print("=== 加权抽取（rarity>=2，10 次）===")
	for i in 10:
		var rolled := db.roll_ore(2)
		print(i, " -> ", rolled.id if rolled else "<null>")

	quit()
