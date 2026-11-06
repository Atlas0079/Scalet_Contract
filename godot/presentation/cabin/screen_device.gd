extends Node3D
## Fixed desktop CRT. Feed generation remains owned by the cabin.
const TV = preload("res://assets/environment/television_02/television_live.gltf")
var glass: ShaderMaterial
var mesh: MeshInstance3D
var faces := PackedVector3Array()
var face_blocks: Array[Dictionary] = []
var glow: AreaLight3D
var home := Transform3D.IDENTITY
var powered := true
var uses_crt := true
var glass_rect := Vector4(-0.16010,0.14021,0.31654,0.23720)
var glass_centre := Vector3(-0.002,0.259,0.115)
var housing_bounds := AABB()
var focus_margin := 1.35
var picture_rect := Vector4(0,0,1,1)

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
 # Bound small triangle groups once. The finer wide glass must not make every
 # pointer event walk its entire mesh in GDScript.
 for start in range(0,faces.size(),192):
  var bounds := AABB(faces[start],Vector3.ZERO)
  var end := mini(start+192,faces.size())
  for i in range(start+1,end): bounds=bounds.expand(faces[i])
  face_blocks.append({"start":start,"end":end,"bounds":bounds.grow(0.00001)})
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
 glow.area_size = Vector2(glass_rect.z,glass_rect.w)
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
 var uv := Vector2((hit.x-glass_rect.x)/glass_rect.z,1.0-(hit.y-glass_rect.y)/glass_rect.w)
 return Vector2(picture_rect.x,picture_rect.y)+uv*Vector2(picture_rect.z,picture_rect.w)

func set_picture(texture: Texture2D, source_size: Vector2i):
 # Both CRTs retain one shared simulation. The active screen receives its native
 # aspect; an unfocused screen shows a centred crop without stretching the image.
 var source_aspect := float(source_size.x)/source_size.y
 var aspect := glass_rect.z/glass_rect.w
 var extent := Vector2(minf(1.0,aspect/source_aspect),minf(1.0,source_aspect/aspect))
 picture_rect = Vector4((1.0-extent.x)*0.5,(1.0-extent.y)*0.5,extent.x,extent.y)
 glass.set_shader_parameter("picture_rect",picture_rect)
 glass.set_shader_parameter("live_picture",texture)

func picture_height() -> float:
 return glass_rect.w*mesh.global_basis.y.length()

func focus_center() -> Vector3:return center()
func focus_height() -> float:return picture_height()*focus_margin
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
 for block in face_blocks:
  if SCCombat.box_hit_fraction(origin,origin+direction*20.0,block.bounds)<0.0: continue
  for i in range(block.start,block.end,3):
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
