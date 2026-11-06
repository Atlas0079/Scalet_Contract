shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D live_picture : source_color, filter_linear;
uniform bool powered = true;
uniform vec4 glass_rect = vec4(-0.16010,0.14021,0.31654,0.23720);
uniform vec4 picture_rect = vec4(0.0,0.0,1.0,1.0);
varying vec2 glass_uv;
void vertex() {
 glass_uv = vec2((VERTEX.x-glass_rect.x)/glass_rect.z,1.0-(VERTEX.y-glass_rect.y)/glass_rect.w);
}
void fragment() {
 // The active CRT is rendered at its native aspect. Other physical CRTs take
 // a proportional centre crop of that same signal, with no image stretching.
 vec2 uv = picture_rect.xy+glass_uv*picture_rect.zw;
 vec3 c = vec3(0.0003, 0.0005, 0.0005);
 if (powered && uv.y >= 0.0 && uv.y <= 1.0) {
  c = texture(live_picture, uv).rgb;

 }
 // The curved mesh displays the composed signal directly. Screen content
 // stays readable without cabin lighting, highlights or reflection shading.
 ALBEDO = c;
}
