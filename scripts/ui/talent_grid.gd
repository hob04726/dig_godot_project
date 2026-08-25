extends Node2D
class_name TalentGrid

const ResetVfxScript := preload("res://scripts/vfx/reset_vfx.gd")
const ConfirmDialogClass := preload("res://scripts/ui/confirm_dialog.gd")
const CONFIRM_SCENE := preload("res://scenes/ui/confirm.tscn")
const CHARGE_VFX_SCENE := preload("res://scenes/vfx/charge.tscn")
const WhiteFade := preload("res://scripts/ui/white_fade.gd")

## 天赋树控制器：从 defs/talents/*.csv 动态加载（TalentDb），按 (col,row) 实例化 TalentNode。
## 前置解锁制：所有前置购买后才显示/可解锁；普通天赋还可被升华天赋门控。
## 悬停显示 RichTextLabel 说明框（scenes/vfx/talent_label.tscn 原型）。
## 当前场景默认展示普通天赋树；点击"重置·升华"节点完成升华后，自动进入升华天赋树。
## 经济接入真实 GameState：购买走 spend_coins/record_*，写回 user://save.json。
## 独立运行天赋场景时从存档自载；进程内由 setup_state 注入（未来主场景内嵌用）。

enum TreeMode { NORMAL, ASCENSION }

@export var node_scene: PackedScene = null
@export var tooltip_prototype: PackedScene = null   # scenes/vfx/talent_label.tscn
@export var unlock_prototype: PackedScene = null    # scenes/vfx/unlock.tscn 购买特效（蓝/绿/红闪光爆发随机选一）
@export var reset_vfx_scene: PackedScene = null     # scenes/vfx/reset.tscn 升华（重置）特效
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
var _purchased: Dictionary[StringName, int] = {}
var _hovered: TalentNode = null

## 解锁条件正则：匹配 "dirt_mined ≥ 50"
var _unlock_condition_re := RegEx.new()

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
	_unlock_condition_re.compile(r"^(\w+)_mined\s*≥\s*(\d+)$")
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
	_update_rank_texts(delta)
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
		_update_node_rank_and_cost(node)
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
		# 网格中心遮罩对齐 reset 节点（默认 (0,0)，保险起见同步一次）
		var reset_node := _nodes_by_id.get(&"talent_reset") as TalentNode
		if reset_node != null:
			_grid_overlay.center_mask_position = reset_node.position
	_refresh_all(false)   # 初始/重建展示直置状态，不做弹跳
	_update_gold_label()
	_update_reset_orb_progress()


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
	for i in node.prerequisite_ids.size():
		var pid := node.prerequisite_ids[i]
		var req_rank := node.prerequisite_ranks[i] if i < node.prerequisite_ranks.size() else 1
		var owned: int = _purchased.get(pid, 0)
		if owned < req_rank:
			return false
	if node.ascension_prerequisite_id != &"":
		if not _state.has_ascension(node.ascension_prerequisite_id):
			return false
	return true


func _refresh(node: TalentNode, animated := true, just_revealed := false) -> void:
	# 已购买状态以 GameState（_purchased）为准：节点场景是重建的，
	# 自身 state 不跨档保留，不恢复的话重进界面已购天赋会显示成可再买
	var current_rank: int = _purchased.get(node.talent_id, 0)
	node.set_rank(current_rank)
	_update_node_rank_and_cost(node)
	if current_rank > 0:
		# 已购买：统一显示为 PURCHASED（满级大小/透明度），rank 标签区分等级
		if node.state != TalentNode.State.PURCHASED:
			node.set_state(TalentNode.State.PURCHASED, animated, just_revealed)
		return
	node.set_state(TalentNode.State.AVAILABLE if _can_afford(node) else TalentNode.State.LOCKED, animated, just_revealed)


## 可购买判断：先校验解锁条件，再按货币（金币 / 升华点）读真实 GameState 余额
func _can_afford(node: TalentNode) -> bool:
	if not _meets_unlock_condition(node):
		return false
	if node.currency == "升华点":
		return _state.ascension_points_available().gte(node.cost)
	return _state.coins.gte(node.cost)


