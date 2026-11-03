// The pine pack's bark: its own textures, with the same wind sway as the needles, so the
// branches carry the leaves with them.
shader_type spatial;
render_mode diffuse_burley;

#include "res://assets/trees/pine_pack/pine_sway.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	pine_sway(VERTEX, MODEL_MATRIX, NODE_POSITION_WORLD);
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * tint.rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	ROUGHNESS = texture(roughness_texture, UV).g;
	SPECULAR = 0.25;
}
