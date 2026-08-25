shader_type canvas_item;
render_mode blend_mix;

uniform vec4 water_color: source_color = vec4(1.0, 0.78, 0.05, 1.0);  // 金黄色水（更饱和）
uniform vec4 glass_color: source_color = vec4(0.85, 0.92, 1.0, 0.22);  // 水面上方玻璃：淡蓝、半透明
uniform vec4 ball_color: source_color = vec4(0.95, 0.95, 0.98, 0.9);  // 球缸边界：弱白色
uniform vec4 outline_color: source_color = vec4(0.6, 0.7, 0.85, 1.0); // 外缘轮廓：灰蓝，不抢戏
uniform float height: hint_range(0.0, 1.0, 0.01) = 0.5;               // 当前水位
uniform float wave_speed: hint_range(-10.0, 10.0, 0.1) = 1.5;         // 水面波纹速度
uniform float wave_ci: hint_range(0.0, 0.2, 0.001) = 0.025;           // 水面波纹幅度
uniform float ball_border_ci: hint_range(0.0, 50.0, 1.0) = 8.0;       // 球缸边界浓度
uniform float outline_width: hint_range(0.0, 0.15, 0.001) = 0.025;    // 外缘轮廓宽度
uniform float bottom_residue: hint_range(0.0, 0.2, 0.001) = 0.05;     // 空球底部残留水痕
uniform bool light_effect = false;                                    // 获得升华点时的闪光

void fragment() {
	vec2 uv = UV;
	vec2 suv = (uv - 0.5) * 2.0;
	float dist = length(suv);

	if (dist > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// 有效水位：至少保留底部 residue
		float effective_height = max(height, bottom_residue * (1.0 - dist));

		// 水面正弦波纹
		float wave = sin((suv.x + TIME * wave_speed) * 8.0) * wave_ci * (1.0 - dist * 0.5);
		float surface_y = 1.0 - effective_height + wave;

		vec4 col;
		if (uv.y > surface_y) {
			// 水面下方：金黄色水，保持饱和度
			float depth = (uv.y - surface_y) / max(1.0 - surface_y, 0.001);
			vec3 deep_water = water_color.rgb * 0.75;
			vec3 water = mix(deep_water, water_color.rgb, 0.6 + depth * 0.4);
			col = vec4(water, water_color.a);
		} else {
			// 水面上方：淡蓝玻璃，低透明度
			col = glass_color;
		}

		// 水面高光线：细白边，不压过黄色
		float surface_dist = abs(uv.y - surface_y);
		float surface_glow = smoothstep(0.04, 0.0, surface_dist) * 0.55;
		col.rgb = mix(col.rgb, vec3(1.0), surface_glow);
		col.a = max(col.a, surface_glow * 0.7);

		// 球缸边界（内圈暗边，让球有体积感）
		float border = pow(dist, ball_border_ci) * 0.5;
		col = mix(col, ball_color, border);

		// 球体外缘轮廓：只在边缘淡淡一圈
		float edge = smoothstep(1.0 - outline_width, 1.0, dist);
		col = mix(col, outline_color, edge);

		// 获得升华点时的闪烁警报
		if (light_effect) {
			float blink = sin(TIME * 12.0) * 0.5 + 0.5;
			col.rgb += vec3(0.35) * blink;
		}

		COLOR = col;
	}
}
