extends Node2D
class_name GameManager

const ABOVE_LAYER_OFFSET := Vector2(0, -8)
const INITIAL_GRID_SIZE := 1   # 初始 3x3 草地（半径 1）

# 矿石破坏后自由落体重力
const ORE_GRAVITY := 700.0

# 放置模式下指针颜色：绿=可放 / 橙=可删 / 红=都不行
const POINTER_PLACE_COLOR := Color(0.4, 1, 0.4)       # 可放置且金币充足：绿
const POINTER_NO_MONEY_COLOR := Color(1, 0.35, 0.35)  # 可放置但金币不足：红
const POINTER_BLOCKED_COLOR := Color(1, 0.72, 0.25)   # 位置不可放置：橙

## 数据层：网格（唯一写入口 + 唯一事件源）
var grid := GridModel.new()
## 定义数据库：启动时扫描 defs/ 目录
var db := DefDb.new()

## 运行时地皮节点（渲染/交互用；矿石节点权威来源在 grid.ores）
var tiles_by_cell: Dictionary[Vector2i, Block] = {}
var _hovered_cell := Vector2i(999999, 999999)
## 批量放置时记录上一次放置的格子，避免同一格重复放
var _last_placed_cell := Vector2i(999999, 999999)
## 批量删除时记录上一次删除的格子，避免同一格重复删
var _last_removed_cell := Vector2i(999999, 999999)

## 经济状态（数据层唯一写入口）：金币/累计开采/升华点/天赋购买
var state := GameState.new()
## 天赋定义数据库（defs/talents/*.csv，与 db=DefDb 的 ore/tile 定义分开）
var _talent_db := TalentDb.new()
## 天赋效果引擎（聚合已购天赋 → 结算/伤害/落矿池查询）
var _talent_system: TalentSystem = null
## 挖矿暴击判定 + 落矿抽取的随机源（可复现种子）
var _mine_rng := RandomNumberGenerator.new()
## 存档 I/O（内容由本组合根组装）
var _save_manager := SaveManager.new()
var _save_dirty := false
## 破纪录火焰：滚动最高值 + 一分钟窗口（会话级，不存档）
var _best_coins := BigNumber.zero()
var _last_beat_time := -100.0
var _fire_tween: Tween
var _money_dance_tween: Tween
const RECORD_WINDOW := 60.0   # 一分钟：没在这段时间内破纪录就把纪录滚到当前值

## 稿子伤害（PickaxeData 阶段再替换成资源）
@export var pickaxe_damage := 10

## 自动落矿参数
@export var spawn_interval := 2.0
## 矿石上限；<= 0 表示填满所有格子（动态取 grid.cells.size()）
@export var max_ores := 0

# pointer
@export var pointer: Node2D = null

# 方块原型：普通方块（地皮/装置）与矿石
@export var block_prototype: PackedScene = null
@export var ore_prototype: PackedScene = null

@export var above_grid_layer: Node2D = null
@export var below_grid_layer: Node2D = null

## 金币 HUD（main.tscn 里的 RichTextLabel）
@export var money_label: RichTextLabel = null
## 金币计数器破纪录时的火焰特效材质（balatro 火焰 shader，amount 控制强度）
@export var money_fire_material: ShaderMaterial = null

## 矿石破坏特效原型：爆炸序列帧 / 金币粒子 / 挖矿进度条 / 伤害跳数
@export var explosion_prototype: PackedScene = null
@export var coin_prototype: PackedScene = null
@export var progress_bar_prototype: PackedScene = null
@export var jump_number_prototype: PackedScene = null   # scenes/vfx/jumpnumber.tscn（稿子伤害跳数，40x40）
@export var coin_number_prototype: PackedScene = null   # scenes/vfx/coin_number.tscn（金币跳数，240x80 大盒子）
@export var tail_prototype: PackedScene = null          # scenes/vfx/tail.tscn（金币飞向计数板的拖尾）
## 金币粒子整体缩放（贴图 20x18 已经小，这个再乘一档）
@export var coin_effect_scale := 0.4
## 矿石飞出力度：基础 + 每点最后一击伤害附加的力。
## 基础调低让大多数矿落回底部，只有高伤害（暴击/草地）才飞得远。
@export var ore_launch_base := 120.0
@export var ore_launch_per_damage := 25.0
## 矿石飞出时的旋转角速度区间（度/秒，随机正负方向）
@export var ore_spin_min := 140.0
@export var ore_spin_max := 360.0
## 爆炸大小：基础缩放 + 每点最后一击伤害附加的缩放
@export var explosion_scale_base := 0.3
@export var explosion_scale_per_damage := 0.015

## 金币飞向计数板：边缘跳数 + 拖尾参数
const COIN_NUM_SPEED := 220.0         # 边缘跳数飞向屏幕中心的速度
const COIN_TRAIL_SPREAD := 120.0      # 拖尾初始扩散速度（先向两侧飞）
const COIN_TRAIL_LATERAL_FORCE := 700.0  # 向左右随机方向的初始侧力（先猛地侧飞）
const COIN_TRAIL_LATERAL_DECAY := 2.0    # 侧力随时间衰减速度（e^(-decay*t)，越小持续越久）
const COIN_TRAIL_PULL_START := 60.0   # 初始拉力很弱（侧飞阶段不被吸走）
const COIN_TRAIL_PULL_GROWTH := 2000.0 # 拉力每秒增长（侧飞衰减后猛吸回计数板）
const COIN_TRAIL_DISTANCE_PULL := 300000.0  # 距离反比引力系数（K/(dist/3)=3K/距离）：越接近计数板吸力越强
const COIN_TRAIL_DAMPING := 0.5       # 速度阻尼（保留弧线）
const COIN_TRAIL_MAX_SPEED := 900.0   # 头部速度上限（防止过冲跳过淡出半径）
const COIN_TRAIL_COUNT_CAP := 10      # 拖尾数量上限

## 正在飞出屏幕的矿石（{ore, velocity, gained}）
var _flying_ores: Array = []
## 正在飞行的伤害跳数（{node, label, velocity, time, crit}）——矿石同款动线，下落渐隐
var _jump_numbers: Array = []
## 金币飞向计数板的飞行体（{kind:"num"|"trail", node, velocity, time, target, pull}）
var _coin_flights: Array = []
## 金币飞行所在层：主 UI CanvasLayer（layer 1，屏幕空间，天然在世界之上）。
## 飞行体 z_index 取负 → 画在主 UI 控件（计数板/HUD）之下 → 汇聚到计数板后面消失。
var _coin_flight_layer: CanvasLayer = null
## 待拖尾消失后再触发的金币跳数：飞行结束后才"震动 + 上涨"
var _pending_coin := false
var _pending_coin_duration := 0.0
## 当前正在挖的矿上方的进度条
var _mining_bar: Node2D = null
var _bar_tween: Tween
## 等待粒子全部消失后再释放的金币粒子（{node, particles, wait}）
var _coin_cleanups: Array = []
## 左上角显示的金币值（跳数动画期间与 state.coins 不同步）
var _displayed_coins := BigNumber.zero()
var _coin_tween: Tween

@onready var _camera: Camera2D = get_node_or_null("Camera2D") as Camera2D

## 自定义鼠标光标：悬停矿 → tile_0108（挖矿），放置模式 → tile_0109（放置），其余项目默认 tile_0026
var _cursor_mine: Texture2D = null
var _cursor_place: Texture2D = null
var _cursor_default: Texture2D = null
## 当前生效的光标（""=默认），避免每帧重复调用 Input.set_custom_mouse_cursor
var _current_cursor := ""          # want + 染色/摇晃姿态键（变化才调原生接口）
var _cursor_tint_cache: Dictionary = {}   # Color -> 染色后的 Image（只生成一次）
## 挖矿光标待机摇晃：预生成的左右旋转帧 + 节奏状态机
var _cursor_mine_left: Image = null
var _cursor_mine_right: Image = null
var _cursor_wiggle_angle := 0.0    # 当前姿态（0 / ±CURSOR_WIGGLE_ANGLE）
var _cursor_wiggle_elapsed := 0.0
var _cursor_wiggling := false
var _cursor_wiggle_wait := 1.2     # 距下次摇晃的等待（随机化）
const CURSOR_WIGGLE_ANGLE := 20.0
const CURSOR_WIGGLE_STEP := 0.07   # 每个姿态停留时长

