shader_type spatial;
// Colorado plains farmland on a section-line grid: rectangular fields (irrigated green, stubble,
// fallow, dry grass, centre pivots) with crop-row stripes, gravel county roads, a grass and
// reed band around the reservoir, and a gravel lot at the sailing club. Detail that would drop
// below a pixel fades to its average so nothing shimmers at distance.
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform sampler2D sdf_tex : filter_linear, repeat_disable;
uniform vec2 sdf_origin = vec2(0.0);
uniform vec2 sdf_dim = vec2(1.0);
uniform float sdf_cell = 5.0;
uniform vec4 lot_rect = vec4(0.0, 0.0, 0.0, 0.0);   // centre (east, north), half size
uniform float lot_angle = 0.0;
uniform vec4 lawn_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 farm_pos[24];
uniform int farm_count = 0;

varying vec3 wpos;

const float ROAD_GRID = 804.67;
const float FIELD = 402.34;

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
	return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.03 + 5.1) + 0.2 * vnoise(p * 4.1 + 1.7);
}

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

// Anti-aliased band: 1 inside |x| < half_w.
float band(float x, float half_w, float fw) {
	return 1.0 - smoothstep(half_w - fw, half_w + fw, abs(x));
}

float in_rect(vec2 p, vec4 r, float ang, float fw) {
	vec2 d = p - r.xy;
	float c = cos(ang);
	float s = sin(ang);
	d = vec2(c * d.x + s * d.y, -s * d.x + c * d.y);
	vec2 q = abs(d) - r.zw;
	float e = max(q.x, q.y);
	return 1.0 - smoothstep(-fw, fw, e);
}

