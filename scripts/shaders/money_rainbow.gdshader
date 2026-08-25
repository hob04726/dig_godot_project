shader_type canvas_item;

uniform float time = 0.0;
uniform float wave_speed = 4.0;
uniform float wave_amp = 2.5;
uniform float rainbow_speed = 0.35;
uniform float mix_strength = 0.65;

void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.08 + time * wave_speed) * wave_amp;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.0) {
		// 基于像素 x 坐标 + 时间产生彩虹色相
		float h = fract(FRAGCOORD.x * 0.003 - time * rainbow_speed);
		vec3 rainbow = vec3(0.5) + 0.5 * cos(6.28318 * (vec3(h) + vec3(0.0, 0.33, 0.67)));
		COLOR = vec4(mix(tex.rgb, rainbow, mix_strength), tex.a);
	} else {
		COLOR = tex;
	}
}
