extends Node3D

const GAIT = preload("res://presentation/tactical/tactical_gait.gd")
const FIRE_FX = preload("res://presentation/tactical/tactical_fire_fx.gd")
var stylized := false
var gait: SkeletonModifier3D
var action_time := 0.0
var current_action := "aim"
var effects: RefCounted
var character_definition: Dictionary
var shooter: SCActor
var aim_height := 1.25
var weapon_state: Dictionary
var weapon_presentation: Dictionary
var rig: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var weapon: MeshInstance3D
var effect_origin := Vector2.ZERO
var aim_target := Vector2(0, -2.5)
var shot_age := 10.0
var pending_shots: Array[Dictionary] = []
var frame_delta := 0.0
var previous_pose: Dictionary = {}
var previous_origin := Vector2.ZERO
var muzzle_socket := Vector3.ZERO
var casing_socket := Vector3.ZERO
var flash_materials: Array[Dictionary] = []
var last_muzzle := Vector3.ZERO
var last_port := Vector3.ZERO

func _ready():
	weapon_presentation = SCData.catalog.presentation.weapons[weapon_state.definition.presentation]
	effects = FIRE_FX.new(weapon_state)
	var socket: Array = weapon_presentation.casing_socket_source_units
	casing_socket = Vector3(socket[0], socket[1], socket[2])
	build_lighting()
	build_character()
	player.play(weapon_presentation.clips.aim)
	player.advance(0.0)
	if stylized:
		style_character()
	else:
		var mat: StandardMaterial3D = weapon.material_override
		flash_materials.append({"material": mat, "base": mat.albedo_color, "weight": 0.7})
	gait = GAIT.new()
	skeleton.add_child(gait)
	gait.recoil_settings = weapon_presentation.recoil
	var posture: Dictionary = SCData.catalog.presentation.characters[character_definition.presentation]
	gait.waist_limit = posture.waist_limit_degrees
	gait.aim_limit = posture.aim_limit_degrees
	gait.pitch_limit = posture.aim_pitch_limit_degrees
	gait.shooter = shooter
	gait.nominal_speed = maxf(0.01, shooter.speed)
	gait.configure()
	gait.gun_bind = weapon.transform
	gait.gun_muzzle = muzzle_socket
	gait.modification_processed.connect(update_fire_sockets)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.advance(0.0)

