shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 2.5;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 0.4);
uniform float saturation : hint_range(0.0, 2.0) = 1.1;

void fragment() {
    vec4 color = textureLod(screen_texture, SCREEN_UV, blur_amount);
    
    // Adjust saturation
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(vec3(gray), color.rgb, saturation);
    
    // Apply tint
    color.rgb = mix(color.rgb, tint_color.rgb, tint_color.a);
    
    COLOR = vec4(color.rgb, 1.0);
}
