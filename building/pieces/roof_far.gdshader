// A hybrid roof's far look (see BuildPiece.dress, WallBaker): a thin slab over each of the roof's
// shaked facets, drawn with textures baked from its own close-up shakes straight on (from above for
// its top, from below for its underside), so rows, staggers and shades line up across the switch and
// only the fine depth changes. The slab's texture coordinates point straight into the bake, and its
// tangents follow the bake's frame, so the baked normals apply as a normal map. The vertex colour's
// alpha says what each part is: 1 the slab's top and underside; 0.5 its narrow edge faces (the
// colour at their edge, not the normals); 0 the trim merged into the same mesh (fascia and barge
// boards, rafters, logs), drawn in its own vertex colour. Until the bake is ready the roof shows its
// close-up look instead, so the plain colour here is never seen in play.
shader_type spatial;

uniform sampler2D baked_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// x and y of the face's normal in the bake's frame (red, green) and how deep it sits (blue: see
// wall_bake.gdshader)
uniform sampler2D baked_surface : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool baked = false;
// How much the baked depth darkens the light from the sky between the shakes, and how rough the
// wood is
uniform float gap_occlusion = 0.6;
uniform float wood_roughness = 0.9;
const vec3 PLAIN = vec3(0.29, 0.22, 0.145);

// Set per piece (see BuildPiece.weather); only the tint and the ghost fade are used here
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform vec3 box_min = vec3(-1.0);
instance uniform vec3 box_max = vec3(1.0);
instance uniform float frame_offset = 0.0;
instance uniform float ghost_fade = 0.0;
const vec3 GHOST_COLOR = vec3(0.6, 0.64, 0.7);

void fragment() {
	vec3 col = PLAIN;
	vec3 s = vec3(0.5, 0.5, 1.0);
	bool trim = COLOR.a < 0.25;
	if (trim) {
		col = COLOR.rgb;
	} else if (baked) {
		col = texture(baked_color, UV).rgb;
		s = texture(baked_surface, UV).rgb;
	}
	vec3 shown = col * tint.rgb;
	if (ghost_fade > 0.0) {
		shown = mix(shown, vec3(dot(shown, vec3(0.3, 0.59, 0.11))), 0.8 * ghost_fade);
		shown = mix(shown, GHOST_COLOR, 0.45 * ghost_fade);
	}
	ALBEDO = shown;
	ROUGHNESS = wood_roughness;
	AO = mix(1.0, s.b, gap_occlusion);
	NORMAL_MAP = COLOR.a > 0.75 ? vec3(s.rg, 1.0) : vec3(0.5, 0.5, 1.0);
	// As the close-up look: no sky reflection on faces turned down or seen almost edge-on (a roof
	// seen along its slope)
	float down = smoothstep(0.1, 0.5, -(INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	float glancing = smoothstep(0.05, 0.4, abs(dot(NORMAL, VIEW)));
	SPECULAR = 0.5 * (1.0 - down) * glancing;
}
