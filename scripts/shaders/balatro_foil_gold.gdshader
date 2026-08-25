shader_type canvas_item;

// ===== 鼠标驱动参数 =====
uniform vec2 mouse_position;
uniform vec2 sprite_position;

// ===== 3D 透视参数 =====
uniform float fov : hint_range(1, 179) = 90;
uniform bool cull_back = true;
uniform float inset : hint_range(0, 1) = 0.0;
uniform float max_tilt : hint_range(0, 2.0) = 1.0;
uniform float max_distance = 500.0;

// ===== Foil 参数 =====
uniform vec3 foilcolor : source_color = vec3(1.0, 1.0, 1.0);
uniform float threshold : hint_range(0.0, 2.0, 0.1) = 1.0;
uniform float fuzziness : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float period = 1.0;
uniform float scroll = 1.0;
uniform float normal_strength = 0.1;
uniform float effect_alpha_mult : hint_range(0, 1) = 0.65;
uniform float direction : hint_range(0, 1.0) = 0.5;

varying flat vec2 o;
varying vec3 p;
varying smooth vec2 direction_to;

float color_mask(vec3 mask, vec3 color, float mask_threshold, float mask_fuzziness) {
    float d = distance(mask, color);
    return clamp(1.0 - smoothstep(mask_threshold, mask_threshold + mask_fuzziness, d), 0.0, 1.0);
}

vec3 rotate_vector(vec3 v, float angleX, float angleY, float magnitude) {
    mat3 rotX = mat3(
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, cos(angleX), -sin(angleX)),
        vec3(0.0, sin(angleX), cos(angleX))
    );
    mat3 rotY = mat3(
        vec3(cos(angleY), 0.0, sin(angleY)),
        vec3(0.0, 1.0, 0.0),
        vec3(-sin(angleY), 0.0, cos(angleY))
    );
    mat3 combinedRotation = rotX * rotY;
    vec3 rotatedVector = combinedRotation * v;
    return normalize(rotatedVector) * magnitude;
}

float hash(vec2 coord) {
    return fract(sin(dot(coord, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 coord) {
    vec2 i = floor(coord);
    vec2 f = fract(coord);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 gradient_gold(float x) {
    float t = fract(x);
    return mix(vec3(1.0, 0.72, 0.05), vec3(1.0, 0.95, 0.55), t);
}

void vertex() {
    direction_to = mouse_position - sprite_position;
    float d = length(direction_to);
    float magnitude = min(max_tilt, d / max_distance);
    float angle = atan(direction_to.x, direction_to.y);
    float x_rota = abs(angle) / PI;
    float y_rota = abs(atan(direction_to.y, direction_to.x)) / PI;

    float sin_b = sin((-y_rota + 0.5) * magnitude * (PI / 2.0));
    float cos_b = cos((-y_rota + 0.5) * magnitude * (PI / 2.0));
    float sin_c = sin((x_rota - 0.5) * magnitude * (PI / 2.0));
    float cos_c = cos((x_rota - 0.5) * magnitude * (PI / 2.0));

    mat3 inv_rot_mat;
    inv_rot_mat[0][0] = cos_b;
    inv_rot_mat[0][1] = 0.0;
    inv_rot_mat[0][2] = -sin_b;
    inv_rot_mat[1][0] = sin_b * sin_c;
    inv_rot_mat[1][1] = cos_c;
    inv_rot_mat[1][2] = cos_b * sin_c;
    inv_rot_mat[2][0] = sin_b * cos_c;
    inv_rot_mat[2][1] = -sin_c;
    inv_rot_mat[2][2] = cos_b * cos_c;

    float t = tan(fov / 360.0 * PI);
    p = inv_rot_mat * vec3((UV - 0.5), 0.5 / t);
    float v = (0.5 / t) + 0.5;
    p.xy *= v * inv_rot_mat[2].z;
    o = v * inv_rot_mat[2].xy;

    VERTEX += (UV - 0.5) / TEXTURE_PIXEL_SIZE * t * (1.0 - inset);
}

void fragment() {
    if (cull_back && p.z <= 0.0) discard;

    vec2 uv = (p.xy / p.z).xy - o;
    vec2 adjusted_uv = uv + 0.5;
    vec4 albedo_tex = texture(TEXTURE, adjusted_uv);
    COLOR = albedo_tex;

    float mask = 1.0;
    float texture_similarity = color_mask(foilcolor, albedo_tex.rgb, threshold, fuzziness);

    float d = length(direction_to);
    float magnitude = min(max_tilt, d / max_distance);
    float angle = atan(direction_to.x, direction_to.y);
    float x_rota = abs(angle) / PI;
    float y_rota = abs(atan(direction_to.y, direction_to.x)) / PI;

    vec3 normal = vec3(x_rota, y_rota, magnitude) * normal_strength;
    normal.xy += (noise(adjusted_uv * 30.0) * 2.0 - 1.0) * normal_strength;

    float noise_tex = noise(adjusted_uv * 20.0 + vec2(TIME * 0.05));

    vec2 gradient_sample = vec2(
        0.25 + (normal.y * direction * 2.0 - normal.x * (1.0 - direction) * 2.0) / 2.0
            + (adjusted_uv.y * direction + adjusted_uv.x * (1.0 - direction)) / 2.0,
        0.0
    );
    gradient_sample += vec2(magnitude, 0.0) * scroll;
    gradient_sample = mod((gradient_sample + adjusted_uv * period), 1.0);
    vec3 gradient_tex = gradient_gold(gradient_sample.x);
    float strength = effect_alpha_mult * mask * texture_similarity;

    COLOR.rgb = mix(albedo_tex.rgb, gradient_tex * (vec3(noise_tex) * 2.0), strength);
    COLOR.a *= step(max(abs(uv.x), abs(uv.y)), 0.5);
}
