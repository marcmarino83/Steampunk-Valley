// A slow band of valley fog for the title screen: two layers of soft noise drifting past each
// other, fading out toward the band's top and bottom. Kept faint.
shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 tint : source_color = vec4(0.72, 0.77, 0.84, 1.0);
uniform float strength = 0.2;
uniform float speed = 0.004;

void fragment() {
	float a = texture(noise_tex, vec2(UV.x * 1.4 + TIME * speed, UV.y * 0.7)).r;
	float b = texture(noise_tex, vec2(UV.x * 0.7 - TIME * speed * 0.55 + 0.37, UV.y * 1.1 + 0.21)).r;
	float mist = clamp((a * 0.6 + b * 0.4 - 0.32) * 2.2, 0.0, 1.0);
	float band = smoothstep(0.0, 0.45, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	COLOR = vec4(tint.rgb, mist * band * strength);
}
