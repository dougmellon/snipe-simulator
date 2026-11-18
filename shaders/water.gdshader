shader_type spatial;
// Union Reservoir water.
//
// Waves: three FFT tiles from scripts/waves.gd (a fetch-limited JONSWAP sea for the wind, from the
// 2-4 m chop down to capillary ripples), each turned to its own angle so their repeats never line
// up. Near the camera they move the surface itself (choppy, sharp-crested waves); everywhere they
// give the slopes that light it. Mipmaps average the small waves away with distance, and the
// slope variance they lose becomes roughness, so the glitter spreads into a sun path and the sky
// reflection softens far off. The chop grows with the fetch of open water upwind (read from the
// shore distance field), so it is small under a windward shore and biggest along the lee shore.
// The ripples follow the local wind: puffs come through rougher and darker, lulls go glassy.
// Whitecaps break where the chop folds over, from about 13 knots.
//
// Light: the sun's glitter is a GGX highlight off the wave facets with water's Fresnel (2%
// straight down, nearly all at grazing); the sky and nearby boats come from the sky and
// screen-space reflections. Light that gets into the water scatters back out of the suspended
// silt and algae, so seen from above the reservoir is a murky olive brown whichever way the
// ripples face; thin crests glow green with the sun behind them.
//
// Wakes are drawn from each boat's real track (a short history of positions): turbulent wash
// behind the transom, a feathered V of diverging waves at the Kelvin angle, transverse waves
// inside it, and a smooth slick that lingers. A bow wave rolls off the stem. Each Snipe's heeled
// hull is cut out of the surface so the cockpit stays dry.
//
// The mesh is a unit grid (a 2 x 2 PlaneMesh, GRID_M quads from centre to edge) that the vertex
// shader spreads around the camera: GRID_D0 m between vertices underfoot, the spacing growing in
// proportion to distance, about 4.8 km to the edge.
render_mode cull_back;

const float GRID_M = 512.0;
const float GRID_D0 = 0.1;
const float GRID_C = 0.0125;

uniform float wave_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);  // (east, north), the way the wind blows
uniform float wind_speed = 5.0;          // mean wind over the lake (m/s)
uniform float fetch_ref = 1200.0;        // the fetch the wave spectrum was made for (m)
uniform vec4 puffs[16];                  // (east, north, radius, strength)
uniform sampler2D sdf_tex : filter_linear, repeat_disable;
uniform vec2 sdf_origin = vec2(0.0);
uniform vec2 sdf_dim = vec2(1.0);
uniform float sdf_cell = 5.0;

uniform sampler2D disp0 : filter_linear, repeat_enable;
uniform sampler2D disp1 : filter_linear, repeat_enable;
uniform sampler2D slope0 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slope1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slope2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tile_len = vec3(57.3, 13.7, 3.27);
uniform vec3 tile_rot = vec3(0.31, 1.47, 2.66);
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 water_color : source_color = vec3(0.22, 0.25, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.34, 0.32, 0.22);
uniform vec3 foam_color : source_color = vec3(0.88, 0.9, 0.89);
uniform vec3 aerated_color : source_color = vec3(0.3, 0.4, 0.31);
uniform vec3 crest_color : source_color = vec3(0.3, 0.42, 0.2);

// Snipe hulls: (east, north, heading, heel), heading compass radians, heel + = starboard down;
// hull_u is each boat's speed through the water (m/s).
uniform vec4 hulls[10];
uniform float hull_u[10];
uniform int hull_count = 0;

// Wake tracks: WAKE_N points per boat, newest first: (east, north, age s, speed m/s). A point
// with negative speed ends the track. wake_box is each track's bounds grown by the wake's reach.
const int WAKE_N = 20;
uniform vec4 wake_pts[200];
uniform vec4 wake_box[10];
uniform int wake_boats = 0;