var _spawn_timer: Timer
var _autosave_timer: Timer


func _ready() -> void:
	# 存档脏标记先连好：初始网格构建（_load_or_init）也要标脏，否则纯新档不会自动存档
	state.changed.connect(_mark_save_dirty)
	grid.tile_changed.connect(_on_grid_changed)

	db.load_all()
	_talent_db.load_all()
	_talent_system = TalentSystem.new(state, _talent_db)
	_mine_rng.randomize()
	_load_or_init()   # 有存档 → 恢复；无存档 → 新游戏初始化
	# 天赋地块行为 override（TILE_BEHAVIOR_UP）推给网格
	grid.set_tile_overrides(_talent_system.get_tile_behavior_overrides())

	grid.ore_removed.connect(_on_ore_removed)
	grid.ore_discarded.connect(_on_ore_discarded)
	grid.ore_moved.connect(_on_ore_moved)
	grid.tile_request_spawn.connect(_on_tile_request_spawn)

	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	_spawn_timer.start()

	# 自动存档（防御：编辑器停跑/崩溃不会触发退出通知，靠定时兜底）
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 15.0
	_autosave_timer.timeout.connect(_on_autosave_tick)
	add_child(_autosave_timer)
	_autosave_timer.start()

	# 挖矿进度条（默认隐藏，挖矿时显示在矿石上方）
	if progress_bar_prototype != null:
		_mining_bar = progress_bar_prototype.instantiate() as Node2D
		above_grid_layer.add_child(_mining_bar)
		_mining_bar.z_index = 4000   # 画在所有地块之上
		_mining_bar.visible = false

	# 火焰画在单独的矩形特效层；单图使用归一化 UV 参数。
	# amount=0 时只让特效层透明，不会再把金币面板本身变透明。
	if money_fire_material != null:
		money_fire_material.set_shader_parameter("image_details", Vector2.ONE)
		money_fire_material.set_shader_parameter("texture_details", Vector4(0, 0, 1, 1))

	# RichTextLabel 是 HBoxContainer 的子节点，用视觉偏移做动画才不会被布局覆盖。
	if money_label != null:
		money_label.offset_transform_enabled = true
		money_label.offset_transform_visual_only = true
		money_label.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
		_reset_money_dance()

	_update_money_label()
	_setup_cursors()
	_setup_coin_flight_layer()
	initialized.emit()   # _ready 完成：依赖方（抽屉等）此时可安全查询解锁状态


## 金币飞行层 = 主 UI CanvasLayer：屏幕空间，天然画在世界之上
func _setup_coin_flight_layer() -> void:
	if money_label != null:
		_coin_flight_layer = money_label.get_parent().get_parent().get_parent() as CanvasLayer
	if _coin_flight_layer == null:
		_coin_flight_layer = get_node_or_null("../CanvasLayer") as CanvasLayer
	if _coin_flight_layer == null:   # 兜底：新建一个
		_coin_flight_layer = CanvasLayer.new()
		_coin_flight_layer.name = "CoinFlightLayer"
		add_child(_coin_flight_layer)


## 加载自定义鼠标光标素材（悬停矿 / 放置模式 / 项目默认）
func _setup_cursors() -> void:
	_cursor_mine = load("res://assets/cursor/Tiles/tile_0108.png") as Texture2D
	_cursor_place = load("res://assets/cursor/Tiles/tile_0109.png") as Texture2D
	_cursor_default = load("res://assets/cursor/Tiles/tile_0026.png") as Texture2D
	# 挖矿光标摇晃用的左右旋转帧（16×16 小图，逐像素最近邻旋转开销可忽略）
	if _cursor_mine != null:
		var src := _cursor_mine.get_image()
		_cursor_mine_left = _rotate_image(src, CURSOR_WIGGLE_ANGLE)
		_cursor_mine_right = _rotate_image(src, -CURSOR_WIGGLE_ANGLE)


## 最近邻旋转小图（光标用，像素风不需要插值），角度为度
func _rotate_image(src: Image, angle_deg: float) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var dst := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rad := deg_to_rad(angle_deg)
	var cs := cos(rad)
	var sn := sin(rad)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var dx := x - cx
			var dy := y - cy
			# 逆变换取源像素
			var sx := int(round(cs * dx + sn * dy + cx))
			var sy := int(round(-sn * dx + cs * dy + cy))
			if sx >= 0 and sy >= 0 and sx < w and sy < h:
				dst.set_pixel(x, y, src.get_pixel(sx, sy))
	return dst


func _process(delta: float) -> void:
	show_target()
	update_hover()
	_update_cursor_wiggle(delta)
	_update_cursor()
	_batch_place_if_held()
	_batch_remove_if_held()
	grid.tick(delta)
	_update_flying_ores(delta)
	_update_jump_numbers(delta)
	_update_coin_flights(delta)
	_update_coin_cleanups(delta)
	_update_fire()


## 悬停中的矿（失效引用安全）：矿被挖掉后 _hovered_node 会短暂指向已释放实例
func _hovered_ore() -> OreBlock:
	if _hovered_node != null and is_instance_valid(_hovered_node) and _hovered_node is OreBlock:
		return _hovered_node as OreBlock
	return null


## 挖矿光标待机摇晃状态机：悬停矿上时每隔 1.2~2.8s 甩一下（+角度 → -角度 → 回正）。
## 非 mine 光标时立即复位，摇晃姿态通过 _cursor_wiggle_angle 参与 _update_cursor 的键比较。
func _update_cursor_wiggle(delta: float) -> void:
	if _hovered_ore() != null and selected_tile == null \
			and get_viewport().gui_get_hovered_control() == null:
		_cursor_wiggle_elapsed += delta
		if not _cursor_wiggling:
			if _cursor_wiggle_elapsed >= _cursor_wiggle_wait:
				_cursor_wiggling = true
				_cursor_wiggle_elapsed = 0.0
		else:
			var t := _cursor_wiggle_elapsed
			if t < CURSOR_WIGGLE_STEP:
				_cursor_wiggle_angle = CURSOR_WIGGLE_ANGLE
			elif t < CURSOR_WIGGLE_STEP * 3.0:
				_cursor_wiggle_angle = -CURSOR_WIGGLE_ANGLE
			elif t < CURSOR_WIGGLE_STEP * 4.0:
				_cursor_wiggle_angle = CURSOR_WIGGLE_ANGLE * 0.5
			elif t < CURSOR_WIGGLE_STEP * 5.0:
				_cursor_wiggle_angle = 0.0
			else:
				_cursor_wiggling = false
				_cursor_wiggle_elapsed = 0.0
				_cursor_wiggle_wait = randf_range(1.2, 2.8)
				_cursor_wiggle_angle = 0.0
	else:
		_cursor_wiggling = false
		_cursor_wiggle_elapsed = 0.0
		_cursor_wiggle_angle = 0.0


## 按当前状态刷新鼠标光标：放置模式(0109) > 悬停矿(0108) > 默认(0026)；鼠标在 UI 上时用默认。
## 放置模式下光标图按状态染色（绿=可放且钱够 / 红=钱不够 / 橙=位置不可放），
## 悬停矿时按 _cursor_wiggle_angle 换左右旋转帧（待机摇晃），
## 染色图缓存复用；只在状态键变化时调用 Input.set_custom_mouse_cursor（原生调用有成本）。
func _update_cursor() -> void:
	var want := &""
	var tint := Color.WHITE
	if selected_tile != null:
		want = &"place"
		if grid.can_place_tile(_hovered_cell):
			tint = POINTER_PLACE_COLOR if _can_afford_selected() else POINTER_NO_MONEY_COLOR
		else:
			tint = POINTER_BLOCKED_COLOR
	elif _hovered_ore() != null:
		want = &"mine"
	if get_viewport().gui_get_hovered_control() != null:
		want = &""   # 鼠标悬停在 UI 控件（抽屉等）上时保持默认
		tint = Color.WHITE
	var key := str(want) + "|" + tint.to_html()
	if want == &"mine":
		key += "|" + str(_cursor_wiggle_angle)
	if key == _current_cursor:
		return
	_current_cursor = key
	if want == &"place" and _cursor_place != null:
		Input.set_custom_mouse_cursor(_tinted_cursor_image(_cursor_place, tint), Input.CURSOR_ARROW)
		return
	if want == &"mine":
		var img := _cursor_mine.get_image()
		if _cursor_wiggle_angle > 0.0 and _cursor_mine_left != null:
			img = _cursor_mine_left
		elif _cursor_wiggle_angle < 0.0 and _cursor_mine_right != null:
			img = _cursor_mine_right
		Input.set_custom_mouse_cursor(img, Input.CURSOR_ARROW)
		return
	var tex := _cursor_default
	if tex != null:
		Input.set_custom_mouse_cursor(tex.get_image(), Input.CURSOR_ARROW)
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


