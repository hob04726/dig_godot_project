extends Node2D
class_name TalentGrid

## 天赋树控制器：从 defs/talents/*.csv 动态加载（TalentDb），按 (col,row) 实例化 TalentNode。
## 前置解锁制：所有前置购买后才显示/可解锁；普通天赋还可被升华天赋门控。
## 悬停显示 RichTextLabel 说明框（scenes/vfx/talent_label.tscn 原型）。
## 当前场景只展示普通天赋树；升华界面（重置后进入 + 新一轮按钮）后续单独设计。
## 经济接入真实 GameState：购买走 spend_coins/record_*，写回 user://save.json。
## 独立运行天赋场景时从存档自载；进程内由 setup_state 注入（未来主场景内嵌用）。

enum TreeMode { NORMAL, ASCENSION }

@export var node_scene: PackedScene = null
@export var tooltip_prototype: PackedScene = null   # scenes/vfx/talent_label.tscn
@export var unlock_prototype: PackedScene = null    # scenes/vfx/unlock.tscn 购买特效（蓝/绿/红闪光爆发随机选一）
@export var cell_size := Vector2(100, 100)
@export var camera: Camera2D = null
@export var gold_label: RichTextLabel = null
@export var tree_mode: TreeMode = TreeMode.NORMAL
## 鼠标周围格子边框渐显（叠加层，画在节点之上）
@export var show_grid_border := true

var _state: GameState = null
var _injected := false
var _payload: Dictionary = {}            # 存档负载：只更新 state，保留原 grid
var _save := SaveManager.new()
var _talent_system: TalentSystem = null
var _db := TalentDb.new()
var _defs: Array[TalentDef] = []
var _def_names: Dictionary[StringName, String] = {}
var _nodes: Array[TalentNode] = []
var _nodes_by_id: Dictionary[StringName, TalentNode] = {}
var _purchased: Dictionary[StringName, bool] = {}
var _hovered: TalentNode = null

var _tooltip: PanelContainer = null
var _tooltip_richtext: RichTextLabel = null
var _grid_overlay: TalentGridBorder = null


## SoundManager autoload 访问器（--script 测试模式下全局标识符不可编译，走节点查找）
func _sm():
	return get_node_or_null("/root/SoundManager")


func _ready() -> void:
	_sm().play_music(&"normal_talent")   # 天赋场景 BGM
	if camera == null:
		camera = get_node_or_null("Camera2D") as Camera2D
	if gold_label == null:
		gold_label = get_node_or_null("UI/PanelContainer/HBoxContainer/Money") as RichTextLabel
	if node_scene == null:
		push_warning("talent_grid: 缺 node_scene")
		return
	_db.load_all()
	# 经济接入：进程内注入优先；独立运行从存档自载
	if _state == null:
		_state = GameState.new()
		_payload = _save.load()
		if not _payload.is_empty():
			_state.load_from_dict(_payload.get("state", {}))
		else:
			_payload = {"version": SaveManager.SAVE_VERSION}
	_talent_system = TalentSystem.new(_state, _db)
	_def_names = _db.get_name_map()
	_setup_tooltip()
	_setup_grid_border()
	_build_tree()
	# 计数器悬浮提示：鼠标下方跟随显示精确余额（白字黑描边）
	if gold_label != null:
		var panel := gold_label.get_parent().get_parent() as PanelContainer
		if panel != null:
			ExactValueTooltip.attach(panel, func() -> String:
				var suffix := "" if tree_mode == TreeMode.ASCENSION else "$"
				return _current_balance().to_full_string() + suffix)


## 进程内注入 GameState（主场景内嵌天赋场景用）；独立运行由 _ready 从存档自载。
## 在 _ready 之前调用则 _ready 直接用它；之后调用则重建树。
func setup_state(state: GameState) -> void:
	_state = state
	_injected = true
	if _talent_system != null:
		_talent_system = TalentSystem.new(_state, _db)
		_sync_purchased()
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
	# 拖动相机时不做节点悬浮，说明框不追着鼠标跑
	var node: TalentNode = null if _dragging else _node_at(camera.get_global_mouse_position())
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


# ==================== 左键拖动平移相机 ====================

