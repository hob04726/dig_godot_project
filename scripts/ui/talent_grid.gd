extends Node2D
class_name TalentGrid

## 天赋树控制器：从 defs/talents/*.csv 动态加载（TalentDb），按 (col,row) 实例化 TalentNode。
## 前置解锁制：所有前置购买后才显示/可解锁；普通天赋还可被升华天赋门控。
## 悬停显示 RichTextLabel 说明框（scenes/vfx/talent_label.tscn 原型）；普通/升华两棵树可切换。
## 金币为 BigNumber 占位（真实经济由 GameState 接入，见 CLAUDE.md TODO）。

enum TreeMode { NORMAL, ASCENSION }

@export var node_scene: PackedScene = null
@export var tooltip_prototype: PackedScene = null   # scenes/vfx/talent_label.tscn
@export var cell_size := Vector2(100, 100)
@export var starting_gold := 1000000
@export var camera: Camera2D = null
@export var gold_label: Label = null
@export var tree_mode: TreeMode = TreeMode.NORMAL
## 鼠标周围格子边框渐显（叠加层，画在节点之上）
@export var show_grid_border := true

var gold := BigNumber.zero()
var _db := TalentDb.new()
var _defs: Array[TalentDef] = []
var _def_names: Dictionary[StringName, String] = {}
var _nodes: Array[TalentNode] = []
var _nodes_by_id: Dictionary[StringName, TalentNode] = {}
var _purchased: Dictionary[StringName, bool] = {}
var _hovered: TalentNode = null

var _tooltip: PanelContainer = null
var _tooltip_richtext: RichTextLabel = null
var _toggle_button: Button = null
var _grid_overlay: TalentGridBorder = null


func _ready() -> void:
	if camera == null:
		camera = get_node_or_null("Camera2D") as Camera2D
	if gold_label == null:
		gold_label = get_node_or_null("UI/GoldLabel") as Label
	if node_scene == null:
		push_warning("talent_grid: 缺 node_scene")
		return
	gold = BigNumber.from_int(starting_gold)
	_db.load_all()
	_def_names = _db.get_name_map()
	_setup_tooltip()
	_setup_toggle()
	_setup_grid_border()
	_build_tree()


## 格子边框叠加层：优先用 talent.tscn 里的静态 GridBorder 节点（参数可在 Inspector 调），
## 没有则运行时创建兜底。z_index 100 保证画在天赋节点之上。
func _setup_grid_border() -> void:
	_grid_overlay = get_node_or_null("GridBorder") as TalentGridBorder
	if _grid_overlay == null and show_grid_border:
		_grid_overlay = TalentGridBorder.new()
		_grid_overlay.name = "GridBorder"
		add_child(_grid_overlay)
	if _grid_overlay != null:
		_grid_overlay.cell_size = cell_size
		_grid_overlay.visible = show_grid_border


## 计算当前树的 (col,row) 包围盒，供边框叠加层画网格
func _compute_bounds() -> Rect2i:
	if _defs.is_empty():
		return Rect2i()
	var min_col := 99999
	var max_col := -99999
	var min_row := 99999
	var max_row := -99999
	for def in _defs:
		min_col = mini(min_col, def.col)
		max_col = maxi(max_col, def.col)
		min_row = mini(min_row, def.row)
		max_row = maxi(max_row, def.row)
	return Rect2i(min_col, min_row, max_col - min_col + 1, max_row - min_row + 1)


const TOOLTIP_FOLLOW_SPEED := 15.0   # 说明框平滑跟随速度（1/秒），越大跟得越紧


func _process(delta: float) -> void:
	if camera == null:
		return
	var node := _node_at(camera.get_global_mouse_position())
	if node != _hovered:
		if _hovered != null:
			_hovered.set_hovered(false)
		_hovered = node
		if _hovered != null:
			_hovered.set_hovered(true)
	if _hovered != null:
		_show_tooltip(_hovered)
		if _tooltip != null:
			# 指数平滑跟随（帧率无关）
			var follow := 1.0 - exp(-delta * TOOLTIP_FOLLOW_SPEED)
			_tooltip.position = _tooltip.position.lerp(_tooltip_target, follow)
	else:
		_hide_tooltip()


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var node := _node_at(camera.get_global_mouse_position())
		if node != null:
			_click(node)


# ==================== 树构建 ====================

func _build_tree() -> void:
	for node in _nodes:
		node.queue_free()
	_nodes.clear()
	_nodes_by_id.clear()
	_hovered = null
	_hide_tooltip()
	_defs = _db.get_normal_defs() if tree_mode == TreeMode.NORMAL else _db.get_ascension_defs()
	for def in _defs:
		var node := node_scene.instantiate() as TalentNode
		node.setup(def)
		# 以中心重置节点(0,0)为世界原点，相机默认对准它
		node.position = Vector2(def.col, def.row) * cell_size
		node.visible = false   # 先全隐藏，_refresh_all 按前置解锁显示
		add_child(node)
		_nodes.append(node)
		_nodes_by_id[def.id] = node
		# "开局已购买"的节点预置为已购买（如 unlock_coal / unlock_tile_dirt），
		# 这样它们的分支链（矿价值升级在上、地块协同在左）初始就能揭示出来
		if def.unlock_condition == "开局已购买":
			node.set_state(TalentNode.State.PURCHASED)
			_purchased[def.id] = true
	if _grid_overlay != null:
		_grid_overlay.grid_bounds = _compute_bounds()
	_refresh_all()
	_update_gold_label()


