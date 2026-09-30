extends Node2D

const ACTOR = preload("res://presentation/tactical/tactical_actor.gd")
const FIRE_FX = preload("res://presentation/tactical/tactical_fire_fx.gd")
const TARGET_PAPER = preload("res://presentation/tactical/tactical_target_paper.gd")
const RANGE_CONTROLS = preload("res://presentation/tactical/range_controls.gd")
const DESIGN_SIZE := Vector2i(2560, 1440)
const ACTOR_DESIGN_SIZE := 104.0
var controls: RefCounted
var target_paper: Control
const CELL := 40.0
const MAP := Rect2(752, 200, 1152, 400)
const ZOOM := Rect2(752, 724, 480, 460)
var units: Array[Node3D] = []
var cameras: Array[Camera3D] = []
var sprites: Array[Sprite2D] = []
var zoom_sprites: Array[Sprite2D] = []
var views: Array[SubViewport] = []
var world_position := Vector2.ZERO
var velocity := Vector2.ZERO
var facing := -PI / 2.0
var desired_facing := -PI / 2.0
var target := Vector2(0, -2.5)
var angle := 0.0
var speed_factor := 1.0
var demo := true
var paused := false
var guides := false
var demo_time := 0.0
var demo_segment := -1
var capture_mode := false
var status: Label
var movement_label: Label
var demo_button: Button
var pause_button: Button
var guide_button: Button
var ui: Control
var effect_views: Array[Dictionary] = []
var trigger_held := false
var fire_cooldown := 0.0
var shots_fired := 0
var ballistic_rng := RandomNumberGenerator.new()
var fire_status: Label
var character_choices: Array
var weapon_choices: Array
var character: SCActor
var weapon_index := 0
var weapon_button: Button
var title_label: Label
var instructions_label: Label
var profile_index := 0
var profile_button: Button
var aim_status: Label
var height_index := 0
var lane_index := 0
var visible_style := 1
var shadows: Array[Sprite2D] = []
var zoom_shadows: Array[Sprite2D] = []
var lane_buttons: Array[Button] = []
var style_button: Button
var map_clip: Control
var zoom_clip: Control
var arena_bounds: Rect2
var test_pilot: SCActor
var simulation_time := 0.0
var aim_speed := 0.0
var aim_turn_rate := 0.0
var force_index := 0

func angle_speed(radians: float) -> float:
	return SCData.angle_speed(character.capabilities.values.move_angle_curve, radians)

func select_character(index: int):
	profile_index = index
	for source in character.sources.duplicate():
		if ":range_input:" in source.source_id or source.source_id.ends_with(":range_force"): character.remove_source(source.source_id)
	force_index = 1
	character.configure_character(character_choices[index])
	if character.definition.species == "robot":
		character.bind_controller(test_pilot,{"connected":true,"quality":1.0,"latency":0.0,"sync_base":0.6,"sync_ceiling":0.6})
	for unit in units:
		unit.character_definition = character.definition
		var posture: Dictionary = SCData.catalog.presentation.characters[character.definition.presentation]
		unit.gait.waist_limit = posture.waist_limit_degrees
		unit.gait.aim_limit = posture.aim_limit_degrees
		unit.gait.pitch_limit = posture.aim_pitch_limit_degrees
		unit.gait.nominal_speed = character.speed
	profile_button.text = "%s / P" % character.definition.name
	if controls:
		reset_experiment()
		controls.sync_editors()
	refresh_ui()

func cycle_profile():
	select_character((profile_index + 1) % character_choices.size())

