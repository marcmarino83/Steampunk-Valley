// The crisp outline on a ghost piece: its plain shape's outer edges and creases as thin lines
// (see BuildPiece.ghost_edges), a slightly brighter blue than its fill. Drawn after the ghosts'
// depth pass and pulled a hair toward the camera, so the edges you'd see show and the ones behind a
// ghost's own faces (or another ghost in front) stay hidden.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.82, 1.0, 0.95);
// How far toward the camera the lines are pulled, as a share of their distance
uniform float pull = 0.003;

void vertex() {
	vec4 seen = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	seen.xyz *= 1.0 - pull;
	POSITION = PROJECTION_MATRIX * seen;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
