extends SceneTree

## 一次性工具：给天赋图标图集追加新矿石/地块图标。
## talents.png 是 32×32 一格的图集，图标按 normal_talents.csv 数据行顺序
## （跳过 talent_reset）从左到右、从上到下对应（见 TalentDb._assign_icons）。
## 本脚本把图集向下扩一行（192×160 → 192×192），在空格 27..35 填入
## 新天赋（ore_stone…tile_tnt_spawn）对应的美术缩略图。
## 运行：godot --headless --path . --script res://tools/gen_talent_icons.gd

const CELL := 32
const ICON_SIZE := 28  # 格内图标边长（留 2px 边距，与既有图标观感一致）

# 追加顺序必须与 normal_talents.csv 新行顺序一致（细胞 27 起）
const SOURCES := [
	"res://assets/blocks/png/ore_stone_small.png",
	"res://assets/blocks/png/ore_emerald_small.png",
	"res://assets/blocks/png/ore_obsidian_small.png",
	"res://assets/blocks/png/ore_diamond_small.png",
	"res://assets/blocks/png/ore_cat_small.png",
	"res://assets/blocks/png/ground_pull.png",
	"res://assets/blocks/png/ground_rarity.png",
	"res://assets/blocks/png/ground_spawn.png",
	"res://assets/blocks/png/ground_TNT_spawn.png",
]
const START_CELL := 27

func _initialize() -> void:
	var atlas_path := "res://assets/talent_icon/png/talents.png"
	var img := Image.load_from_file(ProjectSettings.globalize_path(atlas_path))
	if img == null:
		push_error("gen_talent_icons: 打不开 %s" % atlas_path)
		quit(1)
		return
	var cols := img.get_width() / CELL
	var need_cells := START_CELL + SOURCES.size()
	var need_rows := int(ceil(float(need_cells) / cols))
	if img.get_height() < need_rows * CELL:
		var bigger := Image.create(img.get_width(), need_rows * CELL, false, Image.FORMAT_RGBA8)
		bigger.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		img = bigger

	for i in SOURCES.size():
		var src := Image.load_from_file(ProjectSettings.globalize_path(SOURCES[i]))
		if src == null:
			push_error("gen_talent_icons: 打不开 %s" % SOURCES[i])
			continue
		if src.get_format() != Image.FORMAT_RGBA8:
			src.convert(Image.FORMAT_RGBA8)
		# 裁掉透明边距，再按内容等比缩放到 ICON_SIZE 内（最近邻保持像素风）
		var bbox := src.get_used_rect()
		var content := src.get_region(bbox)
		var scale: float = minf(float(ICON_SIZE) / bbox.size.x, float(ICON_SIZE) / bbox.size.y)
		var w := maxi(1, int(round(bbox.size.x * scale)))
		var h := maxi(1, int(round(bbox.size.y * scale)))
		content.resize(w, h, Image.INTERPOLATE_NEAREST)
		var cell := START_CELL + i
		var cell_pos := Vector2i((cell % cols) * CELL, (cell / cols) * CELL)
		img.blit_rect(content, Rect2i(Vector2i.ZERO, Vector2i(w, h)),
			cell_pos + Vector2i((CELL - w) / 2, (CELL - h) / 2))
		print("gen_talent_icons: cell %d ← %s" % [cell, SOURCES[i]])

	var out := ProjectSettings.globalize_path(atlas_path)
	if img.save_png(out) != OK:
		push_error("gen_talent_icons: 保存失败 %s" % out)
		quit(1)
		return
	print("gen_talent_icons: 完成，图集 %dx%d" % [img.get_width(), img.get_height()])
	quit()
