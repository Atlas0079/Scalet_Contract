/* Adapted from c64cosmin's Realistic CRT shader (CC0):
 https://godotshaders.com/shader/realistic-crt-shader/
 Original credits: c64cosmin (grille/integration), pend00 (warp/vignette),
 Timothy Lottes (scanlines), AHOPNESS (port).
 Project adaptation: viewport texture input, low-intensity signal noise/rolling interference,
 signal-row reconstruction and calibrated grille intensity.
*/
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D scene_texture : filter_linear, repeat_disable;
uniform sampler2D text_texture : filter_linear, repeat_disable;
uniform bool enabled = true;
uniform float strength : hint_range(0.0,1.0) = 0.4;
uniform vec2 resolution = vec2(2560.0,1440.0);
uniform vec2 signal_resolution = vec2(960.0,540.0);
uniform float warp_amount = 0.30;
uniform float elapsed_time = 0.0;
uniform float noise_amount = 0.012;
uniform float interference_amount = 0.02;
uniform float roll_line_amount = 0.035;
uniform float roll_speed = 0.65;
uniform float aberration_pixels = 1.5;
uniform bool fog_enabled = false;
uniform sampler2D fog_texture : filter_nearest, repeat_disable;
uniform vec4 fog_bounds = vec4(0.0,0.0,500.0,500.0);
uniform vec2 fog_view_origin = vec2(0.0);
uniform vec2 fog_view_axis_x = vec2(1.0,0.0);
uniform vec2 fog_view_axis_y = vec2(0.0,1.0);
uniform vec4 fog_map_rect = vec4(0.0);
uniform vec2 fog_display_size = vec2(2304.0,1440.0);

float known_map(vec2 uv) {
 vec2 pixel = uv*fog_display_size;
 if (!fog_enabled || pixel.x < fog_map_rect.x || pixel.y < fog_map_rect.y || pixel.x >= fog_map_rect.x+fog_map_rect.z || pixel.y >= fog_map_rect.y+fog_map_rect.w) return 1.0;
 vec2 point = fog_view_origin+uv.x*fog_view_axis_x+uv.y*fog_view_axis_y;
 vec2 map_uv = (point-fog_bounds.xy)/fog_bounds.zw;
 if (any(lessThan(map_uv,vec2(0.0))) || any(greaterThanEqual(map_uv,vec2(1.0)))) return 0.0;
 return step(0.5,texture(fog_texture,map_uv).g);
}

float legal_ui_gate(vec2 uv,float known) {
 if(known>0.5) return 1.0;
 // Only intentionally unmasked UI has source texels in unknown terrain.
 // Check that texel before chromatic/linear sampling so a knowledge-clipped
 // route or world label cannot acquire a coloured fringe across the fog edge.
 vec2 dimensions=vec2(textureSize(text_texture,0));
 vec2 core=(clamp(floor(uv*dimensions),vec2(0.0),dimensions-1.0)+0.5)/dimensions;
 return (1.0-known_map(core))*step(0.001,textureLod(text_texture,core,0.0).a);
}

float signal_random(vec2 uv) {
 return fract(cos(uv.x*83.4827+uv.y*92.2842)*43758.5453123);
}
float rolling_line(vec2 uv) {
 float x=uv.y*3.0-elapsed_time*roll_speed;
 float f=cos(x)*cos(x*2.35+1.1)*cos(x*4.45+2.3);
 return smoothstep(0.5,0.9,f)*roll_line_amount*(0.6+strength);
}
uniform float pixel_strength = -4.0;
uniform float scan_line_strength = -8.0;

