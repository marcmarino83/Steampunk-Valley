// A ghost piece's see-through blueprint blue (see BuildPiece.ghost_material). Every ghost draws
// twice: first with no colour at all (alpha 0), only to mark the nearest ghost surface in the depth
// buffer, then with its colour, which only lands on that nearest surface. So overlapping ghosts
// (and a ghost's own back faces) never stack into brighter patches: one even blue wherever any
// ghost is. `rim` brightens toward the silhouette (for furniture models, which have no edge lines).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.32, 0.6, 1.0, 0.25);
uniform vec3 rim_color : source_color = vec3(0.7, 0.88, 1.0);
uniform float rim = 0.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = rim * pow(1.0 - facing, 3.0);
	ALBEDO = mix(color.rgb, rim_color, clamp(edge * 2.0, 0.0, 1.0));
	ALPHA = clamp(color.a + edge, 0.0, 1.0);
}
