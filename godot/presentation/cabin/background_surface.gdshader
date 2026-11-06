shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform int material_band = -1;
uniform vec3 tint : source_color = vec3(0.75);
varying vec3 surface_position;
varying vec3 surface_normal;
varying float cable_surface;

void vertex() {
 surface_position=VERTEX;
 surface_normal=NORMAL;
 cable_surface=COLOR.r;
}

void fragment() {
 // Dark background uses one planar sample, with no micro-normal or
 // metallic/roughness maps. Keep the original texture's broad colour wear.
 vec3 n=abs(surface_normal);
 vec2 p=n.x>n.y && n.x>n.z ? surface_position.zy : n.y>n.z ? surface_position.xz : surface_position.xy;
 vec2 uv=p*1.1;
 if(material_band>=0) {
  p=cable_surface>.5 ? vec2(UV.x,UV.y/.035) : p/(material_band==3 ? .16 : .028);
  vec2 tile=abs(fract(p*.5)*2.0-1.0);
  uv=vec2(.014+tile.x*.972,(float(material_band)+.055+tile.y*.890)/4.0);
 }
 vec3 color=texture(color_texture,uv).rgb;
 if(material_band==1) color=mix(color,vec3(dot(color,vec3(.2126,.7152,.0722))),.35);
 ALBEDO=color*tint;
 ROUGHNESS=.95;
 METALLIC=0.0;
 SPECULAR=0.0;
}
