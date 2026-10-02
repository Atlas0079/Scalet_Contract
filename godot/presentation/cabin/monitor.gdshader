shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D live_picture : source_color, filter_linear;
uniform bool powered = true;
varying vec2 glass_uv;
void vertex() {
 glass_uv = vec2((VERTEX.x + 0.16010) / 0.31654, (0.37741 - VERTEX.y) / 0.23720);
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
