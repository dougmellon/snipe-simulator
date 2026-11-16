shader_type spatial;
// A wool telltale or leech ribbon: a crossed pair of thin strips from z = 0 (attached end) to
// z = 1, aimed by its node (local X = off the sail, Z = the way it streams, scaled to length).
// `flap` makes it snake and twirl, `curl` bends the free end off the sail.
render_mode cull_disabled, unshaded, shadows_disabled;

instance uniform vec4 yarn_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
instance uniform float flap = 0.0;
instance uniform float curl = 0.0;
instance uniform float seed = 0.0;
uniform float through = 0.0;

void vertex() {
	float z = clamp(VERTEX.z, 0.0, 1.0);
	float s1 = sin(TIME * (19.0 + seed * 5.0) - z * 10.0 + seed * 6.2831);
	float s2 = sin(TIME * (13.0 + seed * 3.0) - z * 7.0 + seed * 2.7);
	float a = (0.012 + 0.05 * flap) * z;
	VERTEX.x += curl * 0.12 * z * z + a * s1 * (0.3 + flap);
	VERTEX.y += a * s2 * flap * 0.8;
}

void fragment() {
	ALBEDO = yarn_color.rgb * (0.85 + 0.15 * UV.x);
	if (through > 0.0) {
		ALPHA = through;
	}
}
