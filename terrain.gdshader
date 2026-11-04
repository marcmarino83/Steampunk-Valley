// Paints the ground: grass on gentle slopes, dirt patches, mossy forest floor under the trees,
// wet mud by the water, gravel trails, and textured rock wherever it's steep; then whatever
// has been painted on with the Texture Brush. Also used on boulders, which gives them mossy tops.
//
// Every layer has a height (from its texture's Displacement map, or a soft pattern for the
// plain grass and dirt), and layers blend by height rather than fading evenly: where gravel
// meets grass, the stones show through first and the grass fills the low spots between them.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A grayscale cloudy pattern, sampled at several sizes to break up the colors
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 grass_dark : source_color = vec3(0.13, 0.20, 0.06);
uniform vec3 grass_light : source_color = vec3(0.30, 0.34, 0.12);
uniform vec3 grass_dry : source_color = vec3(0.40, 0.36, 0.19);
uniform vec3 dirt_color : source_color = vec3(0.28, 0.24, 0.17);

// The textured ground materials. Each repeats every so many meters.
group_uniforms forest_floor;
uniform sampler2D forest_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_height : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float forest_scale = 3.0;
uniform vec3 forest_tint : source_color = vec3(0.5, 0.52, 0.4);
group_uniforms gravel_path;
uniform sampler2D gravel_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_height : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float gravel_scale = 2.5;
uniform vec3 gravel_tint : source_color = vec3(0.92, 0.86, 0.78);
group_uniforms rock_cliff;
uniform sampler2D rock_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_height : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float rock_scale = 4.0;
uniform vec3 rock_tint : source_color = vec3(0.78, 0.76, 0.72);
group_uniforms;
// How strongly the textures' normal maps tilt the lighting (0 = flat, 1 = as made)
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// How soft height blending is: small = crisp edges along stones, large = closer to a plain fade
uniform float height_blend_depth : hint_range(0.01, 1.0) = 0.2;

// Rock starts showing where the ground is steeper than this (1 = flat, 0 = a cliff)...
uniform float rock_start : hint_range(0.0, 1.0) = 0.62;
// ...and fully covers it from here
uniform float rock_full : hint_range(0.0, 1.0) = 0.45;
// Height of the water surface; the valley sets this to match
uniform float water_height = 42.0;
// How far above the water the ground stays dark and muddy
uniform float shore_width = 1.5;
// Churned-up mud with rain puddles, around the crash site. The valley sets these;
// a radius of 0 means no mud anywhere.
uniform vec2 mud_center = vec2(0.0);
uniform float mud_radius = 0.0;
// Ground burnt black around the crashed engine. A radius of 0 means no scorch mark.
uniform vec2 scorch_center = vec2(0.0);
uniform float scorch_radius = 0.0;
// Editor planning view: tint the ground by how steep it is. The valley switches this on
// from its Show Slope View checkbox, and always off in the game.
uniform bool slope_view = false;
// The steepest ground the player can walk up, in degrees
uniform float walk_limit_degrees = 45.0;
// What the valley works out about the ground, one pixel per terrain grid point: how worn
// into a trail it is (0 = untouched, 1 = trail), how ragged that trail's edge is (its Edge
// Noise), and how much forest floor the trees here spread over it. The valley fills these
// in, along with where the map starts and its grid spacing.
uniform sampler2D ground_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D edge_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D forest_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 ground_map_info = vec4(0.0, 0.0, 1.0, 1.0);
// What's been painted with the Texture Brush, one pixel per meter: how much grass, dirt,
// forest floor and gravel (paint_a's red, green, blue, alpha) and rock (paint_b's red).
uniform sampler2D paint_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D paint_b : hint_default_black, filter_linear, repeat_disable;
// Where the painted map starts (x, z), and how many meters each pixel covers
uniform vec4 paint_info = vec4(0.0, 0.0, 1.0, 0.0);

varying vec3 world_pos;
varying vec3 world_normal;

