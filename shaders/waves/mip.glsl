#[compute]
#version 450
// One mip level of a wave texture: a 2x2 box filter of the level above.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(p, imageSize(dst)))) {
		return;
	}
	ivec2 s = p * 2;
	vec4 v = imageLoad(src, s) + imageLoad(src, s + ivec2(1, 0)) + imageLoad(src, s + ivec2(0, 1)) + imageLoad(src, s + ivec2(1, 1));
	imageStore(dst, p, v * 0.25);
}