vec2 warp(vec2 uv) {
 vec2 delta=uv-0.5;
 float delta2=dot(delta,delta);
 vec2 warped=uv+delta*(delta2*delta2*warp_amount);
 return (warped-0.5)/mix(1.0,1.2,warp_amount/5.0)+0.5;
}
vec2 dist(vec2 pos) { return 0.5-fract(pos*signal_resolution); }
float gauss(float pos,float scale) { return exp2(scale*pos*pos); }
vec3 fetch_pixel(vec2 uv,vec2 offset) {
 vec2 pos=(floor(uv*signal_resolution+offset)+0.5)/signal_resolution;
 if(max(abs(pos.x-0.5),abs(pos.y-0.5))>0.5) return vec3(0.0);
 return texture(scene_texture,pos).rgb;
}
vec3 horizontal(vec2 pos,float off) {
 float d=dist(pos).x;
 float a=gauss(d-1.0,pixel_strength);
 float b=gauss(d,pixel_strength);
 float c=gauss(d+1.0,pixel_strength);
 return (fetch_pixel(pos,vec2(-1.0,off))*a
       + fetch_pixel(pos,vec2(0.0,off))*b
       + fetch_pixel(pos,vec2(1.0,off))*c)/(a+b+c);
}
vec3 tri(vec2 pos) {
 float d=dist(pos).y;
 float a=gauss(d-1.0,scan_line_strength);
 float b=gauss(d,scan_line_strength);
 float c=gauss(d+1.0,scan_line_strength);
 // Reference three-line Gaussian reconstruction, compensated to keep luminance.
 vec3 beam=horizontal(pos,-1.0)*a+horizontal(pos,0.0)*b+horizontal(pos,1.0)*c;
 vec3 clear=fetch_pixel(pos,vec2(0.0));
 float amount=0.20+strength*0.38;
 return mix(clear,beam*1.30,amount);
}
vec3 grille(vec2 pixel) {
 float unit=3.14159265/3.0;
 float scale=2.0*unit;
 vec3 mask=smoothstep(vec3(0.5),vec3(0.8),cos(vec3(pixel.x*scale)+vec3(-unit,unit,3.0*unit)));
 float amount=0.025+strength*0.06;
 // Normalize the dimmed triad instead of clipping highlights with a global gain.
 return mix(vec3(1.0),mask,amount)/(1.0-amount*0.75);
}
void fragment() {
 if(!enabled) {
  vec4 text=texture(text_texture,UV);
  float known=known_map(UV);
  COLOR=vec4(mix(texture(scene_texture,UV).rgb*known,text.rgb,text.a*legal_ui_gate(UV,known)),1.0);
 } else {
  vec2 pos=warp(UV);
  float frame=floor(elapsed_time*30.0);
  float line=rolling_line(pos);
  vec2 row=floor(pos*signal_resolution)/signal_resolution;
  float interference=(signal_random(vec2(row.y,frame))-0.5)*interference_amount*(0.6+strength);
  pos.x+=(interference+line*2.0)/signal_resolution.x;
  float shift=(aberration_pixels*(0.6+strength)+line*4.0)/resolution.x;
  // Full separated channel reconstruction, not a barely-visible blend with the original.
  vec3 c=vec3(tri(pos-vec2(shift,0.0)).r,
              tri(pos+vec2(0.0,shift*0.25)).g,
              tri(pos+vec2(shift,0.0)).b);
  // Clear reconstructed terrain before legal UI is composed. Knowledge-bound
  // map overlays are clipped by their own material; controlled-unit badges
  // remain readable even when explored terrain occupies only a few pixels.
  float known=known_map(pos);
  c*=known;
  // Readable pixel-font layer shares curvature/chromatic effects, but not 360-line scene sampling.
  vec4 text_r=texture(text_texture,pos-vec2(shift,0.0));
  vec4 text_g=texture(text_texture,pos+vec2(0.0,shift*0.25));
  vec4 text_b=texture(text_texture,pos+vec2(shift,0.0));
  float ui_gate=legal_ui_gate(pos,known);
  text_r.a*=ui_gate;text_g.a*=ui_gate;text_b.a*=ui_gate;
  c=vec3(mix(c.r,text_r.r,text_r.a),mix(c.g,text_g.g,text_g.a),mix(c.b,text_b.b,text_b.a));
  float noise=(signal_random(floor(pos*signal_resolution)+vec2(frame,frame*0.37))-0.5)*noise_amount*(0.6+strength);
  c+=vec3(noise*known);
  c*=1.0+line*3.0;
  c*=grille(UV*resolution);
  vec2 v=clamp(pos,vec2(0.0),vec2(1.0));
  v*=1.0-v;
  c*=pow(clamp(v.x*v.y*16.0,0.0,1.0),0.035+strength*0.10);
  vec2 edge=min(pos,1.0-pos);
  float aperture=smoothstep(0.0,0.002,min(edge.x,edge.y));
  COLOR=vec4(c*aperture,1.0);
 }
}
