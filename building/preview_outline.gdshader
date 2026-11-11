// A thin outline round a preview (see PreviewLook): the piece's own shape drawn again, its back
// faces only, grown outward on screen by a constant number of pixels at any distance, so a thin line
// of this colour shows round its silhouette. It grows away from the mesh's middle (outline_center,
// set by PreviewLook.wear), not along the normals: the pieces have hard edges (each flat face its
// own normals), and back faces pushed along those just slide behind the front ones, drawing nothing.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The line's width on screen, in pixels
uniform float width_px = 1.5;
// The mesh's middle, in its own space. (Its own slot, the last of the 16: an instance's uniforms are
// shared by all its materials by slot, and the pieces' shaders fill the first ones, tint first.)
instance uniform vec3 outline_center : instance_index(15) = vec3(0.0);

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// The sun's shadow map is drawn with a flat (orthographic) projection, where a "pixel" is huge:
	// the outline casts no shadow (the piece's own looks cast it)
	bool flat_view = PROJECTION_MATRIX[3][3] > 0.5;
	vec4 middle = MODELVIEW_MATRIX * vec4(outline_center, 1.0);
	// Away from the middle as seen on screen (along the normal for a vertex right on it)
	vec2 away = view.xy / max(-view.z, 0.05) - middle.xy / max(-middle.z, 0.05);
	if (length(away) < 1e-5) {
		away = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xy;
	}
	// How big one pixel is at this depth
	float per_px = 2.0 * max(-view.z, 0.05) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	view.xy += normalize(away + vec2(1e-6)) * width_px * per_px;
	POSITION = PROJECTION_MATRIX * view;
	if (flat_view) {
		// (outside the view: nothing drawn)
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	ALBEDO = color.rgb;
}