## 生成光标的染色副本（正片叠底乘色，光标图本身是白色系所以染出来就是目标色）。
## 光标图很小（几十像素见方），逐像素乘一次后按颜色缓存。
func _tinted_cursor_image(base: Texture2D, tint: Color) -> Image:
	if _cursor_tint_cache.has(tint):
		return _cursor_tint_cache[tint]
	var img: Image = base.get_image().duplicate()
	for y in img.get_height():
		for x in img.get_width():
			var px: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(px.r * tint.r, px.g * tint.g, px.b * tint.b, px.a))
	_cursor_tint_cache[tint] = img
	return img


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell := world_to_grid(get_global_mouse_position())
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# 放置模式：左键放置选中地皮；普通模式：左键挖矿
				if selected_tile != null:
					_place_selected(cell)
				else:
					_mine_at(cell)
			MOUSE_BUTTON_RIGHT:
				# 放置模式下右键删除光标处地块
				if selected_tile != null:
					_remove_tile_at(cell)


func show_target() -> void:
	pointer.position = grid_to_world(_hovered_cell)


## 初始 3x3 泥土（设计：开局只有 dirt 可放置，见 defs/talents）：先写数据（CellData），再建渲染（Sprite）
func grid_init() -> void:
	var dirt := db.get_tile(&"dirt")
	if dirt == null:
		push_error("game_manager: 缺少 dirt 地皮定义，请检查 res://defs/tiles")
		return

	for x in range(-INITIAL_GRID_SIZE, INITIAL_GRID_SIZE + 1):
		for y in range(-INITIAL_GRID_SIZE, INITIAL_GRID_SIZE + 1):
			var cell := Vector2i(x, y)
			grid.set_cell(cell, CellData.new(null, dirt))
			create_sprite(false, cell, dirt)


# ==================== 落矿 ====================

func _on_spawn_tick() -> void:
	if grid.ores.size() >= _effective_max_ores():
		return
	var free_cells := _free_cells()
	if free_cells.is_empty():
		return
	_spawn_ore_on(free_cells.pick_random())


## 矿石上限：max_ores <= 0 时填满所有格子
func _effective_max_ores() -> int:
	return grid.cells.size() if max_ores <= 0 else max_ores


## 手动生成一个随机矿石（测试用，C 键）
func spawn_random_ore() -> void:
	var free_cells := _free_cells()
	if free_cells.is_empty():
		print("没有空闲格子了")
		return
	_spawn_ore_on(free_cells.pick_random())


## 抽取矿石并生成；rarity 地皮提高稀有度门槛，UNLOCK_ORE 天赋门控落矿池
## （水晶永远排除：只在地块 spawn 上产生，见 TalentSystem.get_natural_spawn_ores）
func _spawn_ore_on(cell: Vector2i) -> void:
	var min_rarity := grid.effective_min_rarity(cell)
	var ore_def := db.roll_ore(min_rarity, _mine_rng, _talent_system.get_natural_spawn_ores())
	if ore_def == null:
		return
	spawn_ore(cell, ore_def, 1)


## 空闲且可落矿的格子：水格允许（矿落上去会沉没并返还 10%），火山排除（不能落矿）
func _free_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in grid.cells.keys():
		if grid.ores.has(cell):
			continue
		var tile := grid.get_tile_at(cell)
		if tile == null or tile.behavior == TileDef.Behavior.VOLCANO:
			continue
		result.append(cell)
	return result


## 矿石工厂：实例化场景 → 注册进网格 → 挂到渲染层。
## 工厂在这里（场景在这里，定义在 DefDb）
func spawn_ore(cell: Vector2i, ore_def: OreDef, level: int = 1) -> void:
	if ore_def == null:
		push_warning("spawn_ore: 无效定义")
		return

	var ore := ore_prototype.instantiate() as OreBlock
	ore.setup_ore(ore_def, level, cell)
	ore.node_name = "ore,%d,%d" % [cell.x, cell.y]
	ore.position = grid_to_world(cell) + ABOVE_LAYER_OFFSET
	ore.z_index = cell.x + cell.y + 1 + ore_def.z_bias
	above_grid_layer.add_child(ore)

	var result := grid.try_spawn_ore(cell, ore)
	if not result.is_ok():
		ore.queue_free()
		push_warning("spawn_ore 失败: %s" % result.message)
		return

	ore.landed.connect(_on_ore_landed.bind(ore), CONNECT_REFERENCE_COUNTED)


func _on_ore_landed(ore: OreBlock) -> void:
	grid.notify_ore_landed(ore)


# ==================== 挖矿 ====================

func _mine_at(cell: Vector2i) -> void:
	var ore := grid.get_ore(cell)
	if ore == null or not ore.has_landed:
		_hide_mining_bar()   # 点空处/未落地矿：收起进度条
		return
	# 稿子伤害管线：基础 + 天赋 flat，grass 等倍率（effective），暴击乘区（TalentSystem）
	var hit := _talent_system.hit_damage_details(
		pickaxe_damage, grid.effective_damage_multiplier(cell), _mine_rng)
	var damage: int = hit["damage"]
	ore.hit()
	# 伤害跳数（暴击彩色晃动）
	_spawn_damage_number(ore.global_position + Vector2(0, -16), damage, hit["crit"])
	if ore.take_damage(damage):
		ore.kill_damage = damage   # 最后一击伤害 → 决定飞出力度
		state.increment_ore_mined(ore.get_def().id)   # 玩家挖死才计开采
		grid.remove_ore(cell)  # 发 ore_removed → 结算金币 + 破坏特效
	else:
		_update_mining_bar(ore)   # 还活着：更新挖矿进度条


