shader_type spatial;
// A flag hoisted along its local -Y edge at z = 0, flying toward +Z. UV.x runs hoist to fly.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind = 5.0;
uniform float phase = 0.0;
uniform float fly_len = 0.6;

void vertex() {
	float u = UV.x;
	float k = 7.0;
	float w = TIME * (5.0 + wind * 0.7) + phase;
	float amp = (0.035 + 0.006 * wind) * fly_len * 2.0;
	float s = sin(u * k - w + UV.y * 1.5);
	float c = cos(u * k - w + UV.y * 1.5);
	VERTEX.x += amp * u * s;
	VERTEX.z -= amp * 0.3 * u * (1.0 - c);
	float dxdz = amp * (s + u * k * c) / fly_len;
	NORMAL = normalize(vec3(1.0, 0.0, -dxdz));
}

void fragment() {
	vec4 t = texture(tex, UV);
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = t.rgb * 0.35;
}