// One layer of ground: its color, which way it faces (in the world), how rough and how
// shadowed in its crevices it is, and how high its surface stands (for height blending)
struct Ground {
	vec3 albedo;
	vec3 normal;
	float roughness;
	float ao;
	float height;
};

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// How much of `top` shows over `base`, when `amount` of it has been laid on (0 to 1). The
// higher parts of each surface win: a little gravel shows only its tallest stones, a little
// grass over gravel only fills the hollows between them.
float height_mix(float base_height, float top_height, float amount) {
	float a = base_height + (1.0 - amount);
	float b = top_height + amount;
	float level = max(a, b) - height_blend_depth;
	float wa = max(a - level, 0.0);
	float wb = max(b - level, 0.0);
	return wb / max(wa + wb, 0.0001);
}

Ground mix_ground(Ground a, Ground b, float t) {
	Ground g;
	g.albedo = mix(a.albedo, b.albedo, t);
	g.normal = normalize(mix(a.normal, b.normal, t));
	g.roughness = mix(a.roughness, b.roughness, t);
	g.ao = mix(a.ao, b.ao, t);
	g.height = mix(a.height, b.height, t);
	return g;
}

// A normal map's tilt (from its red and green), as a tangent-space normal. The maps are in
// OpenGL style (green = up in the picture), which points against Godot's texture v.
vec3 unpack_normal(vec4 texel) {
	vec2 xy = (texel.rg * 2.0 - 1.0) * vec2(1.0, -1.0) * normal_strength;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// A texture laid flat on the ground (looking down), tilting the ground's own normal
vec3 flat_normal(vec3 tn, vec3 n) {
	return normalize(vec3(tn.x + n.x, abs(tn.z) * n.y, tn.y + n.z));
}

// Forest floor and gravel: laid flat, with a second, larger and turned copy blended in by a
// slow pattern, and a gentle brightness wander, so the repeats don't line up into a grid
Ground flat_layer(sampler2D albedo_map, sampler2D normal_map, sampler2D rough_map, sampler2D height_map, float scale, vec3 tint, vec3 n, float large, float medium) {
	vec2 uv = world_pos.xz / scale;
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * world_pos.xz / (scale * 1.7) + vec2(0.37, 0.71);
	float other = smoothstep(0.35, 0.65, medium) * 0.5;
	Ground g;
	g.albedo = mix(texture(albedo_map, uv).rgb, texture(albedo_map, uv2).rgb, other) * tint * (0.85 + large * 0.3);
	g.normal = flat_normal(unpack_normal(texture(normal_map, uv)), n);
	// (never quite as glossy as the scans: the ground is dry and dusty)
	g.roughness = mix(0.6, 1.0, texture(rough_map, uv).r);
	g.ao = 1.0;
	g.height = mix(texture(height_map, uv).r, texture(height_map, uv2).r, other);
	return g;
}

// Rock, projected from three sides and blended by which way the ground faces ("triplanar"),
// so it doesn't stretch down cliffs
Ground rock_layer(vec3 n, float large) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 p = world_pos / rock_scale;
	vec2 uvx = p.zy;
	vec2 uvy = p.xz;
	vec2 uvz = p.xy;
	Ground g;
	g.albedo = (texture(rock_albedo, uvx).rgb * w.x + texture(rock_albedo, uvy).rgb * w.y + texture(rock_albedo, uvz).rgb * w.z) * rock_tint * (0.85 + large * 0.3);
	// Each side's normal map tilts the surface around its own axis ("whiteout" blend)
	vec3 tx = unpack_normal(texture(rock_normal, uvx));
	vec3 ty = unpack_normal(texture(rock_normal, uvy));
	vec3 tz = unpack_normal(texture(rock_normal, uvz));
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	g.normal = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	g.roughness = mix(0.55, 1.0, texture(rock_roughness, uvx).r * w.x + texture(rock_roughness, uvy).r * w.y + texture(rock_roughness, uvz).r * w.z);
	g.ao = texture(rock_ao, uvx).r * w.x + texture(rock_ao, uvy).r * w.y + texture(rock_ao, uvz).r * w.z;
	g.height = texture(rock_height, uvx).r * w.x + texture(rock_height, uvy).r * w.y + texture(rock_height, uvz).r * w.z;
	return g;
}

Ground gravel_layer(vec3 n, float large, float medium) {
	Ground g = flat_layer(gravel_albedo, gravel_normal, gravel_roughness, gravel_height, gravel_scale, gravel_tint, n, large, medium);
	g.ao = texture(gravel_ao, world_pos.xz / gravel_scale).r;
	return g;
}

