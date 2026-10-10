shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D live_picture : source_color, filter_linear;
uniform bool powered = true;
uniform vec4 glass_rect = vec4(-0.16010,0.14021,0.31654,0.23720);
varying vec2 glass_uv;
void vertex() {
 glass_uv = vec2((VERTEX.x-glass_rect.x)/glass_rect.z,1.0-(VERTEX.y-glass_rect.y)/glass_rect.w);
}
void fragment() {
 // Native 4:3 game picture fills the original curved glass; no letterbox.
 vec2 uv = glass_uv;
 vec3 c = vec3(0.0003, 0.0005, 0.0005);
 if (powered && uv.y >= 0.0 && uv.y <= 1.0) {
  c = texture(live_picture, uv).rgb;

 }
 ALBEDO = c;
}
