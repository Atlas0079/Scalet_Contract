shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;
uniform float reflection_energy = 0.0;

// A transparent coated element over real iris geometry. The two soft highlights
// represent inspection softboxes; curvature and view direction determine their shape.
void fragment() {
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 4.0);
    vec3 reflected = reflect(-normalize(VIEW), normalize(NORMAL));
    float key = pow(max(dot(reflected, normalize(vec3(-.60,.46,1.0))),0.0),100.0);
    float strip = pow(max(dot(reflected, normalize(vec3(.72,-.20,1.0))),0.0),210.0);
    ALBEDO = mix(vec3(.018,.042,.048),vec3(.065,.032,.083),fresnel);
    METALLIC = .08;
    ROUGHNESS = .055;
    CLEARCOAT = 1.0;
    CLEARCOAT_ROUGHNESS = .06;
    EMISSION = (vec3(.32,.43,.52)*key + vec3(.16,.20,.28)*strip)*reflection_energy;
    ALPHA = .025 + .20*fresnel + .065*key + .04*strip;
}
