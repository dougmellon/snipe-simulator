shader_type spatial;
// A triangular sail posed entirely in the vertex shader from three corners. The mesh is a grid
// whose UV is (u along the chord from luff to leech, v up the luff from foot to head).
// Sails cast shadows but do not receive them: thin two-sided cloth self-shadows into acne.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform vec3 tack = vec3(0.0, 1.17, -0.71);
uniform vec3 head = vec3(0.0, 6.5, -0.71);
uniform vec3 clew = vec3(0.0, 1.17, 2.1);
// Camber depth as a fraction of the chord; the sign picks the side (+ toward +X of a chord running aft).
uniform float belly = 0.1;
uniform float twist = 0.15;
uniform float roach = 0.0;
uniform float foot_attached = 0.0;
uniform float flutter = 0.0;
uniform float phase = 0.0;
uniform float batten_count = 0.0;
uniform vec3 cloth : source_color = vec3(0.95, 0.95, 0.92);
uniform sampler2D decal : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_decal = false;
// Decal boxes in sail metres (x aft along the chord from the luff, y up from the foot): x0, y0, w, h.
uniform vec4 num_stbd = vec4(0.25, 2.9, 1.0, 0.32);
uniform vec4 num_port = vec4(0.25, 2.45, 1.0, 0.32);
uniform vec4 bird_box = vec4(0.3, 3.55, 0.45, 0.45);

varying vec2 sail_m;
varying vec3 n_view;
varying vec2 uv_s;

vec3 sail_point(vec2 uv) {
	float u = uv.x;
	float v = clamp(uv.y, 0.0, 1.0);
	float side = belly >= 0.0 ? 1.0 : -1.0;
	vec3 luff = mix(tack, head, v);
	vec3 d = mix(clew, head, v) - luff;
	float a = twist * v * side;
	float ca = cos(a);
	float sa = sin(a);
	d = vec3(d.x * ca + d.z * sa, d.y, -d.x * sa + d.z * ca);
	float len = length(d);
	vec3 cdir = d / max(len, 1e-4);
	d += cdir * roach * pow(sin(3.14159 * v), 0.8);
	len = length(d);
	vec3 p = luff + d * u;
	vec3 n = vec3(d.z, 0.0, -d.x);
	n /= max(length(n), 1e-4);
	float shape = 3.05 * u * (1.0 - u) * (1.0 + 0.6 * (1.0 - u));
	float foot = mix(1.0, smoothstep(0.0, 0.14, v), foot_attached);
	p += n * belly * len * shape * foot;
	float wave = sin(TIME * 17.0 + phase - u * 11.0 + v * 7.0) + 0.5 * sin(TIME * 29.0 + phase * 1.7 - u * 19.0);
	float env = 4.0 * u * (1.0 - u) * (1.0 - u) * (1.0 - 0.6 * v);
	p += n * flutter * len * 0.11 * wave * env;
	return p;
}

void vertex() {
	vec2 uv = UV;
	vec3 p = sail_point(uv);
	vec2 uq = vec2(uv.x, min(uv.y, 0.96));
	vec3 pq = sail_point(uq);
	vec3 du = sail_point(uq + vec2(0.02, 0.0)) - pq;
	vec3 dv = sail_point(uq + vec2(0.0, 0.02)) - pq;
	vec3 nrm = normalize(cross(dv, du));
	VERTEX = p;
	NORMAL = nrm;
	float foot_len = length(clew - tack);
	sail_m = vec2(uv.x * foot_len * (1.0 - uv.y), uv.y * length(head - tack));
	uv_s = uv;
	n_view = (MODELVIEW_MATRIX * vec4(nrm, 0.0)).xyz;
}

vec4 decal_at(vec4 box, vec2 m, vec2 region_min, vec2 region_size, bool flip_x) {
	vec2 l = (m - box.xy) / box.zw;
	if (l.x < 0.0 || l.x > 1.0 || l.y < 0.0 || l.y > 1.0) {
		return vec4(0.0);
	}
	float tx = flip_x ? 1.0 - l.x : l.x;
	return texture(decal, region_min + vec2(tx, 1.0 - l.y) * region_size);
}

void fragment() {
	vec3 ns = normalize(n_view);
	bool stbd = dot(ns, VIEW) > 0.0;
	NORMAL = stbd ? ns : -ns;
	vec3 col = cloth;
	// Crosscut panel seams, roughly perpendicular to the leech.
	float seam_y = sail_m.y + sail_m.x * 0.35;
	float fs = fwidth(seam_y);
	float seam = 1.0 - smoothstep(0.0, 0.012 + fs, abs(fract(seam_y / 0.62) - 0.5) * 0.62 - 0.29);
	col *= 1.0 - 0.06 * (1.0 - seam) * (1.0 - smoothstep(0.02, 0.1, fs));
	// Battens: short pockets in from the leech.
	if (batten_count > 0.5) {
		for (int i = 1; i <= 4; i++) {
			float bv = float(i) / 5.0;
			float dv = abs(uv_s.y - bv) * length(head - tack);
			if (dv < 0.022 && uv_s.x > 0.78) {
				col *= 0.86;
			}
		}
	}
	if (has_decal) {
		vec4 nd = stbd ? decal_at(num_stbd, sail_m, vec2(0.0, 0.0), vec2(1.0, 0.5), true)
				: decal_at(num_port, sail_m, vec2(0.0, 0.0), vec2(1.0, 0.5), false);
		col = mix(col, nd.rgb, nd.a);
		vec4 bd = decal_at(bird_box, sail_m, vec2(0.25, 0.5), vec2(0.5, 0.5), true);
		col = mix(col, bd.rgb, bd.a);
		// The print on the far side shows faintly through the cloth.
		vec4 ghost = stbd ? decal_at(num_port, sail_m, vec2(0.0, 0.0), vec2(1.0, 0.5), false)
				: decal_at(num_stbd, sail_m, vec2(0.0, 0.0), vec2(1.0, 0.5), true);
		col = mix(col, col * 0.82, ghost.a * 0.35);
	}
	ALBEDO = col;
	ROUGHNESS = 0.62;
	SPECULAR = 0.3;
	BACKLIGHT = cloth * 0.45;
}
