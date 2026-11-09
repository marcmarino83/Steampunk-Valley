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
// Base colours (linear): warm weathered grey-brown wood (#7d705f), warm tan-grey stone (#8a8272),
// hemp rope (#8b6f47). The textures only give light and dark variation round these: their light
// blotches are squashed so nothing goes near white, while their dark grain is kept.
// (Set a little above the swatches' own values: rendered under the valley's light, with the gaps,
// grain and edges darkening them, they average out near the swatches.)
uniform vec3 wood_color = vec3(0.37, 0.28, 0.185);
uniform vec3 stone_color = vec3(0.38, 0.33, 0.228);
uniform vec3 rope_color = vec3(0.258, 0.159, 0.064);
// The textures' average brightness (measured), so they vary round 1
const float WOOD_MEAN = 0.124;
const float STONE_MEAN = 0.066;

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
		float k = dot(c, vec3(0.3, 0.59, 0.11)) / WOOD_MEAN;
		// Dark grain kept (a touch stronger), light blotches flattened
		k = k < 1.0 ? pow(k, 1.25) : 1.0 + (k - 1.0) * 0.3;
		col = wood_color * min(k, 1.3);
		rough = clamp(texture(wood_rough, UV).r + 0.12, 0.0, 1.0);
		nm = texture(wood_normal, UV).rgb;
	} else if (kind < 1.5) {
		vec3 c = texture(stone_albedo, UV).rgb;
		float k = dot(c, vec3(0.3, 0.59, 0.11)) / STONE_MEAN;
		k = k < 1.0 ? mix(0.55, 1.0, k) : 1.0 + (k - 1.0) * 0.25;
		col = stone_color * min(k, 1.35);
		rough = clamp(texture(stone_rough, UV).r, 0.6, 1.0);
		nm = texture(stone_normal, UV).rgb;
	} else if (kind < 2.5) {
		// Rope: twisted hemp, its strands as slanted stripes, darker in the twists
		float s = fract(UV.x * 34.0 + UV.y * 1.5);
		float strand = smoothstep(0.0, 0.3, s) * (1.0 - smoothstep(0.7, 1.0, s));
		col = rope_color * mix(0.5, 1.25, strand);
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
