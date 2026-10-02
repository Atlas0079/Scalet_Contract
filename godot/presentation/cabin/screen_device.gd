extends Node3D
## Fixed desktop CRT. Feed generation remains owned by the cabin.
const TV = preload("res://assets/environment/television_02/television_live.gltf")
var glass: ShaderMaterial
var mesh: MeshInstance3D
var faces := PackedVector3Array()
var glow: AreaLight3D
var home := Transform3D.IDENTITY
var powered := true

func configure(at: Vector3, yaw: float, screen_scale: float):
 position = at
 rotation.y = yaw
 scale = Vector3.ONE * screen_scale
 var model = TV.instantiate()
 add_child(model)
 for node in model.find_children("*", "MeshInstance3D", true, false):
  if node.mesh.get_surface_count() > 1: mesh = node
 glass = ShaderMaterial.new()
 glass.shader = preload("res://presentation/cabin/monitor.gdshader")
 mesh.set_surface_override_material(1, glass)
 var arrays := mesh.mesh.surface_get_arrays(1)
 var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 for index in arrays[Mesh.ARRAY_INDEX]: faces.append(vertices[index])
 glow = AreaLight3D.new()
 # The emitter sits just outside the authored glass/front panel and faces the player.
 glow.position = Vector3(-0.002,0.259,0.16)
 glow.rotation.y = PI
 glow.area_size = Vector2(0.31654,0.23720)
 glow.light_color = Color.WHITE
 glow.light_energy = 60.0
 glow.area_normalize_energy = false
 glow.area_range = 1.1
 glow.area_attenuation = 1.5
 glow.shadow_enabled = true
 add_child(glow)
 home = transform

func center() -> Vector3:
 return mesh.to_global(Vector3(-0.002, 0.259, 0.115))

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