Ground forest_layer(vec3 n, float large, float medium) {
	return flat_layer(forest_albedo, forest_normal, forest_roughness, forest_height, forest_scale, forest_tint, n, large, medium);
}

// The plain grass: big patches of darker and lighter green, some dry areas, fine speckle.
// It sits low, so other materials show over it first.
Ground grass_layer(vec3 n, float large, float medium, float small) {
	Ground g;
	g.albedo = mix(grass_dark, grass_light, smoothstep(0.35, 0.65, large + (medium - 0.5) * 0.5));
	g.albedo = mix(g.albedo, grass_dry, smoothstep(0.62, 0.78, large) * 0.6);
	g.albedo *= 0.8 + small * 0.4;
	g.normal = n;
	g.roughness = 0.95;
	g.ao = 1.0;
	g.height = 0.15 + small * 0.3;
	return g;
}

// Bare dirt, flecked with grit
Ground dirt_layer(vec3 n, float small) {
	Ground g;
	g.albedo = dirt_color * (0.75 + small * 0.5);
	g.normal = n;
	g.roughness = 0.97;
	g.ao = 1.0;
	g.height = 0.3 + small * 0.3;
	return g;
}

void fragment() {
	vec3 n = normalize(world_normal);

	// The same pattern at big, medium and small sizes
	float large = texture(detail_noise, world_pos.xz * 0.003).r;
	float medium = texture(detail_noise, world_pos.xz * 0.027).r;
	float small = texture(detail_noise, world_pos.xz * 0.31).r;

	// ---- The automatic ground ----
	Ground g = grass_layer(n, large, medium, small);
	Ground dirt = dirt_layer(n, small);
	// Bare dirt patches
	float patches = smoothstep(0.60, 0.70, medium * 0.75 + large * 0.25);
	g = mix_ground(g, dirt, patches);
	// Fairly steep ground (but not cliff) wears down to bare, stony soil
	float worn = smoothstep(0.86, 0.70, n.y + (medium - 0.5) * 0.2);
	g = mix_ground(g, dirt, worn * 0.85);

	// Forest floor under the trees, with a ragged edge where the woods give way to grass
	vec2 map_uv = ((world_pos.xz - ground_map_info.xy) / ground_map_info.zw + 0.5) / vec2(textureSize(ground_map, 0));
	float trail = texture(ground_map, map_uv).r;
	float between = texture(detail_noise, world_pos.xz * 0.11 + vec2(0.53, 0.19)).r;
	float woods = smoothstep(0.35, 0.8, texture(forest_map, map_uv).r + (medium - 0.5) * 0.3 + (between - 0.5) * 0.45 + (small - 0.5) * 0.15);
	if (woods > 0.001) {
		Ground forest = forest_layer(n, large, medium);
		g = mix_ground(g, forest, height_mix(g.height, forest.height, woods));
	}

	// Dark wet mud right by the water
	float shore = 1.0 - smoothstep(water_height, water_height + shore_width, world_pos.y);
	g.albedo = mix(g.albedo, dirt_color * 0.45, shore);
	g.roughness -= shore * 0.35;

	// Around the crash site: ground churned to mud, with a ragged edge, and rain puddles in it
	float churned = 0.0;
	float puddle = 0.0;
	if (mud_radius > 0.0) {
		float ragged = (medium - 0.5) * mud_radius * 0.6;
		churned = 1.0 - smoothstep(mud_radius * 0.5, mud_radius, distance(world_pos.xz, mud_center) + ragged);
		g.albedo = mix(g.albedo, dirt_color * vec3(1.05, 0.95, 0.82) * (0.85 + small * 0.4), churned * 0.85);
		g.roughness -= churned * 0.25;
		float pools = texture(detail_noise, world_pos.xz * 0.06 + vec2(0.37, 0.61)).r;
		puddle = churned * smoothstep(0.72, 0.76, pools);
	}

	// Scorched black around the engine, with a ragged, sooty edge (and no puddles in it)
	if (scorch_radius > 0.0) {
		float ragged = (medium - 0.5) * scorch_radius * 0.7 + (small - 0.5) * scorch_radius * 0.3;
		float burnt = 1.0 - smoothstep(scorch_radius * 0.55, scorch_radius, distance(world_pos.xz, scorch_center) + ragged);
		// Black soot, flecked with pale grey ash
		vec3 soot = mix(vec3(0.018, 0.016, 0.015), vec3(0.085, 0.08, 0.075), smoothstep(0.74, 0.84, small));
		g.albedo = mix(g.albedo, soot, burnt * 0.95);
		puddle *= 1.0 - burnt;
	}

	// Rock wherever it's steep, with a ragged edge where it meets the grass
	float steep = smoothstep(rock_start, rock_full, n.y + (medium - 0.5) * 0.18);
	if (steep > 0.001) {
		Ground rock = rock_layer(n, large);
		g = mix_ground(g, rock, height_mix(g.height, rock.height, steep));
	}

	// Trails: gravel, fraying into the ground at its edges (more raggedly if the trail's
	// Edge Noise is turned up)
	if (trail > 0.001) {
		float ragged = 0.2 + texture(edge_map, map_uv).r * 1.6;
		float fray = smoothstep(0.2, 0.8, trail + ((medium - 0.5) * 0.6 + (small - 0.5) * 0.35) * ragged);
		if (fray > 0.001) {
			Ground gravel = gravel_layer(n, large, medium);
			g = mix_ground(g, gravel, height_mix(g.height, gravel.height, fray));
		}
	}

	// ---- What's been painted on top ----
	if (paint_info.w > 0.0) {
		vec2 paint_uv = (world_pos.xz - paint_info.xy) / paint_info.z / vec2(textureSize(paint_a, 0));
		vec4 pa = texture(paint_a, paint_uv);
		float pb = texture(paint_b, paint_uv).r;
		float coverage = min(pa.r + pa.g + pa.b + pa.a + pb, 1.0);
		if (coverage > 0.003) {
			// The painted materials, each laid over the last by height in proportion to how
			// much of it there is...
			float laid = pa.r;
			Ground painted = grass_layer(n, large, medium, small);
			if (pa.g > 0.002) {
				laid += pa.g;
				painted = mix_ground(painted, dirt, height_mix(painted.height, dirt.height, pa.g / laid));
			}
			if (pa.b > 0.002) {
				laid += pa.b;
				Ground forest = forest_layer(n, large, medium);
				painted = mix_ground(painted, forest, height_mix(painted.height, forest.height, pa.b / laid));
			}
			if (pa.a > 0.002) {
				laid += pa.a;
				Ground gravel = gravel_layer(n, large, medium);
				painted = mix_ground(painted, gravel, height_mix(painted.height, gravel.height, pa.a / laid));
			}
			if (pb > 0.002) {
				laid += pb;
				Ground rock = rock_layer(n, large);
				painted = mix_ground(painted, rock, height_mix(painted.height, rock.height, pb / laid));
			}
			// ...then over the automatic ground, by how much has been painted here
			g = mix_ground(g, painted, height_mix(g.height, painted.height, coverage));
		}
	}

	// Puddles: dark, glassy and dead flat, so they mirror the sky
	g.albedo = mix(g.albedo, vec3(0.06, 0.05, 0.04), puddle * 0.9);
	g.roughness = mix(g.roughness, 0.08, puddle);
	g.normal = normalize(mix(g.normal, n, puddle));

	ALBEDO = g.albedo * mix(1.0, g.ao, 0.6);
	ROUGHNESS = clamp(g.roughness, 0.05, 1.0);
	SPECULAR = mix(0.5, 0.65, puddle);
	AO = g.ao;
	NORMAL = normalize((VIEW_MATRIX * vec4(g.normal, 0.0)).xyz);

	// Slope view: green = easy walking, yellow = close to the limit, red = too steep to climb
	if (slope_view) {
		float angle = degrees(acos(clamp(n.y, -1.0, 1.0)));
		vec3 tint = vec3(0.15, 0.75, 0.2);
		if (angle >= walk_limit_degrees) {
			tint = vec3(0.9, 0.15, 0.1);
		} else if (angle >= walk_limit_degrees - 8.0) {
			tint = vec3(0.95, 0.8, 0.1);
		}
		ALBEDO = mix(ALBEDO, tint, 0.7);
	}
}