const DRAG_THRESHOLD := 6.0   # 像素：按住左键移动超过这个距离才算拖动（防止点击抖动带跑相机）

var _drag_armed := false      # 左键已在空白处按下，还没过阈值
var _drag_accum := 0.0        # 按下后累计的移动距离
var _dragging := false        # 正在拖动相机


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var node := _node_at(camera.get_global_mouse_position())
			if node != null:
				_click(node)
			else:
				# 空白处按下：进入拖动预备（购买/相机二选一，节点上按下不拖相机）
				_drag_armed = true
				_drag_accum = 0.0
		else:
			_drag_armed = false
			_dragging = false
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_drag_armed = false   # 兜底：释放事件被 UI 吃掉时也能退出拖动
			_dragging = false
			return
		if _dragging:
			camera.move_camera(event.relative)
		elif _drag_armed:
			_drag_accum += event.relative.length()
			if _drag_accum > DRAG_THRESHOLD:
				_dragging = true


# ==================== 树构建 ====================

func _build_tree() -> void:
	for node in _nodes:
		node.queue_free()
	_nodes.clear()
	_nodes_by_id.clear()
	_hovered = null
	_hide_tooltip()
	_sync_purchased()
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
		# 所有天赋（含 0 费的 unlock_coal / unlock_tile_dirt）都需手动购买，
		# 购买记录统一走 GameState.record_talent_purchase 进存档
	if _grid_overlay != null:
		_grid_overlay.grid_bounds = _compute_bounds()
	_refresh_all(false)   # 初始/重建展示直置状态，不做弹跳
	_update_gold_label()


## 前置解锁刷新：所有前置（含升华前置）已购买才显示，并更新可购买状态。
## animated=false 用于初始/重建（直置状态，不弹跳）；购买后的刷新默认动画。
## 隐藏节点也直置样式（LOCKED 0.3/0.7），避免揭示时才从默认值跳变。
## 刚从隐藏揭示出来的节点传 just_revealed=true（播 0→1.1→base 弹跳）；
## 本就在屏上、只是买得起/买不起变化的节点走平滑过渡。
func _refresh_all(animated := true) -> void:
	for node in _nodes:
		var was_visible := node.visible
		node.visible = _is_revealed(node)
		var just_revealed := animated and node.visible and not was_visible
		_refresh(node, animated, just_revealed)


func _is_revealed(node: TalentNode) -> bool:
	for pid in node.prerequisite_ids:
		if not _purchased.get(pid, false):
			return false
	if node.ascension_prerequisite_id != &"":
		if not _purchased.get(node.ascension_prerequisite_id, false):
			return false
	return true


func _refresh(node: TalentNode, animated := true, just_revealed := false) -> void:
	# 已购买状态以 GameState（_purchased）为准：节点场景是重建的，
	# 自身 state 不跨档保留，不恢复的话重进界面已购天赋会显示成可再买
	if _purchased.get(node.talent_id, false):
		if node.state != TalentNode.State.PURCHASED:
			node.set_state(TalentNode.State.PURCHASED, animated, just_revealed)
		return
	node.set_state(TalentNode.State.AVAILABLE if _can_afford(node) else TalentNode.State.LOCKED, animated, just_revealed)


## 可负担判断：按货币（金币 / 升华点）读真实 GameState 余额
func _can_afford(node: TalentNode) -> bool:
	if node.currency == "升华点":
		return _state.ascension_points_available().gte(node.cost)
	return _state.coins.gte(node.cost)


## 当前树对应货币的余额（金币 / 可花升华点）
func _current_balance() -> BigNumber:
	return _state.ascension_points_available() if tree_mode == TreeMode.ASCENSION else _state.coins


func _node_at(world_pos: Vector2) -> TalentNode:
	for node in _nodes:
		if not node.visible:
			continue
		if node.contains_point(world_pos):
			return node
	return null


