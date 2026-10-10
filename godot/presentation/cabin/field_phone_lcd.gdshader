shader_type spatial;
uniform sampler2D display_texture : source_color, filter_nearest;
uniform vec4 screen_rect;
varying vec2 screen_uv;
void vertex() {
 screen_uv=vec2((VERTEX.x-screen_rect.x)/screen_rect.z,(VERTEX.z-screen_rect.y)/screen_rect.w);
}
void fragment() {
 vec3 color=texture(display_texture,screen_uv).rgb;
 ALBEDO=color;ROUGHNESS=.80;SPECULAR=.12;EMISSION=color*.35;
}
