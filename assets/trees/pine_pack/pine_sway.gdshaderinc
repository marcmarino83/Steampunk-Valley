// Gentle wind sway shared by the pine pack's bark and leaves, so branches and needles move
// together. The higher up the tree a point is, the further it sways; the base stays put.
// Each tree sways a little out of step with its neighbours, so a forest doesn't move as one.

uniform float sway_strength = 0.012;
uniform float sway_speed = 0.9;

void pine_sway(inout vec3 vertex, mat4 model, vec3 tree_base) {
	vec3 world = (model * vec4(vertex, 1.0)).xyz;
	float height = max(world.y - tree_base.y, 0.0);
	// A per-tree offset, from where the tree stands
	float offset = tree_base.x * 0.137 + tree_base.z * 0.091;
	float gust = sin(TIME * sway_speed + offset) + 0.4 * sin(TIME * sway_speed * 2.3 + offset * 1.7);
	vec3 push = vec3(gust, 0.0, gust * 0.6) * height * height * sway_strength * 0.05;
	vertex += (inverse(model) * vec4(push, 0.0)).xyz;
}
