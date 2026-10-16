shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;
uniform float reflection_energy = 0.0;
void fragment() {
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(VIEW);
    float fresnel = pow(1.0 - clamp(dot(n,v),0.0,1.0),5.0);
    vec3 reflected = reflect(-v,n);
    // Curved front cover: broad off-axis card plus a narrow edge reflection.
    float card = exp(-pow((reflected.y-.15)/.035,4.0)) * exp(-pow((reflected.x+.14)/.15,4.0));
    float edge = exp(-pow((reflected.x-.24)/.024,4.0)) * exp(-pow((reflected.y+.10)/.13,4.0));
    ALBEDO = mix(vec3(.025,.048,.058),vec3(.075,.052,.095),fresnel);
    METALLIC = 0.0;
    ROUGHNESS = .045;
    SPECULAR = .5;
    CLEARCOAT = 1.0;
    CLEARCOAT_ROUGHNESS = .04;
    EMISSION = (vec3(.48,.62,.72)*card+vec3(.18,.24,.30)*edge)*reflection_energy;
    ALPHA = clamp(.025+.32*fresnel+reflection_energy*(.27*card+.13*edge),0.0,.65);
}
