shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
uniform int object_id = 0;
uniform sampler2D knowledge_texture : filter_nearest, repeat_disable;
uniform vec4 knowledge_bounds = vec4(0.0,0.0,1.0,1.0);
uniform bool knowledge_enabled = false;
uniform bool current_only = false;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 if(knowledge_enabled){
  vec2 uv=(world_position.xz-knowledge_bounds.xy)/knowledge_bounds.zw;
  if(any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0))) )discard;
  vec2 known=texture(knowledge_texture,uv).rg;
  if(known.g<0.5 || (current_only && known.r<0.5))discard;
 }
 // The viewport is linear HDR, exposure 1, linear tone map and no MSAA.
 // Two normalized bytes remain exactly decodable after half-float storage.
 ALBEDO=vec3(float(object_id & 255)/255.0,float((object_id >> 8) & 255)/255.0,clamp(world_position.y/32.0,0.0,1.0));
}