func cycle_weapon():
	weapon_index = (weapon_index + 1) % weapon_choices.size()
	character.weapon = SCData.weapon(weapon_choices[weapon_index])
	set_trigger(false, false)
	var presentation: Dictionary = SCData.catalog.presentation.weapons[character.weapon.definition.presentation]
	if presentation.rig == units[0].weapon_presentation.rig:
		for unit in units: unit.configure_weapon(character.weapon)
		reset()
		refresh_weapon_ui()
		return
	# Rebuild views to honor a different rig, animation set and FX profile.
	for entry in effect_views: entry.node.get_parent().free()
	effect_views.clear()
	for shadow in shadows: shadow.free()
	shadows.clear()
	for sprite in sprites: sprite.free()
	sprites.clear()
	for view in views: view.queue_free()
	views.clear()
	units.clear()
	cameras.clear()
	for i in range(2):
		make_unit(i)
		zoom_sprites[i].texture = views[i].get_texture()
		zoom_sprites[i].material = sprites[i].material.duplicate() if sprites[i].material else null
		zoom_shadows[i].texture = views[i].get_texture()
		make_effect_views(i)
	reset()
	refresh_visibility()
	refresh_weapon_ui()
	update_render_resolution()

func refresh_weapon_ui():
	weapon_button.text = "%s / V" % character.weapon.definition.item.name
	title_label.text = "射击测试场 · %d m/s" % SCData.projectile_speed(character.weapon)
	instructions_label.text = "H 瞄准高度 %.2f m · C 下一射位\nB 白模 / 风格化 · 右键对准靶心\n橙色弹着：遮挡 · 金色弹着：命中" % SCData.study.target.aim_heights_m[height_index]
	if controls: controls.sync_editors()

func _ready():
	if not SCData.ensure_valid(get_tree()): return
	var window := get_window()
	window.content_scale_size = DESIGN_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	window.min_size = Vector2i(1280, 720)
	window.size = DESIGN_SIZE
	window.size_changed.connect(update_render_resolution)
	var bounds: Array = SCData.study.range.bounds_m
	arena_bounds = Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
	character_choices = SCData.study.character_choices
	weapon_choices = SCData.study.weapon_choices
	character = SCActor.new(0, "试射员", "red", Vector2.ZERO, -PI / 2, SCData.study.unit)
	character.training_enabled = false
	test_pilot = SCActor.new(-1,"测试机师","red",Vector2.ZERO,0,"test_operator",character.skill_registry)
	test_pilot.training_enabled = false
	profile_index = character_choices.find(character.character_id)
	weapon_index = weapon_choices.find(character.weapon.definition.item.id)
	for i in range(SCData.study.force_choices.size()):
		if is_equal_approx(SCData.study.force_choices[i].multiplier,1.0): force_index = i
	RenderingServer.set_default_clear_color(Color("11191c"))
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	label("SCARLET CONTRACT    /    BALLISTICS LAB", Vector2(24, 16), 22, "849a90")
	title_label = label("射击测试场", Vector2(752, 48), 36, "e0e2d2")
	style_button = button("风格化 / B", Vector2(1674, 48), 230, toggle_style)
	for i in range(SCData.study.range.lanes.size()):
		lane_buttons.append(button("%d · %s" % [i + 1, SCData.study.range.lanes[i].label], Vector2(752 + i * 144, 132), 136, choose_lane.bind(i)))
	map_clip = make_clip(MAP)
	zoom_clip = make_clip(ZOOM)
	for i in range(2):
		make_unit(i)
		var zoom := Sprite2D.new()
		zoom.texture = views[i].get_texture()
		zoom.scale = Vector2.ONE * 3.0
		zoom.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		zoom.material = sprites[i].material.duplicate() if sprites[i].material else null
		zoom_clip.add_child(zoom)
		zoom.z_index = 3
		zoom_sprites.append(zoom)
		zoom_shadows.append(make_shadow(i, zoom_clip, 3.0))
		make_effect_views(i)
	status = label("", Vector2(752, 616), 21, "bfcbbc")
	label("动作观察 / 3×", Vector2(752, 678), 28, "e0e2d2")
	aim_status = label("", Vector2(1264, 736), 24, "b8c6ab")
	fire_status = label("", Vector2(1264, 868), 24, "dad7ba")
	instructions_label = label("", Vector2(1264, 924), 22, "9daf9f")
	movement_label = label("", Vector2(1264, 1052), 22, "a7bcad")
	label("松开扳机后重新瞄准；过补偿每轮连射只发生一次。", Vector2(752, 1210), 22, "9daf9f")
	demo_button = button("巡回演示：开", Vector2(752, 1258), 268, toggle_demo)
	pause_button = button("暂停 / 空格", Vector2(1036, 1258), 268, toggle_pause)
	var fire_button := button("按住射击 / 左键", Vector2(1320, 1258), 284, Callable())
	fire_button.button_down.connect(set_trigger.bind(true))
	fire_button.button_up.connect(set_trigger.bind(false))
	button("换弹 / R", Vector2(1620, 1258), 284, reload_weapon)
	guide_button = button("方向辅助：关", Vector2(752, 1326), 352, toggle_guides)
	button("重置 / Tab", Vector2(1120, 1326), 352, reset)
	button("属性 / F2", Vector2(1488, 1326), 416, show_abilities)
	label("WASD 移动 · 鼠标瞄准 · 左键连射 · 1–8 射位", Vector2(752, 1392), 20, "7b9187")
	target_paper = TARGET_PAPER.new()
	target_paper.position = Vector2(1960, 104)
	target_paper.size = Vector2(576, 1312)
	target_paper.clear_requested.connect(clear_target_paper)
	ui.add_child(target_paper)
	controls = RANGE_CONTROLS.new(self)
	profile_button.text = "%s / P" % character.definition.name
	update_render_resolution()
	reset()
	refresh_visibility()
	get_window().focus_exited.connect(func(): set_trigger(false, false))
	var args := OS.get_cmdline_user_args()
	capture_mode = "--capture" in args or "--still" in args
	if capture_mode: call_deferred("capture_sequence", "--still" in args)
	print("TACTICAL_READY | 40 px/cell | animated silhouette shadow | 8 range lanes")

