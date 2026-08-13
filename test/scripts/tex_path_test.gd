extends SceneTree

func _init() -> void:
	var cases := [
		Vector2i(3, 1), # GROUND/GRASS
		Vector2i(3, 2), # GROUND/DIRT
		Vector2i(2, 1), # ORE/IRON
		Vector2i(2, 4), # ORE/DIAMOND
		Vector2i(1, 1), # BUILDING/HOUSE
		Vector2i(0, 0), # NULL
	]
	for type in cases:
		var block := BlockData.new(type, 0)
		print(type, " -> path=[", block.get_texture_path(), "] tex=", block.get_tex().resource_path)
	quit()