varying vec3 wpos;
varying vec2 v_p0;       // where this bit of water sits at rest (east, north)
varying vec3 v_amp;      // strength of each wave tile here
varying float v_local;   // local wind (m/s)
varying float v_ruffle;  // puff (+) or lull (-)
varying float v_height;  // wave height (m)
varying vec3 v_up;       // world up, in view space, for light()
varying float v_crest;   // how much sun comes through the crest

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float sdf_at(vec2 p) {
	vec2 suv = ((p - sdf_origin) / sdf_cell + 0.5) / sdf_dim;
	return textureLod(sdf_tex, suv, 0.0).r;
}

// Open water upwind of a point (m): march up the wind using the distance to the shore as the step.
float fetch_at(vec2 p, vec2 wd) {
	float s = 0.0;
	for (int i = 0; i < 24; i++) {
		float d = sdf_at(p - wd * s);
		if (d > -1.0) {
			break;
		}
		s += max(-d, 4.0);
		if (s > 3000.0) {
			break;
		}
	}
	return s;
}

float puff_field(vec2 p) {
	float f = 0.0;
	for (int i = 0; i < 16; i++) {
		vec4 q = puffs[i];
		vec2 d = p - q.xy;
		float r2 = max(q.z * q.z, 1.0);
		f += q.w * exp(-dot(d, d) / r2);
	}
	return f;
}

// --- Hulls ------------------------------------------------------------------------------------

// The Snipe's lines at station x forward of the CG: copies of sheer_hb, sheer_h, chine_hb,
// chine_h, keel_h and _run (hull_run here) in boat_view.gd (change them together). The bow is full in plan and
// closes into a rounded tip; the chine and keel run up into a raked stem.
float sheer_hb(float x) {
	if (x <= 0.35) {
		return 0.76 - 0.02 * (0.35 - x) * (0.35 - x);
	}
	float t = clamp((x - 0.35) / 2.1, 0.0, 1.0);
	float w = 1.0 - t * t;
	return 0.76 * sqrt(w) * pow((w + 0.1) / 1.1, 0.25);
}

float sheer_h(float x) {
	return x > 0.0 ? 0.33 + 0.034 * x * x : 0.33 + 0.006 * x * x;
}

float chine_hb(float x) {
	if (x <= 0.3) {
		return sheer_hb(x) * 0.81;
	}
	float t = clamp((x - 0.3) / 2.15, 0.0, 1.0);
	return 0.75995 * 0.81 * (1.0 - pow(t, 1.35));
}

// The run aft: flat to x0, curving up to x1, then straight, rising s per metre.
float hull_run(float x, float x0, float x1, float s) {
	if (x >= x0) {
		return 0.0;
	}
	float d = x0 - x1;
	if (x >= x1) {
		return s * (x0 - x) * (x0 - x) / (2.0 * d);
	}
	return s * (x1 - x + d * 0.5);
}

float chine_h(float x) {
	float h = -0.05;
	if (x > 0.6) {
		h += 0.05 * (x - 0.6) * (x - 0.6);
	}
	h += 0.25 * pow(smoothstep(2.15, 2.45, x), 1.6);
	return h + hull_run(x, 0.3, -0.6, 0.07);
}

float keel_h(float x) {
	float h = -0.15;
	if (x > 0.6) {
		h += 0.0776 * (x - 0.6) * (x - 0.6);
	}
	h += 0.19 * pow(smoothstep(2.15, 2.45, x), 1.6);
	h += hull_run(x, 0.6, -0.34, 0.075);
	return min(h, chine_h(x) - 0.03);
}

