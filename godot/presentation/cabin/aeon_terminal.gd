extends "res://presentation/cabin/screen_device.gd"
## AEON uses its original black/green terminal content, independently of room CRTs.
const MODEL = preload("res://assets/environment/aeon_terminal_v8/aeon_terminal.glb")
var body_height := 0.0
var dial_material: ShaderMaterial
func configure_terminal(at: Vector3, height: float):
 super.configure(at,0.0,1.0,MODEL,"Convex CRT glass")
 for node in find_children("*","MeshInstance3D",true,false):
  for surface in range(node.mesh.get_surface_count()):
   var material: Material=node.get_active_material(surface)
   if material.resource_name=="Service-aged shell PBR atlas":
    var bounds: AABB=global_transform.affine_inverse()*node.global_transform*node.get_aabb()
    body_height=bounds.end.y-housing_bounds.position.y
   elif material.resource_name=="Aged ivory markings":
    dial_material=ShaderMaterial.new();dial_material.shader=preload("res://presentation/cabin/gauge_wear.gdshader")
    dial_material.set_shader_parameter("wear_texture",preload("res://assets/environment/aeon_terminal_v8/textures/aged_dial_ivory.png"))
    dial_material.set_shader_parameter("original_tint",material.albedo_color)
    dial_material.set_shader_parameter("original_roughness",material.roughness)
    dial_material.set_shader_parameter("original_specular",material.metallic_specular)
    node.set_surface_override_material(surface,dial_material)
 assert(body_height>0.0,"AEON casing material must identify its visible body height")
 scale=Vector3.ONE*(height/body_height)
 glow.area_size=Vector2(glass_rect.z,glass_rect.w)*scale.x
 uses_crt=false
 glass.shader=preload("res://presentation/cabin/terminal_screen.gdshader")
 glass.set_shader_parameter("glass_rect",glass_rect)
 glass.set_shader_parameter("terminal_content",preload("res://assets/environment/aeon_terminal_v8/aeon_terminal_terminal_phosphor.png"))
 home=transform
