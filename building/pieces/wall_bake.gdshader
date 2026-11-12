// Bakes a wood wall's close-up look into its far look's textures (see WallBaker): the close-up mesh
// drawn unlit, straight on, by an orthographic camera looking down -Z with no turn (so its view
// space is the piece's own space). Two passes:
//   0  colour: exactly the close-up look's albedo (piece_detail.gdshader), with no tint
//   1  surface: the face's normal, the close-up normal map included (x and y in red and green), and
//      how deep the face sits (blue: the gaps' dark core 0.35, plank faces 1), stored as is
// The viewport turns what's drawn from linear to sRGB, so pass 1 writes its values turned the other
// way first, to be stored unchanged.
shader_type spatial;
render_mode unshaded;

uniform sampler2D wood_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wood_color = vec3(0.37, 0.28, 0.185);
uniform vec3 stone_color = vec3(0.38, 0.33, 0.228);
uniform vec3 rope_color = vec3(0.258, 0.159, 0.064);
const float WOOD_MEAN = 0.124;
const float STONE_MEAN = 0.066;
// (as the close-up look's NORMAL_MAP_DEPTH)
const float NORMAL_DEPTH = 0.8;

uniform int bake_pass = 0;
// The camera's distance along +Z from the piece's origin, so a face's depth in the piece is known
uniform float camera_z = 5.0;
// How deep the faces sit: the dark core behind the gaps, and the plank faces in front
uniform float core_depth = 0.03;
uniform float face_depth = 0.08;
uniform float core_shade = 0.35;

varying flat float kind;

void vertex() {
	kind = UV2.x;
}

vec3 linear_from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 col;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (kind < 0.5) {
		vec3 c = texture(wood_albedo, UV).rgb;
		float k = dot(c, vec3(0.3, 0.59, 0.11)) / WOOD_MEAN;
		k = k < 1.0 ? pow(k, 1.25) : 1.0 + (k - 1.0) * 0.3;
		col = wood_color * min(k, 1.3);
		nm = texture(wood_normal, UV).rgb;
	} else if (kind < 1.5) {
		vec3 c = texture(stone_albedo, UV).rgb;
		float k = dot(c, vec3(0.3, 0.59, 0.11)) / STONE_MEAN;
		k = k < 1.0 ? mix(0.55, 1.0, k) : 1.0 + (k - 1.0) * 0.25;
		col = stone_color * min(k, 1.35);
		nm = texture(stone_normal, UV).rgb;
	} else if (kind < 2.5) {
		float s = fract(UV.x * 34.0 + UV.y * 1.5);
		float strand = smoothstep(0.0, 0.3, s) * (1.0 - smoothstep(0.7, 1.0, s));
		col = rope_color * mix(0.5, 1.25, strand);
	} else if (kind < 3.5) {
		col = vec3(0.12, 0.115, 0.11);
	} else {
		col = vec3(0.06, 0.055, 0.05);
	}
	if (bake_pass == 0) {
		ALBEDO = col * COLOR.rgb;
	} else {
		// The normal map applied as Godot applies NORMAL_MAP (view space here is the piece's space)
		vec3 m;
		m.xy = nm.xy * 2.0 - 1.0;
		m.z = sqrt(max(0.0, 1.0 - dot(m.xy, m.xy)));
		vec3 n = normalize(mix(NORMAL, TANGENT * m.x + BINORMAL * m.y + NORMAL * m.z, NORMAL_DEPTH));
		float depth = camera_z + VERTEX.z;
		float shade = mix(core_shade, 1.0, smoothstep(core_depth, face_depth, depth));
		ALBEDO = linear_from_srgb(clamp(vec3(n.xy * 0.5 + 0.5, shade), 0.0, 1.0));
	}
}
