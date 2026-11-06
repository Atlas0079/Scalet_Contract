shader_type canvas_item;
render_mode unshaded;
uniform sampler2D knowledge_texture : filter_nearest, repeat_disable;
uniform vec4 knowledge_bounds=vec4(0.0,0.0,1.0,1.0);
uniform vec2 view_origin=vec2(0.0);
uniform vec2 view_axis_x=vec2(1.0,0.0);
uniform vec2 view_axis_y=vec2(0.0,1.0);
uniform vec2 display_size=vec2(2304.0,1440.0);
void fragment(){
 vec2 screen_uv=FRAGCOORD.xy/display_size;
 vec2 world=view_origin+screen_uv.x*view_axis_x+screen_uv.y*view_axis_y;
 vec2 uv=(world-knowledge_bounds.xy)/knowledge_bounds.zw;
 if(any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0))) || texture(knowledge_texture,uv).g<.5)discard;
 COLOR*=texture(TEXTURE,UV);
}