vec3 field_color(vec2 p, float fp, out float rough) {
	vec2 cell = floor(p / FIELD);
	vec2 local = p - cell * FIELD;
	float h = hash12(cell + 11.0);
	float h2 = hash12(cell * 1.7 + 3.0);
	// Some quarter-quarters split in two strips.
	vec2 sub = cell;
	if (h2 > 0.55) {
		bool ns = h2 > 0.78;
		float split = FIELD * (0.35 + 0.3 * hash12(cell + 5.0));
		float k = ns ? local.x : local.y;
		sub = cell * 2.0 + (k > split ? vec2(1.0, 0.0) : vec2(0.0, 0.0));
		h = hash12(sub + 31.0);
	}
	vec3 col;
	float rows = 0.0;
	float row_period = 5.0;
	float row_dir = hash12(sub + 2.0) > 0.5 ? 1.0 : 0.0;
	rough = 0.92;
	if (h < 0.22) {
		col = srgb(mix(vec3(0.33, 0.45, 0.16), vec3(0.42, 0.52, 0.2), hash12(sub + 9.0)));   // corn / alfalfa
		rows = 0.18;
	} else if (h < 0.40) {
		col = srgb(mix(vec3(0.72, 0.64, 0.42), vec3(0.8, 0.7, 0.47), hash12(sub + 9.0)));    // wheat stubble
		rows = 0.12;
		row_period = 7.0;
	} else if (h < 0.52) {
		col = srgb(mix(vec3(0.5, 0.4, 0.3), vec3(0.58, 0.47, 0.35), hash12(sub + 9.0)));     // fallow
		rows = 0.2;
		row_period = 4.0;
	} else if (h < 0.72) {
		col = srgb(mix(vec3(0.6, 0.58, 0.4), vec3(0.66, 0.62, 0.43), hash12(sub + 9.0)));    // dry grass
	} else if (h < 0.84) {
		col = srgb(mix(vec3(0.45, 0.5, 0.27), vec3(0.52, 0.55, 0.3), hash12(sub + 9.0)));    // pasture
	} else {
		// Centre pivot: an irrigated green circle in a dry square.
		vec2 c = cell * FIELD + FIELD * 0.5;
		float r = length(p - c);
		float inside = 1.0 - smoothstep(FIELD * 0.47 - fp, FIELD * 0.47 + fp, r);
		vec3 green = srgb(mix(vec3(0.3, 0.44, 0.15), vec3(0.4, 0.5, 0.18), hash12(cell + 4.0)));
		vec3 dry = srgb(vec3(0.66, 0.61, 0.42));
		float ring = sin(r * 6.2831 / 6.0) * (1.0 - smoothstep(1.5, 4.0, fp));
		col = mix(dry, green * (1.0 + 0.08 * ring), inside);
		// Wheel track spokes and the pivot pad.
		col = mix(col, srgb(vec3(0.55, 0.5, 0.38)), (1.0 - smoothstep(3.0 - fp, 3.0 + fp, r)) * 0.8);
		return col;
	}
	if (rows > 0.0) {
		float coord = row_dir > 0.5 ? p.x : p.y;
		float fade = 1.0 - smoothstep(row_period * 0.12, row_period * 0.45, fp);
		col *= 1.0 + rows * fade * sin(coord * 6.2831 / row_period);
	}
	// Soft moisture variation within the field.
	col *= 0.9 + 0.2 * fbm(p / 60.0);
	// Darker fence lines and ditches along field edges.
	vec2 e = min(local, FIELD - local);
	float edge = min(e.x, e.y);
	col = mix(col, srgb(vec3(0.42, 0.44, 0.28)), band(edge, 2.0, fp) * 0.6);
	return col;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wpos.x, -wpos.z);
	float fp = max(length(dFdx(wpos.xz)), length(dFdy(wpos.xz))) * 0.7;
	float rough;
	vec3 col = field_color(p, fp, rough);

	// Farmyards: packed dirt around the buildings.
	for (int i = 0; i < 24; i++) {
		if (i >= farm_count) {
			break;
		}
		vec2 d = abs(p - farm_pos[i]);
		float yard = 1.0 - smoothstep(55.0 - fp, 55.0 + fp, max(d.x, d.y * 1.2) + 12.0 * vnoise(p / 12.0));
		col = mix(col, srgb(vec3(0.56, 0.52, 0.42)) * (0.9 + 0.2 * vnoise(p / 5.0)), yard * 0.85);
	}

	// Gravel county roads on the half-mile grid.
	vec2 rg = p / ROAD_GRID;
	vec2 rd = (rg - round(rg)) * ROAD_GRID;
	float road = max(band(rd.x, 4.0, fp), band(rd.y, 4.0, fp));
	vec3 gravel = srgb(vec3(0.66, 0.62, 0.55)) * (0.95 + 0.1 * vnoise(p / 3.0));
	float shoulder = max(band(rd.x, 7.0, fp), band(rd.y, 7.0, fp)) - road;
	col = mix(col, srgb(vec3(0.5, 0.52, 0.34)), max(shoulder, 0.0) * 0.7);
	col = mix(col, gravel, road);

	// Around the reservoir: wet bank, reeds, then a grass strip before the fields.
	vec2 suv = ((p - sdf_origin) / sdf_cell + 0.5) / sdf_dim;
	float d = texture(sdf_tex, suv).r;
	float nz = fbm(p / 9.0);
	vec3 grass = srgb(mix(vec3(0.46, 0.5, 0.27), vec3(0.56, 0.56, 0.33), nz));
	vec3 reeds = srgb(mix(vec3(0.33, 0.38, 0.18), vec3(0.47, 0.46, 0.25), fbm(p / 3.0)));
	vec3 bank = srgb(mix(vec3(0.5, 0.45, 0.37), vec3(0.62, 0.58, 0.5), vnoise(p / 1.5)));
	float w_grass = 1.0 - smoothstep(55.0, 85.0, d + 25.0 * nz);
	col = mix(col, grass, w_grass);
	float w_reeds = (1.0 - smoothstep(9.0, 20.0, d + 10.0 * nz)) * smoothstep(0.3, 0.55, fbm(p / 40.0));
	col = mix(col, reeds, w_reeds);
	col = mix(col, bank, 1.0 - smoothstep(4.0, 8.0, d + 3.0 * nz));

	// Sailing club: gravel lot and mown lawn.
	float lawn = in_rect(p, lawn_rect, lot_angle, fp + 1.0);
	col = mix(col, srgb(vec3(0.38, 0.52, 0.2)) * (0.93 + 0.1 * vnoise(p / 4.0)), lawn);
	float lot = in_rect(p, lot_rect, lot_angle, fp + 0.5);
	col = mix(col, srgb(vec3(0.62, 0.6, 0.55)) * (0.92 + 0.12 * vnoise(p / 1.7)), lot);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
