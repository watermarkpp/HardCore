shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec4 source = COLOR;
	if (source.a <= 0.0) {
		discard;
	}
	vec3 background = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 blended = source.rgb + (vec3(1.0) - source.rgb) * background;
	COLOR = vec4(mix(background, blended, source.a), 1.0);
}