## 解锁条件判断：解析 "dirt_mined ≥ 50" 格式，与 GameState.ore_mined 比较。
## 空条件或不符合 {ore}_mined ≥ {n} 格式的条件视为显示文本，不做数值门控。
func _meets_unlock_condition(node: TalentNode) -> bool:
	if node.unlock_condition == "":
		return true
	var m := _unlock_condition_re.search(node.unlock_condition.strip_edges())
	if m == null:
		return true
	var ore_id := StringName(m.get_string(1))
	var threshold := int(m.get_string(2))
	return _state.get_ore_mined(ore_id) >= threshold


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
	# "重置·升华"节点：弹出确认后继续升华
	if node.effect_type == "PRESTIGE_RESET":
		_sm().play_sfx(&"choose_to_reset")
		_prompt_ascension()
		return
	var current_rank: int = _purchased.get(node.talent_id, 0)
	if current_rank >= node.max_rank:
		print("已满级：%s" % node.display_name)
		_sm().play_sfx(&"cant_buy")
		return
	_update_node_rank_and_cost(node)
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
		_purchased[node.talent_id] = 1
	else:
		# 金币购买：先扣款，再记录
		if not _state.spend_coins(node.cost):
			print("金币不足：%s" % node.display_name)
			_sm().play_sfx(&"cant_buy")
			return
		var new_rank := _state.record_talent_purchase(node.talent_id)
		_purchased[node.talent_id] = new_rank
	# 购买成功音效：升华点/金币两种音色
	_sm().play_sfx(&"sublimation_talent_click" if node.currency == "升华点" else &"talent_click")
	# 已购（rank ≥ 1）统一 PURCHASED：完全不透明 + 正常大小；
	# 重复购买（已是 PURCHASED）时 set_state 不会重播弹跳，手动补一次升级弹跳
	var is_upgrade := current_rank > 0
	var was_purchased := node.state == TalentNode.State.PURCHASED
	node.set_state(TalentNode.State.PURCHASED)
	if was_purchased:
		node.play_purchase_pop()
	_spawn_rank_text(node, is_upgrade)   # 跳数：首次 unlock!（灰）/ 升级 upgrade!（黄）
	_talent_system.invalidate()
	_play_purchase_unlock(node)   # 购买特效：节点位置随机播放 unlock 闪光爆发
	print("升级天赋：%s → Lv.%d，剩余 %s %s" % [node.display_name, current_rank + 1, _current_balance().to_compact_string(), node.currency])
	# 卡在爆发高点（下蹲+过冲≈0.24s）揭示新解锁节点（0→base+0.3→base 弹跳出现）
	await get_tree().create_timer(TalentNode.REVEAL_DELAY).timeout
	_refresh_all()   # 升级后可能揭示新节点或改变可买状态
	_persist()
	_update_gold_label()


# ==================== 购买跳数（unlock! / upgrade!） ====================

## 动效与金币跳数一致：匀速上飘、前 0.12s 从 0.1 放大到 1、0.6s 后渐隐消失。
## 文字带 [wave] BBCode 波浪动效；首次解锁 = 灰色 unlock!，升级 = 黄色 upgrade!。
## 注意：[wave] 不会驱动 RichTextLabel 自动重绘（实测冻结在静态波形上），
## 必须由 _update_rank_texts 每帧 queue_redraw() 才会真正波动。
const RANK_TEXT_SPEED := 140.0
const RANK_TEXT_UNLOCK_COLOR := Color(0.8, 0.8, 0.85)
const RANK_TEXT_UPGRADE_COLOR := Color(1.0, 0.85, 0.25)

var _rank_texts: Array = []   # {node, label, time}


