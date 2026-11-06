shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool vertex_palette = false;
uniform vec4 emission_tint : source_color = vec4(0.0);
uniform sampler2D knowledge_texture : filter_nearest, repeat_disable;
uniform vec4 knowledge_bounds = vec4(0.0,0.0,1.0,1.0);
uniform bool knowledge_enabled = false;
varying vec3 knowledge_position;
void vertex(){knowledge_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
vec2 knowledge_at(){
 vec2 uv=(knowledge_position.xz-knowledge_bounds.xy)/knowledge_bounds.zw;
 if(any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0))))return vec2(0.0);
 return texture(knowledge_texture,uv).rg;
}
void fragment() {
 vec2 known=knowledge_enabled ? knowledge_at() : vec2(1.0);
 if(known.g<0.5)discard;
 vec3 palette = COLOR.rgb;
 if (OUTPUT_IS_SRGB) {
  palette = mix(palette * 12.92,1.055 * pow(palette,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),palette));
 }
 ALBEDO = base_color.rgb * (vertex_palette ? palette : vec3(1.0));
 ROUGHNESS = 1.0;
 EMISSION = emission_tint.rgb;
 if(known.r<0.5){float grey=dot(ALBEDO,vec3(.2126,.7152,.0722));EMISSION=mix(vec3(grey),ALBEDO,.15)*.17;ALBEDO=vec3(0.0);}
}
void light() {
 if(!knowledge_enabled || knowledge_at().r>=0.5){
  float n = max(dot(NORMAL, LIGHT), 0.0);
  DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * n / PI;
 }
}
