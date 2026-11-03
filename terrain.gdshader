// Paints the ground: grass on gentle slopes, dirt patches, wet mud by the water,
// and layered rock wherever it's steep. Also used on boulders, which gives them mossy tops.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A grayscale cloudy pattern, sampled at several sizes to break up the colors
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 grass_dark : source_color = vec3(0.13, 0.20, 0.06);
uniform vec3 grass_light : source_color = vec3(0.30, 0.34, 0.12);
uniform vec3 grass_dry : source_color = vec3(0.40, 0.36, 0.19);
uniform vec3 dirt_color : source_color = vec3(0.28, 0.24, 0.17);
uniform vec3 rock_dark : source_color = vec3(0.22, 0.20, 0.17);
uniform vec3 rock_light : source_color = vec3(0.47, 0.43, 0.37);

// Rock starts showing where the ground is steeper than this (1 = flat, 0 = a cliff)...
uniform float rock_start : hint_range(0.0, 1.0) = 0.62;
// ...and fully covers it from here
uniform float rock_full : hint_range(0.0, 1.0) = 0.45;
// How bumpy the rock looks, in meters
uniform float rock_bumpiness = 0.5;
// Height of the water surface; the valley sets this to match
uniform float water_height = 42.0;
// How far above the water the ground stays dark and muddy
uniform float shore_width = 1.5;
// Churned-up mud with rain puddles, around the crash site. The valley sets these;
// a radius of 0 means no mud anywhere.
uniform vec2 mud_center = vec2(0.0);
uniform float mud_radius = 0.0;
// Ground burnt black around the crashed boiler. A radius of 0 means no scorch mark.
uniform vec2 scorch_center = vec2(0.0);
uniform float scorch_radius = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Samples the pattern from three directions and blends by which way the surface faces,
// so it doesn't smear on cliffs ("triplanar" mapping)
float triplanar(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	return texture(detail_noise, p.zy).r * w.x
		+ texture(detail_noise, p.xz).r * w.y
		+ texture(detail_noise, p.xy).r * w.z;
}

// Small speckles of light and dark, like gravel in the soil
float grit_soil(vec3 p) {
	return texture(detail_noise, p.xz * 0.6).r;
}

void fragment() {
	vec3 n = normalize(world_normal);

	// The same pattern at big, medium and small sizes
	float large = texture(detail_noise, world_pos.xz * 0.003).r;
	float medium = texture(detail_noise, world_pos.xz * 0.027).r;
	float small = texture(detail_noise, world_pos.xz * 0.31).r;

	// Grass: big patches of darker and lighter green, some dry areas, fine speckle
	vec3 grass = mix(grass_dark, grass_light, smoothstep(0.35, 0.65, large + (medium - 0.5) * 0.5));
	grass = mix(grass, grass_dry, smoothstep(0.62, 0.78, large) * 0.6);
	grass *= 0.8 + small * 0.4;

	// Bare dirt patches
	float dirt = smoothstep(0.60, 0.70, medium * 0.75 + large * 0.25);
	vec3 ground = mix(grass, dirt_color * (0.75 + small * 0.5), dirt);

	// Fairly steep ground (but not cliff) wears down to bare, stony soil
	float worn = smoothstep(0.86, 0.70, n.y + (medium - 0.5) * 0.2);
	ground = mix(ground, dirt_color * (0.7 + grit_soil(world_pos) * 0.6), worn * 0.85);

	// Dark wet mud right by the water
	float shore = 1.0 - smoothstep(water_height, water_height + shore_width, world_pos.y);
	ground = mix(ground, dirt_color * 0.45, shore);

	// Around the crash site: ground churned to mud, with a ragged edge, and rain puddles in it
	float churned = 0.0;
	float puddle = 0.0;
	if (mud_radius > 0.0) {
		float ragged = (medium - 0.5) * mud_radius * 0.6;
		churned = 1.0 - smoothstep(mud_radius * 0.5, mud_radius, distance(world_pos.xz, mud_center) + ragged);
		ground = mix(ground, dirt_color * vec3(1.05, 0.95, 0.82) * (0.85 + small * 0.4), churned * 0.85);
		float pools = texture(detail_noise, world_pos.xz * 0.06 + vec2(0.37, 0.61)).r;
		puddle = churned * smoothstep(0.72, 0.76, pools);
	}

	// Scorched black around the boiler, with a ragged, sooty edge (and no puddles in it)
	if (scorch_radius > 0.0) {
		float ragged = (medium - 0.5) * scorch_radius * 0.7 + (small - 0.5) * scorch_radius * 0.3;
		float burnt = 1.0 - smoothstep(scorch_radius * 0.55, scorch_radius, distance(world_pos.xz, scorch_center) + ragged);
		// Black soot, flecked with pale grey ash
		vec3 soot = mix(vec3(0.018, 0.016, 0.015), vec3(0.085, 0.08, 0.075), smoothstep(0.74, 0.84, small));
		ground = mix(ground, soot, burnt * 0.95);
		puddle *= 1.0 - burnt;
	}

	// Rock: blotchy color plus horizontal layers, like the strata in a cliff face
	float blotches = triplanar(world_pos * 0.09, n);
	float layers = triplanar(world_pos * vec3(0.07, 0.2, 0.07), n);
	float grit = triplanar(world_pos * 0.35, n);
	vec3 rock = mix(rock_dark, rock_light, smoothstep(0.25, 0.75, blotches * 0.6 + layers * 0.4));
	rock *= 0.8 + grit * 0.35;

	// How much rock shows, with a ragged edge where it meets the grass
	float steep = smoothstep(rock_start, rock_full, n.y + (medium - 0.5) * 0.18);

	ALBEDO = mix(ground, rock, steep);
	ROUGHNESS = mix(0.95, 0.82, steep) - shore * 0.35 - churned * 0.25;

	// Puddles: dark, glassy and dead flat, so they mirror the sky
	ALBEDO = mix(ALBEDO, vec3(0.06, 0.05, 0.04), puddle * 0.9);
	ROUGHNESS = mix(ROUGHNESS, 0.08, puddle);
	SPECULAR = mix(0.5, 0.65, puddle);

	// Fake little bumps and ledges by tilting the lighting ("bump mapping")
	float bump = (steep * (blotches * 0.6 + grit * 0.25 + layers * 0.4) * rock_bumpiness
		+ (1.0 - steep) * small * 0.06) * (1.0 - puddle);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 slope = sign(det) * (dFdx(bump) * r1 + dFdy(bump) * r2);
	NORMAL = normalize(abs(det) * NORMAL - slope);
}
