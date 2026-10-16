shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 local_position;
uniform float lens_radius = 0.466;
void vertex() { local_position = VERTEX; }
void fragment() {
    float radius = length(local_position.xy) / lens_radius;
    // Smooth optical coating. All barrel steps are geometry, not concentric shading.
    float coat = smoothstep(0.2, 1.0, radius);
    ALBEDO = mix(vec3(0.008, 0.018, 0.022), vec3(0.022, 0.014, 0.028), coat);
    METALLIC = 0.62;
    ROUGHNESS = 0.08;
    CLEARCOAT = 1.0;
    CLEARCOAT_ROUGHNESS = 0.12;
    // Faint reflected inner coating; the central sensor is separate geometry.
    EMISSION = vec3(0.0004, 0.0007, 0.0008);
}