func material(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result

func configure_weapon(state: Dictionary):
	weapon_state = state
	weapon_presentation = SCData.catalog.presentation.weapons[state.definition.presentation]
	effects.configure(state)
	var socket: Array = weapon_presentation.casing_socket_source_units
	casing_socket = Vector3(socket[0], socket[1], socket[2])
	gait.recoil_settings = weapon_presentation.recoil
	if stylized: style_weapon()
	clear_fire()
	trigger("aim")

func build_character():
	rig = load(weapon_presentation.rig).instantiate()
	add_child(rig)
	skeleton = rig.find_children("*", "Skeleton3D", true, false)[0]
	player = rig.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "Rifle":
			weapon = mesh
			mesh.material_override = material(Color("374247"), 0.75)
		else:
			mesh.set_surface_override_material(0, material(Color("a7aba1"), 0.78))
			mesh.set_surface_override_material(1, material(Color("333b3d"), 0.92))
	assert(weapon != null, "Configured rig must contain its weapon mesh")
	for clip in weapon_presentation.clips.values():
		assert(player.has_animation(clip), "Missing configured animation: " + clip)
	var end_y := weapon.get_aabb().end.y
	var count := 0
	for surface in range(weapon.mesh.get_surface_count()):
		for vertex in weapon.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			if vertex.y > end_y - 0.5:
				muzzle_socket += vertex
				count += 1
	assert(count > 0)
	muzzle_socket /= count

func build_lighting():
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b3c8d7")
	env.ambient_light_energy = 0.4
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	add_child(key)
	key.rotation_degrees = Vector3(-75, -38, 0)
	key.light_energy = 0.8

func toon_material(color: Color, vertex_palette := false) -> ShaderMaterial:
	var style: Dictionary = SCData.catalog.presentation.characters[character_definition.presentation].style
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://presentation/tactical/mannequin_toon.gdshader")
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("use_vertex_palette", vertex_palette)
	mat.set_shader_parameter("shade_bands", int(style.shade_bands))
	mat.set_shader_parameter("shadow_floor", style.shadow_floor)
	return mat

func style_character():
	# Retain every original vertex, normal, skin weight and animation. Only add
	# palette colors; the existing skin already tells us which region it is.
	var style: Dictionary = SCData.catalog.presentation.characters[character_definition.presentation].style
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		if node == weapon: continue
		var colored := ArrayMesh.new()
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var colors := PackedColorArray()
			var influences := bones.size() / vertices.size()
			for i in range(vertices.size()):
				var strongest := 0
				for j in range(1, influences):
					if weights[i * influences + j] > weights[i * influences + strongest]: strongest = j
				var bind: int = bones[i * influences + strongest]
				var bone_name: String = node.skin.get_bind_name(bind)
				if bone_name.is_empty(): bone_name = skeleton.get_bone_name(node.skin.get_bind_bone(bind))
				var color := Color(style.body_color)
				for prefix in style.bone_colors:
					if bone_name.begins_with(prefix):
						color = Color(style.bone_colors[prefix])
						break
				if surface == 1: color = Color(style.joint_color)
				colors.append(color.srgb_to_linear())
			arrays[Mesh.ARRAY_COLOR] = colors
			colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			colored.surface_set_material(surface, toon_material(Color.WHITE, true))
		node.mesh = colored
		for surface in range(colored.get_surface_count()): node.set_surface_override_material(surface, null)
	style_weapon()

func style_weapon():
	flash_materials.clear()
	weapon.material_override = toon_material(Color(weapon_presentation.style.color))
	flash_materials.append({"material": weapon.material_override, "weight": weapon_presentation.style.flash_strength})

func trigger(clip: String, angular_error := Vector2.ZERO, elapsed_since_shot := 0.0):
	if clip == "shoot":
		if current_action == "reload": return
		# Repeated impulses, not repeated restarts of the 0.8 s single-shot clip.
		shot_age = elapsed_since_shot
		pending_shots.append({"error": angular_error, "holding":SCCombat.holding_error(shooter), "age": elapsed_since_shot, "target": Vector3(aim_target.x, aim_height, aim_target.y)})
		return
	current_action = clip
	action_time = 0.0
	player.play(weapon_presentation.clips.reload if clip == "reload" else weapon_presentation.clips.aim, 0.10)
	if clip == "reload":
		pending_shots.clear()
		shot_age = 10.0

func clear_fire():
	gait.clear_recoil()
	effects.clear()
	pending_shots.clear()
	shot_age = 10.0
	previous_pose.clear()

func update_fire_sockets():
	# Derive from the just-modified right hand; BoneAttachment updates may run
	# later in the frame. Thus flashes and ejection use this shot's gun pose.
	var gun_pose: Transform3D = skeleton.global_transform * gait.grip_pose * weapon.transform
	var offset := Vector3(effect_origin.x, 0, effect_origin.y)
	last_muzzle = gun_pose * muzzle_socket + offset
	last_port = gun_pose * casing_socket + offset
	var barrel := gun_pose.basis.y.normalized()
	var forward_2d := Vector2(barrel.x, barrel.z).normalized()
	effects.muzzle = Vector2(last_muzzle.x, last_muzzle.z)
	effects.forward = forward_2d
	for shot in pending_shots:
		# Interpolate the neutral animation, then solve this shot's holding pose.
		# Do not interpolate already-kicked barrels or apply holding error twice.
		var fraction := 1.0 - clampf(shot.age / maxf(frame_delta, 0.000001), 0.0, 1.0)
		var context: Dictionary = gait.pose_context.duplicate()
		var origin := effect_origin
		if not previous_pose.is_empty():
			context.gun = previous_pose.gun.interpolate_with(context.gun,fraction)
			for key in ["pivot","support","shoulder"]: context[key] = previous_pose[key].lerp(context[key],fraction)
			for key in ["low","high","reach"]: context[key] = lerpf(previous_pose[key],context[key],fraction)
			origin = previous_origin.lerp(effect_origin,fraction)
		var shot_gun: Transform3D = gait.solve_aim(context,shot.target-Vector3(origin.x,0,origin.y),shot.holding).gun
		var socket := shot_gun * muzzle_socket + Vector3(origin.x,0,origin.y)
		var port := shot_gun * casing_socket + Vector3(origin.x,0,origin.y)
		var direction := SCCombat.shot_direction(shot_gun.basis.y.normalized(), shot.error)
		var shot_right := -shot_gun.basis.x.normalized()
		socket = effects.clear_muzzle_origin(Vector3(origin.x, socket.y, origin.y), socket)
		effects.emit_shot(socket, port, direction, Vector2(shot_right.x, shot_right.z).normalized(), shot.age,shot.target)
	pending_shots.clear()
	previous_pose = gait.pose_context.duplicate()
	previous_origin = effect_origin
	# Muzzle flashes follow the gun, never the random ballistic deviation.
	effects.muzzle = Vector2(last_muzzle.x, last_muzzle.z)
	effects.forward = forward_2d
	effects.shooter_position = effect_origin
	var neutral_gun:Transform3D=gait.pose_context.gun
	var neutral_muzzle:=neutral_gun*muzzle_socket
	var reach:float=neutral_muzzle.distance_to(gait.pose_context.pivot)
	effects.reticle = SCCombat.reticle_bounds(shooter, neutral_muzzle+offset, neutral_gun.basis.y.normalized(), Vector3(aim_target.x, aim_height, aim_target.y),reach)
	var light := maxf(0.0, 1.0 - shot_age / 0.07)
	for entry in flash_materials:
		if entry.material is ShaderMaterial:
			entry.material.set_shader_parameter("flash", light * entry.weight)
		else:
			entry.material.albedo_color = entry.base.lerp(Color("fff0bc"), light * entry.weight)

func advance_unit(delta: float, yaw: float, local_velocity: Vector2, turning: float):
	frame_delta = delta
	for shot in pending_shots: shot.age += delta
	rig.rotation.y = yaw
	gait.aim_enabled = current_action != "reload"
	var relative := aim_target - effect_origin
	gait.aim_target = skeleton.global_transform.affine_inverse() * Vector3(relative.x, aim_height, relative.y)
	action_time += delta
	shot_age += delta
	var animation_delta := delta
	if current_action == "reload":
		animation_delta *= player.get_animation(weapon_presentation.clips.reload).length / weapon_state.definition.reload_time * shooter.operation_rate("reload")
	if current_action == "aim": player.seek(0.0,true)
	else: player.advance(animation_delta)
	if current_action != "aim" and not player.is_playing():
		current_action = "aim"
		player.play(weapon_presentation.clips.aim, 0.15)
	gait.advance_gait(delta, local_velocity, turning)