func make_clip(rect: Rect2) -> Control:
	var clip := Control.new()
	clip.position = rect.position
	clip.size = rect.size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	return clip

func world_to_screen(point: Vector2) -> Vector2:
	return MAP.position + (point - arena_bounds.position) * CELL

func screen_to_world(point: Vector2) -> Vector2:
	return (point - MAP.position) / CELL + arena_bounds.position

func make_shadow(index: int, parent: Control, scale_factor: float) -> Sprite2D:
	var settings: Dictionary = SCData.catalog.presentation.characters[character.definition.presentation].style.shadow
	var shadow := Sprite2D.new()
	shadow.texture = views[index].get_texture()
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow.scale = Vector2.ONE * scale_factor
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://presentation/tactical/silhouette_shadow.gdshader")
	var color := Color(settings.color)
	color.a = settings.opacity
	mat.set_shader_parameter("shadow_color", color)
	shadow.material = mat
	shadow.z_index = 1
	parent.add_child(shadow)
	return shadow

func refresh_visibility():
	for i in range(units.size()):
		for node in [sprites[i], shadows[i], zoom_sprites[i], zoom_shadows[i]]: node.visible = i == visible_style
		views[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if i == visible_style else SubViewport.UPDATE_DISABLED
	for entry in effect_views: entry.node.get_parent().visible = entry.index == visible_style
	style_button.text = ("风格化" if visible_style == 1 else "原白模") + " / B"

func toggle_style():
	visible_style = 1 - visible_style
	refresh_visibility()

func choose_lane(index: int):
	demo = false
	demo_button.text = "巡回演示：关"
	select_lane(index)

func select_lane(index: int):
	lane_index = index
	var lane: Dictionary = SCData.study.range.lanes[index]
	world_position = SCCombat.pair(lane.spawn_m)
	target = units[0].effects.target_by_id(lane.target).position
	velocity = Vector2.ZERO
	facing = (target - world_position).angle()
	desired_facing = facing
	set_trigger(false, false)
	fire_cooldown = 0.0
	character.weapon.cooldown = 0.0
	SCCombat.reset_recoil(character.weapon)
	character.aim_progress = 0.0
	character.aim_has_heading = false
	for unit in units:
		unit.pending_shots.clear()
		unit.effects.bullets.clear()
		unit.effects.clear_paper()
		unit.effects.flashes.clear()
		unit.effects.selected_target_id = lane.target
		unit.effects.shooter_position = world_position
		unit.effects.reticle = {"valid":false}
		unit.gait.clear_recoil()
		unit.shot_age = 10.0
		unit.previous_pose.clear()
		unit.trigger("aim")
	for i in range(lane_buttons.size()): lane_buttons[i].modulate = Color.WHITE if i == index else Color("93a39c")
	update_visual_positions()
	refresh_ui()
	queue_redraw()

func update_visual_positions():
	var settings: Dictionary = SCData.catalog.presentation.characters[character.definition.presentation].style.shadow
	var offset := SCCombat.pair(settings.offset_pixels)
	for i in range(sprites.size()):
		sprites[i].position = world_to_screen(world_position) - MAP.position
		shadows[i].position = sprites[i].position + offset
		zoom_sprites[i].position = ZOOM.size * 0.5 - Vector2.from_angle(facing) * 22.0
		zoom_shadows[i].position = zoom_sprites[i].position + offset * 3.0
	for entry in effect_views:
		entry.node.origin = zoom_sprites[entry.index].position - world_position * CELL * 3.0 if entry.zoom else -arena_bounds.position * CELL
		entry.node.queue_redraw()

func label(text: String, at: Vector2, font_size: int, color: String) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", Color(color))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(result)
	return result

func button(text: String, at: Vector2, width: float, callback: Callable) -> Button:
	var result := Button.new()
	result.focus_mode = Control.FOCUS_NONE
	result.text = text
	result.position = at
	result.size = Vector2(width, 52)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("2e413d") if state in ["hover", "pressed"] else Color("1b2a28")
		style.border_color = Color("456054")
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		result.add_theme_stylebox_override(state, style)
	result.add_theme_font_size_override("font_size", 22 if width > 150 else 18)
	if callback.is_valid(): result.pressed.connect(callback)
	ui.add_child(result)
	return result

func make_unit(index: int):
	var view := SubViewport.new()
	view.size = Vector2i(104, 104)
	view.transparent_bg = true
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	views.append(view)
	var unit := ACTOR.new()
	unit.stylized = index == 1
	unit.character_definition = character.definition
	unit.shooter = character
	unit.aim_height = SCData.study.target.aim_heights_m[height_index]
	unit.weapon_state = character.weapon
	view.add_child(unit)
	units.append(unit)
	unit.gait.modification_processed.connect(refresh_ui)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.position = Vector3(0, 8, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.near = 0.1
	camera.far = 20
	camera.current = true
	cameras.append(camera)
	var sprite := Sprite2D.new()
	sprite.texture = view.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if index == 1:
		var style: Dictionary = SCData.catalog.presentation.characters[character.definition.presentation].style
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://presentation/tactical/sprite_outline.gdshader")
		mat.set_shader_parameter("outline_color", Color(style.outline_color))
		mat.set_shader_parameter("outline_pixels", int(style.outline_pixels))
		sprite.material = mat
	map_clip.add_child(sprite)
	sprite.z_index = 3
	sprites.append(sprite)
	shadows.append(make_shadow(index, map_clip, 1.0))

func update_render_resolution():
	if views.size() != 2 or zoom_sprites.size() != 2: return
	# Render at the largest display demand (the 3x view). Sprite scale keeps
	# world projection at 40 design pixels/metre regardless of texture size.
	var window_scale := minf(float(get_window().size.x) / DESIGN_SIZE.x, float(get_window().size.y) / DESIGN_SIZE.y)
	var side := maxi(128, ceili(ACTOR_DESIGN_SIZE * 3.0 * window_scale / 16.0) * 16)
	for i in range(views.size()):
		if views[i].size != Vector2i(side, side): views[i].size = Vector2i(side, side)
		var normal_scale := ACTOR_DESIGN_SIZE / side
		for node in [sprites[i], shadows[i]]: node.scale = Vector2.ONE * normal_scale
		for node in [zoom_sprites[i], zoom_shadows[i]]: node.scale = Vector2.ONE * normal_scale * 3.0
		for sprite in [sprites[i], zoom_sprites[i]]:
			# Sampling resolves a base-view design pixel. The sprite transform
			# applies observation magnification to the entire art, including ink.
			if sprite.material: sprite.material.set_shader_parameter("source_pixel_scale", side / ACTOR_DESIGN_SIZE)
	if controls: controls.refresh()

func reset_experiment():
	var selected_lane := lane_index
	var selected_height := height_index
	demo = false
	demo_button.text = "巡回演示：关"
	reset()
	select_lane(selected_lane)
	height_index = selected_height
	for unit in units: unit.aim_height = SCData.study.target.aim_heights_m[height_index]
	refresh_weapon_ui()

func make_effect_views(index: int):
	for zoom in [false, true]:
		var rect: Rect2 = ZOOM if zoom else MAP
		for ground in [true, false]:
			var clip := Control.new()
			clip.position = rect.position
			clip.size = rect.size
			clip.clip_contents = true
			clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clip.z_index = 2 if ground else 4
			add_child(clip)
			var view = FIRE_FX.View.new()
			view.effects = units[index].effects
			view.ground = ground
			view.pixels_per_cell = CELL * (3.0 if zoom else 1.0)
			view.origin = rect.size * 0.5
			clip.add_child(view)
			units[index].gait.modification_processed.connect(view.queue_redraw)
			effect_views.append({"node": view, "index": index, "zoom": zoom, "rect": rect})

func reset():
	world_position = Vector2.ZERO
	velocity = Vector2.ZERO
	facing = -PI / 2
	desired_facing = facing
	target = Vector2(0, -2.5)
	demo_time = 0.0
	demo_segment = -1
	trigger_held = false
	fire_cooldown = 0.0
	shots_fired = 0
	ballistic_rng.seed = 71093
	SCCombat.reset_recoil(character.weapon)
	character.weapon.cooldown = 0.0
	character.weapon.shots_fired = 0
	character.aim_progress = 0.0
	character.aim_clock = 0.0
	character.aim_has_heading = false
	height_index = 0
	lane_index = 0
	for unit in units:
		unit.gait.phase = 0.0
		unit.gait.weight = 0.0
		unit.trigger("aim")
		unit.clear_fire()
		unit.aim_height = SCData.study.target.aim_heights_m[0]
	select_lane(0)
	refresh_weapon_ui()

func toggle_demo():
	demo = not demo
	reset()
	demo_button.text = "巡回演示：开" if demo else "巡回演示：关"

func toggle_pause():
	paused = not paused
	set_trigger(false, false)
	pause_button.text = "继续 / 空格" if paused else "暂停 / 空格"

func toggle_guides():
	guides = not guides
	guide_button.text = "方向辅助：开" if guides else "方向辅助：关"
	queue_redraw()

func fire(elapsed_since_shot := 0.0) -> bool:
	if paused or fire_cooldown > 0.000001 or not character.capabilities.permissions.can_aim: return false
	for unit in units:
		if unit.current_action == "reload": return false
	var error := SCCombat.mechanical_error(character.weapon, ballistic_rng)
	for unit in units:
		unit.aim_target = target
		unit.trigger("shoot", error, elapsed_since_shot)
	var impulse:=SCCombat.record_shot(character, ballistic_rng, false)
	var lateral_limit:float=character.weapon.definition.recoil.impulse_degrees_per_second[0]*character.capabilities.values.recoil_kick_scale
	for unit in units: unit.gait.kick(elapsed_since_shot,impulse.x/lateral_limit if lateral_limit>0 else 0.0)
	shots_fired += 1
	fire_cooldown = character.weapon.definition.fire_interval
	return true

func set_trigger(value: bool, manual := true):
	if value and paused: return
	if value and manual and demo:
		demo = false
		demo_button.text = "巡回演示：关"
	if value == trigger_held: return
	trigger_held = value
	if value: fire()
	else: SCCombat.stop_firing(character)

func advance_firing(delta: float):
	var remaining := delta
	# Split at shot times so gun motion and spread do not depend on display FPS.
	while trigger_held and units[0].current_action != "reload" and fire_cooldown <= remaining + 0.000001:
		var until_shot := minf(maxf(fire_cooldown, 0.0), remaining)
		advance_shooter(until_shot)
		remaining -= until_shot
		fire_cooldown = 0.0
		if not fire(remaining): break
	advance_shooter(remaining)
	fire_cooldown = maxf(0.0, fire_cooldown - remaining)
	character.weapon.cooldown = fire_cooldown

func advance_shooter(delta: float):
	SCCombat.advance_recoil(character, delta)
	SCCombat.advance_aim(character, delta, units[0].current_action != "reload", aim_speed, aim_turn_rate)

func cycle_shooting_skill():
	var current:float=character.capabilities.skills.shooting
	var level:=10 if current<10 else (20 if current<20 else 0)
	for entry in SCSkills.learners(character): entry.holder.xp.shooting=level*level*100.0
	test_pilot.refresh_capabilities()
	character.refresh_capabilities()
	reset()


func cycle_force():
	force_index = (force_index+1)%SCData.study.force_choices.size()
	character.remove_source(character.identity+":range_input:force_n")
	var source_id: String = character.identity+":range_force"
	character.remove_source(source_id)
	var choice: Dictionary = SCData.study.force_choices[force_index]
	if not is_equal_approx(choice.multiplier,1.0):
		var entry := SCAbilityRules.contribution("force","capability","force_n",choice.multiplier,"bonus","factor")
		var source := SCAbilityRules.source(source_id,"actor",character.identity,"trait","body",[entry])
		source.definition_id = "测试场力量条件"
		character.sources.append(source)
		character.refresh_capabilities()
	reset()


func cycle_height():
	clear_target_paper()
	height_index = (height_index + 1) % SCData.study.target.aim_heights_m.size()
	for unit in units: unit.aim_height = SCData.study.target.aim_heights_m[height_index]
	character.aim_progress *= character.capabilities.values.switch_retention
	refresh_weapon_ui()

func cycle_lane():
	choose_lane((lane_index + 1) % SCData.study.range.lanes.size())

func reload_weapon():
	if paused or character.operation_rate("reload") <= 0: return
	set_trigger(false, false)
	for unit in units:
		unit.trigger("reload")

func manual_input() -> Vector2:
	if get_viewport().gui_get_focus_owner() is LineEdit: return Vector2.ZERO
	return Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))).normalized()

