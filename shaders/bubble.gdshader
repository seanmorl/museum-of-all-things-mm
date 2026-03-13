shader_type canvas_item;

uniform float time_offset : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);

	// Circular bubble shape
	float alpha = smoothstep(0.5, 0.45, dist);

	// Highlight shimmer
	vec2 highlight_uv = UV - vec2(0.35, 0.3);
	float highlight = smoothstep(0.2, 0.0, length(highlight_uv));

	// Edge refraction glow
	float edge = smoothstep(0.5, 0.42, dist) * (1.0 - smoothstep(0.42, 0.35, dist));

	vec4 bubble_color = COLOR;
	bubble_color.a *= alpha * 0.75;
	bubble_color.rgb += highlight * 0.6;
	bubble_color.rgb += edge * 0.3;

	COLOR = bubble_color;
}
