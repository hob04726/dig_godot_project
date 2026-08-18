extends SceneTree

## 逐行移植 balatro_original_fire.gdshader 的 fragment 数学，
## 在面板 UV 网格上采样，统计透明/不透明(有火)像素分布，排查"整体透明看不到火"。

func _init() -> void:
	# 参数与 main.tscn / _ready 一致
	var image_details := Vector2(86, 40)
	var texture_details := Vector4(0, 0, 86, 40)
	for TIME in [0.0, 1.0, 3.0, 5.0]:
		var stats := _sample(6.0, TIME, image_details, texture_details)
		print("TIME=%.1f  amount=6  transparent=%d  flame=%d  flame_top_only=%d" % [TIME, stats[0], stats[1], stats[2]])
	# 低强度也看一眼
	var stats_low := _sample(1.0, 2.0, image_details, texture_details)
	print("TIME=2.0  amount=1  transparent=%d  flame=%d" % [stats_low[0], stats_low[1]])
	quit()


func _sample(amount: float, TIME: float, image_details: Vector2, texture_details: Vector4) -> Array:
	var W := 86   # 面板 86x40，逐像素采样
	var H := 40
	var transparent := 0
	var flame := 0
	var flame_top := 0   # 上半部分（y>0，火舌应到的地方）有火的像素
	var intensity := minf(10.0, amount)
	var PIXEL_SIZE_FAC := 60.0
	for tx in range(W):
		for ty in range(H):
			var UV := Vector2((float(tx) + 0.5) / W, (float(ty) + 0.5) / H)
			var uv := ((UV * image_details) - Vector2(texture_details.x, texture_details.y) * Vector2(texture_details.z, texture_details.w)) / Vector2(texture_details.z, texture_details.w) - Vector2(0.5, 0.5)

			var floored_uv := Vector2(floorf(uv.x * PIXEL_SIZE_FAC) / PIXEL_SIZE_FAC, floorf(uv.y * PIXEL_SIZE_FAC) / PIXEL_SIZE_FAC)
			var uv_scaled_centered := floored_uv
			uv_scaled_centered += uv_scaled_centered * 0.01 * (
				sin(-1.123 * floored_uv.x + 0.2 * TIME) *
				cos(5.3332 * floored_uv.y + TIME * 0.931)
			)

			var flame_up_vec := Vector2(0.0, fmod(4.0 * TIME, 10000.0) - 5000.0 + fmod(1.781 * 0.0, 1000.0))
			var scale_fac := 7.5 + 3.0 / (2.0 + 2.0 * intensity)
			var sv := uv_scaled_centered * scale_fac + flame_up_vec
			var speed := fmod(20.781 * 0.0, 100.0) + 1.0 * sin(TIME) * cos(TIME * 0.151)
			var sv2 := Vector2(0.0, 0.0)

			for i in range(5):
				var iteration_mod := -1.0 if (fmod(float(i), 2.0) > 1.0) else 1.0
				# GLSL 里 vec2 + float 会把标量广播到两个分量，GDScript 需显式包成 Vector2
				sv2 += sv + 0.05 * Vector2(sv2.y, sv2.x) * iteration_mod + Vector2.ONE * 0.3 * (
					cos(sv.length() * 0.411) +
					0.3344 * sin(sv.length()) -
					0.23 * cos(sv.length())
				)
				sv += 0.5 * Vector2(
					cos(cos(sv2.y) + speed * 0.0812) * sin(3.22 + sv2.x - speed * 0.1531),
					sin(-sv2.x * 1.21222 + 0.113785 * speed) * cos(sv2.y * 0.91213 - 0.13582 * speed)
				)

			var smoke_res := maxf(0.0, (
				((sv - flame_up_vec) / scale_fac * 5.0).length() + 0.1 * (uv_scaled_centered.length() - 0.5)) *
				(2.0 / (2.0 + intensity * 0.2))
			)
			smoke_res += maxf(0.0, 2.0 - 0.3 * intensity) * maxf(0.0, 2.0 * (uv_scaled_centered.y - 0.5) * (uv_scaled_centered.y - 0.5))

			if absf(uv.x) > 0.4:
				smoke_res += 10.0 * (absf(uv.x) - 0.4)

			var hole_vec := Vector2(uv.x, uv.y - 0.1) * Vector2(0.19, 1.0)
			var hole_len := hole_vec.length()
			if hole_len < minf(0.1, intensity * 0.5) and smoke_res > 1.0:
				smoke_res += minf(8.5, intensity * 10.0) * (hole_len - 0.1)

			if smoke_res > 1.0:
				transparent += 1
			else:
				flame += 1
				if uv.y > 0.0:
					flame_top += 1
	return [transparent, flame, flame_top]
