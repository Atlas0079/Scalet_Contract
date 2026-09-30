shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.04, 0.08, 0.06, 0.38);

void fragment() {
    // Reuse the current animated character texture, not a static blob.
    COLOR = vec4(shadow_color.rgb, texture(TEXTURE, UV).a * shadow_color.a);
}
