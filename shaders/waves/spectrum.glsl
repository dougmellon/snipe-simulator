#[compute]
#version 450
// Wind-wave spectrum for each FFT cascade, evolved to the current time and written out as the
// four complex fields the inverse FFT turns into displacement, slope and the Jacobian.
//
// Sea state: a fetch-limited JONSWAP spectrum (Hasselmann et al. 1973) with Donelan-Banner
// directional spreading, gravity-capillary dispersion in deep water. Each cascade keeps its own
// band of wavenumbers so no wave is counted twice, and each is laid out in its own rotated frame
// (wind_ang is the downwind direction in that frame) so the tiles of different cascades never
// line up.
//
// Conventions: h(x) = sum over k of h~(k) exp(i k.x); a component h0(k) exp(i(k.x - wt)) runs
// along +k. Horizontal displacement D~ = i (k/|k|) h~ moves water toward the crests (Gerstner).

#define N 256
#define PI 3.14159265359
#define G 9.81
#define SIGMA_RHO 7.28e-5

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict writeonly buffer Spectra {
	vec2 data[];
} spec;

layout(push_constant, std430) uniform Params {
	vec4 patch_len;  // tile size per cascade (m)
	vec4 k_lo;       // band edges per cascade (rad/m)
	vec4 k_hi;
	vec4 wind_ang;   // downwind direction in each cascade's frame (rad)
	float wind;      // wind speed at 10 m (m/s)
	float fetch;     // m
	float time;      // s, wrapped to the loop period on the CPU
	float omega0;    // frequency quantum 2 pi / loop period, so the wrap is seamless
	ivec4 debug;     // (x, y, cascade, on): a single unit wave at that index, for testing
} pc;

uint hash(uint x) {
	x ^= x >> 16;
	x *= 0x7feb352dU;
	x ^= x >> 15;
	x *= 0x846ca68bU;
	x ^= x >> 16;
	return x;
}

// Two independent standard normal numbers for a wavenumber cell (Box-Muller).
vec2 gauss(ivec2 id, uint c) {
	uint h = hash(uint(id.x) + hash(uint(id.y) + hash(c * 7919u + 17u)));
	float u1 = (float(h >> 8) + 0.5) / 16777216.0;
	float u2 = (float(hash(h) >> 8) + 0.5) / 16777216.0;
	return sqrt(-2.0 * log(u1)) * vec2(cos(2.0 * PI * u2), sin(2.0 * PI * u2));
}

float omega(float k) {
	return sqrt(G * k + SIGMA_RHO * k * k * k);
}

float domega_dk(float k) {
	return (G + 3.0 * SIGMA_RHO * k * k) / (2.0 * omega(k));
}

float jonswap(float w, float wp) {
	float u = max(pc.wind, 0.3);
	float f = max(pc.fetch, 10.0);
	float alpha = 0.076 * pow(u * u / (f * G), 0.22);
	float sigma = w <= wp ? 0.07 : 0.09;
	float r = exp(-(w - wp) * (w - wp) / (2.0 * sigma * sigma * wp * wp));
	float x = wp / w;
	return alpha * G * G / pow(w, 5.0) * exp(-1.25 * x * x * x * x) * pow(3.3, r);
}

// Donelan-Banner spreading, normalised over -pi..pi.
float spreading(float w, float wp, float theta) {
	float x = w / wp;
	float beta;
	if (x < 0.95) {
		beta = 2.61 * pow(x, 1.3);
	} else if (x < 1.6) {
		beta = 2.28 * pow(x, -1.3);
	} else {
		beta = pow(10.0, -0.4 + 0.8393 * exp(-0.567 * log(x * x)));
	}
	float c = cosh(beta * theta);
	return beta / (2.0 * tanh(beta * PI)) / (c * c);
}

vec2 h0(ivec2 id, uint c) {
	float L = pc.patch_len[c];
	float dk = 2.0 * PI / L;
	vec2 k = (vec2(id) - float(N / 2)) * dk;
	float kl = length(k);
	if (pc.debug.w != 0) {
		return (id == pc.debug.xy && int(c) == pc.debug.z) ? vec2(1.0, 0.0) : vec2(0.0);
	}
	if (kl < max(pc.k_lo[c], 1e-4) || kl >= pc.k_hi[c]) {
		return vec2(0.0);
	}
	float u = max(pc.wind, 0.3);
	float wp = 22.0 * pow(G * G / (u * max(pc.fetch, 10.0)), 1.0 / 3.0);
	float w = omega(kl);
	float theta = atan(k.y, k.x) - pc.wind_ang[c];
	theta = mod(theta + PI, 2.0 * PI) - PI;
	float s = jonswap(w, wp) * spreading(w, wp, theta) * domega_dk(kl) / kl;
	return gauss(id, c) * 0.5 * sqrt(s) * dk;
}

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

vec2 times_i(vec2 z) {
	return vec2(-z.y, z.x);
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	uint c = gl_GlobalInvocationID.z;
	ivec2 nid = (ivec2(N) - id) % N;  // the cell of -k
	vec2 a = h0(id, c);
	vec2 b = h0(nid, c);
	b.y = -b.y;
	float L = pc.patch_len[c];
	vec2 k = (vec2(id) - float(N / 2)) * (2.0 * PI / L);
	float kl = length(k);
	float w = omega(kl);
	w = floor(w / pc.omega0 + 0.5) * pc.omega0;
	float ph = w * pc.time;
	vec2 e = vec2(cos(ph), sin(ph));
	vec2 h = cmul(a, vec2(e.x, -e.y)) + cmul(b, e);
	vec2 ih = times_i(h);
	float ik = kl > 1e-6 ? 1.0 / kl : 0.0;
	vec2 dx = ih * (k.x * ik);
	vec2 dy = ih * (k.y * ik);
	vec2 hx = ih * k.x;
	vec2 hy = ih * k.y;
	vec2 dxx = h * (-k.x * k.x * ik);
	vec2 dyy = h * (-k.y * k.y * ik);
	vec2 dxy = h * (-k.x * k.y * ik);
	uint plane = uint(N * N);
	uint base = (c * 4u) * plane + uint(id.y * N + id.x);
	spec.data[base] = dx + times_i(dy);
	spec.data[base + plane] = h + times_i(hx);
	spec.data[base + 2u * plane] = hy + times_i(dxx);
	spec.data[base + 3u * plane] = dyy + times_i(dxy);
}
