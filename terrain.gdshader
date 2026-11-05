// Mountains: a map of where water would drain (baked by the Valley) lays green veins down the
// real gullies, while ribs running down the faces carve the rock into light and shade, and the
// rock turns pale higher up.
//
// Paints the ground: grass on gentle slopes, light dry soil on worn ground and bare patches,
// dark damp soil in hollows and where grass gives way to rock, mossy forest floor under the trees,
// wet mud by the water, sandy and gravel trails with soil along their edges, and on the
// mountains a mix of rocks: mossy rock on
// moderate and shaded slopes, plain rock, sheer cliff rock on the steepest faces, and scree
// at the foot of steep slopes and down the gullies. Then whatever has been painted on with
// the Texture Brush. Also used on boulders, which gives them mossy tops.
//
// The textured materials come from assets/textures, one set per *_Color image, gathered by
// the Valley into texture arrays (one layer per set). Every layer has a height (from its
// Displacement map, or a soft pattern for the plain grass and dirt), and layers blend by
// height rather than fading evenly: where gravel meets grass, the stones show through first
// and the grass fills the low spots between them; rock rises through the grass the same way.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A grayscale cloudy pattern, sampled at several sizes to break up the colors
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 grass_dark : source_color = vec3(0.13, 0.20, 0.06);
uniform vec3 grass_light : source_color = vec3(0.30, 0.34, 0.12);
uniform vec3 grass_dry : source_color = vec3(0.40, 0.36, 0.19);
uniform vec3 dirt_color : source_color = vec3(0.28, 0.24, 0.17);

// The texture sets, one layer each (the Valley fills these in), with how many meters each
// repeats over, a color tint (its alpha is 1 for rock sets, which wrap round steep ground
// from three sides), and whether it has an ambient occlusion map
group_uniforms texture_sets;
uniform sampler2DArray set_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray set_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray set_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray set_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray set_height : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float set_scale[16];
uniform vec4 set_tint[16];
uniform float set_has_ao[16];
// Which layer the ground uses for each job (-1 = none, so that job is skipped)
uniform int forest_set = -1;
uniform int gravel_set = -1;
uniform int rock_set = -1;
uniform int mossy_rock_set = -1;
uniform int cliff_rock_set = -1;
uniform int scree_set = -1;
uniform int path_set = -1;
uniform int light_soil_set = -1;
uniform int dark_soil_set = -1;
group_uniforms;
// How strongly the textures' normal maps tilt the lighting (0 = flat, 1 = as made)
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// How soft height blending is: small = crisp edges along stones, large = closer to a plain fade
uniform float height_blend_depth : hint_range(0.01, 1.0) = 0.2;

group_uniforms mountains;
// Rock starts rising through the grass from this slope (degrees)...
uniform float rock_begin_degrees : hint_range(0.0, 90.0) = 30.0;
// ...and covers the ground fully by this one. A pattern nudges both up and down, so the
// edge wanders and breaks up instead of following the slope exactly.
uniform float rock_full_degrees : hint_range(0.0, 90.0) = 52.0;
// How far (in degrees) the pattern nudges where rock begins
uniform float rock_edge_noise : hint_range(0.0, 30.0) = 12.0;
// Sheer cliff rock takes over on faces steeper than this
uniform float cliff_degrees : hint_range(0.0, 90.0) = 48.0;
// Moss grows thickest on slopes facing this way (in the world: x, z), out of the sun
uniform vec2 moss_facing = vec2(0.0, -1.0);
// How strongly the broad light and dark streaks and color shifts show across the rock
uniform float rock_variation : hint_range(0.0, 1.0) = 0.7;
// Scree gathers below slopes that rise faster than this (meters up per meter across)...
uniform float scree_below_rise = 0.7;
// ...and in gullies dug in deeper than this (meters, compared with the ground 7 m around)
uniform float scree_gully_depth = 0.8;
group_uniforms;

