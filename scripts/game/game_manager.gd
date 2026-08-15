extends Node2D
class_name GameManager

const ABOVE_LAYER_OFFSET := Vector2(0, -8)
const INITIAL_GRID_SIZE := 1   # 初始 3x3 草地（半径 1）

# 矿石破坏后自由落体重力
const ORE_GRAVITY := 700.0

# 放置模式下指针颜色：绿=可放 / 橙=可删 / 红=都不行
const POINTER_PLACE_COLOR := Color(0.4, 1, 0.4)
const POINTER_REMOVE_COLOR := Color(1, 0.72, 0.25)
const POINTER_BLOCKED_COLOR := Color(1, 0.35, 0.35)

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

## 矿石破坏特效原型：爆炸序列帧 / 金币粒子 / 挖矿进度条
@export var explosion_prototype: PackedScene = null
@export var coin_prototype: PackedScene = null
@export var progress_bar_prototype: PackedScene = null
## 金币粒子整体缩放（贴图 20x18 已经小，这个再乘一档）
@export var coin_effect_scale := 0.4
## 矿石飞出力度：基础 + 每点最后一击伤害附加的力。
## 基础调低让大多数矿落回底部，只有高伤害（暴击/草地）才飞得远。
@export var ore_launch_base := 120.0
@export var ore_launch_per_damage := 25.0
## 爆炸大小：基础缩放 + 每点最后一击伤害附加的缩放
@export var explosion_scale_base := 0.3
@export var explosion_scale_per_damage := 0.015

## 正在飞出屏幕的矿石（{ore, velocity, gained}）
var _flying_ores: Array = []
## 当前正在挖的矿上方的进度条
var _mining_bar: Node2D = null
var _bar_tween: Tween
## 等待粒子全部消失后再释放的金币粒子（{node, particles, wait}）
var _coin_cleanups: Array = []
## 左上角显示的金币值（跳数动画期间与 state.coins 不同步）
var _displayed_coins := BigNumber.zero()
var _coin_tween: Tween

@onready var _camera: Camera2D = get_node_or_null("Camera2D") as Camera2D

var _spawn_timer: Timer
var _autosave_timer: Timer


func _ready() -> void:
	# 存档脏标记先连好：初始网格构建（_load_or_init）也要标脏，否则纯新档不会自动存档
	state.changed.connect(_mark_save_dirty)
	grid.tile_changed.connect(_on_grid_changed)

	db.load_all()
	_load_or_init()   # 有存档 → 恢复；无存档 → 新游戏初始化

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


func _process(delta: float) -> void:
	show_target()
	update_hover()
	_batch_place_if_held()
	_batch_remove_if_held()
	grid.tick(delta)
	_update_flying_ores(delta)
	_update_coin_cleanups(delta)
	_update_fire()


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


## 初始 3x3 草地：先写数据（CellData），再建渲染（Sprite）
func grid_init() -> void:
	var grass := db.get_tile(&"grass")
	if grass == null:
		push_error("game_manager: 缺少 grass 地皮定义，请检查 res://defs/tiles")
		return

	for x in range(-INITIAL_GRID_SIZE, INITIAL_GRID_SIZE + 1):
		for y in range(-INITIAL_GRID_SIZE, INITIAL_GRID_SIZE + 1):
			var cell := Vector2i(x, y)
			grid.set_cell(cell, CellData.new(null, grass))
			create_sprite(false, cell, grass)


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


## 抽取矿石并生成；rarity 地皮会提高稀有度门槛
func _spawn_ore_on(cell: Vector2i) -> void:
	var tile := grid.get_tile_at(cell)
	var min_rarity := tile.min_rarity if tile != null else 1
	var ore_def := db.roll_ore(min_rarity)
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
	# grass 地皮会放大受到的挖矿伤害
	var damage := grid.hit_damage(ore, pickaxe_damage)
	ore.hit()
	if ore.take_damage(damage):
		ore.kill_damage = damage   # 最后一击伤害 → 决定飞出力度
		state.increment_ore_mined(ore.get_def().id)   # 玩家挖死才计开采
		grid.remove_ore(cell)  # 发 ore_removed → 结算金币 + 破坏特效
	else:
		_update_mining_bar(ore)   # 还活着：更新挖矿进度条


