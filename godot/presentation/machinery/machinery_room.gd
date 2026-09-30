extends Node2D
const WORLD = preload("res://presentation/machinery/equipment_world.gd")
const ACTOR = preload("res://presentation/tactical/tactical_actor.gd")
const FIRE_FX = preload("res://presentation/tactical/tactical_fire_fx.gd")
const PPM := 200.0
const DESIGN := Vector2i(1920,1200)
const ORIGIN := Vector2(960,600)
var world: Node3D
var world_view: SubViewport
var background: Sprite2D
var character: SCActor
var unit: Node3D
var actor_view: SubViewport
var sprite: Sprite2D
var shadow: Sprite2D
var camera: Camera2D
var fx_views: Array[Node2D] = []
var velocity := Vector2.ZERO
var facing := -PI/2
var target := Vector2(-0.6,-0.3)
var cooldown := 0.0
var trigger_held := false
var paused := false
var simulation_time := 0.0
var aim_speed := 0.0
var aim_turn_rate := 0.0
var rng := RandomNumberGenerator.new()
var status: Label
var overlay: Node2D
var hud: CanvasLayer
var shots := 0

class RoomAirEffects extends FIRE_FX.View:
	func _draw():
		var bounds: Dictionary = effects.reticle
		effects.reticle = {"valid": false}
		effects.draw_air(self,origin,pixels_per_cell)
		effects.reticle = bounds

class RoomGroundEffects extends Node2D:
	var effects: RefCounted
	func _draw():
		for shell in effects.casings:
			if shell.settled: effects.draw_shell(self,shell,Vector2(960,600),200.0)
		for mark in effects.hit_marks:
			var p: Vector2 = Vector2(960,600)+mark.p*200.0
			var color := Color("9b7356")
			color.a = minf(0.8,(SCData.study.range.impact_lifetime_seconds-mark.age)/1.5)
			draw_circle(p,2,color,true,-1,true)

class AimOverlay extends Node2D:
	var room: Node2D
	func _draw():
		var t: Vector2 = room.ORIGIN+room.target*room.PPM
		for axis in [Vector2.RIGHT,Vector2.DOWN]:
			draw_line(t+axis*5,t+axis*10,Color("d8d5cc"),1,true)
			draw_line(t-axis*5,t-axis*10,Color("d8d5cc"),1,true)

func _ready():
	if not SCData.ensure_valid(get_tree()): return
	get_window().title = "Scarlet Contract · Equipment Study"
	get_window().content_scale_size = DESIGN
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_window().min_size = Vector2i(960,600)
	get_window().size = Vector2i(1536,960)
	RenderingServer.set_default_clear_color(Color("252527"))
	world_view = SubViewport.new()
	world_view.size = DESIGN
	world_view.own_world_3d = true
	world_view.msaa_3d = Viewport.MSAA_4X
	add_child(world_view)
	world = WORLD.new()
	world_view.add_child(world)
	background = Sprite2D.new()
	background.texture = world_view.get_texture()
	background.position = ORIGIN
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(background)
	camera = Camera2D.new()
	camera.position = ORIGIN
	add_child(camera)
	character = SCActor.new(0,"行动员","red",Vector2(0.45,1.05),-PI/2,SCData.study.unit)
	character.training_enabled = false
	rng.seed = 92032
	make_actor()
	get_window().size_changed.connect(update_resolution)
	update_resolution()
	build_hud()
	overlay = AimOverlay.new()
	overlay.room = self
	overlay.z_index = 8
	add_child(overlay)
	get_window().focus_exited.connect(release_trigger)
	step(0.016,Vector2.ZERO)
	if "--capture-room" in OS.get_cmdline_user_args(): capture.call_deferred()

