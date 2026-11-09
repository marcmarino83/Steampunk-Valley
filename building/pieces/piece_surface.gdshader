// The surface of building pieces: Poly Haven wood planks (or stone, or reed thatch on roof tops)
// mapped at real-world scale, so planks run on continuously from one piece to the next with no
// seams or stretching, plus a slight colour difference per piece and darker grime toward edges and
// the foot of upright faces. Set up by PieceRegistry; each piece passes its tint and box.
//
// Mapping modes:
//   0  house frame: world positions turned by the piece's own turn folded into 45° steps, so pieces
//      snapped together (at 90° or 45° to each other) share one frame. Flat faces: planks along the
//      frame's X. Upright faces: planks run level. Sloped faces: planks run down the slope.
//   1  ring: upright faces mapped round the piece's origin (the middle of the ring that curved walls
//      and round floors share), planks running round the curve; flat faces world-aligned.
//   2  cone: planks running down from the tip.
//   3  along X / 4  along Y: the grain along a beam (X) or a post (Y), in the piece's own space.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D wood_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_rough : filter_linear_mipmap_anisotropic, repeat_enable;
// Stone (for stone pieces) or reed thatch (on roof tops)
uniform sampler2D alt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alt_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alt_rough : filter_linear_mipmap_anisotropic, repeat_enable;

uniform int mode = 0;
// Roof tops (sloped faces facing up) get the other texture (thatch)
uniform bool alt_on_top = false;
// Everything gets the other texture (stone)
uniform bool alt_everywhere = false;
// How many meters one copy of the texture covers
uniform float tile_size = 2.0;
uniform float ring_radius = 2.6131259;
uniform float normal_strength = 1.0;
// How dark the grime gets at edges and at the foot of upright faces
uniform float edge_grime = 0.32;
uniform float foot_grime = 0.28;

instance uniform vec4 tint : source_color = vec4(1.0);
// Added to the piece's turn before folding (the 45° triangle sits 22.5° off the grid about its
// middle), so its frame matches the pieces it joins
instance uniform float frame_offset = 0.0;
instance uniform vec3 box_min = vec3(-1.0);
instance uniform vec3 box_max = vec3(1.0);

varying vec3 v_world;
varying vec3 v_frame;
varying vec3 v_frame_normal;
varying vec3 v_local;
varying vec3 v_local_normal;
varying float v_fold;

// Turns about Y: (x cos a + z sin a, y, -x sin a + z cos a)
vec3 turn_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 forward = MODEL_MATRIX[2].xyz;
	float yaw = atan(forward.x, forward.z) + frame_offset;
	float step = 0.78539816;
	v_fold = yaw - round(yaw / step) * step;
	v_frame = turn_y(v_world, -v_fold);
	v_frame_normal = turn_y(world_normal, -v_fold);
	v_local = VERTEX;
	v_local_normal = NORMAL;
}

