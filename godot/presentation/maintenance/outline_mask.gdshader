shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
uniform float object_id = 0.0;
void fragment() {
 // R: logical object identity. G: visible surface height for overlap ordering.
 float height=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).y;
 ALBEDO=vec3(object_id/255.0,clamp(height/8.0,0.0,1.0),0.0);
}