func make_actor():
	actor_view = SubViewport.new()
	actor_view.size = Vector2i(640,640)
	actor_view.transparent_bg = true
	actor_view.own_world_3d = true
	actor_view.msaa_3d = Viewport.MSAA_4X
	actor_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(actor_view)
	unit = ACTOR.new()
	unit.stylized = true
	unit.character_definition = character.definition
	unit.shooter = character
	unit.aim_height = 1.25
	unit.weapon_state = character.weapon
	actor_view.add_child(unit)
	unit.effects.targets.clear()
	unit.effects.obstacles = world.obstacles
	for child in unit.get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_color = Color.WHITE
			child.environment.ambient_light_energy = 0.52
		if child is DirectionalLight3D:
			child.rotation_degrees = Vector3(-66,-28,0)
			child.light_color = Color("fff9ed")
	var eye := Camera3D.new()
	actor_view.add_child(eye)
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = 2.6
	eye.position = Vector3(0,8,0)
	eye.look_at(Vector3.ZERO,Vector3.FORWARD)
	eye.current = true
	shadow = Sprite2D.new()
	shadow.texture = actor_view.get_texture()
	shadow.scale = Vector2.ONE*(2.6*PPM/640)
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = preload("res://presentation/tactical/silhouette_shadow.gdshader")
	shadow.material = shadow_material
	shadow.z_index = 3
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture = actor_view.get_texture()
	sprite.scale = Vector2.ONE*(2.6*PPM/640)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = 4
	add_child(sprite)
	for ground in [true,false]:
		var view = RoomGroundEffects.new() if ground else RoomAirEffects.new()
		view.effects = unit.effects
		if not ground:
			view.pixels_per_cell = PPM
			view.origin = ORIGIN
		view.z_index = 2 if ground else 5
		add_child(view)
		fx_views.append(view)

func build_hud():
	hud = CanvasLayer.new()
	add_child(hud)
	label_at("SCARLET CONTRACT   /   EQUIPMENT STUDY",Vector2(76,36),19,Color("d3d0c8"))
	label_at("设备与材质小样",Vector2(76,67),14,Color("999892"))
	label_at("WASD 移动   ·   鼠标瞄准 / 左键射击   ·   R 换弹   ·   空格暂停",Vector2(76,1118),16,Color("bcbab3"))
	label_at("滚轮缩放   ·   中键平移   ·   HOME 复位   ·   TAB 隐藏界面",Vector2(76,1150),14,Color("999892"))
	status = label_at("",Vector2(1450,1120),15,Color("bcbab3"))

func update_resolution():
	var window_factor := minf(float(get_window().size.x)/DESIGN.x,float(get_window().size.y)/DESIGN.y)
	var factor := maxf(1.0,ceilf(window_factor*camera.zoom.x*4)/4)
	world_view.size = Vector2i(Vector2(DESIGN)*factor)
	background.scale = Vector2.ONE/factor
	var side := maxi(256,ceili(2.6*PPM*window_factor*camera.zoom.x/16)*16)
	actor_view.size = Vector2i(side,side)
	sprite.scale = Vector2.ONE*(2.6*PPM/side)
	shadow.scale = sprite.scale

func label_at(text: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font",preload("res://assets/NotoSansSC-Regular.ttf"))
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(label)
	return label

func refresh_status():
	status.text = "%s  /  %03d 发\n缩放 %d%%" % ["暂停" if paused else "行动员 01",shots,roundi(camera.zoom.x*100)]

func _process(delta: float):
	if not unit or "--capture-room" in OS.get_cmdline_user_args(): return
	if not paused:
		target = (get_global_mouse_position()-ORIGIN)/PPM
		var move := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).normalized()
		step(minf(delta,0.05),move)

func _input(event: InputEvent):
	if not unit: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed: release_trigger()
			elif not paused:
				target = (get_global_mouse_position()-ORIGIN)/PPM
				unit.aim_target = target
				trigger_held = true
				fire()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before := get_global_mouse_position()
			camera.zoom = Vector2.ONE*clampf(camera.zoom.x*(1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1/1.12),0.5,2)
			camera.force_update_scroll()
			camera.position += before-get_global_mouse_position()
			update_resolution()
			refresh_status()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): camera.position -= event.relative/camera.zoom
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_TAB: hud.visible = not hud.visible
			KEY_HOME:
				camera.zoom = Vector2.ONE
				camera.position = ORIGIN
				update_resolution()
			KEY_SPACE:
				release_trigger()
				paused = not paused
			KEY_R:
				if not paused and character.operation_rate("reload") > 0:
					release_trigger()
					unit.trigger("reload")
		refresh_status()

