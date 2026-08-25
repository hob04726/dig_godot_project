extends Node2D
## 挖矿进度条：横向 15 帧贴图表示 0%~100% 挖掘进度。
## 从图集自动裁出 15 帧（每帧 16x16），set_progress(0~1) 切到对应帧。

@export var frames := 15
@export var frame_size := Vector2(16, 16)

var _texture_rect: TextureRect
var _frame_textures: Array[Texture2D] = []


func _ready() -> void:
	_texture_rect = $TextureRect
	var first := _texture_rect.texture as AtlasTexture
	var atlas := first.atlas if first != null else null
	if atlas == null:
		push_warning("progress_bar: 找不到图集")
		return
	# 使用导出的帧数（默认 15），但不超过图集实际可容纳的帧数，避免最后一帧被空/冗余贴图占用
	var max_frames := atlas.get_width() / int(frame_size.x)
	frames = clampi(frames, 1, max_frames)
	for i in frames:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(i * frame_size.x, 0, frame_size.x, frame_size.y)
		_frame_textures.append(at)
	set_progress(0.0)


## 0.0~1.0 的挖掘进度（0 = 还没挖，1 = 挖完）
func set_progress(p: float) -> void:
	if _frame_textures.is_empty():
		return
	var index := clampi(int(p * frames), 0, frames - 1)
	_texture_rect.texture = _frame_textures[index]