## 金币结算：订阅网格事件。
## 内部总额立即更新，但左上角数字用"跳数"动画滚到新值（小丑牌式结算），
## 时长 = 金币粒子播放时长 = 由该矿价值决定。矿石本身爆炸后飞出屏幕。
func _on_ore_removed(ore: OreBlock, _cell: Vector2i, reward_ratio: float = 1.0) -> void:
	var gained := int(roundf(grid.settle_value(ore) * reward_ratio))
	state.add_coins(BigNumber.from_int(gained))
	print("+%d 金币（总计 %s）" % [gained, state.coins.to_save_string()])
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
	_launch_ore(ore, 0, ore.kill_damage)
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
func _launch_ore(ore: OreBlock, gained: int, kill_damage: int) -> void:
	var a := deg_to_rad(randf_range(-45.0, 45.0))
	var speed := ore_launch_base + kill_damage * ore_launch_per_damage
	var velocity := Vector2(sin(a), -cos(a)) * speed
	ore.z_index = 4000   # 飞到最上层（CanvasItem 上限 4096 内）
	ore.modulate = Color.WHITE   # 去掉悬停/下落残留的染色
	_flying_ores.append({"ore": ore, "velocity": velocity, "gained": gained})


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
		var gained: int = entry["gained"]
		if gained > 0:
			_play_coin_and_count(exit_pos, gained, edge_dir)
		ore.queue_free()
	_flying_ores = still


## 在落点播金币粒子：时长 = 价值决定；同时金币数字在该时长内跳数。
## dir 是粒子发射方向（侧面出屏就朝屏幕内喷）。
func _play_coin_and_count(pos: Vector2, gained: int, dir := Vector2.UP) -> void:
	var duration := _coin_duration(gained)
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
	_count_up_coins(duration)


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
func _coin_duration(gained: int) -> float:
	return clampf(0.5 + gained * 0.006, 0.5, 3.0)


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
func _sink_ore(ore: OreBlock, gained: int) -> void:
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

## 有存档 → 恢复 state + 网格；无存档 → 新游戏初始化
func _load_or_init() -> void:
	var data := _save_manager.load()
	if data.is_empty():
		grid_init()
		spawn_ore(Vector2i.ONE, db.get_ore(&"gold"), 1)
		spawn_random_ore()
		spawn_random_ore()
		return
	state.load_from_dict(data.get("state", {}))
	_restore_grid(data.get("grid", {}))
	# 兜底：存档缺中心地块（旧档/损坏）→ 重新初始化保证可玩
	if not grid.has_cell(GridModel.CENTER_CELL):
		push_warning("存档恢复: 缺少中心地块，重新初始化")
		grid_init()


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


## 组装存档内容（state + 网格快照）并写盘
func _save_game() -> void:
	var payload := {
		"version": SaveManager.SAVE_VERSION,
		"state": state.to_dict(),
		"grid": {"cells": grid.snapshot_cells(), "ores": grid.snapshot_ores()},
	}
	_save_manager.save(payload)
	_save_dirty = false


func _on_autosave_tick() -> void:
	if _save_dirty:
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


## 抽屉按钮调用：切换某地皮为当前放置目标；再点一次取消选择
func toggle_tile_selection(id: StringName) -> void:
	var def := db.get_tile(id)
	if def == null:
		push_warning("toggle_tile_selection: 未知地皮 %s" % id)
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
	var result := grid.try_place_tile(cell, selected_tile)
	if not result.is_ok():
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
	var result := grid.try_remove_tile(cell)
	if not result.is_ok():
		print("删除失败: %s" % result.message)
		return
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


## 放置模式下给鼠标指针染色：绿=可放、橙=可删（矿石会随地块一起删）、红=都不行（中心/桥/太远）
func _update_pointer_tint() -> void:
	if pointer == null:
		return
	if selected_tile == null:
		pointer.modulate = Color.WHITE
		return
	if grid.can_place_tile(_hovered_cell):
		pointer.modulate = POINTER_PLACE_COLOR
	elif grid.can_remove_tile(_hovered_cell):
		pointer.modulate = POINTER_REMOVE_COLOR
	else:
		pointer.modulate = POINTER_BLOCKED_COLOR


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


func update_hover() -> void:
	var hovered_cell := world_to_grid(get_global_mouse_position())
	var node := _node_at(hovered_cell)
	if node == _hovered_node and hovered_cell == _hovered_cell:
		return
	if _hovered_node != null:
		_hovered_node.set_hovered(false)
	_hovered_cell = hovered_cell
	_hovered_node = node
	if _hovered_node != null:
		_hovered_node.set_hovered(true)
	_update_pointer_tint()


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
