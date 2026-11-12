// A hybrid floor's or foundation's far look (see BuildPiece.dress, WallBaker.FLOORS): a thin slab over
// its top, drawn with textures baked from its own close-up look straight from above, so planks,
// gaps, flagstones and shades line up across the switch and only the fine depth changes; and its
// sides (a floor's base, a foundation's logs and stone courses, its dark core) as real geometry, drawn
// exactly as the close-up look draws them (piece_detail.gdshader: the same textures, texture
// coordinates, shades and normal maps), so its edges and sides don't change at the switch at all.
// The vertex colour's alpha says what each part is: 1 the slab's top; 0.5 its narrow edge faces and
// its underside (the colour at the top's edge, no normal map); 0 the close-up sides, whose UV2.x says
// what they're made of (wood, stone, rope, iron, dark) and whose colour is their shade. Until the bake
// is ready the piece shows its close-up look instead, so the plain colour here is never seen in play.
shader_type spatial;

uniform sampler2D baked_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// x and y of the face's normal in the bake's frame (red, green) and how deep it sits (blue: see
// wall_bake.gdshader)
uniform sampler2D baked_surface : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool baked = false;
// How much the baked depth darkens the light from the sky in the gaps, and how rough the top is
uniform float gap_occlusion = 0.6;
uniform float top_roughness = 0.88;
const vec3 PLAIN = vec3(0.29, 0.22, 0.145);

// The close-up look's (piece_detail.gdshader), for the sides
uniform sampler2D wood_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wood_color = vec3(0.37, 0.28, 0.185);
uniform vec3 stone_color = vec3(0.38, 0.33, 0.228);
uniform vec3 rope_color = vec3(0.258, 0.159, 0.064);
const float WOOD_MEAN = 0.124;
const float STONE_MEAN = 0.066;

// Set per piece (see BuildPiece.weather); only the tint and the ghost fade are used here
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform vec3 box_min = vec3(-1.0);
instance uniform vec3 box_max = vec3(1.0);
instance uniform float frame_offset = 0.0;
instance uniform float ghost_fade = 0.0;
const vec3 GHOST_COLOR = vec3(0.6, 0.64, 0.7);

varying flat float kind;

void vertex() {
	kind = UV2.x;
}

void fragment() {
	vec3 col;
	float rough = top_roughness;
	float metal = 0.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float nm_depth = 1.0;
	AO = 1.0;
	if (COLOR.a < 0.25) {
		// The close-up sides, exactly as piece_detail.gdshader draws them
		nm_depth = 0.8;
		if (kind < 0.5) {
			vec3 c = texture(wood_albedo, UV).rgb;
			float k = dot(c, vec3(0.3, 0.59, 0.11)) / WOOD_MEAN;
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
		col *= COLOR.rgb;
	} else {
		// The baked top (and, unmapped, its narrow edges and underside)
		col = PLAIN;
		vec3 s = vec3(0.5, 0.5, 1.0);
		if (baked) {
			col = texture(baked_color, UV).rgb;
			s = texture(baked_surface, UV).rgb;
		}
		AO = mix(1.0, s.b, gap_occlusion);
		if (COLOR.a > 0.75) {
			nm = vec3(s.rg, 1.0);
		}
	}
	vec3 shown = col * tint.rgb;
	if (ghost_fade > 0.0) {
		shown = mix(shown, vec3(dot(shown, vec3(0.3, 0.59, 0.11))), 0.8 * ghost_fade);
		shown = mix(shown, GHOST_COLOR, 0.45 * ghost_fade);
	}
	ALBEDO = shown;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = nm_depth;
	// As the close-up look: no sky reflection on faces turned down or seen almost edge-on (a floor's
	// top seen from standing height far off)
	float down = smoothstep(0.1, 0.5, -(INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	float glancing = smoothstep(0.05, 0.4, abs(dot(normalize(NORMAL), VIEW)));
	SPECULAR = 0.5 * (1.0 - down) * glancing;
}