// Inside a (heeled) hull, and the bow wave's foam just outside the forward half of one. A point
// s metres to starboard on the water sits at hull-local height s * sin(heel): up the topsides on
// the low side, down toward the chine on the high side.
bool hull_test(vec2 p, out float bow_foam) {
	bow_foam = 0.0;
	for (int i = 0; i < hull_count; i++) {
		vec4 h = hulls[i];
		vec2 d = p - h.xy;
		if (dot(d, d) > 12.0 || abs(h.w) > 1.0) {
			continue;
		}
		float sh = sin(h.z);
		float ch = cos(h.z);
		float x = d.x * sh + d.y * ch;
		float s = d.x * ch - d.y * sh;
		if (x < -2.24 || x > 2.9) {
			continue;
		}
		float ly = s * cos(h.w);
		float lh = s * sin(h.w);
		// The hull's half-breadth at that height: the bottom panel from the keel to the chine,
		// then the topside out to the sheer.
		float kh = keel_h(x);
		float cht = chine_h(x);
		float sht = sheer_h(x);
		float cb = chine_hb(x);
		float w = lh < cht
			? cb * clamp((lh - kh) / max(cht - kh, 0.001), 0.0, 1.0)
			: mix(cb, sheer_hb(x), clamp((lh - cht) / max(sht - cht, 0.001), 0.0, 1.0));
		if (lh <= sht && abs(ly) < w * 0.97 && x < 2.45) {
			return true;
		}
		// The bow wave: a curl of white water peeling off the stem and along the forward topsides.
		float u = hull_u[i];
		float edge = abs(ly) - max(w, 0.0);
		float fwd = smoothstep(-0.6, 1.4, x) * (1.0 - smoothstep(2.3, 2.9, x));
		bow_foam = max(bow_foam, smoothstep(0.08 + 0.05 * u, 0.0, edge) * fwd * smoothstep(1.0, 3.0, u));
	}
	return false;
}

// --- Wakes ------------------------------------------------------------------------------------

// Wave height (m) of a wake at a point s metres astern of where the boat was and y metres off
// its track, for a boat that was doing u m/s.
float kelvin(float s, float y, float u) {
	if (s <= 0.0) {
		return 0.0;
	}
	float ay = abs(y);
	float lt = max(6.2832 * u * u / 9.81, 0.4);      // transverse wavelength
	float amp = 0.03 * clamp(u / 2.6, 0.0, 1.6) * clamp(u / 2.6, 0.0, 1.6);
	float fade = exp(-s / 22.0) * smoothstep(0.0, 1.2, s);
	// Diverging waves: short crests in echelon along each arm of the V (19.5 degrees).
	float arm = ay - 0.354 * s;
	float band = exp(-arm * arm / (0.05 + 0.03 * s + 0.002 * s * s));
	float kd = 6.2832 / (lt * 0.45);
	float div = band * cos(kd * (0.82 * s + 0.57 * ay));
	// Transverse waves across the track inside the V.
	float inside = smoothstep(0.354 * s, 0.18 * s, ay);
	float tr = 0.45 * inside * cos(6.2832 * s / lt) * exp(-s / 10.0);
	return amp * fade * (div + tr);
}

