shader_type spatial;
// Front Range backdrop: layered ridge silhouettes, backlit by the afternoon sun, with their own
// aerial haze (scene fog is off here so the far peaks stay visible) and snow on the high tops.
// COLOR: r = height fraction up the strip, g = layer haze, b = sunlit, a = snow allowed.
// UV = (compass bearing, elevation angle), both in degrees, so the rock texture is isotropic.
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 haze_color : source_color = vec3(0.7, 0.78, 0.88);
uniform vec3 forest : source_color = vec3(0.24, 0.3, 0.3);
uniform vec3 rock : source_color = vec3(0.4, 0.42, 0.46);
uniform vec3 snow : source_color = vec3(0.9, 0.92, 0.97);
uniform float snowline = 2.75;

varying vec4 vcol;

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

float fbm(vec2 p) {
	return 0.5 * vnoise(p) + 0.28 * vnoise(p * 2.1 + 3.1) + 0.14 * vnoise(p * 4.3 + 7.7) + 0.08 * vnoise(p * 8.9 + 1.3);
}

void vertex() {
	vcol = COLOR;
}

void fragment() {
	float hf = vcol.r;
	float haze = vcol.g;
	float lit = vcol.b;
	vec2 q = UV * vec2(9.0, 9.0) + haze * 31.0;
	float n = fbm(q);
	// Gullies run down the slopes: noise stretched vertically, but only gently.
	float gully = vnoise(vec2(UV.x * 22.0, UV.y * 7.0) + haze * 13.0);
	float tree = 1.0 - smoothstep(0.35, 0.75, hf + 0.25 * (n - 0.5));
	vec3 col = mix(rock, forest, tree);
	col *= 0.78 + 0.34 * n + 0.1 * (gully - 0.5);
	col *= 0.8 + 0.4 * lit;
	float sn = smoothstep(snowline - 0.05, snowline + 0.05, UV.y + 0.35 * (n - 0.5) + 0.15 * (gully - 0.5));
	sn *= step(0.5, vcol.a);
	col = mix(col, snow * (0.82 + 0.18 * n) * (0.85 + 0.2 * lit), sn * 0.92);
	float h = clamp(haze + (1.0 - hf) * 0.25, 0.0, 0.95);
	ALBEDO = mix(col, haze_color, h);
}