group_uniforms mountain_veins;
// How much water would collect at each spot (the Valley fills this in)
uniform sampler2D flow_map : hint_default_black, filter_linear, repeat_disable;
// The green running down the gullies, in shade and in full growth
uniform vec3 vein_dark : source_color = vec3(0.06, 0.13, 0.03);
uniform vec3 vein_bright : source_color = vec3(0.34, 0.46, 0.08);
// How little drainage it takes for green to start (smaller = more, finer veins)
uniform float vein_from : hint_range(0.0, 1.0) = 0.33;
// How much the ribs running down the faces darken their grooves and catch the light
uniform float rib_contrast : hint_range(0.0, 1.0) = 0.95;
uniform float rib_relief : hint_range(0.0, 3.0) = 1.8;
// Rock turns pale from this height up, fully by 80 m higher
uniform vec3 pale_rock : source_color = vec3(0.74, 0.70, 0.62);
uniform float pale_from = 105.0;
group_uniforms;

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
// Noise), how much forest floor the trees here spread over it, and the ground's height.
// The valley fills these in, along with where the map starts and its grid spacing.
uniform sampler2D ground_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D edge_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D forest_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 ground_map_info = vec4(0.0, 0.0, 1.0, 1.0);
// What's been painted with the Texture Brush, one pixel per meter: twelve channels (red,
// green, blue, alpha of each map), each holding how much of one material is there. Which
// material each channel is: -1 = grass, -2 = dirt, -3 = unused, 0 or more = a texture set.
uniform sampler2D paint_0 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D paint_1 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D paint_2 : hint_default_black, filter_linear, repeat_disable;
uniform int paint_channel[12];
// Where the painted map starts (x, z), how many meters each pixel covers, and whether
// anything is painted at all
uniform vec4 paint_info = vec4(0.0, 0.0, 1.0, 0.0);

varying vec3 world_pos;
varying vec3 world_normal;
// How soft height blending is here: softer far away, where a texture's fine bumps average out
// to nothing and would leave a hard edge between materials
varying float blend_depth;

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
	blend_depth = mix(height_blend_depth, 0.75, smoothstep(25.0, 160.0, length((VIEW_MATRIX * vec4(world_pos, 1.0)).xyz)));
}

