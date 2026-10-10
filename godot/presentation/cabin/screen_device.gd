extends Node3D
## Fixed desktop CRT. Feed generation remains owned by the cabin.
const TV = preload("res://assets/environment/television_02/television_live.gltf")
var glass: ShaderMaterial
var mesh: MeshInstance3D
var faces := PackedVector3Array()
var glow: AreaLight3D
var home := Transform3D.IDENTITY
var powered := true
var uses_crt := true
var glass_rect := Vector4(-0.16010,0.14021,0.31654,0.23720)
var glass_centre := Vector3(-0.002,0.259,0.115)
var housing_bounds := AABB()

func configure(at: Vector3, yaw: float, screen_scale: float, scene: PackedScene = TV, glass_name := ""):
 position = at
 rotation.y = yaw
 scale = Vector3.ONE * screen_scale
 var model = scene.instantiate()
 add_child(model)
 var first := true
 for node in model.find_children("*", "MeshInstance3D", true, false):
  var bounds: AABB=global_transform.affine_inverse()*node.global_transform*node.get_aabb()
  housing_bounds=bounds if first else housing_bounds.merge(bounds);first=false
  if (glass_name.is_empty() and node.mesh.get_surface_count()>1) or String(node.name)==glass_name:mesh=node
 var surface := 1 if glass_name.is_empty() else 0
 glass = ShaderMaterial.new()
 glass.shader = preload("res://presentation/cabin/monitor.gdshader")
 mesh.set_surface_override_material(surface, glass)
 var arrays := mesh.mesh.surface_get_arrays(surface)
 var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 for index in arrays[Mesh.ARRAY_INDEX]: faces.append(vertices[index])
 if not glass_name.is_empty():
  var bounds:=AABB(vertices[0],Vector3.ZERO)
  for vertex in vertices:bounds=bounds.expand(vertex)
  glass_rect=Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y)
  glass_centre=bounds.get_center()
 glass.set_shader_parameter("glass_rect",glass_rect)
 glow = AreaLight3D.new()
 # The emitter sits just outside the authored glass/front panel and faces the player.
 glow.position = Vector3(-0.002,0.259,0.16) if glass_name.is_empty() else mesh.transform*(glass_centre+Vector3(0,0,0.06))
 glow.rotation.y = PI
 glow.area_size = Vector2(glass_rect.z,glass_rect.w)*(1.0 if glass_name.is_empty() else screen_scale)
 glow.light_color = Color("8daac6")
 glow.light_energy = 5.0
 glow.area_normalize_energy = false
 glow.area_range = 1.1
 glow.area_attenuation = 1.5
 glow.shadow_enabled = true
 glow.light_size = 0.06
 glow.shadow_bias = 0.01
 glow.shadow_normal_bias = 0.2
 add_child(glow)
 home = transform

func center() -> Vector3:
 return mesh.to_global(glass_centre)

func picture_uv(hit: Vector3) -> Vector2:
 return Vector2((hit.x-glass_rect.x)/glass_rect.z,1.0-(hit.y-glass_rect.y)/glass_rect.w)

func picture_height() -> float:
 return glass_rect.w*mesh.global_basis.y.length()

func focus_center() -> Vector3:return center()
func focus_height() -> float:return picture_height()*1.35
func release_controls():pass

func set_power(value: bool):
 powered = value
 glass.set_shader_parameter("powered", value)
 glow.visible = value

func intersect(camera: Camera3D, point: Vector2) -> Variant:
 var inverse := mesh.global_transform.affine_inverse()
 var origin := inverse * camera.project_ray_origin(point)
 var direction := (inverse.basis * camera.project_ray_normal(point)).normalized()
 var nearest: Variant = null
 var distance := INF
 for i in range(0, faces.size(), 3):
  var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, faces[i], faces[i+1], faces[i+2])
  if hit != null and origin.distance_squared_to(hit) < distance:
   distance = origin.distance_squared_to(hit)
   nearest = hit
 return nearest

func housing_hit(camera: Camera3D, point: Vector2) -> Variant:
 # Coarse housing selection; precise glass triangles still own game input mapping.
 var inverse := global_transform.affine_inverse()
 var origin := inverse*camera.project_ray_origin(point)
 var end := origin+inverse.basis*camera.project_ray_normal(point)*20.0
 var fraction := SCCombat.box_hit_fraction(origin,end,housing_bounds)
 return to_global(origin.lerp(end,fraction)) if fraction >= 0.0 else null
