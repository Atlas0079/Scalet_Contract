shader_type spatial;
render_mode unshaded;
uniform sampler2D terminal_content : source_color, filter_nearest, repeat_disable;
uniform vec3 phosphor_color : source_color = vec3(0.04,0.82,0.20);
uniform float threshold = 0.035;
uniform vec2 screen_resolution = vec2(512.0,384.0);
uniform vec4 glass_rect;
uniform bool powered = true;
varying vec2 picture_uv;
void vertex() {
 picture_uv=vec2((VERTEX.x-glass_rect.x)/glass_rect.z,1.0-(VERTEX.y-glass_rect.y)/glass_rect.w);
}
void fragment() {
 vec2 pixel_uv=(floor(picture_uv*screen_resolution)+.5)/screen_resolution;
 float ink=step(threshold,texture(terminal_content,pixel_uv).g);
 vec2 cell=abs(fract(picture_uv*screen_resolution)-.5);
 float grid=smoothstep(.40,.49,max(cell.x,cell.y));
 ALBEDO=powered ? phosphor_color*ink*(1.0-grid*.04) : vec3(.0003,.0005,.0005);
}
