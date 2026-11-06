shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D knowledge_texture : filter_nearest, repeat_disable;
uniform vec4 knowledge_bounds = vec4(0.0,0.0,1.0,1.0);
uniform bool knowledge_enabled = false;
uniform vec4 base_color : source_color = vec4(0.29,0.34,0.34,1.0);
uniform bool metre_grid = true;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
vec2 knowledge_at(){
 vec2 uv=(world_position.xz-knowledge_bounds.xy)/knowledge_bounds.zw;
 if(any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0))))return vec2(0.0);
 return texture(knowledge_texture,uv).rg;
}
void fragment(){
 vec2 known=knowledge_enabled ? knowledge_at() : vec2(1.0);
 if(known.g<0.5)discard;
 vec3 color=base_color.rgb;
 if(metre_grid){
  vec2 d=abs(fract(world_position.xz+0.5)-0.5);
  vec2 aa=max(fwidth(world_position.xz),vec2(.001));
  vec2 grid=1.0-smoothstep(vec2(.012),vec2(.012)+aa,d);
  color*=1.0-max(grid.x,grid.y)*.14;
 }
 ALBEDO=color;ROUGHNESS=.95;
 if(known.r<.5){float grey=dot(color,vec3(.2126,.7152,.0722));EMISSION=mix(vec3(grey),color,.15)*.17;ALBEDO=vec3(0.0);}
}
void light(){if(!knowledge_enabled || knowledge_at().r>=.5){DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*max(dot(NORMAL,LIGHT),0.0)/PI;}}
