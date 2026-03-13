shader_type canvas_item;

uniform float cycle_speed : hint_range(0.1, 2.0) = 0.3;
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float t = TIME * cycle_speed;

	// Colour cycle through HSL hues
	vec3 col_a = vec3(0.2 + 0.8 * abs(sin(t)),
					  0.2 + 0.8 * abs(sin(t + 2.094)),
					  0.2 + 0.8 * abs(sin(t + 4.189)));

	// Vertical gradient — brighter at bottom (light source)
	float grad = 1.0 - UV.y * 0.6;

	// Soft edge vignette
	float edge_x = smoothstep(0.0, 0.15, UV.x) * smoothstep(1.0, 0.85, UV.x);

	vec4 result = vec4(col_a * grad * glow_intensity, 1.0);
	result.a = edge_x * 0.55;

	COLOR = result;
}