## 挖矿伤害跳数：弹出伤害数字，动线与矿石破坏一致——随机 -45°~45° 向上抛出 + 重力自由落体
## （速度 = 基础 + 伤害×系数，与 _launch_ore 同一套参数）。下落过程中渐隐后消失。
## 暴击：彩虹变色 + 旋转晃动。全部在 _update_jump_numbers 逐帧积分，不用 Tween。
func _spawn_damage_number(world_pos: Vector2, amount: int, is_crit: bool) -> void:
	if jump_number_prototype == null:
		return
	var node := jump_number_prototype.instantiate() as Node2D
	above_grid_layer.add_child(node)
	node.global_position = world_pos
	node.z_index = 4000   # 画在方块之上
	var label := node.get_node_or_null("RichTextLabel") as RichTextLabel
	if label != null:
		label.bbcode_enabled = true
		label.text = "[center]%d[/center]" % amount   # 居中：放大时不从一侧甩出
		label.add_theme_font_size_override("normal_font_size", 20 if not is_crit else 28)
		# 高对比：白字 + 深色描边（游戏背景近白，纯白字看不见）
		label.add_theme_color_override("default_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 1.0))
		label.add_theme_constant_override("outline_size", 5)
	node.scale = Vector2(0.1, 0.1)
	# 与矿石破坏同款动线：力度 = 基础 + 伤害×系数，随机 -45°~45° 向上
	var a := deg_to_rad(randf_range(-45.0, 45.0))
	var speed := ore_launch_base + amount * ore_launch_per_damage
	var velocity := Vector2(sin(a), -cos(a)) * speed
	_jump_numbers.append({
		"node": node, "label": label, "velocity": velocity,
		"time": 0.0, "crit": is_crit,
	})


## 每帧积分伤害跳数：重力 + 位移（同矿石）；前 0.1s 弹入；下落（速度向下）后渐隐，消失即释放。
func _update_jump_numbers(delta: float) -> void:
	if _jump_numbers.is_empty():
		return
	var remaining: Array = []
	for entry in _jump_numbers:
		var node: Node2D = entry["node"]
		var velocity: Vector2 = entry["velocity"]
		entry["time"] += delta
		velocity.y += ORE_GRAVITY * delta
		entry["velocity"] = velocity
		node.global_position += velocity * delta
		# 前 0.1s 从 0.1 放大到 1（弹入）
		var grow := clampf(entry["time"] / 0.1, 0.0, 1.0)
		node.scale = Vector2.ONE * (0.1 + 0.9 * grow)
		if entry["crit"]:
			# 彩色：label 循环 hue；晃动：快速旋转
			var label: RichTextLabel = entry["label"]
			if label != null:
				label.modulate = Color.from_hsv(fmod(entry["time"] * 6.0, 1.0), 1.0, 1.0)
			node.rotation = sin(entry["time"] * 40.0) * 0.12
		else:
			node.rotation = 0.0
		# 下落（速度向下）后渐隐，消失即释放
		if velocity.y > 0.0:
			node.modulate.a -= delta * 2.5
		if node.modulate.a > 0.0:
			remaining.append(entry)
		else:
			node.queue_free()
	_jump_numbers = remaining


## 金币结算：订阅网格事件。
## 内部总额立即更新，但左上角数字用"跳数"动画滚到新值（小丑牌式结算），
## 时长 = 金币粒子播放时长 = 由该矿价值决定。矿石本身爆炸后飞出屏幕。
func _on_ore_removed(ore: OreBlock, _cell: Vector2i, reward_ratio: float = 1.0) -> void:
	# 完整结算管线：settle × 矿价值 × 地块协同 × 全局矿石价值 × reward_ratio × 全局金币 × 永久倍率
	var gained := _talent_system.compute_coin_gain(
		grid.settle_value(ore), ore.get_def().id, grid.get_placed_counts(), reward_ratio)
	state.add_coins(gained)
	print("+%s 金币（总计 %s）" % [gained.to_compact_string(), state.coins.to_compact_string()])
	if reward_ratio < 1.0:
		# 水沉没（返还 10%）：不弹射，慢慢下沉渐隐，消失后在水面开金币粒子
		_sink_ore(ore, gained)
	else:
		_play_explosion(ore.global_position, ore)
		_launch_ore(ore, gained, ore.kill_damage)
	_hide_mining_bar()   # 矿没了，进度条收起


## 删除地块时连带移除的矿（不给金币）：也播爆炸+飞出（无金币粒子）
func _on_ore_discarded(ore: OreBlock, _cell: Vector2i) -> void:
	_play_explosion(ore.global_position, ore)
	_launch_ore(ore, BigNumber.zero(), ore.kill_damage)
	_hide_mining_bar()   # 矿没了，进度条收起


## 更新/显示矿石上方的挖矿进度条（进度 = 已挖比例）。
## 首次出现时弹性缩放"弹出"。
func _update_mining_bar(ore: OreBlock) -> void:
	if _mining_bar == null:
		return
	_mining_bar.global_position = ore.global_position + Vector2(0, -26)
	var first_show := not _mining_bar.visible
	_mining_bar.visible = true
	var mined := 1.0 - float(ore.hp) / float(ore.get_max_hp())
	_mining_bar.set_progress(clampf(mined, 0.0, 1.0))
	if first_show:
		_pop_in()


## 收起进度条（先弹性缩小再隐藏）
func _hide_mining_bar() -> void:
	if _mining_bar == null or not _mining_bar.visible:
		return
	_pop_out()


## 出现：从 0.2 弹到 1（带回弹感）
func _pop_in() -> void:
	if _bar_tween:
		_bar_tween.kill()
	_mining_bar.scale = Vector2(0.2, 0.2)
	_bar_tween = create_tween()
	_bar_tween.tween_property(_mining_bar, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 消失：弹到 0.1 后隐藏
func _pop_out() -> void:
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(_mining_bar, "scale", Vector2(0.1, 0.1), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_bar_tween.tween_callback(func() -> void: _mining_bar.visible = false)


# ==================== 矿石破坏特效 ====================

## 在位置播一次爆炸序列帧动画，播完自动释放。
## 水晶类矿用 break_*（碎晶感），其他矿用 explosion*。
func _play_explosion(world_pos: Vector2, ore: OreBlock = null) -> void:
	if explosion_prototype == null:
		return
	var explosion := explosion_prototype.instantiate() as Node2D
	above_grid_layer.add_child(explosion)
	explosion.global_position = world_pos
	# 爆炸大小随最后一击伤害：伤害越高炸得越大
	var damage := ore.kill_damage if ore != null else 0
	var s := explosion_scale_base + damage * explosion_scale_per_damage
	explosion.scale = Vector2(s, s)
	explosion.z_index = 4000              # 画在所有方块之上
	var anim := explosion.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim == null:
		explosion.queue_free()
		return
	var names := anim.sprite_frames.get_animation_names()
	if names.is_empty():
		explosion.queue_free()
		return
	var is_crystal := ore != null and ore.get_def() != null and ore.get_def().id == &"crystal"
	var pool := _explosion_animation_pool(names, is_crystal)
	if pool.is_empty():
		pool = names
	anim.animation = pool[randi() % pool.size()]
	anim.play()
	anim.animation_finished.connect(func() -> void: explosion.queue_free())


## 按矿物类型挑动画池：水晶类 → break_*，其他 → explosion*
func _explosion_animation_pool(names: PackedStringArray, crystal: bool) -> Array:
	var pool: Array = []
	for n in names:
		var s := String(n)
		if crystal and s.begins_with("break_"):
			pool.append(n)
		elif not crystal and s.begins_with("explosion"):
			pool.append(n)
	return pool


## 给矿石一个随机向上角度(-45°~+45°)的初速度，之后自由落体；
## 力度 = 基础 + 最后一击伤害×系数（伤害越低越轻，大多落回屏幕底部）。
## 同时给一个随机角速度，飞行途中自由旋转（翻跟头）。
## 注意：矿石贴图透明边很多（如 256×352 里矿石只画在底部），直接转 sprite 会绕
## 贴图中心甩出诡异弧线——这里把旋转支点（sprite.offset）挪到 alpha 包围盒中心
## （矿石视觉中心），并把节点位置反向补偿同样距离：轨迹与原来完全一致，原地自转。
func _launch_ore(ore: OreBlock, gained: BigNumber, kill_damage: int) -> void:
	var a := deg_to_rad(randf_range(-45.0, 45.0))
	var speed := ore_launch_base + kill_damage * ore_launch_per_damage
	var velocity := Vector2(sin(a), -cos(a)) * speed
	var spin := deg_to_rad(randf_range(ore_spin_min, ore_spin_max)) * (1.0 if randf() < 0.5 else -1.0)
	_center_ore_pivot(ore)
	ore.z_index = 4000   # 飞到最上层（CanvasItem 上限 4096 内）
	ore.modulate = Color.WHITE   # 去掉悬停/下落残留的染色
	_flying_ores.append({"ore": ore, "velocity": velocity, "gained": gained, "spin": spin})


## 贴图 alpha 包围盒中心缓存（避免每次发射都 get_image）
var _tex_vis_center_cache := {}


## 把 sprite 的旋转支点挪到贴图内容（alpha 包围盒）中心，节点位置反向补偿：
## 发射瞬间矿石在屏幕上的位置不变，之后旋转绕矿石视觉中心原地进行
func _center_ore_pivot(ore: OreBlock) -> void:
	var sprite := ore.sprite
	if sprite == null or sprite.texture == null:
		return
	var tex := sprite.texture
	if not _tex_vis_center_cache.has(tex):
		var c := tex.get_size() * 0.5   # 兜底：全透明就用贴图中心
		var img := tex.get_image()
		if img != null:
			var used := img.get_used_rect()
			if used.has_area():
				c = used.get_center()
		_tex_vis_center_cache[tex] = c
	var vis: Vector2 = _tex_vis_center_cache[tex]
	var tex_center := tex.get_size() * 0.5
	var d := (vis - tex_center) * sprite.scale   # 矿石视觉中心相对节点的世界偏移
	if d.is_zero_approx():
		return
	sprite.offset = tex_center - vis             # 之后旋转绕矿石视觉中心
	ore.global_position += d                     # 反向补偿，画面位置不变（发射时 rotation=0）


func _update_flying_ores(delta: float) -> void:
	if _flying_ores.is_empty():
		return
	var rect := _screen_world_rect()
	var still: Array = []
	for entry in _flying_ores:
		var ore := entry["ore"] as OreBlock
		var velocity: Vector2 = entry["velocity"]
		velocity.y += ORE_GRAVITY * delta
		entry["velocity"] = velocity
		ore.global_position += velocity * delta
		# 只转精灵（原地自转）：根节点保持纯平移，轨迹不受旋转影响
		if ore.sprite:
			ore.sprite.rotation += entry["spin"] * delta
		# 判断从哪个边出屏，金币粒子在那边朝屏幕内发射
		var p := ore.global_position
		var edge_dir := Vector2.ZERO
		var exit_pos := p
		if p.y >= rect.end.y:
			exit_pos = Vector2(clampf(p.x, rect.position.x, rect.end.x), rect.end.y)
			edge_dir = Vector2.UP
		elif p.x >= rect.end.x:
			exit_pos = Vector2(rect.end.x, clampf(p.y, rect.position.y, rect.end.y))
			edge_dir = Vector2.LEFT
		elif p.x <= rect.position.x:
			exit_pos = Vector2(rect.position.x, clampf(p.y, rect.position.y, rect.end.y))
			edge_dir = Vector2.RIGHT
		elif p.y <= rect.position.y:
			exit_pos = Vector2(clampf(p.x, rect.position.x, rect.end.x), rect.position.y)
			edge_dir = Vector2.DOWN
		if edge_dir == Vector2.ZERO:
			still.append(entry)
			continue
		var gained: BigNumber = entry["gained"]
		if not gained.is_zero():
			_play_coin_and_count(exit_pos, gained, edge_dir)
		ore.queue_free()
	_flying_ores = still


## 在落点播金币粒子：时长 = 价值决定；同时金币数字在该时长内跳数。
## dir 是粒子发射方向（侧面出屏就朝屏幕内喷）。
## 同时产生"金币飞向计数板"效果：边缘跳数 + 若干拖尾（见 _spawn_coin_flight）。
func _play_coin_and_count(pos: Vector2, gained: BigNumber, dir := Vector2.UP) -> void:
	var duration := _coin_duration(gained)
	var spawned := _spawn_coin_flight(pos, gained, dir)
	if coin_prototype != null:
		var coin := coin_prototype.instantiate() as Node2D
		above_grid_layer.add_child(coin)
		coin.global_position = pos
		coin.z_index = 4000
		var particles := coin.get_node_or_null("GPUParticles2D") as GPUParticles2D
		if particles:
			particles.one_shot = true          # 一次性爆发，别一直喷
			particles.lifetime = duration
			particles.emitting = true
			# 复制材质改参数（避免污染共享资源）：
			# 粒子大小由材质的 scale_min/max 控制（不是节点缩放），
			# direction 让侧面出屏时朝屏幕内喷。
			var mat := particles.process_material as ParticleProcessMaterial
			if mat:
				mat = mat.duplicate() as ParticleProcessMaterial
				mat.direction = Vector3(dir.x, dir.y, 0)
				mat.scale_min = coin_effect_scale
				mat.scale_max = coin_effect_scale
				particles.process_material = mat
			particles.restart()
		# 等粒子全部消失再释放，避免动画被截断（戛然而止）
		_coin_cleanups.append({"node": coin, "particles": particles, "wait": duration + 1.0})
	if spawned:
		# 数字等拖尾消失后再震动上涨：把跳数挂到金币飞行完成时触发
		_pending_coin = true
		_pending_coin_duration = duration
	else:
		_count_up_coins(duration)   # 无飞行（如金币 0）立即上涨


# ==================== 金币飞向计数板 ====================

## 产生"金币飞向计数板"（主 UI 屏幕空间）：一个边缘跳数（沿出屏边缘切向飞出，放大后渐隐）
## + 若干拖尾（从两侧 20°~30° 射出，随后被 max(增长拉力, 距离反比引力 K/距离) 吸向金币计数板，汇聚后消失）。
## 返回是否产生了飞行（false 时调用方立即跳数，如金币为 0）。
func _spawn_coin_flight(pos: Vector2, gained: BigNumber, dir: Vector2) -> bool:
	if gained.is_zero() or _coin_flight_layer == null:
		return false
	var screen_pos := _screen_from_world(pos)
	# 从边缘向屏幕内缩进，避免跳数标签被屏幕边缘裁掉一半
	var view := get_viewport().get_visible_rect().size
	screen_pos.x = clampf(screen_pos.x, 36.0, view.x - 36.0)
	screen_pos.y = clampf(screen_pos.y, 36.0, view.y - 36.0)
	_spawn_edge_number(screen_pos, gained, dir)
	var counter := _money_counter_screen_pos()
	for i in _coin_trail_count(gained):
		_spawn_coin_trail(screen_pos, dir, counter)
	return true


## 边缘跳数（屏幕空间）：显示本次金币额，沿出屏边缘的切向（正上/正下/正左/正右）直线飞出，
## 快速放大后渐隐。
func _spawn_edge_number(pos: Vector2, gained: BigNumber, dir: Vector2) -> void:
	var proto := coin_number_prototype if coin_number_prototype != null else jump_number_prototype
	if proto == null or _coin_flight_layer == null:
		return
	var node := proto.instantiate() as Node2D
	node.z_index = 4000   # 跳数盖在主 UI 之上（拖尾才在计数板之下）
	_coin_flight_layer.add_child(node)
	node.position = pos
	var label := node.get_node_or_null("RichTextLabel") as RichTextLabel
	if label != null:
		label.bbcode_enabled = true
		label.text = "[center]%s[/center]" % gained.to_compact_string()   # 居中：放大时不从一侧甩出
		label.add_theme_font_size_override("normal_font_size", 30)
		label.add_theme_color_override("default_color", Color(1.0, 0.9, 0.3))   # 金黄
		label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 1.0))
		label.add_theme_constant_override("outline_size", 8)
	# 只做竖直方向：底/侧边出屏 → 直上；顶部出屏 → 直下（不做左右偏移）
	var fly_dir := Vector2.UP
	if dir == Vector2.DOWN:
		fly_dir = Vector2.DOWN
	_coin_flights.append({
		"kind": "num", "node": node, "velocity": fly_dir * COIN_NUM_SPEED,
		"time": 0.0, "target": Vector2.ZERO, "pull": 0.0,
	})


## 单个拖尾（屏幕空间，细长）：从屏幕边缘沿出屏方向的扇形扩散飞出，
## 后续由 _update_coin_flights 施加拉力拉向计数板
func _spawn_coin_trail(pos: Vector2, dir: Vector2, counter: Vector2) -> void:
	if tail_prototype == null or _coin_flight_layer == null:
		return
	var trail := tail_prototype.instantiate() as Node2D
	trail.width = 3.0
	trail.max_alpha = 0.8
	trail.trail_length = 50
	trail.line_z_index = -5   # 线画在主 UI 控件（计数板）之下
	_coin_flight_layer.add_child(trail)
	trail.position = Vector2.ZERO   # 静态锚点：节点不动，线画在图层里（喂 head 坐标）
	# 初始：从两侧 20°~30° 射出（随机取左/右），先向两侧飞、再被吸回
	var side := 1.0 if randf() < 0.5 else -1.0
	var a := atan2(dir.y, dir.x) + side * deg_to_rad(randf_range(20.0, 30.0))
	var velocity := Vector2(cos(a), sin(a)) * COIN_TRAIL_SPREAD
	_coin_flights.append({
		"kind": "trail", "node": trail, "head": pos, "velocity": velocity,
		"time": 0.0, "target": counter, "target_rect": _money_counter_rect(),
		"pull": COIN_TRAIL_PULL_START, "lateral_dir": 1.0 if randf() < 0.5 else -1.0,
	})


## 拖尾数量：随金币额增长但封顶（实际金币可能上亿，不能 1:1）
func _coin_trail_count(gained: BigNumber) -> int:
	var v := gained.to_float()
	var n := int(roundf(sqrt(min(v, 1e6))))
	return clampi(n, 2, COIN_TRAIL_COUNT_CAP)


## 每帧处理金币飞行体；全部消失后触发挂起的金币跳数（先震动再上涨）
func _update_coin_flights(delta: float) -> void:
	_process_coin_flights(delta)
	# 拖尾全部消失后，触发挂起的金币跳数（_count_up_coins 内先 _play_money_dance 震动）
	if _coin_flights.is_empty() and _pending_coin:
		_pending_coin = false
		_count_up_coins(_pending_coin_duration)


## 积分金币飞行体：
##   跳数 → 沿切向匀速直线飞，前 0.12s 放大，0.3s 后渐隐；
##   拖尾 → 扩散飞出 + max(增长拉力, 距离反比引力) 拉向计数板，靠近目标/超时渐隐消失。
func _process_coin_flights(delta: float) -> void:
	if _coin_flights.is_empty():
		return
	var remaining: Array = []
	for e in _coin_flights:
		var node: Node2D = e["node"]
		e["time"] += delta
		var time: float = e["time"]
		var velocity: Vector2 = e["velocity"]
		var target: Vector2 = e["target"]
		var alive := true
		if e["kind"] == "num":
			node.global_position += velocity * delta
			var grow := clampf(time / 0.12, 0.0, 1.0)
			node.scale = Vector2.ONE * (0.1 + 0.9 * grow)
			if time > 0.6:
				node.modulate.a -= delta * 2.0
			alive = node.modulate.a > 0.02
		else:
			# 拖尾：节点不动，跟踪"头部位置"并喂给拖尾画线
			var head: Vector2 = e["head"]
			var pull: float = e["pull"]
			# 向左右随机方向的力，随时间衰减（先猛地侧飞，随后衰减让拉力接管）
			var lateral_force := COIN_TRAIL_LATERAL_FORCE * exp(-COIN_TRAIL_LATERAL_DECAY * e["time"])
			velocity += Vector2.RIGHT * float(e["lateral_dir"]) * lateral_force * delta
			# 终点引力 = max(当前增长拉力, 距离反比引力 K/(dist/3))：越靠近计数板吸力越强，
			# 与现有拉力取 max 只强不弱；min 距离下限防除零/爆炸
			var dist := maxf(head.distance_to(target), 40.0)
			var pull_eff := maxf(pull, COIN_TRAIL_DISTANCE_PULL / (dist / 3.0))
			velocity += (target - head).normalized() * pull_eff * delta
			velocity *= maxf(0.0, 1.0 - COIN_TRAIL_DAMPING * delta)
			velocity = velocity.limit_length(COIN_TRAIL_MAX_SPEED)   # 限速防过冲
			e["velocity"] = velocity
			head += velocity * delta
			# 夹取在视口内：侧飞顶到屏幕边缘时贴边滑行，不出屏
			var view_size := get_viewport().get_visible_rect().size
			head.x = clampf(head.x, 0.0, view_size.x)
			head.y = clampf(head.y, 0.0, view_size.y)
			e["head"] = head
			e["pull"] = pull + COIN_TRAIL_PULL_GROWTH * delta
			node.call("add_position", head)
			# 头部进入计数板面板矩形或贴近中心（<60px）→ 快速消失（藏到面板后面/避免高速过冲）；
			# 超时兜底（4.5s，绕大弧线的拖尾）→ 缓慢淡出，不会"戛然而止"
			var rect: Rect2 = e["target_rect"]
			if rect.has_point(head) or head.distance_to(target) < 90.0:
				node.set_alpha(node.get_alpha() - delta * 3.2)
			elif time > 4.5:
				node.set_alpha(node.get_alpha() - delta * 1.5)
			alive = node.get_alpha() > 0.02
		if alive and time < 5.0:
			remaining.append(e)
		else:
			node.queue_free()
	_coin_flights = remaining


## 世界坐标 → 屏幕坐标（相机投影）
func _screen_from_world(world_pos: Vector2) -> Vector2:
	if _camera == null:
		return world_pos
	var center := _camera.get_screen_center_position()
	var view := get_viewport().get_visible_rect().size
	return (world_pos - center) * _camera.zoom + view * 0.5


## 金币计数板中心（屏幕坐标，金币飞行的汇聚目标）
func _money_counter_screen_pos() -> Vector2:
	if money_label != null:
		var panel := money_label.get_parent().get_parent() as Control
		if panel != null:
			return panel.get_global_rect().get_center()
	return Vector2(91, 53)   # 兜底：计数板左上角附近


## 金币计数板面板矩形（屏幕坐标）：拖尾"藏到面板后面"的判断依据
func _money_counter_rect() -> Rect2:
	if money_label != null:
		var panel := money_label.get_parent().get_parent() as Control
		if panel != null:
			return panel.get_global_rect()
	return Rect2(48, 33, 86, 40)   # 兜底：计数板大致位置


## 每帧递减等待计时，粒子播完（含最后一批粒子寿命）后释放金币节点
func _update_coin_cleanups(delta: float) -> void:
	if _coin_cleanups.is_empty():
		return
	var remaining: Array = []
	for entry in _coin_cleanups:
		var wait: float = entry["wait"] - delta
		entry["wait"] = wait
		if wait <= 0.0:
			(entry["node"] as Node).queue_free()
		else:
			remaining.append(entry)
	_coin_cleanups = remaining


## 金币粒子播放时长：价值越高播得越久（0.5s ~ 3s）
func _coin_duration(gained: BigNumber) -> float:
	return clampf(0.5 + gained.to_float() * 0.006, 0.5, 3.0)


## 金币数字跳数：从当前显示值滚到最新总额，时长与粒子一致（小丑牌式结算）
func _count_up_coins(duration: float) -> void:
	if money_label == null:
		return
	_play_money_dance()
	if _coin_tween:
		_coin_tween.kill()
	var from := _displayed_coins
	var target := state.coins
	_coin_tween = create_tween()
	_coin_tween.tween_method(_tick_count_up.bind(from, target), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_coin_tween.tween_callback(_set_money_display_exact.bind(target))


## 跳数逐帧：大数走对数空间插值，避免大值线性插值时长时间停在原位
func _tick_count_up(progress: float, from: BigNumber, to: BigNumber) -> void:
	_set_money_display(BigNumber.lerp(from, to, progress))


func _set_money_display(value: BigNumber) -> void:
	_displayed_coins = value
	_refresh_money_text()


func _set_money_display_exact(value: BigNumber) -> void:
	_displayed_coins = value
	_refresh_money_text()


func _refresh_money_text() -> void:
	if money_label:
		money_label.text = format_compact_coins(_displayed_coins)


## Cookie Clicker 式紧凑数字：约三位有效数字，并避免显示成 1000K。
static func format_compact_coins(value: BigNumber) -> String:
	return value.to_compact_string()


## 获得金币时让文字做一次短促的弹跳、摇摆和挤压；连续收益会从头重播。
func _play_money_dance() -> void:
	if money_label == null:
		return
	if _money_dance_tween:
		_money_dance_tween.kill()
	_reset_money_dance()

	_money_dance_tween = create_tween()
	_money_dance_tween.tween_property(money_label, "offset_transform_position", Vector2(-1, -5), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_scale", Vector2(1.22, 0.84), 0.08)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_rotation", deg_to_rad(-8.0), 0.08)

	_money_dance_tween.tween_property(money_label, "offset_transform_position", Vector2(1, -3), 0.09)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_scale", Vector2(0.92, 1.20), 0.09)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_rotation", deg_to_rad(7.0), 0.09)

	_money_dance_tween.tween_property(money_label, "offset_transform_position", Vector2(-1, -1), 0.08)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_scale", Vector2(1.10, 0.94), 0.08)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_rotation", deg_to_rad(-3.0), 0.08)

	_money_dance_tween.tween_property(money_label, "offset_transform_position", Vector2.ZERO, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_scale", Vector2.ONE, 0.12)
	_money_dance_tween.parallel().tween_property(money_label, "offset_transform_rotation", 0.0, 0.12)
	_money_dance_tween.tween_callback(_reset_money_dance)


func _reset_money_dance() -> void:
	if money_label == null:
		return
	money_label.offset_transform_position = Vector2.ZERO
	money_label.offset_transform_scale = Vector2.ONE
	money_label.offset_transform_rotation = 0.0


## 相机当前可见的世界矩形（用于判断矿石从哪条边出屏）
func _screen_world_rect() -> Rect2:
	if _camera == null:
		return Rect2(-100000, -100000, 200000, 200000)
	var center := _camera.get_screen_center_position()
	var view := get_viewport().get_visible_rect().size
	var half := view * 0.5 / _camera.zoom
	return Rect2(center - half, half * 2.0)


## 水沉没：矿石不弹射，慢慢下沉+渐隐，消失后在水面开金币粒子
func _sink_ore(ore: OreBlock, gained: BigNumber) -> void:
	var surface := ore.global_position
	ore.modulate = Color.WHITE
	ore.z_index = 4000
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ore, "global_position", surface + Vector2(0, 36), 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(ore, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tween.chain().set_parallel(false)
	tween.tween_callback(func() -> void:
		_play_coin_and_count(surface, gained)
		ore.queue_free())


## 位移（push/pull）：移动节点位置并更新叠放顺序
func _on_ore_moved(ore: OreBlock, _from_cell: Vector2i, to_cell: Vector2i) -> void:
	var tween := create_tween()
	tween.tween_property(ore, "position", grid_to_world(to_cell) + ABOVE_LAYER_OFFSET, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ore.z_index = to_cell.x + to_cell.y + 1 + ore.get_def().z_bias


## spawn 地皮请求生成矿石：实例化场景并走网格写入口。
## 尊重全局矿石上限（与其他落矿路径一致）。
func _on_tile_request_spawn(cell: Vector2i, ore_id: StringName) -> void:
	if grid.ores.size() >= _effective_max_ores():
		return
	var ore_def := db.get_ore(ore_id)
	if ore_def == null:
		push_warning("tile_request_spawn: 未知矿石 %s" % ore_id)
		return
	spawn_ore(cell, ore_def, 1)


func _update_money_label() -> void:
	_displayed_coins = state.coins.duplicate()
	_refresh_money_text()


## 破纪录火焰：金币超过之前的最高值 → 冒火特效；
## 一分钟内没破纪录则把纪录滚到当前值（下次超过再冒火）
func _update_fire() -> void:
	if money_fire_material == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if state.coins.gt(_best_coins):
		_best_coins = state.coins.duplicate()
		_last_beat_time = now
		_trigger_fire()
	elif now - _last_beat_time > RECORD_WINDOW:
		_best_coins = state.coins.duplicate()


## 冒火：拉高 shader 的 amount（火焰强度）保持一会儿再淡出
func _trigger_fire() -> void:
	if _fire_tween:
		_fire_tween.kill()
	money_fire_material.set_shader_parameter("amount", 6.0)
	_fire_tween = create_tween()
	_fire_tween.tween_interval(2.5)
	_fire_tween.tween_property(money_fire_material, "shader_parameter/amount", 0.0, 0.8)


# ==================== 存档 ====================

## 有存档 → 恢复 state + 网格；无存档 → 新游戏初始化。
## 升华后 run_version 失配（天赋场景跨进程写入）→ 网格是旧轮的，重建新一轮。
func _load_or_init() -> void:
	var data := _save_manager.load()
	if data.is_empty():
		_init_new_run()
		return
	state.load_from_dict(data.get("state", {}))
	var saved_grid: Dictionary = data.get("grid", {})
	var grid_run: int = int(saved_grid.get("run_version", 0))
	if grid_run != state.run_version:
		push_warning("存档: 网格 run_version(%d) ≠ state(%d)，升华后重建新一轮" % [grid_run, state.run_version])
		_init_new_run()
		return
	_restore_grid(saved_grid)
	# 兜底：存档缺中心地块（旧档/损坏）→ 重新初始化保证可玩
	if not grid.has_cell(GridModel.CENTER_CELL):
		push_warning("存档恢复: 缺少中心地块，重新初始化")
		_init_new_run()


## 新一轮初始化：初始 dirt 网格 + 金币种子矿（显式 spawn，绕过落矿门控）
func _init_new_run() -> void:
	grid_init()
	spawn_ore(Vector2i.ONE, db.get_ore(&"gold"), 1)
	spawn_random_ore()
	spawn_random_ore()


## 从快照重建网格：先数据（cells），再场景（sprite），最后矿石（工厂）
func _restore_grid(data: Dictionary) -> void:
	for entry: Dictionary in data.get("cells", []):
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		var below: BlockDef = db.get_tile(entry["below"]) if entry["below"] != "" else null
		var above: BlockDef = db.get_tile(entry["above"]) if entry["above"] != "" else null
		grid.set_cell(cell, CellData.new(above, below))
		if below != null:
			create_sprite(false, cell, below)
		if above != null:
			create_sprite(true, cell, above)
	for entry: Dictionary in data.get("ores", []):
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		var ore_def := db.get_ore(StringName(entry["ore"]))
		if ore_def == null:
			push_warning("存档恢复: 未知矿石 %s，跳过" % entry["ore"])
			continue
		spawn_ore(cell, ore_def, int(entry["level"]))
		var ore := grid.get_ore(cell)
		if ore != null:
			ore.hp = int(entry["hp"])
			ore.has_landed = true


## 组装存档内容（state + 网格快照）并写盘。
## grid.run_version = state.run_version：主场景启动用它判断网格是否属于当前轮。
func _save_game() -> void:
	var payload := {
		"version": SaveManager.SAVE_VERSION,
		"state": state.to_dict(),
		"grid": {
			"run_version": state.run_version,
			"cells": grid.snapshot_cells(),
			"ores": grid.snapshot_ores(),
		},
	}
	_save_manager.save(payload)
	_save_dirty = false


func _on_autosave_tick() -> void:
	if _save_dirty:
		_save_game()


## 场景切换前强制存档（进入天赋界面等用），不依赖脏标记/定时器
func save_now() -> void:
	_save_game()


func _mark_save_dirty() -> void:
	_save_dirty = true


func _on_grid_changed(_cell: Vector2i) -> void:
	_save_dirty = true


## 窗口关闭前存档；编辑器停跑/崩溃由自动存档兜底
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
		get_tree().quit()


# ==================== 地皮放置 / 删除 ====================

## 当前选中的放置地皮（null = 未进入放置模式）
var selected_tile: TileDef = null

## 放置模式切换信号：视图订阅它来同步抽屉按钮状态
signal tile_selection_changed(tile: TileDef)
## _ready 完成信号：抽屉等视图在此时刷新（TalentSystem 已就绪，可查解锁状态）
signal initialized


## 该地块是否已在天赋中解锁（UNLOCK_TILE 门控；抽屉据此隐藏未解锁按钮）。
## TalentSystem 未就绪时放行（避免启动时序竞态把全部按钮藏掉）。
func is_tile_unlocked(tile_id: StringName) -> bool:
	return _talent_system == null or _talent_system.has_unlocked_tile(tile_id)


## 抽屉按钮调用：切换某地皮为当前放置目标；再点一次取消选择。
## 未在天赋中解锁的地块不能进入放置模式。
func toggle_tile_selection(id: StringName) -> void:
	var def := db.get_tile(id)
	if def == null:
		push_warning("toggle_tile_selection: 未知地皮 %s" % id)
		return
	if selected_tile != def and not is_tile_unlocked(id):
		push_warning("toggle_tile_selection: %s 未解锁（先去天赋树解锁）" % def.display_name)
		return
	selected_tile = null if selected_tile == def else def
	tile_selection_changed.emit(selected_tile)
	_update_pointer_tint()


## 清除放置选择（抽屉关闭时调用），退出放置模式
func clear_tile_selection() -> void:
	if selected_tile == null:
		return
	selected_tile = null
	tile_selection_changed.emit(null)
	_update_pointer_tint()


func _place_selected(cell: Vector2i) -> void:
	if selected_tile == null:
		return
	# 防御：未解锁地块不可放置（正常入口已被抽屉/toggle 拦截）
	if not is_tile_unlocked(selected_tile.id):
		push_warning("_place_selected: %s 未解锁" % selected_tile.display_name)
		return
	# 放置计价：base × 1.15^已放置；先扣钱再写网格（失败回滚）
	var cost := TilePricing.placement_cost(selected_tile, grid.get_placed_count(selected_tile.id))
	if not state.spend_coins(cost):
		print("金币不足：%s 需要 %s" % [selected_tile.display_name, cost.to_compact_string()])
		return
	var result := grid.try_place_tile(cell, selected_tile)
	if not result.is_ok():
		state.add_coins(cost)   # 放置失败回滚
		print("放置失败: %s" % result.message)
		return
	create_sprite(false, cell, selected_tile)
	_last_placed_cell = cell
	# 写入后立刻刷新指针颜色（鼠标没动时 update_hover 会提前返回）
	_update_pointer_tint()


## 长按左键批量放置：按住左键拖动，经过可放的格子就连续放置
func _batch_place_if_held() -> void:
	if selected_tile == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_last_placed_cell = Vector2i(999999, 999999)
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return  # 右键批量删除优先，避免同一格上互相打架
	# 鼠标悬停在 UI 控件上时不批量放（避免隔着抽屉按钮放块）
	if get_viewport().gui_get_hovered_control() != null:
		return
	if _hovered_cell == _last_placed_cell:
		return
	if not grid.can_place_tile(_hovered_cell):
		return
	_place_selected(_hovered_cell)


func _remove_tile_at(cell: Vector2i) -> void:
	var tile := grid.get_tile_at(cell)
	if tile == null:
		print("删除失败: 该位置没有地块")
		return
	var placed_before := grid.get_placed_count(tile.id)
	var result := grid.try_remove_tile(cell)
	if not result.is_ok():
		print("删除失败: %s" % result.message)
		return
	# 卖出返还 25% 的当前买入价（移除前数量计算）
	var refund := TilePricing.refund_value(tile, placed_before)
	if not refund.is_zero():
		state.add_coins(refund)
		print("卖出 %s 返还 %s" % [tile.display_name, refund.to_compact_string()])
	var node := tiles_by_cell.get(cell) as Block
	if node != null:
		tiles_by_cell.erase(cell)
		node.queue_free()
	# 刚删掉的格不立刻被批量放置补回来（长按左键 + 右键删除的组合操作）
	_last_placed_cell = cell
	_last_removed_cell = cell
	# 地块上的矿石由 ore_discarded 处理器统一释放（不给金币）
	_update_pointer_tint()


## 长按右键批量删除：按住右键拖动，经过可删的格子就连续删除
func _batch_remove_if_held() -> void:
	if selected_tile == null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_last_removed_cell = Vector2i(999999, 999999)
		return
	# 鼠标悬停在 UI 控件上时不批量删
	if get_viewport().gui_get_hovered_control() != null:
		return
	if _hovered_cell == _last_removed_cell:
		return
	if not grid.can_remove_tile(_hovered_cell):
		return
	_remove_tile_at(_hovered_cell)


## 放置模式下给格子高亮指针（世界内 AnimatedSprite2D）染色：绿=可放且钱够、红=钱不够、橙=位置不可放。
## 鼠标光标本体的同款染色在 _update_cursor 里做。
func _update_pointer_tint() -> void:
	if pointer == null:
		return
	if selected_tile == null:
		pointer.modulate = Color.WHITE
		return
	if grid.can_place_tile(_hovered_cell):
		# 可放置：金币充足绿 / 不足红
		pointer.modulate = POINTER_PLACE_COLOR if _can_afford_selected() else POINTER_NO_MONEY_COLOR
	else:
		# 位置不可放置（含已被占用/不可达的格子）：橙
		pointer.modulate = POINTER_BLOCKED_COLOR


## 当前选中地块的放置价（base × 1.15^已放置）是否负担得起
func _can_afford_selected() -> bool:
	return selected_tile != null and state.coins.gte(
		TilePricing.placement_cost(selected_tile, grid.get_placed_count(selected_tile.id)))


# ==================== 通用方块（地皮等） ====================

func set_block(is_above: bool, cell: Vector2i, block_def: BlockDef) -> void:
	grid.set_block(is_above, cell, block_def)
	create_sprite(is_above, cell, block_def)


func create_sprite(is_above: bool, cell: Vector2i, block_def: BlockDef) -> void:
	var block_instance := block_prototype.instantiate() as Block
	block_instance.setup_from_def(block_def, cell)
	block_instance.starts_falling = false
	block_instance.node_name = "%s,%d,%d" % [is_above, cell.x, cell.y]

	block_instance.position = grid_to_world(cell) + (ABOVE_LAYER_OFFSET if is_above else Vector2.ZERO)
	block_instance.z_index = cell.x + cell.y + (1 if is_above else 0) + block_def.z_bias

	if is_above:
		above_grid_layer.add_child(block_instance)
	else:
		below_grid_layer.add_child(block_instance)

	if not is_above:
		tiles_by_cell[cell] = block_instance


# ==================== 悬停 / 坐标 ====================

## 交互目标：优先矿石，其次地皮
func _node_at(cell: Vector2i) -> Block:
	if grid.ores.has(cell):
		return grid.ores[cell]
	return tiles_by_cell.get(cell) as Block


## 当前悬停的节点（矿石或地皮）。跟踪节点而非格子：
## 这样当"下方块"悬停时又有矿落在同格，悬停会转移到矿上，下方的块正常退出漂浮。
var _hovered_node: Block = null
var _hovered_allow_float := true   # 当前悬停是否允许上浮（放置模式下有矿压着的地块=false）

## 放置预览虚影（半透明）：放置模式下悬停可放格子时显示要放置的地块
var _ghost: Sprite2D = null
const GHOST_ALPHA := 0.45


const INVALID_CELL := Vector2i(999999, 999999)   # update_hover 的"不覆盖"哨兵


func update_hover(cell_override := INVALID_CELL) -> void:
	# 悬停的矿可能刚被挖掉/销毁：先清失效引用，否则后续 == 比较和 is 判断会报
	# "Left operand of 'is' is a previously freed instance"
	if _hovered_node != null and not is_instance_valid(_hovered_node):
		_hovered_node = null
	var hovered_cell := cell_override if cell_override != INVALID_CELL \
		else world_to_grid(get_global_mouse_position())
	_hovered_cell = hovered_cell
	_update_ghost(hovered_cell)
	_update_pointer_tint()   # 每帧刷：金币量变化时虚影/指针颜色实时更新
	var node: Block = null
	var allow_float := true
	if selected_tile != null:
		# 放置模式：只跟地块互动（矿不响应悬浮/挖矿光标）；
		# 有矿压着的地块只显示描边、不上浮（矿压在上面，浮起来会穿帮）
		node = tiles_by_cell.get(hovered_cell) as Block
		allow_float = node != null and not grid.ores.has(hovered_cell)
	else:
		node = _node_at(hovered_cell)
	if node == _hovered_node and allow_float == _hovered_allow_float:
		return
	if _hovered_node != null:
		_hovered_node.set_hovered(false)
	_hovered_node = node
	_hovered_allow_float = allow_float
	if _hovered_node != null:
		_hovered_node.set_hovered(true, allow_float)


## 放置预览虚影：放置模式下、鼠标在可放置格子上（且不在 UI 上）时显示。
## 每帧从 update_hover 调用，选择切换/放置/删除后悬停格语义变化也走这里刷新。
## 颜色：绿 = 可放且钱够；红 = 可放但钱不够。位置不可放时虚影隐藏（指针显示橙色）。
func _update_ghost(cell: Vector2i) -> void:
	var show := selected_tile != null \
		and get_viewport().gui_get_hovered_control() == null \
		and grid.can_place_tile(cell)
	if show:
		if _ghost == null:
			_ghost = Sprite2D.new()
			_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 与方块一致：像素风
			_ghost.scale = Vector2.ONE * Block.TEXTURE_BASE_SCALE      # 与地块方块同缩放
			below_grid_layer.add_child(_ghost)
		_ghost.texture = selected_tile.get_texture(0)
		_ghost.position = grid_to_world(cell)
		_ghost.z_index = cell.x + cell.y + selected_tile.z_bias   # 与真实地块同一套遮挡序
		_ghost.modulate = Color(POINTER_PLACE_COLOR, GHOST_ALPHA) if _can_afford_selected() \
			else Color(POINTER_NO_MONEY_COLOR, GHOST_ALPHA)
	if _ghost != null:
		_ghost.visible = show


func grid_to_world(cell: Vector2i) -> Vector2:
	var tile_width := 32.0
	var tile_height := 16.0

	return Vector2(
		(cell.x - cell.y) * tile_width / 2.0,
		(cell.x + cell.y) * tile_height / 2.0
	)

func world_to_grid(world_position: Vector2) -> Vector2i:
	var d := world_position.x / 16.0
	var s := world_position.y / 8.0

	return Vector2i(
		roundi((s + d) / 2.0),
		roundi((s - d) / 2.0)
	)
