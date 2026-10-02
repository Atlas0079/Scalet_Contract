shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool vertex_palette = false;
uniform vec4 emission_tint : source_color = vec4(0.0);
void fragment() {
 vec3 palette = COLOR.rgb;
 if (OUTPUT_IS_SRGB) {
  palette = mix(palette * 12.92,1.055 * pow(palette,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),palette));
 }
 ALBEDO = base_color.rgb * (vertex_palette ? palette : vec3(1.0));
 ROUGHNESS = 1.0;
 EMISSION = emission_tint.rgb;
}
void light() {
 float n = max(dot(NORMAL, LIGHT), 0.0);
 DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * n / PI;
}
