// Water that's clear in the shallows and darker the deeper it gets, with gentle ripples
// and a pale edge where it laps against the shore.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.30, 0.42, 0.34);
uniform vec3 deep_color : source_color = vec3(0.03, 0.10, 0.12);
// Roughly how deep (in meters) you can see before the water turns murky
uniform float clarity = 2.5;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// How far it is from the water's surface down to whatever's behind it
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float water_depth = max(VERTEX.z - behind.z, 0.0);
	float murk = 1.0 - exp(-water_depth / clarity);

	// Two ripple patterns drifting in different directions
	vec3 a = texture(ripples, world_pos.xz * 0.035 + TIME * vec2(0.011, 0.006)).rgb;
	vec3 b = texture(ripples, world_pos.xz * 0.09 - TIME * vec2(0.007, 0.013)).rgb;
	NORMAL_MAP = mix(a, b, 0.5);
	NORMAL_MAP_DEPTH = 0.5;

	float shoreline = 1.0 - smoothstep(0.0, 0.25, water_depth);
	ALBEDO = mix(shallow_color, deep_color, murk) + shoreline * 0.12;
	ALPHA = clamp(mix(0.2, 0.94, murk) + shoreline * 0.2, 0.0, 1.0);
	ROUGHNESS = 0.03;
	SPECULAR = 0.6;
}