func _spawn_rank_text(node: TalentNode, is_upgrade: bool) -> void:
	var holder := Node2D.new()
	holder.z_index = 200   # 画在节点与购买闪光（50）、网格边框（100）之上
	holder.global_position = node.global_position + Vector2(0, -40)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE   # VFX 不吃鼠标输入
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(-120, -40)
	label.size = Vector2(240, 80)
	var text := "upgrade!" if is_upgrade else "unlock!"
	var color := RANK_TEXT_UPGRADE_COLOR if is_upgrade else RANK_TEXT_UNLOCK_COLOR
	label.text = "[wave amp=26 freq=5]%s[/wave]" % text
	label.add_theme_font_size_override("normal_font_size", 26)
	label.add_theme_color_override("default_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.12, 1.0))
	label.add_theme_constant_override("outline_size", 6)
	holder.add_child(label)
	add_child(holder)
	holder.scale = Vector2(0.1, 0.1)
	_rank_texts.append({"node": holder, "label": label, "time": 0.0})


func _update_rank_texts(delta: float) -> void:
	if _rank_texts.is_empty():
		return
	var remaining: Array = []
	for e in _rank_texts:
		var node: Node2D = e["node"]
		var label: RichTextLabel = e["label"]
		label.queue_redraw()   # [wave] 只在重绘时推进相位
		e["time"] += delta
		var time: float = e["time"]
		node.position += Vector2.UP * RANK_TEXT_SPEED * delta
		var grow := clampf(time / 0.12, 0.0, 1.0)
		node.scale = Vector2.ONE * (0.1 + 0.9 * grow)
		if time > 0.6:
			node.modulate.a -= delta * 2.0
		if node.modulate.a > 0.02:
			remaining.append(e)
		else:
			node.queue_free()
	_rank_texts = remaining


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
		_purchased[id] = _state.talent_purchases[id]
	for id in _state.ascension_purchases:
		_purchased[id] = 1 if _state.ascension_purchases[id] else 0


## 同步节点的当前等级与显示成本（已购等级越高，下一级越贵）
func _update_node_rank_and_cost(node: TalentNode) -> void:
	node.current_rank = _purchased.get(node.talent_id, 0)
	var next_rank := node.current_rank + 1
	if next_rank > node.max_rank:
		next_rank = node.max_rank
	var mult := pow(float(node.cost_mult), maxi(next_rank - 1, 0))
	if node.base_cost != null:
		node.cost = node.base_cost.mul(BigNumber.from_float(mult))
	else:
		node.cost = BigNumber.zero()


## 弹出升华确认对话框：根据当前可结算升华点显示不同提示，确认后再执行升华。
func _prompt_ascension() -> void:
	var pending := _state.ascension_points_total().sub(_state.ascension_points_earned)
	var message: String
	if pending.is_zero() or pending.is_negative():
		message = "目前无法获得任何升华点，确定要重置本轮进度吗？"
	else:
		message = "继续升华将重置本轮所有进度，可结算为 %s 升华点，是否继续？" % pending.to_compact_string()

	var overlay := CanvasLayer.new()
	overlay.layer = 90   # 在天赋 UI 之上、场景转场(100)之下
	var dialog := CONFIRM_SCENE.instantiate() as ConfirmDialogClass
	overlay.add_child(dialog)
	get_tree().root.add_child(overlay)
	var confirmed: bool = await dialog.confirm(message)
	overlay.queue_free()
	if confirmed:
		_do_ascension()


## 点击"重置·升华"：领取差值 → 在重置节点播放 charge 特效 + 摄像头拉近 →
## 白场淡入 → 切换场景 → 进入升华天赋树。
func _do_ascension() -> void:
	var from_earned := _state.ascension_points_earned
	var gain := _state.apply_ascension()
	_talent_system.invalidate()
	print("升华：领取 %s 升华点，进入新一轮" % gain.to_compact_string())
	_persist()

	var reset_node := _nodes_by_id.get(&"talent_reset") as TalentNode
	var focus_pos := Vector2.ZERO if reset_node == null else reset_node.global_position

	# 在重置节点上播放 charge 特效
	if CHARGE_VFX_SCENE != null:
		var charge := CHARGE_VFX_SCENE.instantiate() as Node2D
		add_child(charge)
		charge.global_position = focus_pos
		charge.z_index = 3000
		var anim := charge.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if anim != null:
			anim.frame = 0
			anim.frame_progress = 0.0
			anim.play()

	# 摄像头在 1.5s 内平滑拉近、移动到重置节点，直到白场转场
	if camera != null:
		# 先冻结摄像头的自动平滑，避免与 Tween 冲突
		camera.target_position = camera.position
		camera.target_zoom = camera.zoom
		var zoom_tween := create_tween().set_parallel(true)
		zoom_tween.tween_property(camera, "zoom",
			Vector2(camera.max_zoom, camera.max_zoom), 1.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		zoom_tween.tween_property(camera, "position", focus_pos, 1.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	# charge 播放 1.5s 后白场转场
	await get_tree().create_timer(1.5).timeout
	WhiteFade.play(0.5, 0.0, 0.5, "res://scenes/talent_ascension.tscn")


## 播放升华（重置）特效：把 scenes/vfx/reset.tscn 实例加到根节点顶层，
## 展示从上一轮回的升华点阈值到本轮累计金币的水位上升过程。动画结束后自动释放。
func _play_reset_vfx(from_lifetime: BigNumber, to_lifetime: BigNumber) -> void:
	if reset_vfx_scene == null:
		return
	var vfx := reset_vfx_scene.instantiate() as ResetVfxScript
	if vfx == null:
		return
	get_tree().root.add_child(vfx)
	vfx.z_index = 2000   # 确保画在所有 UI 之上
	vfx.setup(from_lifetime, to_lifetime)
	vfx.play()
	await vfx.finished
	vfx.queue_free()


## 写回存档：只更新 state，保留原网格数据（grid 由主场景持有并比对 run_version）
func _persist() -> void:
	_payload["state"] = _state.to_dict()
	_save.save(_payload)


## 返回主场景前写档（供返回按钮调用）
func persist() -> void:
	_persist()


## 切换普通/升华天赋树（UI 按钮调用）
func _update_gold_label() -> void:
	if gold_label:
		# 普通天赋树显示“数值$”；升华树只显示数值，不加“升华点：”前缀
		var suffix := "" if tree_mode == TreeMode.ASCENSION else "$"
		gold_label.text = "%s%s" % [_current_balance().to_compact_string(), suffix]
	_update_reset_orb_progress()


## 找到重置节点并同步升华进度球缸水位
func _update_reset_orb_progress() -> void:
	if _state == null:
		return
	for node in _nodes:
		if node.effect_type == "PRESTIGE_RESET":
			node.set_orb_progress(_state.lifetime_coins)
			return


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
	if node.effect_type == "PRESTIGE_RESET" and _state != null:
		var points := Prestige.points_for(_state.lifetime_coins)
		var remaining := Prestige.coins_to_next_point(_state.lifetime_coins)
		text += "\n\n当前 [b]%s[/b] 升华点 ｜ 下一级还需 [b]%s[/b]$" % [points.to_full_string(), remaining.to_compact_string()]
	else:
		text += "\n\n成本：[b]%s[/b] %s" % [node.cost.to_compact_string(), node.currency]
	if not node.prerequisite_ids.is_empty():
		var names: Array[String] = []
		for i in node.prerequisite_ids.size():
			var pid := node.prerequisite_ids[i]
			var req_rank := node.prerequisite_ranks[i] if i < node.prerequisite_ranks.size() else 1
			var name: String = _def_names.get(pid, str(pid))
			if req_rank > 1:
				name += " Lv.%d" % req_rank
			names.append(name)
		text += "\n前置：" + "、".join(names)
	if node.ascension_prerequisite_id != &"":
		text += "\n升华前置：" + _def_names.get(node.ascension_prerequisite_id, str(node.ascension_prerequisite_id))
	if node.unlock_condition != "":
		text += "\n解锁条件：" + node.unlock_condition
	return text