// Wash foam, slick and wave slope from every boat's recent track.
void wakes(vec2 p, out float foam, out float slick, out vec2 slope) {
	foam = 0.0;
	slick = 0.0;
	slope = vec2(0.0);
	for (int b = 0; b < wake_boats; b++) {
		vec4 box = wake_box[b];
		if (p.x < box.x || p.y < box.y || p.x > box.z || p.y > box.w) {
			continue;
		}
		int base = b * WAKE_N;
		float best = 1e9;
		float bt = 0.0;
		int bi = -1;
		for (int i = 0; i < WAKE_N - 1; i++) {
			vec4 a = wake_pts[base + i];
			vec4 c = wake_pts[base + i + 1];
			if (c.w < 0.0) {
				break;
			}
			vec2 ab = c.xy - a.xy;
			float l2 = max(dot(ab, ab), 1e-4);
			float t = clamp(dot(p - a.xy, ab) / l2, 0.0, 1.0);
			vec2 q = a.xy + ab * t;
			float d2 = dot(p - q, p - q);
			if (d2 < best) {
				best = d2;
				bt = t;
				bi = i;
			}
		}
		if (bi < 0) {
			continue;
		}
		vec4 a = wake_pts[base + bi];
		vec4 c = wake_pts[base + bi + 1];
		vec2 dir = a.xy - c.xy;                      // direction of travel
		float dl = length(dir);
		if (dl < 1e-3) {
			continue;
		}
		dir /= dl;
		vec2 nrm = vec2(-dir.y, dir.x);
		vec2 q = mix(a.xy, c.xy, bt);
		float along = dot(p - q, -dir);
		// Nothing ahead of the stem, and nothing beyond the tail of the track.
		if (bi == 0 && bt <= 0.0 && along < -2.4) {
			continue;
		}
		if (bt >= 1.0 && along > 1.0) {
			continue;
		}
		float age = mix(a.z, c.z, bt);
		float u = max(mix(a.w, c.w, bt), 0.0);
		float y = dot(p - q, nrm);
		// Distance astern of the boat now; the part of the track ahead of this point is
		// approximated by the speed times the age.
		float s = along + age * max(u, 0.3);
		// Everything dies away before the end of the recorded track (about 11 s).
		float moving = smoothstep(0.7, 2.0, u) * (1.0 - smoothstep(6.0, 10.5, age));
		// Turbulent wash behind the transom: a boat length or two of froth, spreading and settling.
		float ww = 0.26 + 0.06 * age;
		float wash = smoothstep(ww, ww * 0.2, abs(y)) * exp(-age / 1.2) * moving * 0.6 * step(-2.3, along);
		foam = max(foam, wash);
		// The flattened slick left on the chop: a faint, narrow lane that soon fills in.
		float sw = 0.7 + 0.2 * age;
		slick = max(slick, smoothstep(sw, sw * 0.3, abs(y)) * exp(-age / 6.0) * moving * 0.8);
		// Waves: slope by finite differences in the track's frame.
		float e = 0.12;
		// The V starts at the stem, 2.4 m ahead of the track point (the boat's centre).
		float sv = s + 2.4;
		float h0 = kelvin(sv, y, u);
		float hs = kelvin(sv + e, y, u);
		float hy = kelvin(sv, y + e, u);
		vec2 g = (-dir) * ((hs - h0) / e) + nrm * ((hy - h0) / e);
		slope += g * moving;
		// Broken water along the first metres of each V arm when she's moving fast.
		float arm = abs(y) - 0.354 * sv;
		foam = max(foam, exp(-arm * arm / 0.02) * exp(-sv / 3.0) * smoothstep(3.3, 4.5, u) * 0.4);
	}
}

// --- Waves ------------------------------------------------------------------------------------

