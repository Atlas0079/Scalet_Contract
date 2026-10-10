shader_type spatial;
uniform sampler2D wear_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 original_tint : source_color;
uniform float original_roughness;
uniform float original_specular;
varying vec3 part_position;
void vertex(){part_position=VERTEX;}
void fragment(){
 vec2 centre=vec2(part_position.x<1.81 ? 1.31 : 2.31,3.04);
 vec2 offset=(part_position.xy-centre)/0.3555;
 float radius=length(offset);
 // This material also owns the knob indices; keep their authored ivory colour.
 bool face=radius<1.01 && part_position.z>1.70;
 vec2 uv=offset*0.5+0.5;
 if(part_position.x>1.81)uv=vec2(1.0-uv.y,uv.x);
 vec3 aged=texture(wear_texture,uv).rgb;
 float dust=smoothstep(0.75,1.0,radius);
 aged*=mix(1.0,0.58,dust);
 ALBEDO=face ? aged : original_tint.rgb;
 ROUGHNESS=face ? 0.94 : original_roughness;
 METALLIC=0.0;SPECULAR=face ? 0.16 : original_specular;
}
