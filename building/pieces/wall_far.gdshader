// A hybrid wood wall's far look (see BuildPiece.dress, WallBaker): its plain box, drawn with
// textures baked from its own close-up look straight on, so every board, joint, stagger and shade
// lines up across the switch and only the fine depth changes. The bake is laid on by the piece's
// own X and Y, on both faces (the planks run right through the wall, so its back is the same layout
// seen from behind) and on the narrow faces (their edge of the bake). Until the bake is ready it's
// drawn in the wood's plain colour.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D baked_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// x and y of the face's normal (red, green) and how deep it sits (blue: see wall_bake.gdshader)
uniform sampler2D baked_surface : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool baked = false;
// The bake's lower-left corner and size, in the piece's X and Y
uniform vec2 bake_min = vec2(-1.0, 0.0);
uniform vec2 bake_size = vec2(2.0, 2.0);
// How much the baked depth darkens the light from the sky in the gaps, and how rough the wood is
// (the close-up look's rough maps average about this)
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

varying vec3 v_local;
varying vec3 v_local_normal;

void vertex() {
	v_local = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	vec2 uv = vec2((v_local.x - bake_min.x) / bake_size.x, 1.0 - (v_local.y - bake_min.y) / bake_size.y);
	vec3 ln = normalize(v_local_normal);
	vec3 n = ln;
	vec3 col = PLAIN;
	float occlusion = 1.0;
	if (baked) {
		col = texture(baked_color, uv).rgb;
		vec3 s = texture(baked_surface, uv).rgb;
		occlusion = mix(1.0, s.b, gap_occlusion);
		// The faces the bake was drawn on (front and back) take its normal, mirrored front to back
		if (abs(ln.z) > 0.5) {
			vec2 xy = s.rg * 2.0 - 1.0;
			n = vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))) * sign(ln.z));
		}
	}
	vec3 shown = col * tint.rgb;
	if (ghost_fade > 0.0) {
		shown = mix(shown, vec3(dot(shown, vec3(0.3, 0.59, 0.11))), 0.8 * ghost_fade);
		shown = mix(shown, GHOST_COLOR, 0.45 * ghost_fade);
	}
	vec3 view_n = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
	vec3 face_n = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ln, 0.0)).xyz);
	// (both sides are drawn: a back face is lit as facing the way it's seen from)
	if (!FRONT_FACING) {
		view_n = -view_n;
		face_n = -face_n;
	}
	ALBEDO = shown;
	ROUGHNESS = wood_roughness;
	AO = occlusion;
	NORMAL = view_n;
	// As the close-up look: no sky reflection on faces turned down or seen almost edge-on
	float down = smoothstep(0.1, 0.5, -(INV_VIEW_MATRIX * vec4(face_n, 0.0)).y);
	float glancing = smoothstep(0.05, 0.4, abs(dot(face_n, VIEW)));
	SPECULAR = 0.5 * (1.0 - down) * glancing;
}