// A tile's texture coordinates for a point, and its vectors back into (east, north).
vec2 tile_uv(vec2 p, float ang, float len) {
	return rot(-ang) * p / len;
}

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec2 g = VERTEX.xz;
	float r = max(abs(g.x), abs(g.y));
	float R = GRID_D0 / GRID_C * (exp(GRID_C * r * GRID_M) - 1.0);
	vec2 off = r > 0.0 ? g / r * R : vec2(0.0);
	vec2 snap = floor(cam.xz / GRID_D0 + 0.5) * GRID_D0;
	vec3 w = vec3(snap.x + off.x, 0.0, snap.y + off.y);
	vec2 p = vec2(w.x, -w.z);
	vec2 wd = normalize(wind_dir);

	// Local wind: puffs ruffle, lulls smooth; a slow warp keeps their edges ragged, and faint
	// lanes run down the wind.
	vec2 warp = vec2(textureLod(foam_noise, p / 520.0, 0.0).r, textureLod(foam_noise, p / 520.0 + 0.37, 0.0).r) * 2.0 - 1.0;
	float ruffle = clamp(puff_field(p + warp * 60.0), -0.45, 0.7);
	vec2 wc = rot(-atan(wd.y, wd.x)) * p;
	float lane = textureLod(foam_noise, wc / vec2(260.0, 45.0) - vec2(wave_time * wind_speed * 0.0015, 0.0), 0.0).r;
	float local = max(wind_speed * (1.0 + 1.4 * ruffle) * (0.85 + 0.3 * lane), 0.0);
	float rel = clamp(local / max(wind_speed, 0.5), 0.0, 2.0);

	// The chop needs open water upwind to build; ripples answer the wind at once.
	float fetch = fetch_at(p, wd);
	float ff = sqrt(clamp(fetch / fetch_ref, 0.0, 1.8));
	vec3 amp;
	amp.x = ff * (0.75 + 0.25 * rel);
	amp.y = mix(ff, 1.0, 0.5) * pow(rel, 1.2);
	amp.z = smoothstep(0.4, 2.4, local) * rel * rel;
	// Right against the bank the water is too shallow to hold the waves.
	amp.xy *= 1.0 - smoothstep(-4.0, 1.0, sdf_at(p));

	// Move the surface near the camera; the finer tiles only very close.
	float dist = length(w - cam);
	float f0 = amp.x * (1.0 - smoothstep(30.0, 75.0, dist));
	float f1 = amp.y * (1.0 - smoothstep(6.0, 16.0, dist));
	vec3 d = vec3(0.0);
	if (f0 > 0.0) {
		vec4 t0 = textureLod(disp0, tile_uv(p, tile_rot.x, tile_len.x), 0.0);
		d += vec3(rot(tile_rot.x) * t0.xz, t0.y) * f0;
	}
	if (f1 > 0.0) {
		vec4 t1 = textureLod(disp1, tile_uv(p, tile_rot.y, tile_len.y), 0.0);
		d += vec3(rot(tile_rot.y) * t1.xz, t1.y) * f1;
	}
	w += vec3(d.x, d.z, -d.y);
	VERTEX = w;
	wpos = w;
	v_p0 = p;
	v_amp = amp;
	v_local = local;
	v_ruffle = ruffle;
	v_height = d.z;
}

