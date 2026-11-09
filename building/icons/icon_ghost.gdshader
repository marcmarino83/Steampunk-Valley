shader_type spatial;
// The faint, see-through neighbours in a build icon (see IconStudio): pale, nearly clear where a
// face looks toward the camera and brighter only right at its outline, so the shape reads as a
// light sketch behind the solid piece. The depth pre-pass draws only each ghost's nearest surface,
// so its layers (the plain look and the detailed one over it) don't pile up.
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.93, 0.87, 0.75, 1.0);
// How much a face seen straight on shows, and how much more its outline does
uniform float fill = 0.045;
uniform float edge = 0.75;

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = color.rgb;
	ALPHA = clamp(fill + edge * pow(rim, 4.0), 0.0, 1.0) * color.a;
}
