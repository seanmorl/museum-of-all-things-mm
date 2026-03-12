shader_type canvas_item;

// PS1‑style post‑processing: low‑res sampling, colour quantization, slight wobble.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest, repeat_disable;

// Target “internal” resolution for sampling (pixelation).
uniform vec2 target_resolution = vec2(320.0, 240.0);

// Number of colour steps per channel (e.g. 6–8 feels PS1‑ish).
uniform float color_steps : hint_range(2.0, 16.0) = 8.0;

// Strength of a subtle UV wobble to mimic affine jitter.
uniform float wobble_amount : hint_range(0.0, 1.0) = 0.15;

// Dither strength applied before quantisation.
uniform float dither_strength : hint_range(0.0, 1.0) = 0.4;


float hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p.x * p.y) * 43758.5453);
}


void fragment() {
	// Start from screen UV so this works as an overlay on a ColorRect.
	vec2 uv = SCREEN_UV;

	// Slight “wobble” based on time and screen position to emulate unstable affine mapping.
	if (wobble_amount > 0.0) {
		float t = TIME * 2.0;
		vec2 wobble = vec2(
			sin(uv.y * 600.0 + t * 3.0),
			cos(uv.x * 400.0 + t * 2.0)
		) * (wobble_amount * 0.002);
		uv += wobble;
	}

	// Pixelation to a low internal resolution.
	vec2 scaled = uv * target_resolution;
	scaled = floor(scaled) / target_resolution;

	vec3 col = texture(SCREEN_TEXTURE, scaled).rgb;

	// Simple ordered‑noise dither before quantisation.
	if (dither_strength > 0.0) {
		vec2 pixel = floor(uv * target_resolution);
		float n = hash(pixel) - 0.5;
		col += n * (1.0 / color_steps) * dither_strength;
	}

	// Per‑channel colour quantisation.
	float steps = max(2.0, color_steps);
	col = floor(col * steps) / steps;

	COLOR = vec4(col, 1.0);
}

