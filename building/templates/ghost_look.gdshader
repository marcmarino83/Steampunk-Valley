// What a ghost piece wears in place of its look (see BuildPiece.ghost_material): its full detailed
// shape (every plank, shake and rafter) in a soft see-through grey, a little lighter and stronger
// toward the edges, where a surface turns away from you.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 fill_color : source_color = vec4(0.604, 0.604, 0.604, 0.3);
uniform vec4 edge_color : source_color = vec4(0.76, 0.76, 0.76, 0.8);
// How sharply the edge falls off (higher: thinner)
uniform float sharpness = 2.5;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, sharpness);
	ALBEDO = mix(fill_color.rgb, edge_color.rgb, rim);
	ALPHA = clamp(mix(fill_color.a, edge_color.a, rim), 0.0, 1.0);
}
