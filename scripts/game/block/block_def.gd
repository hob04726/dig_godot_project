extends Resource
class_name BlockDef

@export var id: StringName
@export var display_name: String = ""
@export var texture: Texture2D                       # 单图
@export var textures: Array[Texture2D] = []          # 多图按索引取（矿按级，地皮按帧）
@export var z_bias: int = 0

func get_texture(index: int = 0) -> Texture2D:
	if not textures.is_empty():
		return textures[clampi(index, 0, textures.size() - 1)]
	return texture
