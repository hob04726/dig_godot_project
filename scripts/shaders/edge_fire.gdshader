shader_type canvas_item;
render_mode unshaded;

// 长条火焰：为屏幕底边的火焰条（60px 厚、上千像素宽）设计。
// 不做循环单元——火苗上沿是一条连续的 1D 噪声曲线，随时间上滚，
// 根部在条带局部底部（贴屏幕边），火舌朝屏幕内；像素化块保持像素风。
// amount < 0.1 整条透明；colour_2 根部 → colour_1 火舌尖。

uniform float amount : hint_range(0.0, 10.0) = 0.0;
uniform vec4 colour_1 : source_color = vec4(1.0, 0.72, 0.2, 1.0);   // 火舌主色
uniform vec4 colour_2 : source_color = vec4(1.0, 0.18, 0.06, 1.0);  // 根部颜色
uniform float aspect : hint_range(0.01, 100.0, 0.01) = 1.0;   // 条带宽/高（布局时写入，防横向拉伸）
uniform float id = 0.0;   // 相位偏移（多条带之间错开）

const float PIXEL_SIZE_FAC = 16.0;   // 每 1.0 单位（=条带厚度）的像素块数

// 1D 噪声：不同频率/速度的正弦叠加，长条上连续不断裂
float wave(float x, float t) {
	return sin(x * 3.1 + t * 2.1) * 0.45
		+ sin(x * 7.3 - t * 3.7 + 1.3) * 0.3
		+ sin(x * 13.9 + t * 5.9 + 4.2) * 0.18
		+ sin(x * 27.7 - t * 8.3 + 2.6) * 0.07;
}

// 三角波（尖峰）：叠进火舌轮廓，让上沿出现向上升腾的尖舌头而不是圆波
float tri(float x) {
	return 1.0 - abs(fract(x) - 0.5) * 2.0;
}

float tongues(float x, float t) {
	return tri(x * 1.9 + t * 0.9) * 0.55
		+ tri(x * 4.3 - t * 1.7 + 0.37) * 0.3
		+ tri(x * 9.1 + t * 2.9 + 0.71) * 0.15;
}

void fragment() {
	float intensity = min(10.0, amount);
	if (intensity < 0.1) {
		COLOR = vec4(0.0);
	} else {
		// 方形像素空间：x 沿条带 0..aspect，y 0..1
		vec2 p = vec2(UV.x * aspect, UV.y);
		p = floor(p * PIXEL_SIZE_FAC) / PIXEL_SIZE_FAC;
		float t = TIME + id * 37.0;
		float y = 1.0 - p.y;   // 0 = 根部（贴边侧），1 = 条带内沿

		// 火焰上沿轮廓：基础高度随强度增加；wave 给整体起伏，
		// tongues 给向上尖舌（乘 y 相关相位让舌头随高度错动、上滚分叉）
		float edge = 0.22 + intensity * 0.035;
		edge += wave(p.x, t) * (0.08 + intensity * 0.010);
		float tongue = tongues(p.x * 0.5 + wave(p.x * 0.23, t * 0.6) * 0.4, t * 0.8 - y * 2.2);
		edge += tongue * (0.16 + intensity * 0.02);
		// 生长系数：amount 从 0 点燃气时火焰从贴边一线慢慢长高，
		// 约到 3.3 长满（否则跨过 0.1 的可见阈值时会直接弹出整条火焰）
		edge *= clamp(intensity * 0.3, 0.0, 1.0);

		if (y > edge) {
			COLOR = vec4(0.0);   // 火外透明
		} else {
			float d = y / max(edge, 0.001);   // 0 根部 → 1 火舌尖
			vec4 col = mix(colour_2, colour_1, d);
			col.rgb *= 1.0 + (1.0 - d) * 0.6;   // 根部亮核
			float flicker = wave(p.x * 2.3 + 9.0, t * 2.2 - y * 5.0);
			// 舌尖快速收窄透明，舌形更利落
			col.a = clamp(1.0 - smoothstep(edge - 0.05, edge, y) + flicker * 0.10, 0.0, 1.0);
			COLOR = col;
		}
	}
}