func _input(event):
	# Releases are handled before UI consumption, including releases outside
	# the map. Losing focus, pausing and reloading also release the trigger.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		set_trigger(false, false)

func show_abilities():
	var was_paused := paused
	paused = true
	set_trigger(false,false)
	var dialog := AcceptDialog.new()
	dialog.title = "角色属性与技能 · 当前快照（机器人使用测试机师）"
	dialog.ok_button_text = "返回测试场"
	dialog.add_child(SCInterface.ability_view(character))
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			paused = was_paused
			dialog.queue_free())
	dialog.popup_centered(Vector2i(650,540))


func _unhandled_input(event):
	if capture_mode: return
	if event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit: return
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_8:
			choose_lane(event.physical_keycode - KEY_1)
			return
		match event.physical_keycode:
			KEY_F2: show_abilities()
			KEY_K: cycle_shooting_skill()
			KEY_J: cycle_force()
			KEY_SPACE: toggle_pause()
			KEY_R: reload_weapon()
			KEY_TAB: reset()
			KEY_G: toggle_guides()
			KEY_P: cycle_profile()
			KEY_V: cycle_weapon()
			KEY_H: cycle_height()
			KEY_C: cycle_lane()
			KEY_B: toggle_style()
	if event is InputEventMouseMotion and MAP.has_point(event.position):
		target = screen_to_world(event.position)
		if target.distance_to(world_position) > 0.08: desired_facing = (target - world_position).angle()
	if event is InputEventMouseButton and event.pressed and MAP.has_point(event.position):
		target = screen_to_world(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT: set_trigger(true)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			demo = false
			demo_button.text = "巡回演示：关"
			set_trigger(false, false)
			for entry in units[0].effects.targets:
				if entry.position.distance_to(target) < 0.7:
					target = entry.position
					for unit in units: unit.effects.selected_target_id = entry.id
					break

func demo_motion(delta: float) -> Vector2:
	demo_time += delta
	var segment: int = int(demo_time / 1.6) % SCData.study.range.lanes.size()
	var local_time := fposmod(demo_time, 1.6)
	if segment != demo_segment:
		demo_segment = segment
		select_lane(segment)
		facing -= PI / 2.0
	target = units[0].effects.target_by_id(SCData.study.range.lanes[segment].target).position
	desired_facing = (target - world_position).angle()
	set_trigger(local_time >= 0.65 and local_time < 1.35, false)
	return Vector2.ZERO

func move_in_range(start: Vector2, offset: Vector2) -> Vector2:
	var at := start
	# Axis-separated sweeps allow sliding while preventing high-speed tunneling.
	for axis in [Vector2(offset.x, 0), Vector2(0, offset.y)]:
		if axis.length_squared() < 0.00000001: continue
		var fraction := 1.0
		for obstacle in units[0].effects.obstacles:
			var rect: Rect2 = obstacle.rect.grow(character.radius)
			var box := AABB(Vector3(rect.position.x, 0, rect.position.y), Vector3(rect.size.x, 10, rect.size.y))
			var hit := SCCombat.box_hit_fraction(Vector3(at.x, 1, at.y), Vector3(at.x + axis.x, 1, at.y + axis.y), box)
			if hit >= 0.0: fraction = minf(fraction, maxf(0.0, hit - 0.0001))
		at += axis * fraction
	var allowed := arena_bounds.grow(-character.radius)
	return at.clamp(allowed.position, allowed.end)

func step(delta: float, move: Vector2):
	if paused: return
	simulation_time += delta
	character.refresh_capabilities(simulation_time)
	if not character.capabilities.permissions.can_move: move = Vector2.ZERO
	var before_facing := facing
	facing = rotate_toward(facing, desired_facing, character.turn_speed * delta)
	angle = absf(angle_difference(facing, move.angle())) if move.length_squared() > 0 else 0.0
	speed_factor = angle_speed(angle)
	velocity = velocity.move_toward(move * character.speed * speed_factor, delta * character.capabilities.values.acceleration_mps2)
	var before := world_position
	world_position = move_in_range(world_position, velocity * delta)
	var actual_velocity := (world_position - before) / maxf(delta, 0.00001)
	velocity = actual_velocity
	var yaw := PI / 2.0 - facing
	var local := Vector3(actual_velocity.x, 0, actual_velocity.y).rotated(Vector3.UP, -yaw)
	var turn := absf(angle_difference(before_facing, facing)) / maxf(delta, 0.00001) / maxf(character.turn_speed, 0.000001)
	for unit in units:
		unit.effect_origin = world_position
		unit.aim_target = target
		unit.effects.advance(delta)
		unit.advance_unit(delta, yaw, Vector2(local.x, local.z), turn)
	aim_speed = actual_velocity.length()
	var desired_heading := (target - world_position).angle()
	aim_turn_rate = absf(rad_to_deg(angle_difference(character.aim_heading, desired_heading))) / maxf(delta, 0.000001) if character.aim_has_heading else 0.0
	character.aim_heading = desired_heading
	character.aim_has_heading = true
	advance_firing(delta)
	for unit in units:
		unit.skeleton.advance(delta)
	update_visual_positions()
	refresh_ui()
	queue_redraw()

func _process(delta: float):
	if capture_mode or paused: return
	delta = minf(delta, 0.05)
	var move := manual_input()
	if move != Vector2.ZERO and demo:
		demo = false
		set_trigger(false, false)
		demo_button.text = "巡回演示：关"
	if demo:
		move = demo_motion(delta)
	elif target.distance_to(world_position) > 0.08:
		desired_facing = (target - world_position).angle()
	step(delta, move)

func clear_target_paper():
	set_trigger(false, false)
	for unit in units: unit.effects.clear_paper()
	refresh_ui()

func refresh_ui():
	if not fire_status or units.is_empty(): return
	var fx = units[visible_style].effects
	if target_paper:
		target_paper.effects = fx
		target_paper.queue_redraw()
	status.text = "1 格 = 1 米 · 40 像素/格       射位：%s       当前瞄准距离 %.2f m       枪械射程 %.0f m" % [SCData.study.range.lanes[lane_index].label, world_position.distance_to(target), character.weapon.definition.range]
	var bounds: Dictionary = fx.reticle
	var height_text := "枪口尚未对准"
	if bounds.valid: height_text = "预计弹高 %.2f–%.2f m" % [bounds.height_min, bounds.height_max]
	var offset: Vector2 = character.weapon.recoil_offset_degrees+character.weapon.reaim_offset_degrees
	var phase := "重新瞄准" if not character.weapon.recoil_active and offset.length() > .001 else ("过补偿" if character.weapon.recoil_overshoot_phase == "push" else "持枪")
	aim_status.text = "瞄准 %.2f · 偏移 %.1f° · 补偿 %.0f%% · %s\n%s\n最近弹着：%s" % [character.aim_progress, offset.y, character.weapon.recoil_compensation*100, phase, height_text, fx.last_impact]
	fire_status.text = "%s · %d 发 / %d 中 / %d 挡" % ["连射" if trigger_held else "待机", shots_fired, fx.total_hits, fx.total_blocked]
	movement_label.text = "移速 %.2f m/s · 夹角 %d°\n躯干 %.1f° · 技能 %.0f\n通用力量 %.0f N" % [velocity.length(), roundi(rad_to_deg(angle)), units[0].gait.twist_degrees, character.capabilities.skills.shooting, character.capabilities.values.force_n]
	if controls: controls.refresh()

func _draw():
	draw_rect(MAP, Color("26322f"))
	for x in range(30):
		var px := MAP.position.x + x * CELL
		if px <= MAP.end.x: draw_line(Vector2(px, MAP.position.y), Vector2(px, MAP.end.y), Color("30413a"), 1)
	for y in range(11):
		var py := MAP.position.y + y * CELL
		draw_line(Vector2(MAP.position.x, py), Vector2(MAP.end.x, py), Color("30413a"), 1)
	draw_rect(MAP, Color("4b6155"), false, 1)
	draw_rect(ZOOM, Color("1a2724"))
	if units.is_empty(): return
	for i in range(SCData.study.range.lanes.size()):
		var lane: Dictionary = SCData.study.range.lanes[i]
		var spawn := world_to_screen(SCCombat.pair(lane.spawn_m))
		var goal := world_to_screen(units[0].effects.target_by_id(lane.target).position)
		var color := Color("718c79") if i == lane_index else Color("455d50")
		draw_dashed_line(spawn, goal, color, 1, 4)
		draw_arc(spawn, 15, 0, TAU, 24, color, 1)
		draw_string(ThemeDB.fallback_font, spawn + Vector2(-4, 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	if guides:
		var fx = units[visible_style].effects
		var muzzle := world_to_screen(fx.muzzle)
		draw_dashed_line(muzzle, muzzle + fx.forward * 4.0 * CELL, Color("c7b77b"), 1, 4)

func capture_sequence(still: bool):
	var folder := ProjectSettings.globalize_path("res://../.art-preview-local/renders-current")
	DirAccess.make_dir_recursive_absolute(folder)
	await get_tree().process_frame
	var count := 1 if still else 384
	for frame in range(count):
		if still:
			select_lane(4)
			for warm in range(30):
				step(1.0 / 30.0, Vector2.ZERO)
				await get_tree().process_frame
			set_trigger(true, false)
			step(1.0 / 30.0, Vector2.ZERO)
		else:
			step(1.0 / 30.0, demo_motion(1.0 / 30.0))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("frame_%04d.png" % frame))
		if frame % 48 == 0: print("TACTICAL_CAPTURE ", frame)
	print("TACTICAL_CAPTURE_COMPLETE ", count)
	get_tree().quit()
