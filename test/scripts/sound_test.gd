extends SceneTree
## 音效系统自检：autoload 注册、全部素材可加载、SFX 池并发、音乐切换。
## 用法：godot --headless --path . --script res://test/scripts/sound_test.gd

var _failures := 0


func _init() -> void:
	await process_frame   # autoload 在 SceneTree 脚本 _init 之后才挂上 root
	var sm := root.get_node_or_null("SoundManager")
	_check(sm != null, "SoundManager autoload 已注册")
	if sm == null:
		_finish()
		return

	# 全部 SFX + 音乐素材可加载
	for id in sm.SFX:
		_check(sm._get_stream(sm.SFX_DIR, sm.SFX[id]) != null, "SFX 可加载: %s" % id)
	for id in sm.MUSIC:
		_check(sm._get_stream(sm.MUSIC_DIR, sm.MUSIC[id]) != null, "音乐可加载: %s" % id)

	# SFX 池并发：连播 12 个不报错（池 8 个轮播复用）
	for i in 12:
		sm.play_sfx(&"dig", 1.0 + i * 0.01)
	await process_frame
	var playing := 0
	for p in sm._sfx_pool:
		if p.playing:
			playing += 1
	_check(playing == 8, "SFX 池 8 个播放器全部在播（实测 %d）" % playing)

	# 音乐切换：播 main1 → 同曲不打断 → 切 normal_talent
	sm.play_music(&"main1")
	_check(sm._music_player.playing, "main1 播放中")
	_check(sm._music_player.stream is AudioStreamWAV \
		and (sm._music_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"WAV 音乐已开循环")
	var s1: AudioStream = sm._music_player.stream
	sm.play_music(&"main1")
	_check(sm._music_player.stream == s1, "重复切同曲不重载")
	sm.play_music(&"normal_talent")
	_check(sm._music_player.stream != s1, "切换到天赋 BGM")
	sm.stop_music()
	_check(not sm._music_player.playing, "停止音乐")

	# 节流：SFX_MIN_INTERVAL 内的 id 连发只响一声
	for i in 5:
		sm.play_sfx(&"cant_buy")
	await process_frame
	var cant_buy_playing := 0
	for p in sm._sfx_pool:
		if p.playing and p.stream == sm._get_stream(sm.SFX_DIR, sm.SFX[&"cant_buy"]):
			cant_buy_playing += 1
	_check(cant_buy_playing == 1, "cant_buy 连发 5 次只播 1 声（实测 %d）" % cant_buy_playing)

	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[通过] ", message)
	else:
		_failures += 1
		print("[失败] ", message)


func _finish() -> void:
	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(1 if _failures > 0 else 0)
