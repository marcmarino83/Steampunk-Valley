// Grass blades and fern fronds: dark at the base, lighter at the tips, swaying in the wind.
// Each plant's mesh uses UV.y for how far up the blade a point is (0 = base, 1 = tip).
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 base_color : source_color = vec3(0.07, 0.11, 0.03);
uniform vec3 tip_color : source_color = vec3(0.32, 0.40, 0.13);
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.6;

varying float height_up;

void vertex() {
	height_up = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Two waves at different speeds, offset by position, so gusts roll across the field
	float gust = sin(TIME * wind_speed + world.x * 0.21 + world.z * 0.13)
		+ 0.5 * sin(TIME * wind_speed * 2.3 + world.x * 0.9 + world.z * 0.7);
	// Tips move the most, bases stay put
	float bend = height_up * height_up * wind_strength;
	VERTEX.x += gust * bend;
	VERTEX.z += gust * bend * 0.6;
}

void fragment() {
	// COLOR carries each plant's own tint, set when it was scattered
	ALBEDO = mix(base_color, tip_color, height_up) * COLOR.rgb;
	// Light both sides of each blade as if it faced the sky, so none look dark or shiny
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	// Darker down among the blades, where light can't reach
	AO = mix(0.35, 1.0, height_up);
	AO_LIGHT_AFFECT = 0.4;
	// Sunlight glows through thin leaves
	BACKLIGHT = vec3(0.25, 0.3, 0.1) * height_up;
}