## 前置解锁刷新：所有前置（含升华前置）已购买才显示，并更新可购买状态
func _refresh_all() -> void:
	for node in _nodes:
		node.visible = _is_revealed(node)
		if node.visible:
			_refresh(node)


func _is_revealed(node: TalentNode) -> bool:
	for pid in node.prerequisite_ids:
		if not _purchased.get(pid, false):
			return false
	if node.ascension_prerequisite_id != &"":
		if not _purchased.get(node.ascension_prerequisite_id, false):
			return false
	return true


func _refresh(node: TalentNode) -> void:
	if node.state == TalentNode.State.PURCHASED:
		return
	node.set_state(TalentNode.State.AVAILABLE if gold.gte(node.cost) else TalentNode.State.LOCKED)


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
	if gold.gte(node.cost):
		gold = gold.sub(node.cost)
		node.set_state(TalentNode.State.PURCHASED)
		_purchased[node.talent_id] = true
		print("解锁天赋：%s，剩余 %s %s" % [node.display_name, gold.to_compact_string(), node.currency])
		_refresh_all()   # 解锁后可能揭示下一级天赋
	else:
		print("余额不足：还差 %s %s" % [node.cost.sub(gold).to_compact_string(), node.currency])
	_update_gold_label()


func _update_gold_label() -> void:
	if gold_label:
		var prefix := "升华点" if tree_mode == TreeMode.ASCENSION else "金币"
		gold_label.text = "%s：%s" % [prefix, gold.to_compact_string()]


# ==================== 悬浮说明框 ====================

func _setup_tooltip() -> void:
	if tooltip_prototype == null:
		return
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	_tooltip = tooltip_prototype.instantiate() as PanelContainer
	ui.add_child(_tooltip)
	_tooltip_richtext = _tooltip.get_node_or_null("Label") as RichTextLabel
	_tooltip.visible = false
	_tooltip.z_index = 100


var _tooltip_target := Vector2.ZERO   # 说明框平滑跟随的目标位置（屏幕空间）


func _show_tooltip(node: TalentNode) -> void:
	if _tooltip == null:
		return
	if _tooltip_richtext != null:
		_tooltip_richtext.text = _tooltip_text(node)
		_tooltip.reset_size()   # 内容变了先重排，夹取屏幕才准
	var was_hidden := not _tooltip.visible
	_tooltip.visible = true
	_tooltip_target = _clamped_tooltip_pos()
	if was_hidden:
		_tooltip.position = _tooltip_target   # 首次显示直接到位，避免从角落滑进来


## 说明框目标位置：跟随鼠标（屏幕空间），右下偏移并夹到屏幕内
func _clamped_tooltip_pos() -> Vector2:
	var pos := get_viewport().get_mouse_position() + Vector2(18, 18)
	var size := _tooltip.size
	var vp := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, vp.x - size.x - 4.0)
	pos.y = clampf(pos.y, 4.0, vp.y - size.y - 4.0)
	return pos


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


## 说明框内容：名字 + 描述(BBCode) + 成本/货币 + 前置 + 解锁条件
func _tooltip_text(node: TalentNode) -> String:
	var text := "[center][b]%s[/b][/center]\n\n" % node.display_name
	text += node.description
	text += "\n\n成本：[b]%s[/b] %s" % [node.cost.to_compact_string(), node.currency]
	if not node.prerequisite_ids.is_empty():
		var names: Array[String] = []
		for pid in node.prerequisite_ids:
			names.append(_def_names.get(pid, str(pid)))
		text += "\n前置：" + "、".join(names)
	if node.ascension_prerequisite_id != &"":
		text += "\n升华前置：" + _def_names.get(node.ascension_prerequisite_id, str(node.ascension_prerequisite_id))
	if node.unlock_condition != "":
		text += "\n解锁条件：" + node.unlock_condition
	return text


# ==================== 树切换 ====================

func _setup_toggle() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	_toggle_button = Button.new()
	ui.add_child(_toggle_button)
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_toggle_button.custom_minimum_size = Vector2(150, 34)
	_toggle_button.position = Vector2(get_viewport().get_visible_rect().size.x - 166, 12)
	_toggle_button.z_index = 100
	_update_toggle_text()


func _on_toggle_pressed() -> void:
	tree_mode = TreeMode.ASCENSION if tree_mode == TreeMode.NORMAL else TreeMode.NORMAL
	_update_toggle_text()
	_build_tree()
	if camera != null:
		camera.reset_camera()


func _update_toggle_text() -> void:
	if _toggle_button != null:
		_toggle_button.text = "升华天赋" if tree_mode == TreeMode.NORMAL else "普通天赋"
