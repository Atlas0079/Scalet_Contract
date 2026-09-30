shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 base_color : source_color = vec4(1.0);
uniform bool use_vertex_palette = false;
uniform int shade_bands : hint_range(2, 4) = 3;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.65;
uniform vec3 light_direction = vec3(-0.4, 0.85, 0.3);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
    float light = clamp(dot(normal_world, normalize(light_direction)), 0.0, 1.0);
    float band = floor(light * float(shade_bands)) / float(shade_bands - 1);
    float shade = mix(shadow_floor, 1.0, min(band, 1.0));
    vec3 vertex_palette = COLOR.rgb;
    // The mesh stores linear vertex colors; Compatibility outputs sRGB.
    if (OUTPUT_IS_SRGB) {
        vertex_palette = mix(vertex_palette * 12.92,
            1.055 * pow(vertex_palette, vec3(1.0 / 2.4)) - 0.055,
            step(vec3(0.0031308), vertex_palette));
    }
    vec3 palette = use_vertex_palette ? vertex_palette : base_color.rgb;
    ALBEDO = mix(palette * shade, vec3(1.0, 0.87, 0.62), flash);
}
