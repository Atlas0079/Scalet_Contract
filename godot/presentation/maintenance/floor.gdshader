shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p = world_position.xz;
 vec3 work = vec3(0.3725,0.4078,0.3922);
 vec3 corridor = vec3(0.3255,0.3922,0.4118);
 vec3 color = p.y < 1.05 ? work : corridor;
 // Analytical metre grid with a footprint-aware edge: no subpixel gaps between tiles.
 vec2 d = abs(fract(p+0.5)-0.5);
 vec2 aa = max(fwidth(p),vec2(0.001));
 vec2 seam = 1.0-smoothstep(vec2(0.008),vec2(0.008)+aa,d);
 color *= 1.0-max(seam.x,seam.y)*0.16;
 if (!OUTPUT_IS_SRGB) color = pow(color,vec3(2.2));
 ALBEDO = color;
 ROUGHNESS = 1.0;
}
void light() {
 float n = max(dot(NORMAL,LIGHT),0.0);
 DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * n / PI;
}
