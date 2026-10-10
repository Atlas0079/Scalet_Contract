shader_type spatial;
render_mode cull_disabled;
uniform sampler2D aged_atlas: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D body_source: source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int surface_kind = 0;
uniform vec2 uv_to_metres = vec2(1.0);
uniform mat4 surface_to_toy;
uniform mat4 normal_to_toy;
varying vec3 toy_position;
varying vec3 toy_normal;
void vertex() {
 toy_position=(surface_to_toy*vec4(VERTEX,1.0)).xyz;
 toy_normal=normalize((normal_to_toy*vec4(NORMAL,0.0)).xyz);
}
vec2 band_uv(vec2 uv,float band) {
 vec2 mirrored=abs(fract(uv*.5)*2.0-1.0);
 return vec2(.015+mirrored.x*.970,(band+.055+mirrored.y*.890)/3.0);
}
vec3 material_sample(float band,float metres,vec2 source_uv) {
 if(surface_kind==2)return texture(aged_atlas,band_uv(source_uv*uv_to_metres/metres,band)).rgb;
 vec3 p=toy_position/metres;
 vec3 weights=pow(abs(toy_normal),vec3(4.0));weights/=max(dot(weights,vec3(1.0)),.0001);
 return texture(aged_atlas,band_uv(p.yz,band)).rgb*weights.x
       +texture(aged_atlas,band_uv(p.xz,band)).rgb*weights.y
       +texture(aged_atlas,band_uv(p.xy,band)).rgb*weights.z;
}
void fragment() {
 float band=surface_kind==1 ? 1.0 : (surface_kind==2 ? 2.0 : 0.0);
 float metres=surface_kind==2 ? .012 : .024;
 vec3 color=material_sample(band,metres,UV);
 float lum=dot(color,vec3(.2126,.7152,.0722));
 float rust=smoothstep(.012,.050,color.r-color.g);
 float grey=1.0-smoothstep(.008,.045,max(color.r,max(color.g,color.b))-min(color.r,min(color.g,color.b)));
 float relief=.0;
 if(surface_kind==0 || surface_kind==3) {
  // Replace the clean rubber appearance with aged plastic. Source UV colour
  // regions identify the actual painted eyes and orange bill, not flat decals.
  vec3 source=texture(body_source,UV).rgb;
  float ink=1.0-smoothstep(.015,.080,dot(source,vec3(.2126,.7152,.0722)));
  float neutral=1.0-smoothstep(.015,.080,max(source.r,max(source.g,source.b))-min(source.r,min(source.g,source.b)));
  float eye=max(ink,neutral);
  float orange=smoothstep(.26,.50,source.r-source.g)*(1.0-smoothstep(.24,.38,source.g));
  float dust=1.0-smoothstep(.033,.068,toy_position.y);
  ALBEDO=color*(.88-.18*dust);
  ALBEDO=mix(ALBEDO,source*(.57+.50*lum),orange);
  // Remove the source's painted white shine; the eyes reflect scene lighting.
  ALBEDO=mix(ALBEDO,vec3(.007,.009,.008)+vec3(lum*.010),eye);
  ROUGHNESS=mix(clamp(.66+(1.0-lum)*.16,.57,.88),.25+lum*.08,eye);
  METALLIC=0.0;
  relief=(lum-.18)*.000040*(1.0-eye);
  if(surface_kind==3){ALBEDO=color*.62;ROUGHNESS=.85;relief*=.35;}
 } else if(surface_kind==1) {
  ALBEDO=color*.82;
  METALLIC=mix(.10,.78,grey*smoothstep(.04,.18,lum));
  METALLIC=mix(METALLIC,.01,rust);
  ROUGHNESS=mix(.78,.51,grey);ROUGHNESS=mix(ROUGHNESS,.91,rust);
  relief=(lum-.10)*.00014;
 } else if(surface_kind==2) {
  ALBEDO=color*.78;METALLIC=mix(.82,.08,rust);ROUGHNESS=mix(.46,.90,rust);
  relief=(lum-.12)*.000014;
 } else {
  ALBEDO=vec3(.017,.021,.019)*(1.0+lum*.3);ROUGHNESS=.88;METALLIC=0.0;relief=lum*.000015;
 }
 // Surface-gradient bump from the generated image, in view space. Geometry
 // and material classes supply the macro shape; this is only fine relief.
 vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
 vec3 r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);
 float determinant=dot(dx,r1);
 vec3 gradient=sign(determinant)*(dFdx(relief)*r1+dFdy(relief)*r2);
 NORMAL=normalize(max(abs(determinant),1e-12)*NORMAL-gradient);
}
