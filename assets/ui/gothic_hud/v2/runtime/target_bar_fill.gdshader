shader_type canvas_item;

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec2 fill_x_bounds;

void fragment() {
	float limit_x = mix(fill_x_bounds.x, fill_x_bounds.y, fill_ratio);
	if (fill_ratio <= 0.0 || UV.x >= limit_x) {
		COLOR.a = 0.0;
	}
}
