shader_type canvas_item;

uniform float edge_softness : hint_range(0.0, 0.05) = 0.012;

void fragment() {
	vec4 sampled = texture(TEXTURE, UV);
	float radius = distance(UV, vec2(0.5));
	float mask = 1.0 - smoothstep(0.5 - edge_softness, 0.5, radius);
	COLOR = sampled * mask;
}
