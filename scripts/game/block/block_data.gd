extends Resource
class_name BlockData

@export var block_type: Vector2i
@export var block_id: int

enum BlockType { NULL, BUILDING, ORE, GROUND }
enum BuildingType { NULL, HOUSE, FARM, MINE }
enum OreType { NULL, IRON, COPPER, GOLD, DIAMOND }
enum GroundType { NULL, GRASS, DIRT, STONE }


func _init(
	type := Vector2i.ZERO,
	id := 0,
):
	block_type = type
	block_id = id


func get_type_name() -> String:
	match block_type.x:
		BlockType.NULL:
			return "NULL"

		BlockType.BUILDING:
			return BuildingType.keys()[block_type.y]

		BlockType.ORE:
			return OreType.keys()[block_type.y]

		BlockType.GROUND:
			return GroundType.keys()[block_type.y]

		_:
			return "UNKNOWN"


func print_data() -> void:
	print("type=", block_type, ", name=", get_type_name(), ", id=", block_id)


func get_tex() -> Texture2D:
	var path := get_texture_path()

	if ResourceLoader.exists(path):
		return load(path)

	push_warning(
		"BlockData: no texture for type=", block_type, ", id=", block_id, ", fallback to grass_0"
	)
	return load("res://assets/blocks/png/grass_0.png")


func get_texture_path() -> String:
	var subtype_name: String

	match block_type.x:
		BlockType.BUILDING:
			subtype_name = BuildingType.keys()[clampi(block_type.y, 0, BuildingType.size() - 1)]

		BlockType.ORE:
			subtype_name = OreType.keys()[clampi(block_type.y, 0, OreType.size() - 1)]

		BlockType.GROUND:
			subtype_name = GroundType.keys()[clampi(block_type.y, 0, GroundType.size() - 1)]

		_:
			return ""

	return "res://assets/blocks/png/%s_%d.png" % [subtype_name.to_lower(), block_id]