func _click(node: TalentNode) -> void:
	# "重置·升华"节点：直接升华（无确认）
	if node.effect_type == "PRESTIGE_RESET":
		_sm().play_sfx(&"choose_to_reset")
		_do_ascension()
		return
	if node.state == TalentNode.State.PURCHASED:
		return
	if not _can_afford(node):
		print("余额不足：%s 需要 %s %s" % [node.display_name, node.cost.to_compact_string(), node.currency])
		_sm().play_sfx(&"cant_buy")
		return
	if node.currency == "升华点":
		# 升华点购买：record_ascension_purchase 内部检查余额
		if not _state.record_ascension_purchase(String(node.talent_id), node.cost.to_int()):
			print("升华点不足：%s" % node.display_name)
			_sm().play_sfx(&"cant_buy")
			return
	else:
		# 金币购买：先扣款，再记录
		if not _state.spend_coins(node.cost):
			print("金币不足：%s" % node.display_name)
			_sm().play_sfx(&"cant_buy")
			return
		_state.record_talent_purchase(node.talent_id)
	# 购买成功音效：升华点/金币两种音色
	_sm().play_sfx(&"sublimation_talent_click" if node.currency == "升华点" else &"talent_click")
	node.set_state(TalentNode.State.PURCHASED)
	_purchased[node.talent_id] = true
	_talent_system.invalidate()
	_play_purchase_unlock(node)   # 购买特效：节点位置随机播放 unlock 闪光爆发
	print("解锁天赋：%s，剩余 %s %s" % [node.display_name, _current_balance().to_compact_string(), node.currency])
	# 卡在爆发高点（下蹲+过冲≈0.24s）揭示新解锁节点（0→base+0.3→base 弹跳出现）
	await get_tree().create_timer(TalentNode.REVEAL_DELAY).timeout
	_refresh_all()   # 解锁后可能揭示下一级天赋
	_persist()
	_update_gold_label()


## 购买特效：在节点位置实例化 unlock（scenes/vfx/unlock.tscn），
## 从蓝/绿/红三种 round_sparkle_burst 闪光爆发里随机选一个播放，播完（或超时兜底）自毁。
func _play_purchase_unlock(node: TalentNode) -> void:
	if unlock_prototype == null:
		return
	var vfx := unlock_prototype.instantiate() as Node2D
	add_child(vfx)
	vfx.z_index = 50   # 画在天赋节点之上、网格边框(100)之下
	vfx.scale = Vector2.ONE * 1.4   # 64px 帧放大到 ~90px，刚好罩住节点命中框
	vfx.global_position = node.global_position
	var sprite := vfx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		vfx.queue_free()
		return
	var names := sprite.sprite_frames.get_animation_names()
	if names.is_empty():
		vfx.queue_free()
		return
	sprite.frame = 0
	sprite.play(names[randi() % names.size()])
	sprite.animation_finished.connect(vfx.queue_free)
	# 兜底：动画最长 19 帧/30fps ≈ 0.63s，超时也释放（防止意外残留）
	get_tree().create_timer(1.0).timeout.connect(vfx.queue_free)


## 购买状态同步自 GameState（普通 + 升华），是天赋已购记录的唯一来源
func _sync_purchased() -> void:
	_purchased.clear()
	for id in _state.talent_purchases:
		_purchased[id] = true
	for id in _state.ascension_purchases:
		_purchased[id] = true


## 点击"重置·升华"：直接升华。保留永久槽天赋，领取差值，重建普通树并写档。
func _do_ascension() -> void:
	var preserve := _talent_system.select_preserved_talents(_talent_system.get_permanent_slot_count())
	var gain := _state.apply_ascension(preserve)
	_talent_system.invalidate()
	print("升华：领取 %s 升华点，进入新一轮" % gain.to_compact_string())
	_build_tree()
	_persist()


## 写回存档：只更新 state，保留原网格数据（grid 由主场景持有并比对 run_version）
func _persist() -> void:
	_payload["state"] = _state.to_dict()
	_save.save(_payload)


## 返回主场景前写档（供返回按钮调用）
func persist() -> void:
	_persist()


func _update_gold_label() -> void:
	if gold_label:
		var prefix := "升华点" if tree_mode == TreeMode.ASCENSION else "金币"
		var suffix := "" if tree_mode == TreeMode.ASCENSION else "$"
		gold_label.text = "%s：%s%s" % [prefix, _current_balance().to_compact_string(), suffix]


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
