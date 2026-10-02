shader_type canvas_item;
render_mode unshaded;
uniform sampler2D object_mask : filter_nearest, repeat_disable;
uniform bool enabled = true;
uniform vec2 resolution = vec2(2560.0,1440.0);
uniform float outline_pixels = 3.0;
uniform vec4 ink : source_color = vec4(0.045,0.065,0.07,0.86);
float same_id(float a,float b) { return 1.0-step(0.5/255.0,abs(a-b)); }

bool exterior_of(vec2 uv,float id) {
 // A gap enclosed by this object's projection is an internal hole, not an outline.
 // Probe the complement in four directions. 256 source pixels covers the holes
 // in the current assets at the supported 0.75x–2x gameplay zoom.
 for(int axis=0;axis<4;axis++) {
  vec2 dir=axis==0 ? vec2(1.0,0.0) : axis==1 ? vec2(-1.0,0.0) : axis==2 ? vec2(0.0,1.0) : vec2(0.0,-1.0);
  bool enclosed=false;
  for(int distance=1;distance<=256;distance++) {
   vec2 p=uv+dir*float(distance)/resolution;
   if(any(lessThan(p,vec2(0.0))) || any(greaterThanEqual(p,vec2(1.0)))) return true;
   if(same_id(texture(object_mask,p).r,id)>0.5) { enclosed=true;break; }
  }
  if(!enclosed) return true;
 }
 return false;
}

void fragment() {
 vec4 scene=texture(TEXTURE,UV);
 if(enabled) {
  vec2 current=texture(object_mask,UV).rg;
  vec2 nearest=vec2(0.0);
  // All parts of a model share one ID: colors, normals and internal steps
  // cannot generate a stroke. Height only prevents drawing through an occluder.
  for(int i=0;i<8;i++) {
   float angle=float(i)*0.7853981634;
   vec2 p=UV+vec2(cos(angle),sin(angle))*outline_pixels/resolution;
   vec2 candidate=texture(object_mask,p).rg;
   if(candidate.r>0.5/255.0 && same_id(candidate.r,current.r)<0.5 && candidate.g>current.g+0.5/255.0 && candidate.g>nearest.g) nearest=candidate;
  }
  if(nearest.r>0.5/255.0 && exterior_of(UV,nearest.r)) scene.rgb=mix(scene.rgb,ink.rgb,ink.a);
 }
 COLOR=scene;
}
