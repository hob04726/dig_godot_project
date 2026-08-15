extends Node2D
## 天赋树控制器：按设计文档在 (列,行) 实例化 TalentNode，前置解锁制——
## 每个天赋只有前置天赋购买后才显示/可解锁（"点一个，解锁后面的才出现"）。
## 相机逆变换手动命中测试处理点击/悬停；挂在 talent.tscn 根节点（Node2D）上。

@export var node_scene: PackedScene = null
@export var cell_size := Vector2(100, 100)
@export var starting_gold := 1000000
@export var camera: Camera2D = null
@export var gold_label: Label = null

var gold := 0
var _nodes: Array[TalentNode] = []
var _nodes_by_id: Dictionary[StringName, TalentNode] = {}
var _hovered: TalentNode = null


func _ready() -> void:
	# 兜底：NodePath 导出有时解析不到，直接从场景里按名找
	if camera == null:
		camera = get_node_or_null("Camera2D") as Camera2D
	if gold_label == null:
		gold_label = get_node_or_null("UI/GoldLabel") as Label
	if node_scene == null:
		push_warning("talent_grid: 缺 node_scene")
		return
	gold = starting_gold
	_build_nodes()
	_refresh_all()
	_update_gold_label()


func _process(_delta: float) -> void:
	if camera == null:
		return
	var node := _node_at(camera.get_global_mouse_position())
	if node != _hovered:
		if _hovered != null:
			_hovered.set_hovered(false)
		_hovered = node
		if _hovered != null:
			_hovered.set_hovered(true)


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var node := _node_at(camera.get_global_mouse_position())
		if node != null:
			_click(node)


func _build_nodes() -> void:
	var defs := _demo_defs()
	for def in defs:
		var node := node_scene.instantiate() as TalentNode
		node.setup(def)
		# 以中心重置节点(0,0)为世界原点，相机默认对准它
		node.position = Vector2(def.col, def.row) * cell_size
		node.visible = false   # 先全隐藏，_refresh_all 按前置解锁显示
		add_child(node)
		_nodes.append(node)
		_nodes_by_id[def.id] = node


## 前置解锁刷新：前置已购买(或无前置)的节点显示，并更新可购买状态
func _refresh_all() -> void:
	for node in _nodes:
		var prereq := _nodes_by_id.get(node.prerequisite_id) as TalentNode
		var reveal := prereq == null or prereq.state == TalentNode.State.PURCHASED
		node.visible = reveal
		if not reveal:
			continue
		_refresh(node)


func _refresh(node: TalentNode) -> void:
	if node.state == TalentNode.State.PURCHASED:
		return
	node.set_state(TalentNode.State.AVAILABLE if gold >= node.cost else TalentNode.State.LOCKED)


func _node_at(world_pos: Vector2) -> TalentNode:
	for node in _nodes:
		if not node.visible:
			continue
		if node.contains_point(world_pos):
			return node
	return null


func _click(node: TalentNode) -> void:
	if node.state == TalentNode.State.PURCHASED:
		return
	if gold >= node.cost:
		gold -= node.cost
		node.set_state(TalentNode.State.PURCHASED)
		print("解锁天赋：%s，剩余金币 %d" % [node.talent_id, gold])
		_refresh_all()   # 解锁后可能揭示下一级天赋
	else:
		print("金币不足：还差 %d" % (node.cost - gold))
	_update_gold_label()


func _update_gold_label() -> void:
	if gold_label:
		gold_label.text = "金币：%s" % _fmt(gold)


func _fmt(v: int) -> String:
	if v >= 1_000_000_000_000_000_000:
		return "%.1fQi" % (v / 1e18)
	if v >= 1_000_000_000_000_000:
		return "%.1fQa" % (v / 1e15)
	if v >= 1_000_000_000_000:
		return "%.1fT" % (v / 1e12)
	if v >= 1_000_000_000:
		return "%.1fB" % (v / 1e9)
	if v >= 1_000_000:
		return "%.1fM" % (v / 1e6)
	if v >= 1_000:
		return "%.1fK" % (v / 1e3)
	return str(v)


