// The placement state over a preview's real look (see PreviewLook): drawn on top of the piece's
// own materials as its overlay, a light see-through tint, a little stronger toward the edges where
// a surface turns away from you, so the state reads against any background while the real material
// stays clearly visible underneath.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.07);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.3);
// How sharply the edge glow falls off (higher: thinner)
uniform float sharpness = 3.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, sharpness);
	ALBEDO = mix(tint.rgb, rim_color.rgb, rim);
	ALPHA = clamp(mix(tint.a, rim_color.a, rim), 0.0, 1.0);
}
