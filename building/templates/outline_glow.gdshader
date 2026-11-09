// A soft see-through glow that's strongest where a surface turns away from you, so each piece reads
// as a glowing outline with a faint fill. Ghost pieces wear it in blue in place of their look; a
// template's preview wears it in green or red over its real look (as an overlay).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform vec4 glow_color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
// How strong the faint fill is, and the bright edge
uniform float fill = 0.12;
uniform float edge = 0.85;
// How sharply the edge falls off (higher: thinner)
uniform float sharpness = 2.5;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, sharpness);
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(fill + rim * edge, 0.0, 1.0) * glow_color.a;
}
