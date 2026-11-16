#[compute]
#version 450
// Inverse FFT of every row (vertical = 0) or column (vertical = 1) of each N x N plane, in place.
// One workgroup per line: radix-2 Stockham in shared memory, output in natural order, no 1/N.

#define N 256
#define PI 3.14159265359

layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Spectra {
	vec2 data[];
} spec;

layout(push_constant, std430) uniform Params {
	uint vertical;
	uint pad0;
	uint pad1;
	uint pad2;
} pc;

shared vec2 buf[2][N];

void main() {
	uint j = gl_LocalInvocationID.x;
	uint line = gl_WorkGroupID.y;
	uint base = gl_WorkGroupID.z * uint(N * N);
	uint start = pc.vertical == 0u ? base + line * uint(N) : base + line;
	uint stride = pc.vertical == 0u ? 1u : uint(N);
	buf[0][j] = spec.data[start + j * stride];
	buf[0][j + N / 2] = spec.data[start + (j + N / 2) * stride];
	memoryBarrierShared();
	barrier();
	uint src = 0u;
	for (uint ns = 1u; ns < uint(N); ns <<= 1u) {
		vec2 a = buf[src][j];
		vec2 b = buf[src][j + N / 2];
		uint r = j % ns;
		float ang = PI * float(r) / float(ns);
		vec2 w = vec2(cos(ang), sin(ang));
		b = vec2(b.x * w.x - b.y * w.y, b.x * w.y + b.y * w.x);
		uint o = (j / ns) * ns * 2u + r;
		buf[1u - src][o] = a + b;
		buf[1u - src][o + ns] = a - b;
		src = 1u - src;
		memoryBarrierShared();
		barrier();
	}
	spec.data[start + j * stride] = buf[src][j];
	spec.data[start + (j + N / 2) * stride] = buf[src][j + N / 2];
}
