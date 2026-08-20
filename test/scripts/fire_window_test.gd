extends SceneTree

## 屏幕底边火焰「独立的 10 秒滚动窗口收入分档」测试（_record_income + EDGE）。
## _record_income 仍支持任意已注册边，本测试以底边为主、顶边为辅验证窗口独立性。
## 档位：>1e3 红 / >1e6 蓝 / >1e13 紫 / >1e20 黑 / >1e28 呼吸变色；amount = 5 + 档。

var _failures := 0


func _initialize() -> void:
	_run()
	print("=== 结果：失败 %d 处 ===" % _failures)
	quit(_failures)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("[通过] %s" % name)
	else:
		_failures += 1
		print("[失败] %s %s" % [name, detail])


func _make_edge(gm: GameManager, edge: StringName) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/balatro_original_fire.gdshader")
	gm._edge_fires[edge] = {"rect": ColorRect.new(), "mat": mat}
	gm._income_logs[edge] = []
	gm._fire_tiers[edge] = 0
	return mat


func _run() -> void:
	var gm := GameManager.new()   # 不入树：_trigger_fire 只写参数，不播淡出
	var mat_bottom := _make_edge(gm, &"bottom")
	var mat_top := _make_edge(gm, &"top")

	# 低于最低档（1000）不冒火
	gm._record_income(BigNumber.from_int(500), &"bottom")
	_check("底边 500 不冒火", int(gm._fire_tiers[&"bottom"]) == 0
		and mat_bottom.get_shader_parameter("amount") == null)

	# 底边累计超过 1e3 → 1 档红火，amount = 6
	gm._record_income(BigNumber.from_int(600), &"bottom")   # 底边窗口合计 1100
	_check("底边 1100 → 红火 1 档", int(gm._fire_tiers[&"bottom"]) == 1
		and float(mat_bottom.get_shader_parameter("amount")) == 6.0
		and (mat_bottom.get_shader_parameter("colour_2") as Color).r > 0.9)

	# 顶边独立：500 不够档，且底边状态不受影响
	gm._record_income(BigNumber.from_int(500), &"top")
	_check("顶边 500 不冒火（独立窗口）", int(gm._fire_tiers[&"top"]) == 0
		and mat_top.get_shader_parameter("amount") == null)
	_check("底边仍是 1 档", int(gm._fire_tiers[&"bottom"]) == 1)

	# 顶边推到 1e6 → 2 档蓝火，amount = 7；底边不变
	gm._record_income(BigNumber.from_float(2e6), &"top")
	_check("顶边 >1e6 → 蓝火 2 档", int(gm._fire_tiers[&"top"]) == 2
		and float(mat_top.get_shader_parameter("amount")) == 7.0
		and (mat_top.get_shader_parameter("colour_2") as Color).b > 0.9)
	_check("底边仍是红火 1 档", int(gm._fire_tiers[&"bottom"]) == 1
		and float(mat_bottom.get_shader_parameter("amount")) == 6.0)

	# 底边一路推到呼吸火
	gm._record_income(BigNumber.from_float(2e13), &"bottom")
	_check("底边 >1e13 → 紫火 3 档", int(gm._fire_tiers[&"bottom"]) == 3
		and float(mat_bottom.get_shader_parameter("amount")) == 8.0)
	gm._record_income(BigNumber.from_float(2e20), &"bottom")
	_check("底边 >1e20 → 黑火 4 档", int(gm._fire_tiers[&"bottom"]) == 4
		and float(mat_bottom.get_shader_parameter("amount")) == 9.0
		and (mat_bottom.get_shader_parameter("colour_2") as Color).r < 0.1)
	gm._record_income(BigNumber.from_float(2e28), &"bottom")
	_check("底边 >1e28 → 呼吸火 5 档", int(gm._fire_tiers[&"bottom"]) == 5
		and float(mat_bottom.get_shader_parameter("amount")) == 10.0)

	# 呼吸火：只有 5 档的边被 HSV 循环覆写，2 档的顶边保持蓝色
	gm._update_fire_breath()
	_check("呼吸火颜色被覆写", (mat_bottom.get_shader_parameter("colour_1") as Color).s > 0.5)
	_check("顶边蓝火不被呼吸覆写", (mat_top.get_shader_parameter("colour_2") as Color).b > 0.9)

	# 旧记录超窗清除
	gm._income_logs[&"bottom"] = [{"t": Time.get_ticks_msec() / 1000.0 - 20.0, "v": BigNumber.from_float(1e30)}]
	gm._record_income(BigNumber.from_int(10), &"bottom")
	_check("旧记录被清出窗口", (gm._income_logs[&"bottom"] as Array).size() == 1)

	# 零收入不入账；未知边安全忽略
	var before := (gm._income_logs[&"bottom"] as Array).size()
	gm._record_income(BigNumber.zero(), &"bottom")
	_check("零收入不入账", (gm._income_logs[&"bottom"] as Array).size() == before)
	gm._record_income(BigNumber.from_int(99999), &"left")   # left 未注册
	_check("未注册的边安全忽略", true)

	gm.free()
