shader_type canvas_item;

uniform float time : hint_range(0.0, 100.0) = 0.0;
// 0 = 无效果，1 = 满效果；由代码根据剩余引信时间推送，越接近爆炸越强
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 60.0) = 14.0;
uniform float pulse_min : hint_range(0.0, 2.0) = 0.78;
uniform float pulse_max : hint_range(0.0, 2.0) = 1.38;
uniform float blink_speed : hint_range(0.0, 60.0) = 18.0;
uniform vec4 tint : source_color = vec4(1.0, 0.1, 0.05, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 亮度随时间快速闪烁（sin 波）
	float blink = sin(time * blink_speed) * 0.5 + 0.5;
	// 颜色闪烁强度随 intensity 增加，满强度时几乎变成红橙色
	vec3 color = mix(tex.rgb, tint.rgb, (0.2 + 0.65 * intensity) * blink);
	COLOR = vec4(color, tex.a);
}

void vertex() {
	// 让 sprite 围绕中心脉冲缩放；缩放的振幅也随 intensity 增加
	float wave = sin(time * pulse_speed) * 0.5 + 0.5;
	float s = mix(1.0, pulse_min + (pulse_max - pulse_min) * wave, intensity);
	VERTEX *= s;
}
