extends SceneTree

const FIXTURE = preload("res://tests/study_fixture.gd")

var failures: Array[String] = []
var report := {"cases": {}, "max_foot_error_m": 0.0, "max_waist_angle_deg": 0.0, "max_planted_foot_slide_m": 0.0}

func _initialize():
	call_deferred("verify")

func check(condition: bool, message: String):
	if not condition:
		failures.append(message)
		push_error(message)

func verify():
	var scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	await process_frame
	for camera in scene.cameras:
		check(camera.global_basis.z.dot(Vector3.UP) > 0.99999, "Camera is not exactly vertical")
		check(is_equal_approx(104.0 / camera.size, 40.0), "Character scale differs from 40 px/cell")
	var previous := 1.0
	for degrees in range(181):
		var factor: float = scene.angle_speed(deg_to_rad(degrees))
		check(factor <= previous + 0.000001, "Speed curve is not monotonic")
		check(is_equal_approx(factor, scene.angle_speed(-deg_to_rad(degrees))), "Left/right speed differs")
		previous = factor
	for pair in [[0, 1.0], [45, 1.0], [90, 0.7], [180, 0.5]]:
		check(is_equal_approx(scene.angle_speed(deg_to_rad(pair[0])), pair[1]), "Wrong speed anchor")
	var dt := 1.0 / 60.0
	for degrees in [0, 30, 45, 46, 60, 90, 135, 180, -90, -135]:
		FIXTURE.reset(scene)
		scene.desired_facing = -PI / 2
		scene.facing = scene.desired_facing
		var direction := Vector2.from_angle(scene.facing + deg_to_rad(degrees))
		var previous_feet := {}
		var previous_planted := {}
		var max_slide := 0.0
		var max_error := 0.0
		var max_twist := 0.0
		for frame in range(84):
			scene.step(dt, direction)
			await process_frame
			var unit = scene.units[0]
			var gait = unit.gait
			max_error = maxf(max_error, gait.foot_error)
			max_twist = maxf(max_twist, gait.twist_degrees)
			for side in ["l", "r"]:
				var foot: Vector3 = unit.rig.transform * gait.last_feet[side]
				var world_foot: Vector2 = scene.world_position + Vector2(foot.x, foot.z)
				if frame > 24 and gait.planted[side] and previous_planted.get(side, false):
					max_slide = maxf(max_slide, world_foot.distance_to(previous_feet[side]))
				previous_feet[side] = world_foot
				previous_planted[side] = gait.planted[side]
			check(is_equal_approx(gait.phase, scene.units[1].gait.phase), "Comparison phases diverged")
		var expected: float = 2.0 * scene.angle_speed(deg_to_rad(degrees))
		check(absf(scene.velocity.length() - expected) < 0.001, "Wrong actual speed at " + str(degrees))
		check(max_twist <= 35.1, "Waist twist exceeds limit at " + str(degrees))
		check(max_error < 0.006, "Foot target unreachable at " + str(degrees) + ": " + str(max_error))
		check(max_slide < 0.003, "Planted foot slides at " + str(degrees) + ": " + str(max_slide))
		report.cases[str(degrees)] = {"speed": scene.velocity.length(), "waist_deg": max_twist, "foot_error_m": max_error, "planted_slide_m_per_frame": max_slide}
		report.max_foot_error_m = maxf(report.max_foot_error_m, max_error)
		report.max_waist_angle_deg = maxf(report.max_waist_angle_deg, max_twist)
		report.max_planted_foot_slide_m = maxf(report.max_planted_foot_slide_m, max_slide)
		print("TACTICAL_CASE ", degrees, " ", report.cases[str(degrees)])
	# Exercise turns, opposite inputs, stop, and both existing weapon actions.
	FIXTURE.reset(scene)
	for frame in range(240):
		scene.desired_facing += dt * 4.0
		var move := Vector2.RIGHT if frame < 80 else (Vector2.LEFT if frame < 160 else Vector2.ZERO)
		if frame == 30: scene.fire()
		if frame == 110: scene.reload_weapon()
		scene.step(dt, move)
		await process_frame
		for unit in scene.units:
			check(unit.gait.twist_degrees < 35.1, "Waist limit failed during turn/action")
			check(unit.gait.foot_error < 0.006, "Foot target failed during transition")
			for side in ["l", "r"]:
				check(unit.gait.last_feet[side].is_finite(), "Invalid foot pose")
	scene.pause_button.pressed.emit()
	check(scene.paused, "Pause button is not connected")
	scene.guide_button.pressed.emit()
	check(scene.guides, "Direction guide button is not connected")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(scene.manual_input().is_equal_approx(Vector2.UP), "W key did not enter movement input")
	var second_key := InputEventKey.new()
	second_key.physical_keycode = KEY_D
	second_key.pressed = true
	Input.parse_input_event(second_key)
	await process_frame
	check(scene.manual_input().is_equal_approx(Vector2(1, -1).normalized()), "Diagonal movement is incorrect")
	key.pressed = false
	second_key.pressed = false
	Input.parse_input_event(key)
	Input.parse_input_event(second_key)
	await process_frame
	check(scene.manual_input() == Vector2.ZERO, "Released movement keys remain held")
	var motion := InputEventMouseMotion.new()
	scene.arena_bounds = Rect2(-2, -5, 28.8, 10)
	motion.position = scene.world_to_screen(Vector2(2, -1))
	scene._unhandled_input(motion)
	check(scene.target.is_equal_approx(Vector2(2, -1)), "Mouse aim coordinate mapping is incorrect")
	report["input_checks_passed"] = true
	report["failures"] = failures
	var file := FileAccess.open("res://../.art-preview-local/tactical-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("TACTICAL_VERIFICATION_", "PASSED" if failures.is_empty() else "FAILED", " ", failures.size())
	quit(0 if failures.is_empty() else 1)
