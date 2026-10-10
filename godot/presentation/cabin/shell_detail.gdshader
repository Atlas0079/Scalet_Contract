shader_type spatial;
uniform sampler2D detail_atlas: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int material_band = 0;
uniform float cloth_reflectance = 0.17;
uniform float cloth_desaturation = 0.35;
varying vec3 material_position;
varying vec3 material_normal;
varying float cable_surface;
void vertex() { material_position=VERTEX;material_normal=NORMAL;cable_surface=COLOR.r; }
vec2 atlas_uv(vec2 p) {
 vec2 tile=abs(fract(p*.5)*2.0-1.0);
 return vec2(.014+tile.x*.972,(float(material_band)+.055+tile.y*.890)/4.0);
}
vec3 sample_surface(vec2 source_uv) {
 if(cable_surface>.5) {
  // Periodic cylindrical projection joins the closing edge continuously.
  float angle=source_uv.x*6.28318530718;
  vec2 a=vec2(sin(angle)*.22+.31,source_uv.y/.035);
  vec2 b=vec2(cos(angle)*.22+.73,source_uv.y/.035+.37);
  float mix_weight=.5+.5*cos(angle);
  return mix(texture(detail_atlas,atlas_uv(a)).rgb,texture(detail_atlas,atlas_uv(b)).rgb,mix_weight);
 }
 vec3 p=material_position/(material_band!=3 ? .028 : .16);
 vec3 weight=pow(abs(material_normal),vec3(4.0));weight/=max(dot(weight,vec3(1.0)),.0001);
 return texture(detail_atlas,atlas_uv(p.yz)).rgb*weight.x
       +texture(detail_atlas,atlas_uv(p.xz)).rgb*weight.y
       +texture(detail_atlas,atlas_uv(p.xy)).rgb*weight.z;
}
void fragment() {
 vec3 color=sample_surface(UV);
 float lum=dot(color,vec3(.2126,.7152,.0722));
 float relief;
 if(material_band==0) {
  ALBEDO=color*.65;ROUGHNESS=clamp(.80+(1.0-lum)*.08,.74,.90);METALLIC=0.0;relief=lum*.000020;
 } else if(material_band==1) {
  ALBEDO=mix(color,vec3(lum),cloth_desaturation)*cloth_reflectance;
  ROUGHNESS=.89;METALLIC=0.0;relief=lum*.000028;
 } else if(material_band==2) {
  float oxide=smoothstep(.010,.045,color.g-color.r);
  ALBEDO=color*.75;ROUGHNESS=mix(.61,.87,oxide);METALLIC=mix(.70,.15,oxide);relief=lum*.000016;
 } else {
  ALBEDO=color*.55;ROUGHNESS=.88;METALLIC=0.0;relief=lum*.000018;
 }
 vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);vec3 r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);float determinant=dot(dx,r1);
 vec3 gradient=sign(determinant)*(dFdx(relief)*r1+dFdy(relief)*r2);
 NORMAL=normalize(max(abs(determinant),1e-12)*NORMAL-gradient);
}
