shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

void fragment() {
 vec2 p = UV * 2.0 - 1.0;
 float radius_squared = dot(p, p);
 float core = exp(-radius_squared * 160.0);
 float halo = exp(-radius_squared * 12.0);
 vec2 rays = mat2(vec2(0.966, 0.259), vec2(-0.259, 0.966)) * p;
 float horizontal = exp(-rays.y * rays.y * 1600.0 - abs(rays.x) * 9.0);
 float vertical = exp(-rays.x * rays.x * 1600.0 - abs(rays.y) * 11.0);
 float edge = 1.0 - smoothstep(0.65, 1.0, length(p));
 ALBEDO = edge * (
  vec3(5.0, 0.35, 0.15) * core
  + vec3(0.42, 0.009, 0.004) * halo
  + vec3(0.3, 0.005, 0.002) * (horizontal + vertical)
 );
 ALPHA = 1.0;
}
