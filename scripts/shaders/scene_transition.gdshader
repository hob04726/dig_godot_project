shader_type canvas_item;

// 场景切换转场：用灰度 mask 的亮度把 display_texture 盖在画面上。
// 扫 luminance_cutoff：0 → display 铺满（盖住旧场景）；1 → 全透明（露出新场景）。
// mask_texture 用径向渐变（中心亮、边缘暗）→ cutoff 扫动时呈"虹膜开合"式转场。

uniform float luminance_cutoff: hint_range(0.0, 1.0) = 0.0;
uniform bool invert = false;
uniform sampler2D mask_texture;
uniform sampler2D display_texture;

void fragment() {
	vec4 sample_color = texture(mask_texture, UV);
	float luminance = dot(sample_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	bool filter = luminance > luminance_cutoff;
	if (invert) {
		filter = !filter;
	}

	if (filter) {
		COLOR = texture(display_texture, UV);
	} else {
		COLOR = vec4(1.0, 1.0, 1.0, 0.0) * texture(display_texture, UV);
	}
}
