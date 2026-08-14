extends RefCounted
class_name DefDb

## 定义数据库（只读）：
## 启动时扫描 defs/ 目录，把 *.tres 按实际类型归档。
## 运行时只从这里查定义；"造节点"的工厂不在这里——
## 因为 OreBlock 依赖场景文件，工厂职责归组合根（GameManager）。

const ORES_DIR := "res://defs/ores"
const TILES_DIR := "res://defs/tiles"

var ores: Dictionary[StringName, OreDef] = {}
var tiles: Dictionary[StringName, TileDef] = {}


func load_all() -> void:
	load_dir(ORES_DIR)
	load_dir(TILES_DIR)


func load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("DefDb: 打不开 %s（目录不存在？）" % path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "tres":
			var full_path := path.path_join(file_name)
			_register(load(full_path), full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("DefDb: %s 扫描完成 → 矿石 %d 种，地皮 %d 种" % [path, ores.size(), tiles.size()])


## 校验 + 归档。校验失败不静默：警告并跳过，方便定位定义文件问题
func _register(res: Resource, path: String) -> void:
	if res is OreDef:
		if res.id == &"":
			push_warning("DefDb: %s 缺少 id，跳过" % path)
		elif ores.has(res.id):
			push_warning("DefDb: 矿石 id 重复 %s（%s）" % [res.id, path])
		else:
			ores[res.id] = res
			if res.get_texture(0) == null:
				push_warning("DefDb: 矿石 %s 没有贴图（texture/textures 均为空）" % res.id)
	elif res is TileDef:
		if res.id == &"":
			push_warning("DefDb: %s 缺少 id，跳过" % path)
		elif tiles.has(res.id):
			push_warning("DefDb: 地皮 id 重复 %s（%s）" % [res.id, path])
		else:
			tiles[res.id] = res
			if res.get_texture(0) == null:
				push_warning("DefDb: 地皮 %s 没有贴图（texture/textures 均为空）" % res.id)
	else:
		push_warning("DefDb: %s 不是 OreDef/TileDef，跳过" % path)


func get_ore(id: StringName) -> OreDef:
	return ores.get(id)


func get_tile(id: StringName) -> TileDef:
	return tiles.get(id)


## 加权随机抽取一种矿石定义。
## min_rarity：第 5 种地皮"提升掉落稀有度"就是提高这个下限。
## rng 由调用方注入（可复现种子）；不注入则临时随机。
func roll_ore(min_rarity: int = 1, rng: RandomNumberGenerator = null) -> OreDef:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var total := 0.0
	for ore_def in ores.values():
		if ore_def.rarity >= min_rarity and ore_def.spawn_weight > 0.0:
			total += ore_def.spawn_weight
	if total <= 0.0:
		push_warning("DefDb: 没有满足 rarity >= %d 的矿石" % min_rarity)
		return null

	var pick := rng.randf() * total
	for ore_def in ores.values():
		if ore_def.rarity < min_rarity or ore_def.spawn_weight <= 0.0:
			continue
		pick -= ore_def.spawn_weight
		if pick <= 0.0:
			return ore_def
	return null