void fragment() {
	// uv: x across the planks, y along them (the textures' planks and reeds run down the image).
	// T and B: which way uv.x and uv.y grow, in the world (for the normal map).
	vec2 uv;
	vec3 T;
	vec3 B;
	vec3 N;
	bool alt = alt_everywhere;
	vec3 ln = normalize(v_local_normal);
	vec3 lp = v_local;
	if (mode == 0) {
		vec3 p = v_frame;
		vec3 n = normalize(v_frame_normal);
		if (abs(n.y) > 0.97) {
			uv = vec2(p.z, p.x);
			T = vec3(0.0, 0.0, 1.0);
			B = vec3(1.0, 0.0, 0.0);
		} else if (abs(n.y) < 0.03) {
			vec3 t = normalize(vec3(-n.z, 0.0, n.x));
			uv = vec2(-p.y, dot(p, t));
			T = vec3(0.0, -1.0, 0.0);
			B = t;
		} else {
			vec3 up_slope = normalize(vec3(0.0, 1.0, 0.0) - n * n.y);
			vec3 t = normalize(cross(n, up_slope));
			uv = vec2(dot(p, t), -dot(p, up_slope));
			T = t;
			B = -up_slope;
			alt = alt || (alt_on_top && n.y > 0.0);
		}
		T = turn_y(T, v_fold);
		B = turn_y(B, v_fold);
		N = turn_y(n, v_fold);
	} else {
		if (mode == 1) {
			if (abs(ln.y) > 0.97) {
				// Flat faces line up with the world, so wedges turned any way match
				uv = vec2(v_world.z, v_world.x);
				T = (inverse(MODEL_MATRIX) * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
				B = (inverse(MODEL_MATRIX) * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
			} else {
				float a = atan(lp.x, lp.z);
				uv = vec2(-lp.y, a * ring_radius);
				T = vec3(0.0, -1.0, 0.0);
				B = vec3(cos(a), 0.0, -sin(a));
			}
		} else if (mode == 2) {
			float a = atan(lp.x, lp.z);
			uv = vec2(a * ring_radius, length(lp.xz));
			T = vec3(cos(a), 0.0, -sin(a));
			B = vec3(sin(a), 0.0, cos(a));
			alt = alt || (alt_on_top && ln.y > 0.03);
		} else if (mode == 3) {
			if (abs(ln.x) > 0.7) {
				uv = vec2(lp.z, lp.y);
				T = vec3(0.0, 0.0, 1.0);
				B = vec3(0.0, 1.0, 0.0);
			} else if (abs(ln.y) > abs(ln.z)) {
				uv = vec2(lp.z, lp.x);
				T = vec3(0.0, 0.0, 1.0);
				B = vec3(1.0, 0.0, 0.0);
			} else {
				uv = vec2(lp.y, lp.x);
				T = vec3(0.0, 1.0, 0.0);
				B = vec3(1.0, 0.0, 0.0);
			}
		} else {
			if (abs(ln.y) > 0.7) {
				uv = vec2(lp.x, lp.z);
				T = vec3(1.0, 0.0, 0.0);
				B = vec3(0.0, 0.0, 1.0);
			} else if (abs(ln.x) > abs(ln.z)) {
				uv = vec2(lp.z, lp.y);
				T = vec3(0.0, 0.0, 1.0);
				B = vec3(0.0, 1.0, 0.0);
			} else {
				uv = vec2(lp.x, lp.y);
				T = vec3(1.0, 0.0, 0.0);
				B = vec3(0.0, 1.0, 0.0);
			}
		}
		T = (MODEL_MATRIX * vec4(T, 0.0)).xyz;
		B = (MODEL_MATRIX * vec4(B, 0.0)).xyz;
		N = (MODEL_MATRIX * vec4(ln, 0.0)).xyz;
	}
	uv /= tile_size;

	vec3 color;
	vec3 nm;
	float rough;
	if (alt) {
		color = texture(alt_albedo, uv).rgb;
		nm = texture(alt_normal, uv).rgb;
		rough = texture(alt_rough, uv).r;
	} else {
		color = texture(wood_albedo, uv).rgb;
		nm = texture(wood_normal, uv).rgb;
		rough = texture(wood_rough, uv).r;
	}
	// OpenGL-style normal map: green points up the image, against uv.y
	nm = nm * 2.0 - 1.0;
	nm.xy *= normal_strength;
	vec3 bent = normalize(normalize(T) * nm.x - normalize(B) * nm.y + normalize(N) * nm.z);

	// Grime: darker toward the piece's edges (on the face's own two directions) and the foot of
	// upright faces
	vec3 to_edge = min(lp - box_min, box_max - lp);
	vec3 facing = abs(ln);
	float nearest = 10.0;
	if (facing.x < 0.7) nearest = min(nearest, to_edge.x);
	if (facing.y < 0.7) nearest = min(nearest, to_edge.y);
	if (facing.z < 0.7) nearest = min(nearest, to_edge.z);
	float edge = 1.0 - smoothstep(0.0, 0.2, nearest);
	float foot = facing.y < 0.3 ? 1.0 - smoothstep(0.0, 0.8, lp.y - box_min.y) : 0.0;
	float grime = clamp(edge * edge_grime + foot * foot_grime, 0.0, 0.55);

	// Weathered silver-grey wood, to match the close-up look (piece_detail.gdshader) it stands in for
	if (!alt) {
		float k = dot(color, vec3(0.3, 0.59, 0.11)) / 0.124;
		k = k < 1.0 ? pow(k, 1.25) : 1.0 + (k - 1.0) * 0.3;
		color = vec3(0.37, 0.28, 0.185) * min(k, 1.3) * 0.85;
	} else {
		float k = dot(color, vec3(0.3, 0.59, 0.11)) / 0.066;
		k = k < 1.0 ? mix(0.55, 1.0, k) : 1.0 + (k - 1.0) * 0.25;
		color = vec3(0.38, 0.33, 0.228) * min(k, 1.35);
	}
	ALBEDO = color * tint.rgb * (1.0 - grime);
	ROUGHNESS = clamp(rough + grime * 0.15, 0.0, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
}