void fragment() {
	vec2 p = vec2(wpos.x, -wpos.z);
	float bow;
	if (hull_test(p, bow)) {
		discard;
	}
	vec2 wd = normalize(wind_dir);
	float t = wave_time;

	float wake_foam;
	float slick;
	vec2 wake_slope;
	wakes(p, wake_foam, slick, wake_slope);
	float calm = 1.0 - 0.6 * slick;                  // the slick lies flatter
	vec3 amp = v_amp * vec3(mix(1.0, calm, 0.4), calm, calm);

	vec4 s0 = texture(slope0, tile_uv(v_p0, tile_rot.x, tile_len.x));
	vec4 s1 = texture(slope1, tile_uv(v_p0, tile_rot.y, tile_len.y));
	vec4 s2 = texture(slope2, tile_uv(v_p0, tile_rot.z, tile_len.z));
	vec2 slope = amp.x * (rot(tile_rot.x) * s0.xy) + amp.y * (rot(tile_rot.y) * s1.xy) + amp.z * (rot(tile_rot.z) * s2.xy);
	slope += wake_slope;
	// Slope variance the mipmaps averaged away, plus the ripples too small for any tile.
	float lost = amp.x * amp.x * max(s0.z - dot(s0.xy, s0.xy), 0.0)
		+ amp.y * amp.y * max(s1.z - dot(s1.xy, s1.xy), 0.0)
		+ amp.z * amp.z * max(s2.z - dot(s2.xy, s2.xy), 0.0);
	// A puff's ripples are steeper and denser than the wind speed alone gives them, which is most
	// of why it looks dark against the sky; lulls go glassy and bright.
	float alpha = max(sqrt(lost + 0.0006 * amp.z + 0.0001) + 0.14 * v_ruffle, 0.02);
	vec3 nw = normalize(vec3(-slope.x, 1.0, slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	v_up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);

	// Colour: the murky olive of the water itself, siltier and browner in the shallows.
	vec2 suv = ((p - sdf_origin) / sdf_cell + 0.5) / sdf_dim;
	float d = texture(sdf_tex, suv).r;
	float shallow = smoothstep(-10.0, 0.0, d);
	vec3 col = mix(water_color, shallow_color, shallow * 0.75);
	col *= 1.0 - 0.25 * clamp(v_ruffle, 0.0, 0.6);

	// Foam: whitecaps where the chop folds, wakes and bow waves, and a thin line where the chop
	// meets the lee bank.
	float fn = texture(foam_noise, p / 0.9 + vec2(t * 0.05, 0.0)).r * 0.55 + texture(foam_noise, p / 0.31 - vec2(0.0, t * 0.07)).r * 0.45;
	// A whitecap is dense white where it breaks; as it fades the foam thins into lace, then
	// streaks, then nothing.
	float gust = clamp(v_local / max(wind_speed, 0.5), 0.0, 2.0);
	float f = (amp.x * s0.w + 0.5 * amp.y * s1.w) * smoothstep(0.6, 1.1, gust);
	float lace = texture(foam_noise, p / 2.3 + vec2(0.0, t * 0.02)).r;
	float caps = max(smoothstep(0.55, 0.9, f + 0.3 * (fn - 0.5)), smoothstep(1.0 - f, 1.08 - f, 0.5 * fn + 0.5 * lace) * f * 0.8);
	float shore = smoothstep(-2.6, -0.5, d) * smoothstep(0.35, 0.65, fn + 0.25 * smoothstep(-1.2, -0.2, d)) * smoothstep(0.1, 0.6, v_amp.x) * clamp((wind_speed - 2.0) / 5.0, 0.0, 1.0);
	// Churned water is mostly bubbles under the surface (pale green) with white only where it's
	// densest.
	float churn = max(max(wake_foam, bow), caps);
	col = mix(col, aerated_color, clamp(churn * 1.4, 0.0, 0.6));
	float foam = max(max(wake_foam, bow) * smoothstep(0.4, 0.85, fn + 0.1 * churn), caps) + shore;
	foam = clamp(foam, 0.0, 1.0);
	col = mix(col, foam_color, foam * 0.9);

	// Sun through the crests, stronger where the wave stands tall and thin.
	v_crest = clamp(v_height / 0.08, 0.0, 1.0) * (1.0 - foam);

	ALBEDO = col;
	ROUGHNESS = mix(sqrt(clamp(alpha, 0.02, 0.5)), 0.85, foam);
	SPECULAR = 0.354;                                // F0 = 0.02, water
	METALLIC = 0.0;
}

void light() {
	// Sunlight that gets into the water scatters back out of it, whichever way the ripples face.
	float sun_in = max(dot(v_up, LIGHT), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * sun_in / PI;
	// Looking toward the sun, it shines through the thin tops of the waves.
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * v_crest;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * back * crest_color * 1.5 / PI;
	// Glitter: the sun's reflection in each wave facet (GGX, Smith, Fresnel for water).
	vec3 h = normalize(LIGHT + VIEW);
	float nl = max(dot(NORMAL, LIGHT), 0.0);
	float nv = max(dot(NORMAL, VIEW), 1e-3);
	float nh = max(dot(NORMAL, h), 0.0);
	float vh = max(dot(VIEW, h), 0.0);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float dd = nh * nh * (a2 - 1.0) + 1.0;
	float dist = a2 / (PI * dd * dd);
	float vis = 0.5 / (nl * sqrt(nv * nv * (1.0 - a2) + a2) + nv * sqrt(nl * nl * (1.0 - a2) + a2) + 1e-5);
	float fres = 0.02 + 0.98 * pow(1.0 - vh, 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * dist * vis * fres * nl;
}
