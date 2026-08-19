shader_type canvas_item;
render_mode blend_mix;

uniform vec4 water_color: source_color = vec4(1.0, 0.85, 0.1, 1.0);  // 黄色金币水
uniform vec4 ball_color: source_color = vec4(vec3(1.0), 1.0);         // 球缸边界色
uniform float height: hint_range(0.0, 1.0, 0.01) = 0.5;               // 当前水位
uniform float wave_speed: hint_range(-10.0, 10.0, 0.1) = 1.5;         // 水面波纹速度
uniform float wave_ci: hint_range(0.0, 0.2, 0.001) = 0.025;           // 水面波纹幅度
uniform float ball_border_ci: hint_range(0.0, 50.0, 1.0) = 5.0;       // 球缸边界浓度
uniform bool light_effect = false;                                    // 获得升华点时的闪光

void fragment() {
	vec2 uv = UV;
	vec2 suv = (uv - 0.5) * 2.0;
	float dist = length(suv);

	if (dist > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// 水面正弦波纹，越靠近中心越明显
		float wave = sin((suv.x + TIME * wave_speed) * 8.0) * wave_ci * (1.0 - dist * 0.5);
		float surface_y = 1.0 - height + wave;

		vec4 col = vec4(0.0);
		if (uv.y > surface_y) {
			// 水面下方：黄色水
			col = water_color;
		} else {
			// 水面上方：透明（露出球缸玻璃）
			col = vec4(0.0);
		}

		// 球缸边界
		float border = pow(dist, ball_border_ci);
		col = mix(col, ball_color, border);

		// 获得升华点时的闪烁警报
		if (light_effect) {
			float blink = sin(TIME * 12.0) * 0.5 + 0.5;
			col.rgb += vec3(0.35) * blink;
		}

		COLOR = col;
	}
}
