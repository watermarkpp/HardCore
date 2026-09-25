shader_type canvas_item;
render_mode blend_mul;

void fragment() {
	vec4 source = COLOR;
	COLOR = vec4(vec3(1.0) - source.rgb * source.a, 1.0);
}
