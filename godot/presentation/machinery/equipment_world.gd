extends Node3D

const ASSETS := "res://assets/environment/"
var obstacles: Array[Dictionary] = []
var eye: Camera3D

func _ready():
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("252527")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ffffff")
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.35
	environment.ssao_intensity = 1.4
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-66,-28,0)
	key.light_color = Color.WHITE
	key.light_energy = 0.68
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 20
	key.shadow_bias = 0.015
	key.shadow_normal_bias = 0.25
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38,140,0)
	fill.light_color = Color("f0f3ff")
	fill.light_energy = 0.14
	add_child(fill)
	eye = Camera3D.new()
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = 6.0
	eye.position = Vector3(0,12,0)
	add_child(eye)
	eye.look_at(Vector3.ZERO,Vector3.FORWARD)
	eye.current = true
	eye.near = 0.1
	eye.far = 30
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_texture = load(ASSETS+"concrete_floor_worn_001/diff.jpg")
	floor_material.normal_enabled = true
	floor_material.normal_texture = load(ASSETS+"concrete_floor_worn_001/nor_gl.jpg")
	floor_material.normal_scale = 0.65
	floor_material.roughness_texture = load(ASSETS+"concrete_floor_worn_001/rough.jpg")
	floor_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	floor_material.uv1_scale = Vector3(7.6/3.0,4.8/3.0,1)
	floor_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(7.6,4.8)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_material
	add_child(floor_node)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color("c9c5bc")
	wall_material.normal_enabled = true
	wall_material.normal_texture = floor_material.normal_texture
	wall_material.normal_scale = 0.3
	wall_material.roughness = 0.94
	wall_material.uv1_triplanar = true
	wall_material.uv1_scale = Vector3.ONE*0.6
	for rect in [Rect2(-3.8,-2.4,7.6,0.2),Rect2(-3.8,-2.2,0.2,4.6),Rect2(3.6,-2.2,0.2,4.6),Rect2(-3.6,2.2,3.0,0.2),Rect2(0.6,2.2,3.0,0.2)]:
		box(Vector3(rect.get_center().x,0.65,rect.get_center().y),Vector3(rect.size.x,1.3,rect.size.y),wall_material)
		obstacle(rect,3.0,"墙体")
	var equipment: Node3D = load(ASSETS+"old_military_compressor/old_military_compressor_2k.gltf").instantiate()
	add_child(equipment)
	equipment.rotation.y = PI/2
	var bounds := mesh_bounds(equipment)
	equipment.position = Vector3(-0.65-bounds.get_center().x,-bounds.position.y,-0.45-bounds.get_center().z)
	bounds = mesh_bounds(equipment)
	obstacle(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),bounds.size.y,"压缩机")
	print("EQUIPMENT_BOUNDS ",bounds)

func box(at: Vector3, size: Vector3, material: Material):
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)

func obstacle(rect: Rect2, height: float, label: String):
	obstacles.append({"id":"equipment_%d"%obstacles.size(),"rect":rect,"height":height,"label":label,"kind":"solid"})

func mesh_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB = node.global_transform * node.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result
