shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.065, 0.105, 0.105, 1.0);
uniform int outline_pixels : hint_range(0, 2) = 1;
// Source texels per base-view design pixel. Display/zoom transforms scale
// both the character and its outline; source resolution changes sampling only.
uniform float source_pixel_scale = 1.0;

void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float a = 0.0;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            if (abs(x) <= outline_pixels && abs(y) <= outline_pixels) {
                a = max(a, texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * source_pixel_scale).a);
            }
        }
    }
    a *= outline_color.a;
    float out_alpha = c.a + a * (1.0 - c.a);
    vec3 rgb = (c.rgb * c.a + outline_color.rgb * a * (1.0 - c.a)) / max(out_alpha, 0.001);
    COLOR = vec4(rgb, out_alpha);
}
