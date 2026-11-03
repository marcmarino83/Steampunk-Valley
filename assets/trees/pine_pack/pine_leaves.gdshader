// The pine pack's needle clusters and billboards: alpha scissor (cut-out leaves that render
// and cast shadows correctly, with no sorting problems), both sides lit, and wind sway.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

#include "res://assets/trees/pine_pack/pine_sway.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = true;
uniform bool use_roughness = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	// Each mesh's origin sits at the foot of its tree, so that's where the sway starts
	pine_sway(VERTEX, MODEL_MATRIX, NODE_POSITION_WORLD);
}

void fragment() {
	vec4 color = texture(albedo_texture, UV) * tint;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
	ROUGHNESS = use_roughness ? texture(roughness_texture, UV).g : 0.85;
	SPECULAR = 0.3;
	// Sunlight glows a little through the needles
	BACKLIGHT = vec3(0.12, 0.16, 0.06);
}