func capture():
	for i in range(8): await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../.art-preview-local/room-design/equipment-study-runtime.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("ROOM_CAPTURE ",path," error=",error)
	get_tree().quit(error)

func move_in_room(start: Vector2, offset: Vector2) -> Vector2:
	var at := start
	for axis in [Vector2(offset.x,0),Vector2(0,offset.y)]:
		if axis.length_squared() < 0.00000001: continue
		var fraction := 1.0
		for obstacle in unit.effects.obstacles:
			var rect: Rect2 = obstacle.rect.grow(character.radius)
			var bounds := AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,10,rect.size.y))
			var hit := SCCombat.box_hit_fraction(Vector3(at.x,1,at.y),Vector3(at.x+axis.x,1,at.y+axis.y),bounds)
			if hit >= 0: fraction = minf(fraction,maxf(0,hit-0.0001))
		at += axis*fraction
	return at.clamp(Vector2(-3.8,-2.4)+Vector2.ONE*character.radius,Vector2(3.8,2.4)-Vector2.ONE*character.radius)

func release_trigger():
	trigger_held = false
	if character: SCCombat.stop_firing(character)

func fire(age := 0.0) -> bool:
	if paused or cooldown > 0.000001 or unit.current_action == "reload" or not character.capabilities.permissions.can_aim: return false
	unit.trigger("shoot",SCCombat.mechanical_error(character.weapon,rng),age)
	var impulse := SCCombat.record_shot(character,rng,false)
	var limit: float = character.weapon.definition.recoil.impulse_degrees_per_second[0]*character.capabilities.values.recoil_kick_scale
	unit.gait.kick(age,impulse.x/limit if limit>0 else 0.0)
	cooldown = character.weapon.definition.fire_interval
	shots += 1
	return true

func advance_shooter(delta: float):
	SCCombat.advance_recoil(character,delta)
	SCCombat.advance_aim(character,delta,unit.current_action!="reload",aim_speed,aim_turn_rate)

func advance_firing(delta: float):
	var remaining := delta
	while trigger_held and unit.current_action != "reload" and cooldown <= remaining+0.000001:
		var until_shot := minf(maxf(cooldown,0),remaining)
		advance_shooter(until_shot)
		remaining -= until_shot
		cooldown = 0
		if not fire(remaining): break
	advance_shooter(remaining)
	cooldown = maxf(0,cooldown-remaining)
	character.weapon.cooldown = cooldown

func step(delta: float, move: Vector2):
	if paused: return
	simulation_time += delta


	character.refresh_capabilities(simulation_time)
	if not character.capabilities.permissions.can_move: move = Vector2.ZERO
	var before_facing := facing
	var heading := (target-character.position).angle()
	facing = rotate_toward(facing,heading,character.turn_speed*delta)
	var angle := absf(angle_difference(facing,move.angle())) if move != Vector2.ZERO else 0.0
	var factor := SCData.angle_speed(character.capabilities.values.move_angle_curve,angle)
	velocity = velocity.move_toward(move*character.speed*factor,delta*character.capabilities.values.acceleration_mps2)
	var before := character.position
	character.previous_position = before
	character.position = move_in_room(before,velocity*delta)
	character.facing = facing
	velocity = (character.position-before)/maxf(delta,0.000001)
	var yaw := PI/2-facing
	var local := Vector3(velocity.x,0,velocity.y).rotated(Vector3.UP,-yaw)
	var turning := absf(angle_difference(before_facing,facing))/maxf(delta*character.turn_speed,0.000001)
	unit.effect_origin = character.position
	unit.aim_target = target
	unit.effects.advance(delta)
	unit.advance_unit(delta,yaw,Vector2(local.x,local.z),turning)
	aim_speed = velocity.length()
	aim_turn_rate = absf(rad_to_deg(angle_difference(character.aim_heading,heading)))/maxf(delta,0.000001) if character.aim_has_heading else 0.0
	character.aim_heading = heading
	character.aim_has_heading = true
	advance_firing(delta)
	unit.skeleton.advance(delta)
	sprite.position = ORIGIN + character.position*PPM
	shadow.position = sprite.position + Vector2(5,7)
	for view in fx_views: view.queue_redraw()
	if overlay: overlay.queue_redraw()
	if status: refresh_status()
