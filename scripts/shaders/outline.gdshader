shader_type canvas_item;
render_mode unshaded;

// 外描边 shader（社区经典版微调默认值）。
// 注意：thickness 单位是"贴图像素"——矿石/地块贴图是 256×352、显示缩放约 0.13，
// 1 贴图像素 ≈ 0.13 屏幕像素，所以调用方一般会把 thickness 调到 8 左右（≈1 屏幕像素）。
// 默认：thickness=1 / ring_count=4 / 不用 square_border（圆形采样）。

uniform float thickness : hint_range(0.0, 100.0) = 1.0;
uniform int ring_count : hint_range(1,128) = 4;
uniform float ring_offset : hint_range(0.0, 1.0, 0.01);
uniform vec4 outline_color : source_color = vec4(1.0);
uniform bool border_clipping_fix = true;
uniform float aspect_ratio : hint_range(0.1, 10.0, 0.01) = 1.0;
uniform bool square_border = false;
uniform vec2 offset;
uniform bool max_or_add = false;
uniform bool only_outline = false;

void vertex(){
	if (border_clipping_fix){
		vec2 o = (UV * 2.0 - 1.0);
		VERTEX += o * thickness - offset;
		VERTEX.x *= 1.0 + (aspect_ratio-1.0) * (thickness * TEXTURE_PIXEL_SIZE.x) * 2.0;
	}
}

vec2 square(float i){ // samples a square pattern
	i *= 2.0;
	return (vec2(
		clamp(abs(mod(i,2.0)-1.0),0.25,0.75),
		clamp(abs(mod(i+0.5,2.0)-1.0),0.25,0.75)
		)-0.5)*4.0;
}

vec4 tex(sampler2D sampler, vec2 uv){
	vec4 clr;
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0){ // bleeding texture sampling fix
		clr = texture(sampler, uv);
	}else{clr = vec4(0.0);}
	return clr;
}

void fragment(){
	vec2 o = offset / vec2(textureSize(TEXTURE, 0));
	vec2 uv = UV;
	uv -= vec2(0.5);
	if (border_clipping_fix){
		uv.x *= 1.0 + (aspect_ratio-1.0) * thickness * TEXTURE_PIXEL_SIZE.x * 2.0;
		uv *= (1.0 + (thickness * TEXTURE_PIXEL_SIZE * 2.0));
		uv -= o;
		}
	uv += vec2(0.5);
	vec2 size = vec2(thickness) / vec2(textureSize(TEXTURE, 0));

	vec4 sprite_color = tex(TEXTURE, uv);

	float ring_alpha = 0.0;
	if (square_border){
		for(int i=0;i<ring_count;++i){
			float r = float(i) / float(ring_count) + ring_offset;
			ring_alpha = max(ring_alpha, texture(TEXTURE, uv + o + size * square(r) * vec2(aspect_ratio,1.0)).a * outline_color.a);}// texture sampling fix is disabled because both with and without give the same result
	}else{
		for(int i=0;i<ring_count;++i){
			float r = float(i) * 3.14159 / float(ring_count) * 2.0 + ring_offset;
			if (max_or_add){
				ring_alpha = ring_alpha + tex(TEXTURE, uv + o +  vec2(size.x * sin(r) * aspect_ratio, size.y * cos(r))).a * outline_color.a;
			}else{
				ring_alpha = max(ring_alpha, tex(TEXTURE, uv + o +  vec2(size.x * sin(r) * aspect_ratio, size.y * cos(r))).a * outline_color.a);
			}
		}
	}
	ring_alpha = clamp(ring_alpha, 0.0, 1.0);
	float alpha = max(sprite_color.a, ring_alpha);

	if (only_outline) {
		// 只画描边环，中心透明，避免盖住下方带 shader 的图标
		alpha = max(0.0, ring_alpha - sprite_color.a);
		COLOR = vec4(outline_color.rgb, alpha);
	} else {
		vec3 final_color = mix(outline_color.rgb, sprite_color.rgb, sprite_color.a);
		COLOR = vec4(final_color, clamp(alpha, 0.0, 1.0));
	}
}
