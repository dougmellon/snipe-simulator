#[compute]
#version 450
// Turns one cascade's transformed fields into its textures:
//   displacement (dx, height, dy, Jacobian), sampled by the water's vertex shader
//   slope (d h / d x, d h / d y, squared slope, foam), mipmapped for the fragment shader; the
//   mip-averaged squared slope minus the squared mean slope is the variance the filtering lost,
//   which becomes roughness far off
// Foam builds where the choppy surface folds (the Jacobian drops) and fades over a few seconds.

#define N 256

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Spectra {
	vec2 data[];
} spec;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D disp_img;
layout(rgba16f, set = 0, binding = 2) uniform restrict image2D slope_img;

layout(push_constant, std430) uniform Params {
	uint cascade;
	float choppy;     // horizontal displacement scale
	float foam_thr;   // foam where the Jacobian falls below this
	float foam_gain;
	float foam_keep;  // share of last frame's foam that survives
	float pad0;
	float pad1;
	float pad2;
} pc;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	uint plane = uint(N * N);
	uint base = pc.cascade * 4u * plane + uint(id.y * N + id.x);
	// The spectrum is stored centred on k = 0, which flips the sign of alternate samples.
	float sg = ((id.x + id.y) & 1) == 0 ? 1.0 : -1.0;
	vec2 f0 = spec.data[base] * sg;
	vec2 f1 = spec.data[base + plane] * sg;
	vec2 f2 = spec.data[base + 2u * plane] * sg;
	vec2 f3 = spec.data[base + 3u * plane] * sg;
	float dx = f0.x;
	float dy = f0.y;
	float h = f1.x;
	float hx = f1.y;
	float hy = f2.x;
	float dxx = f2.y;
	float dyy = f3.x;
	float dxy = f3.y;
	float l = pc.choppy;
	float jxx = 1.0 + l * dxx;
	float jyy = 1.0 + l * dyy;
	float jxy = l * dxy;
	float jac = jxx * jyy - jxy * jxy;
	// Slope of the displaced surface (from the cross product of its tangents).
	vec2 s = vec2(hx * jyy - jxy * hy, jxx * hy - jxy * hx) / max(jac, 0.25);
	float sl = length(s);
	if (sl > 1.2) {
		s *= 1.2 / sl;
	}
	imageStore(disp_img, id, vec4(l * dx, h, l * dy, jac));
	float old = imageLoad(slope_img, id).w;
	float foam = max(old * pc.foam_keep, clamp((pc.foam_thr - jac) * pc.foam_gain, 0.0, 1.0));
	imageStore(slope_img, id, vec4(s, dot(s, s), foam));
}