// How much of `top` shows over `base`, when `amount` of it has been laid on (0 to 1). The
// higher parts of each surface win: a little gravel shows only its tallest stones, a little
// grass over gravel only fills the hollows between them.
float height_mix(float base_height, float top_height, float amount) {
	float a = base_height + (1.0 - amount);
	float b = top_height + amount;
	float level = max(a, b) - blend_depth;
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

// A texture set laid flat on the ground (looking down), with a second, larger and turned
// copy blended in by a slow pattern, and a gentle brightness wander, so the repeats don't
// line up into a grid
Ground flat_set(int layer, vec3 n, float large, float medium) {
	float scale = set_scale[layer];
	float l = float(layer);
	vec2 uv = world_pos.xz / scale;
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * world_pos.xz / (scale * 1.7) + vec2(0.37, 0.71);
	float other = smoothstep(0.35, 0.65, medium) * 0.5;
	Ground g;
	g.albedo = mix(texture(set_albedo, vec3(uv, l)).rgb, texture(set_albedo, vec3(uv2, l)).rgb, other) * set_tint[layer].rgb * (0.85 + large * 0.3);
	vec3 tn = unpack_normal(texture(set_normal, vec3(uv, l)));
	g.normal = normalize(vec3(tn.x + n.x, abs(tn.z) * n.y, tn.y + n.z));
	// (never quite as glossy as the scans: the ground is dry and dusty)
	g.roughness = mix(0.6, 1.0, texture(set_roughness, vec3(uv, l)).r);
	g.ao = set_has_ao[layer] > 0.5 ? texture(set_ao, vec3(uv, l)).r : 1.0;
	g.height = mix(texture(set_height, vec3(uv, l)).r, texture(set_height, vec3(uv2, l)).r, other);
	return g;
}

// A texture set projected from three sides and blended by which way the ground faces
// ("triplanar"), so rock doesn't stretch down cliffs. Roughness and crevice shadow come from
// the side the ground faces most (they're subtle; this saves samples).
Ground triplanar_set(int layer, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	float l = float(layer);
	vec3 p = world_pos / set_scale[layer];
	vec3 uvx = vec3(p.zy, l);
	vec3 uvy = vec3(p.xz, l);
	vec3 uvz = vec3(p.xy, l);
	Ground g;
	g.albedo = (texture(set_albedo, uvx).rgb * w.x + texture(set_albedo, uvy).rgb * w.y + texture(set_albedo, uvz).rgb * w.z) * set_tint[layer].rgb;
	// Each side's normal map tilts the surface around its own axis ("whiteout" blend)
	vec3 tx = unpack_normal(texture(set_normal, uvx));
	vec3 ty = unpack_normal(texture(set_normal, uvy));
	vec3 tz = unpack_normal(texture(set_normal, uvz));
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	g.normal = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	vec3 main_uv = w.y > max(w.x, w.z) ? uvy : (w.x > w.z ? uvx : uvz);
	g.roughness = mix(0.55, 1.0, texture(set_roughness, main_uv).r);
	g.ao = set_has_ao[layer] > 0.5 ? texture(set_ao, main_uv).r : 1.0;
	g.height = texture(set_height, uvx).r * w.x + texture(set_height, uvy).r * w.y + texture(set_height, uvz).r * w.z;
	return g;
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

// A painted channel's material: grass, dirt, or a texture set (rock sets wrap around steep
// ground from three sides; the rest are laid flat)
Ground paint_layer(int which, vec3 n, float large, float medium, float small) {
	if (which == -1) {
		return grass_layer(n, large, medium, small);
	}
	if (which == -2) {
		return dirt_layer(n, small);
	}
	if (set_tint[which].a > 0.5) {
		return triplanar_set(which, n);
	}
	return flat_set(which, n, large, medium);
}

// The ground's height (from the valley's height map) at a spot
float ground_height(vec2 xz) {
	vec2 uv = ((xz - ground_map_info.xy) / ground_map_info.zw + 0.5) / vec2(textureSize(height_map, 0));
	return texture(height_map, uv).r;
}

// The broad, slow changes across rock: lighter and darker swathes tens of meters across,
// streaks running down the faces, and a drift between cooler and warmer stone
vec3 rock_variety(vec3 albedo, float steep_face, float macro) {
	float broad = texture(detail_noise, world_pos.xz * 0.004 + vec2(world_pos.y * 0.002)).r;
	float blotches = texture(detail_noise, world_pos.xz * 0.02 + vec2(world_pos.y * 0.01, 0.43)).r;
	float streaks = texture(detail_noise, vec2(dot(world_pos.xz, vec2(0.71, 0.71)) * 0.035, world_pos.y * 0.004)).r;
	float warmth = texture(detail_noise, world_pos.xz * 0.0025 + vec2(0.31, 0.77)).r;
	// (the pattern's values mostly sit between 0.35 and 0.65, so that's the range stretched out)
	vec3 varied = albedo * mix(0.5, 1.35, smoothstep(0.36, 0.64, broad));
	varied *= mix(0.75, 1.15, smoothstep(0.38, 0.62, blotches));
	varied *= mix(1.0, mix(0.6, 1.1, smoothstep(0.4, 0.6, streaks)), steep_face);
	// Cool blue-grey stone in some places, warm, iron-stained ochre in others
	varied *= mix(vec3(0.84, 0.92, 1.08), vec3(1.24, 1.02, 0.72), smoothstep(0.38, 0.62, warmth));
	// The rock's own pattern, blown up big: ledges and bands that still read from far away
	varied *= mix(1.0, clamp(macro / 0.33, 0.55, 1.5), 0.55);
	return mix(albedo, varied, rock_variation);
}

// Ribs running down a face: sharp crests in a pattern stretched along the slope, at two sizes
// (1 on a crest, 0 in a groove). Taken from whichever side the slope faces, so they run downhill
// whichever way that is.
float ribs(vec3 p, vec2 facing) {
	float big = texture(detail_noise, vec2(p.z * 0.02, p.y * 0.0016)).r * facing.x + texture(detail_noise, vec2(p.x * 0.02, p.y * 0.0016)).r * facing.y;
	float fine = texture(detail_noise, vec2(p.z * 0.07 + 0.31, p.y * 0.005)).r * facing.x + texture(detail_noise, vec2(p.x * 0.07 + 0.31, p.y * 0.005)).r * facing.y;
	return (1.0 - smoothstep(0.0, 0.2, abs(big - 0.5))) * 0.65 + (1.0 - smoothstep(0.0, 0.2, abs(fine - 0.5))) * 0.35;
}

void fragment() {
	vec3 n = normalize(world_normal);

	// The same pattern at big, medium and small sizes, and one in between
	float large = texture(detail_noise, world_pos.xz * 0.003).r;
	float medium = texture(detail_noise, world_pos.xz * 0.027).r;
	float small = texture(detail_noise, world_pos.xz * 0.31).r;
	float between = texture(detail_noise, world_pos.xz * 0.11 + vec2(0.53, 0.19)).r;
	float slope = degrees(acos(clamp(n.y, -1.0, 1.0)));
	// The ribs running down the faces, which most of the mountain's patterns follow
	vec2 facing = abs(n.xz) + vec2(0.001);
	facing /= facing.x + facing.y;
	float rib = ribs(world_pos, facing);
	float groove = 1.0 - rib;

	// ---- The automatic ground ----
	Ground g = grass_layer(n, large, medium, small);
	// (the plain dirt color stands in for the soils if their texture sets aren't there)
	Ground dirt = dirt_layer(n, small);

	// The shape of the ground around this spot, from the heights 7 m away: how fast it rises
	// (high at the foot of a steep slope) and how far this spot sits below its surroundings
	// (in a hollow or gully; below zero on a ridge or knoll)
	float rise = 0.0;
	float hollow = 0.0;
	if (slope > 3.0) {
		float here = ground_height(world_pos.xz);
		float around = 0.0;
		for (int k = 0; k < 8; k++) {
			float a = float(k) * 0.785398;
			float h = ground_height(world_pos.xz + vec2(cos(a), sin(a)) * 7.0);
			rise = max(rise, (h - here) / 7.0);
			around += h;
		}
		hollow = around / 8.0 - here;
	}
	// Where rock begins, pushed up and down by a pattern so it breaks up (the soil below it and
	// the rock itself both follow this)
	float wobble = ((medium - 0.5) * 1.2 + (between - 0.5) * 0.8 + (small - 0.5) * 0.3) * rock_edge_noise;

	// Light, dry soil: bare patches in the meadows, and worn, exposed slopes and ridges (not the
	// hollows, which stay damp)
	float patches = smoothstep(0.60, 0.70, medium * 0.75 + large * 0.25);
	float worn = smoothstep(22.0, 38.0, slope + (medium - 0.5) * 12.0) * (1.0 - smoothstep(-0.2, 0.6, hollow));
	float dry = max(patches, worn * 0.85);
	if (dry > 0.01) {
		Ground light = light_soil_set >= 0 ? flat_set(light_soil_set, n, large, medium) : dirt;
		g = mix_ground(g, light, height_mix(g.height, light.height, dry));
	}
	// Dark, damp soil: the band where the grass gives way to rock (so rocks rise out of earth,
	// not straight out of the turf), the hollows and gullies, and the ground just above the
	// shore. Broken up by a pattern, and height blended, so it comes and goes in patches.
	float toward_rock = smoothstep(rock_begin_degrees - 7.0, rock_begin_degrees + 2.0, slope + wobble) * (1.0 - smoothstep(rock_begin_degrees + 4.0, rock_begin_degrees + 14.0, slope + wobble));
	float in_hollow = smoothstep(0.8, 2.2, hollow) * smoothstep(6.0, 16.0, slope);
	float by_water = smoothstep(water_height, water_height + 0.6, world_pos.y) * (1.0 - smoothstep(water_height + shore_width, water_height + shore_width + 3.0, world_pos.y));
	float clumps = smoothstep(0.25, 0.75, groove);
	float damp = clamp(max(max(toward_rock * 0.6, in_hollow * 0.8), by_water * 0.6) * mix(0.3, 1.1, clumps) + (small - 0.5) * 0.15, 0.0, 1.0);
	if (damp > 0.01) {
		Ground dark = dark_soil_set >= 0 ? flat_set(dark_soil_set, n, large, medium) : dirt;
		g = mix_ground(g, dark, height_mix(g.height, dark.height, damp));
	}

	// Forest floor under the trees, with a ragged edge where the woods give way to grass
	vec2 map_uv = ((world_pos.xz - ground_map_info.xy) / ground_map_info.zw + 0.5) / vec2(textureSize(ground_map, 0));
	float trail = texture(ground_map, map_uv).r;
	float woods = smoothstep(0.35, 0.8, texture(forest_map, map_uv).r + (medium - 0.5) * 0.3 + (between - 0.5) * 0.45 + (small - 0.5) * 0.15);
	if (woods > 0.001 && forest_set >= 0) {
		Ground forest = flat_set(forest_set, n, large, medium);
		g = mix_ground(g, forest, height_mix(g.height, forest.height, woods));
	}

	// Scree: broken stone gathered where steep ground gives way to gentler (it rolls down and
	// stops there), and down the gullies
	if (scree_set >= 0 && slope > 6.0) {
		float below_steep = smoothstep(scree_below_rise, scree_below_rise + 0.5, rise) * (1.0 - smoothstep(40.0, 52.0, slope));
		float in_gully = smoothstep(scree_gully_depth, scree_gully_depth + 1.5, hollow) * smoothstep(10.0, 22.0, slope);
		float scree_amount = clamp(max(below_steep, in_gully) + (between - 0.5) * 0.6 + (small - 0.5) * 0.2, 0.0, 1.0);
		scree_amount *= smoothstep(water_height + 0.3, water_height + 1.5, world_pos.y);
		if (scree_amount > 0.01) {
			Ground scree = flat_set(scree_set, n, large, medium);
			g = mix_ground(g, scree, height_mix(g.height, scree.height, scree_amount));
		}
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

	// Rock, rising through the soil and grass as the ground steepens. The pattern pushes where
	// it begins up and down, so it comes through in broken outcrops rather than a band, and
	// height blending lets the tallest stones show first.
	float rockiness = smoothstep(rock_begin_degrees, rock_full_degrees, slope + wobble);
	if (rockiness > 0.001 && rock_set >= 0) {
		// Plain rock between the others: the set with its moss muted to bare grey stone
		Ground stone = triplanar_set(rock_set, n);
		Ground rock = stone;
		float grey = dot(stone.albedo, vec3(0.3, 0.55, 0.15));
		rock.albedo = mix(vec3(grey), stone.albedo, 0.6) * vec3(0.92, 0.94, 0.98);
		// Moss on moderately steep slopes, and thickest where they face out of the sun, in big
		// patches that come and go across the mountain
		float shaded = smoothstep(0.05, 0.55, dot(n.xz, normalize(moss_facing)));
		float moderate = smoothstep(22.0, 32.0, slope) * (1.0 - smoothstep(46.0, 60.0, slope));
		float patchy = texture(detail_noise, world_pos.xz * 0.008 + vec2(0.71, 0.13)).r;
		float moss = clamp(max(moderate * 0.8, shaded * smoothstep(18.0, 30.0, slope)) + (between - 0.5) * 0.9 + (smoothstep(0.38, 0.62, patchy) - 0.5) * 1.4, 0.0, 1.0);
		if (moss > 0.01 && mossy_rock_set >= 0) {
			Ground mossy = mossy_rock_set == rock_set ? stone : triplanar_set(mossy_rock_set, n);
			mossy.albedo *= vec3(0.88, 1.06, 0.66);
			rock = mix_ground(rock, mossy, height_mix(rock.height, mossy.height, moss));
		}
		// Sheer cliff rock on the steepest faces
		// (where slopes are all much the same, the pattern decides: cliff in some swathes, mossy
		// and plain rock in others)
		float sheer = smoothstep(cliff_degrees - 8.0, cliff_degrees + 8.0, slope + wobble * 0.6 - (smoothstep(0.38, 0.62, patchy) - 0.5) * 36.0);
		if (sheer > 0.01 && cliff_rock_set >= 0) {
			Ground cliff = triplanar_set(cliff_rock_set, n);
			rock = mix_ground(rock, cliff, height_mix(rock.height, cliff.height, sheer));
		}
		// The big-scale pattern: the cliff rock's (or plain rock's) own texture, nine times larger,
		// from the side the ground faces most
		int big = cliff_rock_set >= 0 ? cliff_rock_set : rock_set;
		vec3 aw = abs(n);
		vec2 big_uv = (aw.y > max(aw.x, aw.z) ? world_pos.xz : (aw.x > aw.z ? world_pos.zy : world_pos.xy)) / (set_scale[big] * 9.0);
		float macro = dot(texture(set_albedo, vec3(big_uv, float(big))).rgb, vec3(0.33));
		rock.albedo = rock_variety(rock.albedo, smoothstep(35.0, 60.0, slope), macro);
		// Ribs: dark grooves and bright crests, and pale stone on the crests higher up
		float high = smoothstep(pale_from, pale_from + 80.0, world_pos.y + (large - 0.5) * 70.0);
		rock.albedo *= mix(1.0, mix(0.38, 1.3, rib), rib_contrast);
		// (keeping the stone's own light and dark, so it stays rock rather than paint)
		float stone_tone = dot(rock.albedo, vec3(0.3, 0.55, 0.15));
		rock.albedo = mix(rock.albedo, pale_rock * (0.35 + stone_tone * 1.6), high * smoothstep(0.42, 0.8, rib) * 0.85);
		// ...and they catch the light, tilting the surface across the slope like real ribs
		vec3 across = normalize(cross(n, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
		float rib_next = ribs(world_pos + across * 2.0, facing);
		rock.normal = normalize(rock.normal + across * (rib - rib_next) * rib_relief);
		g = mix_ground(g, rock, height_mix(g.height, rock.height, rockiness));
	}

	// Green veins down the gullies and across the lower faces, breaking through the rock: where
	// water collects, and in the grooves between the ribs, thinning out high up
	float drainage = texture(flow_map, map_uv + (vec2(small, between) - 0.5) * 0.0018).r;
	float altitude_fade = 1.0 - smoothstep(pale_from + 25.0, pale_from + 110.0, world_pos.y + (large - 0.5) * 60.0);
	float vein = smoothstep(vein_from, vein_from + 0.3, drainage + hollow * 0.03 + (groove - 0.35) * 0.45) * altitude_fade;
	// (boulders use this material too, and stand above the ground: they stay bare)
	vein *= 1.0 - smoothstep(0.25, 0.6, world_pos.y - ground_height(world_pos.xz));
	vein *= smoothstep(10.0, 22.0, slope) * smoothstep(water_height + 0.5, water_height + 2.5, world_pos.y) * (1.0 - churned) * (1.0 - smoothstep(1.2, 3.0, trail * 4.0));
	if (vein > 0.01) {
		// The forest floor's texture gives it detail; its light and dark become the greens
		Ground veg = forest_set >= 0 ? flat_set(forest_set, n, large, medium) : grass_layer(n, large, medium, small);
		float leafy = dot(veg.albedo, vec3(0.3, 0.55, 0.15));
		veg.albedo = mix(vein_dark, vein_bright, smoothstep(0.05, 0.28, leafy + (large - 0.5) * 0.12)) * clamp(leafy / 0.2, 0.55, 1.1);
		g = mix_ground(g, veg, height_mix(g.height, veg.height, vein));
	}

	// Trails. Their edges fray (more raggedly with the trail's Edge Noise turned up) through a
	// fringe of trodden soil, light with patches of dark, that height blends into the ground
	// around, so the trail sits in the ground rather than on it. On the trail itself: packed
	// sandy ground with pebbles worn down the middle, and stony gravel kicked toward the edges
	// and lying in patches along the way.
	if (trail > 0.001) {
		float ragged = 0.2 + texture(edge_map, map_uv).r * 1.6;
		float jitter = ((medium - 0.5) * 0.6 + (small - 0.5) * 0.35) * ragged;
		float fringe = smoothstep(0.03, 0.45, trail + jitter * 0.8);
		if (fringe > 0.01 && light_soil_set >= 0) {
			Ground soil = flat_set(light_soil_set, n, large, medium);
			float darker = smoothstep(0.45, 0.62, between + (large - 0.5) * 0.4);
			if (darker > 0.01 && dark_soil_set >= 0) {
				Ground dark = flat_set(dark_soil_set, n, large, medium);
				soil = mix_ground(soil, dark, height_mix(soil.height, dark.height, darker * 0.7));
			}
			g = mix_ground(g, soil, height_mix(g.height, soil.height, fringe));
		}
		float fray = smoothstep(0.3, 0.85, trail + jitter);
		if (fray > 0.001 && (path_set >= 0 || gravel_set >= 0)) {
			float scattered = texture(detail_noise, world_pos.xz * 0.06 + vec2(0.29, 0.83)).r;
			float stones = clamp(1.0 - smoothstep(0.7, 0.97, trail) + (smoothstep(0.4, 0.6, scattered) - 0.5) * 1.1, 0.0, 1.0);
			Ground surface = path_set >= 0 ? flat_set(path_set, n, large, medium) : flat_set(gravel_set, n, large, medium);
			if (path_set >= 0 && gravel_set >= 0 && stones > 0.01) {
				Ground gravel = flat_set(gravel_set, n, large, medium);
				surface = mix_ground(surface, gravel, height_mix(surface.height, gravel.height, stones));
			}
			g = mix_ground(g, surface, height_mix(g.height, surface.height, fray));
		}
	}

	// ---- What's been painted on top ----
	if (paint_info.w > 0.0) {
		vec2 paint_uv = (world_pos.xz - paint_info.xy) / paint_info.z / vec2(textureSize(paint_0, 0));
		vec4 p0 = texture(paint_0, paint_uv);
		vec4 p1 = texture(paint_1, paint_uv);
		vec4 p2 = texture(paint_2, paint_uv);
		float weights[12] = float[](p0.r, p0.g, p0.b, p0.a, p1.r, p1.g, p1.b, p1.a, p2.r, p2.g, p2.b, p2.a);
		float coverage = 0.0;
		for (int c = 0; c < 12; c++) {
			coverage += weights[c];
		}
		coverage = min(coverage, 1.0);
		if (coverage > 0.003) {
			// The painted materials, each laid over the last by height in proportion to how
			// much of it there is...
			float laid = 0.0;
			Ground painted = g;
			for (int c = 0; c < 12; c++) {
				if (weights[c] > 0.002 && paint_channel[c] > -3) {
					Ground layer = paint_layer(paint_channel[c], n, large, medium, small);
					if (laid == 0.0) {
						painted = layer;
					} else {
						painted = mix_ground(painted, layer, height_mix(painted.height, layer.height, weights[c] / (laid + weights[c])));
					}
					laid += weights[c];
				}
			}
			// ...then over the automatic ground, by how much has been painted here
			if (laid > 0.0) {
				g = mix_ground(g, painted, height_mix(g.height, painted.height, coverage));
			}
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
		vec3 tint = vec3(0.15, 0.75, 0.2);
		if (slope >= walk_limit_degrees) {
			tint = vec3(0.9, 0.15, 0.1);
		} else if (slope >= walk_limit_degrees - 8.0) {
			tint = vec3(0.95, 0.8, 0.1);
		}
		ALBEDO = mix(ALBEDO, tint, 0.7);
	}
}
