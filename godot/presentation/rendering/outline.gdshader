shader_type canvas_item;
render_mode unshaded;
uniform sampler2D object_mask : filter_nearest, repeat_disable;
uniform bool enabled = true;
uniform vec2 resolution = vec2(2560.0,1440.0);
uniform float outline_pixels = 3.0;
uniform vec4 ink : source_color = vec4(0.045,0.065,0.07,0.86);
int decode_id(vec2 bytes){ivec2 b=ivec2(round(bytes*255.0));return b.x+(b.y<<8);}

bool exterior_of(vec2 uv,int id) {
 // A gap enclosed by this object's projection is an internal hole, not an outline.
 // Probe the complement in four directions. 256 source pixels covers the holes
 // in the current assets at the supported 0.75x–2x gameplay zoom.
 for(int axis=0;axis<4;axis++) {
  vec2 dir=axis==0 ? vec2(1.0,0.0) : axis==1 ? vec2(-1.0,0.0) : axis==2 ? vec2(0.0,1.0) : vec2(0.0,-1.0);
  bool enclosed=false;
  for(int distance=1;distance<=256;distance++) {
   vec2 p=uv+dir*float(distance)/resolution;
   if(any(lessThan(p,vec2(0.0))) || any(greaterThanEqual(p,vec2(1.0)))) return true;
   if(decode_id(texture(object_mask,p).rg)==id) { enclosed=true;break; }
  }
  if(!enclosed) return true;
 }
 return false;
}

void fragment() {
 vec4 scene=texture(TEXTURE,UV);
 if(enabled) {
  vec3 current=texture(object_mask,UV).rgb;
  int current_id=decode_id(current.rg);
  vec3 nearest=vec3(0.0);
  int nearest_id=0;
  // All parts of a model share one ID: colors, normals and internal steps
  // cannot generate a stroke. Height only prevents drawing through an occluder.
  for(int i=0;i<8;i++) {
   float angle=float(i)*0.7853981634;
   vec2 p=UV+vec2(cos(angle),sin(angle))*outline_pixels/resolution;
   vec3 candidate=texture(object_mask,p).rgb;
   int candidate_id=decode_id(candidate.rg);
   if(candidate_id!=0 && candidate_id!=current_id && candidate.b>current.b+0.5/1024.0 && candidate.b>nearest.b){nearest=candidate;nearest_id=candidate_id;}
  }
  if(nearest_id!=0 && exterior_of(UV,nearest_id)) scene.rgb=mix(scene.rgb,ink.rgb,ink.a);
 }
 COLOR=scene;
}
