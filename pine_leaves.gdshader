// Pine needles: lit mostly as if they face the sky, so the undersides of each
// tier of branches aren't pitch black, with sunlight glowing through the edges.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 needle_color : source_color = vec3(0.09, 0.17, 0.08);

void fragment() {
	ALBEDO = needle_color;
	vec3 sky = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, sky, 0.55));
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.10, 0.15, 0.05);
}
