class_name TalentDb
extends RefCounted

## 天赋定义数据库（只读）：从 defs/talents/*.csv 动态解析成 TalentDef。
## 两张表列结构不同：
##   normal_talents.csv 24 列（金币，含 cost_display/mantissa/exponent/ascension_prerequisite_id/unlock_condition/target_ids/operation…）
##   ascension_talents.csv 13 列（升华点，缺很多列，落到默认值）
## 这里按表头名取字段，统一映射到 TalentDef，两张表共用一套解析。

const NORMAL_PATH := "res://defs/talents/normal_talents.csv"
const ASCENSION_PATH := "res://defs/talents/ascension_talents.csv"

var normal_defs: Array[TalentDef] = []
var ascension_defs: Array[TalentDef] = []
var _loaded := false


func load_all() -> void:
	if _loaded:
		return
	normal_defs = _load_csv(NORMAL_PATH, "金币")
	ascension_defs = _load_csv(ASCENSION_PATH, "升华点")
	_loaded = true
	print("TalentDb: 普通 %d 条，升华 %d 条" % [normal_defs.size(), ascension_defs.size()])


func get_normal_defs() -> Array[TalentDef]:
	load_all()
	return normal_defs


func get_ascension_defs() -> Array[TalentDef]:
	load_all()
	return ascension_defs


## 全部定义（普通 + 升华），用于跨树查前置名等
func get_all_defs() -> Array[TalentDef]:
	load_all()
	var all: Array[TalentDef] = []
	all.append_array(normal_defs)
	all.append_array(ascension_defs)
	return all


## id -> 显示名（跨两棵树）
func get_name_map() -> Dictionary[StringName, String]:
	load_all()
	var map: Dictionary[StringName, String] = {}
	for def in get_all_defs():
		map[def.id] = def.display_name
	return map


# ==================== CSV 解析 ====================

func _load_csv(path: String, default_currency: String) -> Array[TalentDef]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TalentDb: 打不开 %s" % path)
		return []
	var header := _parse_line(file.get_line())
	var index: Dictionary = {}
	for i in header.size():
		index[header[i]] = i
	var defs: Array[TalentDef] = []
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().is_empty():
			continue
		var row := _parse_line(line)
		if row.size() != header.size():
			push_warning("TalentDb: %s 行列数 %d ≠ %d，跳过" % [path, row.size(), header.size()])
			continue
		var def := _make_def(row, index, default_currency)
		if def.id != &"":
			defs.append(def)
		else:
			push_warning("TalentDb: %s 出现空 id，跳过" % path)
	return defs


func _make_def(row: PackedStringArray, index: Dictionary, default_currency: String) -> TalentDef:
	var def := TalentDef.new()
	def.id = StringName(_cell(row, index, "id"))
	def.display_name = _cell(row, index, "name")
	def.description = _cell(row, index, "description")
	def.currency = _cell(row, index, "currency", default_currency)
	def.cost = BigNumber.from_string(_cell(row, index, "cost", "0"))
	def.cost_display = _cell(row, index, "cost_display")
	def.col = _cell(row, index, "col", "0").to_int()
	def.row = _cell(row, index, "row", "0").to_int()
	def.prerequisite_ids = _split_ids(_cell(row, index, "prerequisite_ids"))
	def.prerequisite_ranks = _split_ints(_cell(row, index, "prerequisite_ranks"))
	def.ascension_prerequisite_id = StringName(_cell(row, index, "ascension_prerequisite_id"))
	def.unlock_condition = _cell(row, index, "unlock_condition")
	def.effect_type = _cell(row, index, "effect_type")
	def.target_ids = _split_ids(_cell(row, index, "target_ids"))
	def.operation = _cell(row, index, "operation")
	def.value = _cell(row, index, "value")
	def.max_rank = _cell(row, index, "max_rank", "1").to_int()
	def.cost_mult = _cell(row, index, "cost_mult", "5").to_int()
	if def.cost_mult < 1:
		def.cost_mult = 1
	def.group = _cell(row, index, "group")
	def.branch = _cell(row, index, "branch")
	def.level = _cell(row, index, "level")
	def.stage = _cell(row, index, "stage")
	def.requires_big_number = _cell(row, index, "requires_big_number") == "true"
	return def


func _cell(row: PackedStringArray, index: Dictionary, key: String, fallback := "") -> String:
	return row[index[key]] if index.has(key) else fallback


func _split_ids(text: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for part in text.split(","):
		var trimmed := part.strip_edges()
		if trimmed != "":
			out.append(StringName(trimmed))
	return out


func _split_ints(text: String) -> Array[int]:
	var out: Array[int] = []
	for part in text.split(","):
		var trimmed := part.strip_edges()
		if trimmed != "" and trimmed.is_valid_int():
			out.append(trimmed.to_int())
		else:
			out.append(0)
	return out


## 解析一行 CSV：支持带引号字段（字段内嵌逗号、"" 转义引号）。
static func _parse_line(line: String) -> PackedStringArray:
	var fields := PackedStringArray()
	var i := 0
	var n := line.length()
	while i < n:
		if line[i] == '"':
			i += 1
			var field := ""
			while i < n:
				if line[i] == '"':
					if i + 1 < n and line[i + 1] == '"':
						field += '"'
						i += 2
					else:
						i += 1
						break
				else:
					field += line[i]
					i += 1
			fields.append(field)
			if i < n and line[i] == ',':
				i += 1
		else:
			var start := i
			while i < n and line[i] != ',':
				i += 1
			fields.append(line.substr(start, i - start))
			if i < n:
				i += 1
	return fields
