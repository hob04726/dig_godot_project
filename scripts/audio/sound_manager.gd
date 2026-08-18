extends Node
## 全局音效/音乐管理（autoload: SoundManager）。
## SFX：AudioStreamPlayer 池轮播（支持并发，挖矿连点不互掐）；
## 音乐：单播放器循环，切场景换曲（重复切同一首不打断）。
## 用法：SoundManager.play_sfx(&"dig") / SoundManager.play_music(&"main1")

const SFX_DIR := "res://assets/sound/Sound Effect/"
const MUSIC_DIR := "res://assets/sound/Music/"

## SFX 表（id → 路径）。音高随机化由调用方传 pitch。
const SFX := {
	&"dig": "dig.wav",                            # 挖矿每一镐
	&"broke_a_ore": "broke_a_ore.wav",            # 矿石被破坏
	&"cant_buy": "cant_buy.wav",                  # 买不起（天赋/放置）
	&"choose_to_reset": "choose_to_reset.ogg",    # 点「重置·升华」
	&"coin_particle": "coin_particle.ogg",        # 金币粒子爆发
	&"count_number_up": "count_number_up.wav",    # 金币数字跳数
	&"talent_click": "talent_click.ogg",          # 金币天赋购买
	&"sublimation_talent_click": "sublimation_talent_click.ogg",   # 升华点天赋购买
	&"below_button_select": "below_button_select.wav",           # 抽屉地块按钮选中
	&"menu_selection_click": "menu_selection_click.wav",         # 通用 UI 点击
	&"place_block": "place_block.wav",                # 地块放置成功
	&"remove_block": "remove_block.wav",              # 地块移除成功
}

## 音乐表（id → 路径）。main2 备用；sublimation_talent 等升华界面落地后启用。
const MUSIC := {
	&"main1": "main1.wav",
	&"main2": "main2.wav",
	&"normal_talent": "normal_talent.wav",
	&"sublimation_talent": "sublimation_talent.wav",
}

const SFX_POOL_SIZE := 8        # 并发上限（连点挖矿每镐一声）
const SFX_VOLUME_DB := 0.0
const MUSIC_VOLUME_DB := -10.0  # BGM 垫底，别盖过音效

## 单个音效的音量补偿（dB）：素材本身响度不均衡，在此统一校平。
## broke_a_ore 素材峰值偏高 → 降；below_button_select 素材接近静音 → 大幅补。
const SFX_VOLUME_OFFSET := {
	&"broke_a_ore": -8.0,
	&"below_button_select": 20.0,
	&"place_block": 10.0,    # 素材 RMS 比 dig 低约 10dB，拉平
	&"remove_block": 8.0,
}

## 同一音效的最小重播间隔（秒）：防止长按批量放置等连发场景下刷屏
## （金币不足时拖过一串可放格子，每格都会失败一次；
##   放置/移除在快速拖动时每格一声，给一个极小间隔防止叠成噪音）
const SFX_MIN_INTERVAL := {
	&"cant_buy": 0.35,
	&"place_block": 0.05,
	&"remove_block": 0.05,
}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music_player: AudioStreamPlayer = null
var _current_music := &""
var _stream_cache: Dictionary = {}   # 路径 → AudioStream（懒加载）
var _last_play_msec: Dictionary = {} # 音效 id → 上次播放时刻（配合 SFX_MIN_INTERVAL 节流）

## 设置文件路径（音量/全屏持久化，settings 界面写、此处启动时读）
const SETTINGS_CFG := "user://settings.cfg"


func _ready() -> void:
	_ensure_players()
	_apply_saved_settings()


## 惰性构建播放器：--script 测试模式下 autoload 挂树晚于场景 _ready，
## play_* 可能比本节点 _ready 先被调用，所以首次使用时兜底构建
func _ensure_players() -> void:
	if _music_player != null:
		return
	_ensure_buses()
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)


## 运行时建 Music/SFX 两条总线（挂在 Master 下），设置界面按总线调音量；
## 不建 default_bus_layout.tres 资源文件，避免编辑器/运行时两套来源
func _ensure_buses() -> void:
	for bus_name in [&"Music", &"SFX"]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")


# ==================== 音量（设置界面用，0.0~1.0 线性） ====================

## 设置总线音量（线性）。bus_name 传 &"" 表示 Master。
func set_bus_linear(bus_name: StringName, v: float) -> void:
	_ensure_buses()
	var idx := 0 if bus_name == &"" else AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, -80.0 if v <= 0.0 else linear_to_db(clampf(v, 0.0, 1.0)))


## 读总线音量（线性）。bus_name 传 &"" 表示 Master。
func get_bus_linear(bus_name: StringName) -> float:
	_ensure_buses()
	var idx := 0 if bus_name == &"" else AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


## 启动时应用已保存的设置（音量 + 全屏），由 settings 界面负责写入
func _apply_saved_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_CFG) != OK:
		return
	set_bus_linear(&"", float(cfg.get_value("audio", "master", 1.0)))
	set_bus_linear(&"Music", float(cfg.get_value("audio", "music", 1.0)))
	set_bus_linear(&"SFX", float(cfg.get_value("audio", "sfx", 1.0)))
	if bool(cfg.get_value("display", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## 播放音效。pitch 默认 1.0；连发型音效（dig）调用方传 0.95~1.1 随机防机枪感。
## SFX_MIN_INTERVAL 表里的 id 会被节流：距上次播放不足间隔时直接丢弃。
func play_sfx(id: StringName, pitch := 1.0) -> void:
	var min_msec := int(SFX_MIN_INTERVAL.get(id, 0.0) * 1000.0)
	if min_msec > 0:
		var now := Time.get_ticks_msec()
		if now - int(_last_play_msec.get(id, -1000000000)) < min_msec:
			return
		_last_play_msec[id] = now
	var stream := _get_stream(SFX_DIR, SFX.get(id, ""))
	if stream == null:
		return
	_ensure_players()
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL_SIZE
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = SFX_VOLUME_DB + SFX_VOLUME_OFFSET.get(id, 0.0)
	p.play()


## 播放/切换循环音乐（同一首重复调用不打断）
func play_music(id: StringName) -> void:
	if id == _current_music:
		return
	_current_music = id
	var stream := _get_stream(MUSIC_DIR, MUSIC.get(id, ""))
	if stream == null:
		return
	_ensure_players()
	_enable_loop(stream)
	_music_player.stream = stream
	_music_player.volume_db = MUSIC_VOLUME_DB
	_music_player.play()


func stop_music() -> void:
	_current_music = &""
	if _music_player != null:
		_music_player.stop()


func _get_stream(dir: String, filename: String) -> AudioStream:
	if filename.is_empty():
		return null
	var path := dir + filename
	if not _stream_cache.has(path):
		if not ResourceLoader.exists(path):
			push_warning("SoundManager: 音频不存在 %s" % path)
			return null
		_stream_cache[path] = load(path)
	return _stream_cache[path]


## 让音乐循环：WAV 和 OGG 的循环参数不同（资源是共享的，设置一次即可）
func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
