extends SceneTree

const FIXTURE = preload("res://tests/study_fixture.gd")

var scene
var failures: Array[String] = []
var report := {"aim_cases": [], "max_aim_error_pixels": 0.0, "max_twist_degrees": 0.0}

func _initialize(): call_deferred("verify")

func check(value: bool, message: String):
	if not value and not failures.has(message):
		failures.append(message)
		push_error(message)

func tick(dt: float, move := Vector2.ZERO):
	scene.step(dt, move)
	await process_frame

func verify():
	scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	# Geometry calibration deliberately disables ballistic error. Configured
	# spread/recoil and fractional shot times have separate integration tests.
	scene.character.weapon.definition.accuracy_degrees = [0.0, 0.0]
	scene.character.weapon.ammunition.accuracy_degrees = [0.0, 0.0]
	FIXTURE.zero_aim(scene.character)
	scene.character.weapon.definition.recoil.impulse_degrees_per_second = [0.0, 0.0]
	for warm in range(3): await tick(1.0 / 60.0)
	# Data-driven curves: anchors, symmetry, smooth interpolation, actual speed.
	for profile in range(scene.character_choices.size()):
		scene.select_character(profile)
		var points: Array = scene.character.definition.movement_angle_curve
		for point in points:
			check(is_equal_approx(scene.angle_speed(deg_to_rad(point[0])), point[1]), "Wrong profile anchor")
		for i in range(1, points.size()):
			var midpoint: float = (points[i - 1][0] + points[i][0]) * 0.5
			var speed: float = (points[i - 1][1] + points[i][1]) * 0.5
			check(is_equal_approx(scene.angle_speed(deg_to_rad(midpoint)), speed), "Wrong curve interpolation")
		for angle in range(181):
			check(is_equal_approx(scene.angle_speed(deg_to_rad(angle)), scene.angle_speed(-deg_to_rad(angle))), "Asymmetric curve")
		FIXTURE.reset(scene)
		for frame in range(40): await tick(1.0 / 60.0, Vector2.DOWN)
		check(absf(scene.velocity.length() - scene.character.speed * points.back()[1]) < 0.001, "Actual movement ignores selected curve")
	scene.select_character(0)
	FIXTURE.zero_aim(scene.character)
	# Calibrate all compass headings at near, normal and far distances.
	for distance in [1.25, 2.5, 6.0]:
		for heading in range(0, 360, 45):
			FIXTURE.reset(scene)
			scene.facing = deg_to_rad(heading)
			scene.desired_facing = scene.facing
			scene.target = Vector2.from_angle(scene.facing) * distance
			for unit in scene.units: unit.effects.target_by_id("calibration").position = scene.target
			for frame in range(4): await tick(1.0 / 60.0)
			var fx = scene.units[0].effects
			var offset: Vector2 = scene.target - fx.muzzle
			var error: float = absf(offset.cross(fx.forward)) * 40.0
			report.max_aim_error_pixels = maxf(report.max_aim_error_pixels, error)
			report.aim_cases.append({"distance": distance, "heading": heading, "error_pixels": error})
			check(error < 0.1 and offset.dot(fx.forward) > 0.0, "Muzzle convergence failed: " + str([distance, heading, error]))
			var shot_muzzle: Vector2 = fx.muzzle
			var shot_forward: Vector2 = fx.forward
			scene.fire()
			await tick(1.0 / 60.0)
			check(fx.bullets.size() == 1, "Missing bullet")
			var bullet: Dictionary = fx.bullets[0].duplicate()
			check(bullet.start.distance_to(shot_muzzle) < 0.00001, "Bullet did not start at emission-time muzzle")
			check(bullet.direction.dot(shot_forward) > 0.99999, "Bullet ignored emission-time barrel")
			scene.desired_facing += PI
			await tick(1.0 / 60.0, Vector2.RIGHT)
			check(fx.bullets[0].direction.is_equal_approx(bullet.direction), "Turning curved a fired bullet")
			for frame in range(20): await tick(1.0 / 60.0)
			check(fx.total_hits == 1, "Aligned shot missed or counted twice")
	# Collision sweeps cannot tunnel; invisible rounds still collide.
	for fps in [20, 30, 60, 144]:
		for every in [1, 3, 5]:
			var fx = load("res://presentation/tactical/tactical_fire_fx.gd").new(SCData.weapon("test_carbine"))
			FIXTURE.configure_fx(fx)
			fx.bullet_speed = 300.0
			fx.tracer_every = every
			for shot in range(10): fx.emit_shot(Vector3(0, 1.25, 0), Vector3(0, 1.25, 0), Vector3.FORWARD, Vector2.RIGHT)
			var visible := 0
			for bullet in fx.bullets:
				if bullet.tracer_visible: visible += 1
			check(visible == ceili(10.0 / every), "Tracer interval incorrect")
			for frame in range(fps): fx.advance(1.0 / fps)
			check(fx.total_hits == 10 and fx.bullets.is_empty(), "Collision/culling failed at " + str([fps, every]))
			fx.clear()
			fx.emit_shot(Vector3(0, 1.25, 0), Vector3(0, 1.25, 0), Vector3.RIGHT, Vector2.DOWN)
			for frame in range(fps): fx.advance(1.0 / fps)
			check(fx.total_hits == 0 and fx.bullets.is_empty(), "Miss was homing or never expired")
	# Extreme close and rear targets must respect posture, even if unreachable.
	FIXTURE.reset(scene)
	for frame in range(180):
		scene.target = Vector2.from_angle(frame * 0.1) * 0.25
		if frame % 6 == 0: scene.fire()
		await tick(1.0 / 60.0)
		for unit in scene.units:
			report.max_twist_degrees = maxf(report.max_twist_degrees, unit.gait.twist_degrees)
			check(unit.gait.twist_degrees < 35.1, "Close aim broke anatomical limit")
			check(unit.effects.forward.is_finite(), "Invalid close-range barrel")
	# Both map coordinates and the profile button use the live controls.
	var right := InputEventMouseButton.new()
	scene.arena_bounds = Rect2(-2, -5, 28.8, 10)
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = scene.world_to_screen(Vector2(2.5, -1.5))
	scene._unhandled_input(right)
	check(scene.target.is_equal_approx(Vector2(2.5, -1.5)), "Target placement input failed")
	scene.profile_button.pressed.emit()
	check(scene.profile_index == 1, "Profile button failed")
	report["failures"] = failures
	var file := FileAccess.open("res://../.art-preview-local/tracer-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("TRACER_VERIFICATION_", "PASSED" if failures.is_empty() else "FAILED", " max aim error px=", report.max_aim_error_pixels, " max twist=", report.max_twist_degrees, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
