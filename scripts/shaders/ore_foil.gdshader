shader_type canvas_item;

uniform vec2 mouse_position;
uniform vec2 sprite_position;

uniform vec3 foilcolor : source_color;
uniform float threshold : hint_range(0.0, 2.0, 0.1) = 0.1;
uniform float fuzziness : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float period = 1.0;
uniform float scroll = 1.0;
uniform float normal_strength = 0.1;
uniform float effect_alpha_mult : hint_range(0, 1) = 1.0;
uniform float direction : hint_range(0, 1.0) = 0.5;

uniform sampler2D foil_mask;
uniform sampler2D gradient;
uniform sampler2D noise;
uniform sampler2D normal_map;

float color_mask(vec3 mask, vec3 color, float mask_threshold, float mask_fuzziness) {
	float d = distance(mask, color);
	return clamp(1.0 - smoothstep(mask_threshold, mask_threshold + mask_fuzziness, d), 0.0, 1.0);
}

void fragment() {
	vec4 albedo_tex = texture(TEXTURE, UV);
	vec4 mask = texture(foil_mask, UV);
	float texture_similarity = color_mask(foilcolor, albedo_tex.rgb, threshold, fuzziness);

	// 用鼠标相对位置驱动 shimmer，不做 3D 透视
	vec2 direction_to = mouse_position - sprite_position;
	float d = length(direction_to);
	float magnitude = clamp(d / 500.0, 0.0, 1.0);
	float angle = atan(direction_to.x, direction_to.y);
	float x_rota = abs(angle) / PI;
	float y_rota = abs(atan(direction_to.y, direction_to.x)) / PI;

	vec3 normal_map_tex = texture(normal_map, UV).rgb * 2.0 - 1.0;
	vec3 normal = vec3(x_rota, y_rota, magnitude) * normal_strength;
	normal.xy += normal_map_tex.xy * normal_strength;

	vec4 noise_tex = texture(noise, UV);

	vec2 gradient_sample = vec2(
		0.25 + (normal.y * direction * 2.0 - normal.x * (1.0 - direction) * 2.0) / 2.0
			+ (UV.y * direction + UV.x * (1.0 - direction)) / 2.0,
		0.0
	);
	gradient_sample += vec2(magnitude, 0.0) * scroll;
	gradient_sample = mod((gradient_sample + UV * period), 1.0);
	vec4 gradient_tex = texture(gradient, gradient_sample);
	float strength = effect_alpha_mult * mask.r * texture_similarity;

	COLOR.rgb = mix(albedo_tex.rgb, gradient_tex.rgb * (noise_tex.rgb * 2.0), strength);
	COLOR.a = albedo_tex.a;
}
