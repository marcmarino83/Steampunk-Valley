// The close-up look of building pieces (see PieceDetail): weathered silver-grey timber from the Wood
// Planks Dirt maps, stone from Rock Wall 13, rope, iron and dark mortar, all in one mesh. UV2.x
// says which each part is; the vertex colour is that part's own shade.
shader_type spatial;

uniform sampler2D wood_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_rough : filter_linear_mipmap_anisotropic, repeat_enable;
// How grey the wood goes (1 = no colour left), how light, and the silver tone it takes
uniform float grey = 0.8;
uniform float wood_light = 1.85;
uniform vec3 silver = vec3(1.0, 0.97, 0.91);

// Set per piece (see BuildPiece.weather); the others are only there for the distance version
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform vec3 box_min = vec3(-1.0);
instance uniform vec3 box_max = vec3(1.0);
instance uniform float frame_offset = 0.0;

varying flat float kind;

void vertex() {
	kind = UV2.x;
}

void fragment() {
	vec3 col;
	float rough = 0.85;
	float metal = 0.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (kind < 0.5) {
		vec3 c = texture(wood_albedo, UV).rgb;
		float g = dot(c, vec3(0.3, 0.59, 0.11));
		col = mix(c, vec3(g), grey) * silver * wood_light;
		rough = clamp(texture(wood_rough, UV).r + 0.08, 0.0, 1.0);
		nm = texture(wood_normal, UV).rgb;
	} else if (kind < 1.5) {
		vec3 c = texture(stone_albedo, UV).rgb;
		float g = dot(c, vec3(0.3, 0.59, 0.11));
		col = mix(c, vec3(g), 0.5) * vec3(1.0, 0.97, 0.92) * 2.0;
		rough = clamp(texture(stone_rough, UV).r, 0.5, 1.0);
		nm = texture(stone_normal, UV).rgb;
	} else if (kind < 2.5) {
		// Rope: twisted strands as slanted stripes
		float s = fract(UV.x * 26.0 + UV.y * 1.0);
		float strand = smoothstep(0.0, 0.35, s) * (1.0 - smoothstep(0.65, 1.0, s));
		col = mix(vec3(0.33, 0.27, 0.18), vec3(0.6, 0.51, 0.36), strand);
		rough = 0.95;
	} else if (kind < 3.5) {
		col = vec3(0.12, 0.115, 0.11);
		rough = 0.55;
		metal = 0.55;
	} else {
		col = vec3(0.06, 0.055, 0.05);
		rough = 1.0;
	}
	ALBEDO = col * COLOR.rgb * tint.rgb;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.8;
}
