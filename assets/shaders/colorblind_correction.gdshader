shader_type canvas_item;

uniform int mode = 0; // 0: None, 1: Protanopia, 2: Deuteranopia, 3: Tritanopia
uniform float strength = 1.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
    vec4 color = texture(screen_texture, SCREEN_UV);
    vec3 result = color.rgb;
    
    if (mode > 0) {
        vec3 rgb = color.rgb;

        // LMS from RGB (Note: GLSL mat3(vec3, vec3, vec3) is COLUMN-MAJOR)
        // Corrected rows:
        // [ 17.8824, 43.5161,  4.1193 ]
        // [  3.4557, 27.1554,  3.8671 ]
        // [  0.0300,  0.1843,  1.4670 ]
        mat3 lms_from_rgb = mat3(
            vec3(17.8824, 3.4557, 0.0300),
            vec3(43.5161, 27.1554, 0.1843),
            vec3(4.1193, 3.8671, 1.4670)
        );

        // RGB from LMS (Inverse of above)
        mat3 rgb_from_lms = mat3(
            vec3(0.0809, -0.0102, -0.0003),
            vec3(-0.1305, 0.0540, -0.0041),
            vec3(0.1167, -0.1136, 0.6935)
        );

        vec3 lms = lms_from_rgb * rgb;
        vec3 simulated_lms = lms;

        if (mode == 1) { // Protanopia (red-blind)
            simulated_lms.x = 2.02344 * lms.y - 2.52581 * lms.z;
        } else if (mode == 2) { // Deuteranopia (green-blind)
            simulated_lms.y = 0.49420 * lms.x + 1.24827 * lms.z;
        } else if (mode == 3) { // Tritanopia (blue-blind)
            simulated_lms.z = -0.39591 * lms.x + 0.80110 * lms.y;
        }

        vec3 simulated_rgb = rgb_from_lms * simulated_lms;
        
        // Daltonization: Shift error into visible spectrum
        vec3 error = rgb - simulated_rgb;
        
        vec3 correction = vec3(0.0);
        if (mode == 1 || mode == 2) { // Red/Green deficiency
            correction.r = 0.0;
            correction.g = 0.7 * error.r + 1.0 * error.g;
            correction.b = 0.7 * error.r + 1.0 * error.b;
        } else if (mode == 3) { // Blue deficiency
            correction.r = 0.7 * error.z + 1.0 * error.r;
            correction.g = 0.7 * error.z + 1.0 * error.g;
            correction.b = 0.0;
        }
        
        result = rgb + correction * strength;
    }
    
    // Clamp to ensure colors stay in 0.0-1.0 range
    COLOR = vec4(clamp(result, 0.0, 1.0), color.a);
}
