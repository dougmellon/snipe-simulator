shader_type spatial;
// Foam around and behind a moving dinghy, drawn on a flat quad in the boat's yaw frame: bow wave
// hugging the hull, two diverging quarter-wave lines from the transom and a turbulent stern trail.
// The noise scrolls aft at boat speed so the foam stays put on the water as the boat passes.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform float strength = 0.0;
instance uniform float speed = 0.0;
instance uniform float seed = 0.0;

varying vec2 lp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float hull_hb(float d) {
	if (d < 2.1) {
		return 0.64 * (1.0 - pow(max(2.1 - d, 0.0) / 2.1, 1.6));
	}
	return 0.64 - 0.024 * (d - 2.1) * (d - 2.1);
}

void vertex() {
	// Plane centred 4.5 m aft of the boat origin; the bow is 2.45 m ahead of it.
	lp = vec2(VERTEX.x, VERTEX.z + 4.5 + 2.45);
}

void fragment() {
	float x = lp.x;
	float d = lp.y;
	float ax = abs(x);
	float sd = d + TIME * speed;
	float tr = max(d - 4.6, 0.0);
	float n = vnoise(vec2(x * 3.5, sd * 2.2) + seed) * 0.6 + vnoise(vec2(x * 9.0, sd * 6.0) + seed * 3.0) * 0.4;
	float bow_x = hull_hb(min(d, 4.72)) + 0.04 + 0.05 * speed * 0.1;
	float bow = exp(-pow((ax - bow_x) / 0.09, 2.0)) * smoothstep(0.1, 0.7, d) * (1.0 - smoothstep(4.0, 5.2, d));
	float line_x = 0.55 + tr * 0.12;
	float lines = exp(-pow((ax - line_x) / (0.07 + tr * 0.03), 2.0)) * exp(-tr / 4.5) * smoothstep(4.3, 4.9, d);
	float trail = exp(-pow(x / (0.35 + tr * 0.05), 2.0)) * exp(-tr / 3.5) * smoothstep(4.5, 5.0, d);
	float foam = max(max(bow, lines * 0.85), trail * 0.45) * smoothstep(0.3, 0.8, n + 0.1);
	float edge = smoothstep(3.5, 2.7, ax) * smoothstep(14.0, 10.0, d);
	ALPHA = clamp(foam * strength * edge, 0.0, 1.0) * 0.55;
	ALBEDO = vec3(0.9, 0.92, 0.92);
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
}
