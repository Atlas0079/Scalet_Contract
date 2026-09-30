extends SceneTree

const FIXTURE = preload("res://tests/study_fixture.gd")

var failures: Array[String] = []
var report := {"cadence": {}, "max_recoil_m": 0.0, "max_grip_drift_m": 0.0, "max_socket_error_m": 0.0, "max_waist_deg": 0.0}
var scene

func _initialize(): call_deferred("verify")

func check(condition: bool, message: String):
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)

func tick(delta: float, move := Vector2.ZERO):
	scene.step(delta, move)
	await process_frame

func measure(grip_reference: Vector3):
	for unit in scene.units:
		var grip: Vector3 = unit.gait.grip_pose.affine_inverse() * unit.gait.support_pose.origin
		report.max_grip_drift_m = maxf(report.max_grip_drift_m, grip.distance_to(grip_reference))
		report.max_recoil_m = maxf(report.max_recoil_m, unit.gait.recoil.x)
		report.max_waist_deg = maxf(report.max_waist_deg, unit.gait.twist_degrees)
		var visible_socket: Vector3 = unit.weapon.global_transform * unit.muzzle_socket + Vector3(scene.world_position.x, 0, scene.world_position.y)
		report.max_socket_error_m = maxf(report.max_socket_error_m, visible_socket.distance_to(unit.last_muzzle))
		check(unit.effects.total_shots == scene.shots_fired, "Shot and flash events differ")
		check(unit.effects.total_ejected == scene.shots_fired, "Not exactly one casing per shot")
		check(unit.gait.recoil_impulses == scene.shots_fired, "Not exactly one recoil impulse per shot")
		check(unit.gait.twist_degrees < 35.1, "Recoil exceeded the waist constraint")
		check(unit.gait.foot_error < 0.006, "Firing disturbed the feet")

func verify():
	scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	for warm in range(3): await tick(1.0 / 60.0)
	var gait = scene.units[0].gait
	var grip_reference: Vector3 = gait.grip_pose.affine_inverse() * gait.support_pose.origin
	for fps in [30, 60, 144]:
		FIXTURE.reset(scene)
		scene.set_trigger(true, false)
		for frame in range(fps):
			scene.desired_facing = -PI / 2 + sin(frame / float(fps)) * 0.3
			await tick(1.0 / fps, Vector2.RIGHT)
			measure(grip_reference)
		check(scene.shots_fired == 11, "Cadence differs at " + str(fps) + " fps")
		report.cadence[str(fps)] = {"shots_t0_through_t1_inclusive": scene.shots_fired}
		scene.set_trigger(false, false)
		for frame in range(24): await tick(1.0 / 60.0)
		check(scene.shots_fired == 11, "Shots continued after trigger release")
		check(gait.recoil.length() < 0.0001, "Recoil failed to settle after release")
		check(scene.units[0].effects.flashes.is_empty(), "Muzzle flame stayed on after release")
	# A tap emits once; releasing over the UI is still caught by _input.
	FIXTURE.reset(scene)
	var down := InputEventMouseButton.new()
	scene.arena_bounds = Rect2(-2, -5, 28.8, 10)
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = scene.world_to_screen(Vector2(2, -1))
	down.pressed = true
	scene._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = Vector2(1150, 740)
	up.pressed = false
	scene._input(up)
	for frame in range(20): await tick(1.0 / 60.0)
	check(scene.shots_fired == 1 and not scene.trigger_held, "Tap/release-outside-map failed")
	# Frozen effects while paused; no implicit resumption of firing afterward.
	scene.set_trigger(true, false)
	await tick(1.0 / 60.0)
	scene.toggle_pause()
	var paused_count: int = scene.shots_fired
	var paused_age: float = scene.units[0].effects.elapsed
	for frame in range(10): await tick(1.0 / 30.0)
	check(scene.shots_fired == paused_count and not scene.trigger_held, "Pause did not release trigger")
	check(scene.units[0].effects.elapsed == paused_age, "Effects advanced while paused")
	scene.toggle_pause()
	await tick(0.05)
	check(scene.shots_fired == paused_count, "Unpause unexpectedly resumed firing")
	# Focus loss and reload both release the trigger; reload cannot fire.
	scene.set_trigger(true, false)
	scene.get_window().focus_exited.emit()
	check(not scene.trigger_held, "Focus loss did not release trigger")
	scene.reload_weapon()
	var before_reload: int = scene.shots_fired
	for frame in range(50):
		scene.fire()
		await tick(1.0 / 60.0)
	check(scene.shots_fired == before_reload, "A shot fired during reload")
	for frame in range(ceili(scene.character.weapon.definition.reload_time * 60.0) - 50 + 2): await tick(1.0 / 60.0)
	check(scene.units[0].current_action == "aim", "Reload failed to return to aim")
	# Landed casings stay at their world positions when the shooter moves away.
	FIXTURE.reset(scene)
	scene.fire()
	for frame in range(78): await tick(1.0 / 60.0)
	var effects = scene.units[0].effects
	check(effects.casings.size() == 1 and effects.casings[0].settled, "Casing did not settle")
	var landed: Vector3 = effects.casings[0].p
	for frame in range(100):
		scene.desired_facing += 0.016
		await tick(1.0 / 60.0, Vector2.RIGHT)
	check(effects.casings[0].p.is_equal_approx(landed), "Landed casing moved with shooter")
	check(effects.total_landed == 1, "Landing accounting failed")
	for frame in range(170): await tick(1.0 / 60.0)
	check(effects.casings.is_empty() and effects.smoke.is_empty() and effects.flashes.is_empty(), "Expired effects leaked")
	# Bound long bursts, even if an outside caller produces more shot events.
	for i in range(180): effects.emit_shot(Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3.FORWARD, Vector2.RIGHT)
	check(effects.casings.size() <= int(effects.casing_settings.maximum), "Casing budget exceeded")
	check(report.max_recoil_m > 0.025 and report.max_recoil_m <= 0.065, "Recoil amplitude is outside intended range")
	check(report.max_grip_drift_m < 0.003, "Support hand lost its grip during recoil")
	check(report.max_socket_error_m < 0.001, "Muzzle effects do not match rendered gun")
	report["failures"] = failures
	report["input_pause_reload_focus_passed"] = failures.is_empty()
	var file := FileAccess.open("res://../.art-preview-local/fire-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("FIRE_VERIFICATION_", "PASSED" if failures.is_empty() else "FAILED", " ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
