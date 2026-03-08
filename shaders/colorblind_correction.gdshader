// Colorblind correction shader for Museum of All Things
// Place at: res://assets/shaders/colorblind_correction.gdshader
//
// Uses LMS (Long-Medium-Short cone) colour space daltonisation.
// Applies to a full-screen ColorRect with MOUSE_FILTER_IGNORE.
//
// Uniforms:
//   mode     — 0: none  1: protanopia  2: deuteranopia  3: tritanopia
//   strength — 0.0–1.0 blend factor (1.0 = full correction)

shader_type canvas_item;

uniform int mode : hint_range(0, 3) = 0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// sRGB → linear
vec3 srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// linear → sRGB
vec3 linear_to_srgb(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// RGB → LMS (Hunt-Pointer-Estévez, D65 adapted)
vec3 rgb_to_lms(vec3 rgb) {
    return mat3(
        vec3(0.31399022, 0.63951294, 0.04649755),
        vec3(0.15537241, 0.75789446, 0.08670142),
        vec3(0.01775239, 0.10944209, 0.87256922)
    ) * rgb;
}

// LMS → RGB
vec3 lms_to_rgb(vec3 lms) {
    return mat3(
        vec3( 5.47221206, -4.64196010,  0.16963708),
        vec3(-1.12524190,  2.29317094, -0.16789520),
        vec3( 0.02980165, -0.19318073,  1.16364789)
    ) * lms;
}

// Simulate how a dichromat sees colour, then apply correction shift.
// Brettel et al. model — simplified Viénot (1999) confuse-line projection.
vec3 daltonize(vec3 lms, int cvd_mode) {
    vec3 sim = lms;
    if (cvd_mode == 1) {
        // Protanopia: no L cone. Project onto L-absent plane.
        sim.x = (-0.06150039 * lms.y + 0.08277 * lms.z) / 0.992856;
        // Viénot correction: shift error back to visible channels
        vec3 err = lms - sim;
        sim += vec3(0.0, err.x * 0.7, err.x * 0.7);
    } else if (cvd_mode == 2) {
        // Deuteranopia: no M cone.
        sim.y = (-0.01980007 * lms.x + 0.022561 * lms.z) / 0.988;
        vec3 err = lms - sim;
        sim += vec3(err.y * 0.7, 0.0, err.y * 0.7);
    } else if (cvd_mode == 3) {
        // Tritanopia: no S cone.
        sim.z = (-0.01007 * lms.x + 0.01440 * lms.y) / 0.990;
        vec3 err = lms - sim;
        sim += vec3(err.z * 0.7, err.z * 0.7, 0.0);
    }
    return sim;
}

void fragment() {
    vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV);
    if (mode == 0 || strength <= 0.0) {
        COLOR = screen_color;
        return;
    }

    vec3 lin = srgb_to_linear(screen_color.rgb);
    vec3 lms = rgb_to_lms(lin);
    vec3 corrected_lms = daltonize(lms, mode);
    vec3 corrected_rgb = lms_to_rgb(corrected_lms);
    corrected_rgb = linear_to_srgb(corrected_rgb);
    corrected_rgb = clamp(corrected_rgb, 0.0, 1.0);

    COLOR = vec4(mix(screen_color.rgb, corrected_rgb, strength), screen_color.a);
}
