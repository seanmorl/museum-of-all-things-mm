shader_type sky;

// ── Directions ────────────────────────────────────────────────────────────────
group_uniforms Directions;
uniform vec3 sun_dir  = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);

// ── Sky gradients (1D textures — create with GradientTexture1D in Godot) ─────
// sun_zenith_gradient  : black→dark-blue→azure→pale-blue (left = night, right = noon)
// view_zenith_gradient : transparent→pale-orange→pale-blue (horizon haze)
// sun_view_gradient    : transparent→deep-orange→yellow (bloom around sun)
group_uniforms SkyGradients;
uniform sampler2D sun_zenith_gradient  : source_color, repeat_disable, filter_linear;
uniform sampler2D view_zenith_gradient : source_color, repeat_disable, filter_linear;
uniform sampler2D sun_view_gradient    : source_color, repeat_disable, filter_linear;

// ── Sun ───────────────────────────────────────────────────────────────────────
group_uniforms Sun;
uniform float sun_radius : hint_range(0.0, 1.0) = 0.05;
uniform vec3  sun_color  : source_color = vec3(1.0, 0.98, 0.92);

// ── Moon ──────────────────────────────────────────────────────────────────────
group_uniforms Moon;
uniform float moon_radius : hint_range(0.0, 1.0) = 0.07;

// ── Stars ─────────────────────────────────────────────────────────────────────
group_uniforms Stars;
uniform float star_density  : hint_range(0.0, 1.0) = 0.015;
uniform float star_strength : hint_range(0.0, 5.0)  = 1.2;

// ─────────────────────────────────────────────────────────────────────────────

float get_sun_mask(float sv_dot, float radius) {
    float step_r = 1.0 - radius * radius;
    return step(step_r, sv_dot);
}

// From Inigo Quilez — sphere ray intersection
float sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius) {
    vec3 oc = -sphere_pos;
    float b  = dot(oc, ray_dir);
    float c  = dot(oc, oc) - radius * radius;
    float h  = b * b - c;
    if (h < 0.0) return -1.0;
    return -b - sqrt(h);
}

// Simple hash-based star field
float stars(vec3 dir) {
    // Quantise direction into discrete sky cells
    vec3 q = floor(dir * 150.0);
    float h = fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453);
    return h > (1.0 - star_density) ? pow(h, 4.0) : 0.0;
}

void sky() {
    vec3 view_dir = EYEDIR;

    // ── Main angles ───────────────────────────────────────────────────────────
    float sun_view_dot    = dot(sun_dir, view_dir);
    float sun_zenith_dot  = sun_dir.y;
    float view_zenith_dot = view_dir.y;

    float sun_view_dot01   = (sun_view_dot   + 1.0) * 0.5;
    float sun_zenith_dot01 = (sun_zenith_dot + 1.0) * 0.5;

    // ── Sky colour ────────────────────────────────────────────────────────────
    vec2 uv = vec2(sun_zenith_dot01, 0.5);

    vec3 sun_zenith_color  = texture(sun_zenith_gradient,  uv).rgb;
    vec3 view_zenith_color = texture(view_zenith_gradient, uv).rgb;
    vec3 sun_view_color    = texture(sun_view_gradient,    uv).rgb;

    // Horizon haze mask — strongest at horizon, fades above
    float vz_mask = pow(clamp(1.0 - view_zenith_dot, 0.0, 1.0), 4.0);
    // Sun bloom mask — strongest looking at sun
    float sv_mask = pow(clamp(sun_view_dot, 0.0, 1.0), 4.0);

    vec3 sky_output = sun_zenith_color
                    + vz_mask * view_zenith_color
                    + sv_mask * sun_view_color;

    // ── Sun ───────────────────────────────────────────────────────────────────
    float sun_mask   = get_sun_mask(sun_view_dot, sun_radius);
    vec3  sun_output = sun_color * sun_mask;

    // ── Moon ──────────────────────────────────────────────────────────────────
    float moon_intersect = sphere_intersect(view_dir, moon_dir, moon_radius);
    float moon_mask      = moon_intersect > -1.0 ? 1.0 : 0.0;

    // Simple NdotL moon shading
    vec3 moon_normal = normalize(view_dir * moon_intersect - moon_dir);
    vec3 light_dir   = normalize(sun_dir - moon_dir);
    float moon_ndotl = clamp(dot(moon_normal, light_dir), 0.0, 1.0);
    vec3 moon_output = vec3(0.92, 0.93, 0.95) * moon_mask * (moon_ndotl * 0.8 + 0.2);

    // ── Stars ─────────────────────────────────────────────────────────────────
    float night  = clamp(-sun_zenith_dot * 3.0, 0.0, 1.0);  // visible only at night
    float star   = stars(normalize(view_dir)) * night * star_strength;
    vec3  star_output = vec3(star);

    // ── Combine ───────────────────────────────────────────────────────────────
    // Suppress stars/moon behind the sun disc area
    float sun_suppress = clamp(1.0 - sun_mask * 10.0, 0.0, 1.0);
    vec3 output = sky_output
                + sun_output
                + moon_output  * sun_suppress
                + star_output  * sun_suppress;

    COLOR = output;
}
