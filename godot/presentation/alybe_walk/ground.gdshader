shader_type spatial;
render_mode cull_back;
uniform vec4 surface_color : source_color = vec4(0.3,0.34,0.3,1.0);
uniform bool show_grid = true;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 cell=abs(fract(world_position.xz)-0.5);
 vec2 aa=max(fwidth(world_position.xz),vec2(0.002));
 float grid=max(smoothstep(0.485-aa.x,0.49,cell.x),smoothstep(0.485-aa.y,0.49,cell.y));
 float grain=fract(sin(dot(floor(world_position.xz*25.0),vec2(127.1,311.7)))*43758.5453);
 ALBEDO=surface_color.rgb*(0.94+grain*0.09)*(show_grid?mix(1.0,0.64,grid):1.0);
 ROUGHNESS=0.88;
}
