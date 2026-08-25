shader_type canvas_item;

// 受击闪色（@triangledevv 的 hit flash，canvas_item 版）：
// active 时把像素替换为 tint（alpha 沿用原贴图），modulate 照常生效。
// 与原版唯一区别：补了 else 分支——active=false 时正常渲染贴图，
// 否则材质常驻时非闪白帧会渲染成纯白色块（COLOR 默认值）。
// 注意材质必须每个实例一份（active 参数各自独立），不能共享。
uniform bool active = false;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 previous_color = texture(TEXTURE, UV);
	if (active == true) {
		vec4 tint_copy = tint;
		tint_copy.a = previous_color.a;
		COLOR = tint_copy;
	} else {
		COLOR = previous_color;
	}
}