## 演示数据：对应设计文档 Basic 树的四条主分支链（稿子/金币/矿石/地块），
## 每级前置 = 链上上一级。设计稿里的「高级/巨大矿石」「X升级」列暂缓（后续加）。
func _demo_defs() -> Array[TalentDef]:
	var defs: Array[TalentDef] = []
	# 中心·重置（始终可见）
	_add(defs, "talent_reset", "重置·升华", 0, 0, 0, &"")
	# 上支·稿子（从中心向上延伸）
	_add_chain(defs, Vector2i(0, -1), Vector2i(0, -1), [
		["pickaxe_bonus", "稿子方面加成", 1],
		["pickaxe_damage", "稿子基础伤害", 10],
		["crit_chance", "暴击几率", 100],
		["combo_chance", "连击几率", 500],
		["crit_damage", "暴击伤害", 10000],
		["pickaxe_aoe", "稿子作用范围", 1000000],
	])
	# 左支·金币：金币加成(头) + 两条平行链（稿子收益/地块效率，各5级，向下延伸）。
	# 稿子收益 前3级照设计稿 200/2000/20000，4~5级按 ×10 推 200000/2000000；
	# 地块效率 设计稿未给数值，按同级稿子收益定价（两条左链平衡）。
	_add(defs, "gold_bonus", "金币加成", 100, -2, 0, &"")
	_add_chain(defs, Vector2i(-3, 0), Vector2i(0, 1), [
		["pickaxe_income_1", "稿子收益+1%", 200],
		["pickaxe_income_2", "稿子收益+1%", 2000],
		["pickaxe_income_3", "稿子收益+1%", 20000],
		["pickaxe_income_4", "稿子收益+1%", 200000],
		["pickaxe_income_5", "稿子收益+1%", 2000000],
	], &"gold_bonus")
	_add_chain(defs, Vector2i(-4, 0), Vector2i(0, 1), [
		["tile_eff_1", "地块效率+10%", 200],
		["tile_eff_2", "地块效率+10%", 2000],
		["tile_eff_3", "地块效率+10%", 20000],
		["tile_eff_4", "地块效率+10%", 200000],
		["tile_eff_5", "地块效率+10%", 2000000],
	], &"gold_bonus")
	# 右支·矿石：矿石加成在 col1；解锁链从 col2 起（不占加成节点位置），
	# 每个矿带「高级X矿」（解锁成本×20）与「巨大X矿」（×200），在其正上方。
	# 成本推算：设计稿只给了煤炭 高级200/巨大2000（=×20/×200），其余按同一规则。
	var ores: Array = [
		["coal", "煤炭", 10],
		["iron", "铁矿", 10],
		["gold", "金矿", 100],
		["zinc", "锌矿", 100000],
		["emerald", "绿宝石", 1000000],
		["diamond", "钻石", 100000000],
		["obsidian", "黑曜石", 100000000000],
		["crystal", "水晶", 10000000000],
		["cat", "小猫矿", 100000000000],
	]
	_add(defs, "ore_bonus", "矿石加成", 5, 1, 0, &"")
	var prev_ore: StringName = &"ore_bonus"
	for i in ores.size():
		var ore: Array = ores[i]
		var ore_id: StringName = "unlock_%s" % ore[0]
		_add(defs, ore_id, "解锁%s" % ore[1], ore[2], 2 + i, 0, prev_ore)
		_add(defs, "adv_%s" % ore[0], "高级%s" % ore[1], ore[2] * 20, 2 + i, -1, ore_id)
		_add(defs, "giant_%s" % ore[0], "巨大%s" % ore[1], ore[2] * 200, 2 + i, -2, "adv_%s" % ore[0])
		prev_ore = ore_id

	# 下支·地块：地块方面加成在 row1；解锁链从 row2 起（不占加成节点位置），
	# 每个地块带 5 级「X升级」，成本 = 解锁成本 × 10^(级数+1)，在解锁节点右侧 col1~5。
	var tiles: Array = [
		["grass", "草地", 20],
		["rock", "岩石", 50],
		["water", "水", 100],
		["fire", "火焰", 1000],
		["pull", "pull", 10000],
		["push", "push", 10000],
		["spawn", "spawn", 100000],
		["volcano", "火山", 10000000000],
		["upgrade", "upgrade", 100000000000],
		["rarity", "rarity", 1000000000000],
	]
	_add(defs, "tile_bonus", "地块方面加成", 10, 0, 1, &"")
	var prev_tile: StringName = &"tile_bonus"
	for i in tiles.size():
		var tile: Array = tiles[i]
		var tile_id: StringName = "unlock_%s" % tile[0]
		_add(defs, tile_id, "解锁%s" % tile[1], tile[2], 0, 2 + i, prev_tile)
		var prev_up: StringName = tile_id
		for tier in 5:
			var up_id: StringName = "up_%s_%d" % [tile[0], tier + 1]
			_add(defs, up_id, "%s升级" % tile[1], int(tile[2] * pow(10, tier + 1)), 1 + tier, 2 + i, prev_up)
			prev_up = up_id
		prev_tile = tile_id

	return defs


## 一条链：从 start 开始沿 step 逐格放置；第一级前置 = head_prereq（空则开局可见），
## 之后每级的上一级是它的前置。
func _add_chain(defs: Array[TalentDef], start: Vector2i, step: Vector2i, items: Array, head_prereq: StringName = &"") -> void:
	var prev := head_prereq
	for i in items.size():
		var it: Array = items[i]
		var pos := start + step * i
		_add(defs, it[0], it[1], it[2], pos.x, pos.y, prev)
		prev = it[0]


func _add(defs: Array[TalentDef], id: StringName, name: String, cost: int, col: int, row: int, prereq: StringName) -> void:
	var d := TalentDef.new()
	d.id = id
	d.display_name = name
	d.cost = cost
	d.col = col
	d.row = row
	d.prerequisite_id = prereq
	defs.append(d)
