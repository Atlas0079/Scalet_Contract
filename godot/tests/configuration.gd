extends SceneTree

const FIXTURE = preload("res://tests/study_fixture.gd")

var failures: Array[String] = []
var checks := 0

func _initialize(): call_deferred("verify")

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func zero_error(actor):
	FIXTURE.zero_aim(actor)
	actor.weapon.definition.accuracy_degrees = [0.0, 0.0]
	actor.weapon.ammunition.accuracy_degrees = [0.0, 0.0]

func verify():
	check(SCData.ensure_valid(self), "Production configuration must validate")
	for mutation in ["missing", "reference", "curve", "number", "body", "presentation"]:
		var c := SCData.catalog.duplicate(true)
		match mutation:
			"missing": c.weapons.rifle.erase("fire_interval")
			"reference": c.weapons.rifle.ammunition = "not_present"
			"curve": c.characters.human.movement_angle_curve = [[0, 1], [90, 0.5], [80, 0.3], [180, 0.1]]
			"number": c.ammunition.rifle_ammo.speed_mps = NAN
			"body": c.bodies.robot.fatal_parts = ["heart"]
			"presentation": c.presentation.tracers.warm_tracer.length_m = -1
		check(not SCData.validate(c).is_empty(), "Invalid configuration accepted: " + mutation)
	var a := SCActor.new()
	var b := SCActor.new()
	a.weapon.ammo -= 1
	a.parts.heart.hp -= 1
	check(b.weapon.ammo == 30 and b.parts.heart.hp == 25, "Shared instance state")
	a.weapon.definition.magazine_size = 1
	check(SCData.catalog.weapons.rifle.magazine_size == 30, "Instance mutated source definition")
	var robot := SCActor.new()
	robot.configure_character("robot")
	check(robot.alive and not robot.parts.has("heart") and not robot.parts.has("brain"), "Robot depends on human organs")
	robot.parts.motor_left.hp = 0
	check(is_equal_approx(robot.body_function("movement"), 0.5), "Robot single drive damage")
	robot.parts.motor_right.hp = 0
	check(robot.body_function("movement") == 0, "Robot damaged drives still move")
	robot.parts.power_core.hp = 0
	check(not robot.alive, "Robot vital component has no effect")
	var saved: float = SCData.catalog.ability_rules.base.move_speed_mps
	SCData.catalog.ability_rules.base.move_speed_mps = 3.25
	var configured := SCActor.new()
	check(is_equal_approx(configured.speed, 3.25), "Character speed is not data-driven")
	SCData.catalog.ability_rules.base.move_speed_mps = saved
	var grid := SCGrid.new()
	grid.width = 100
	grid.height = 100
	var rng := RandomNumberGenerator.new()
	rng.seed = 4821
	# Real combat uses finite flight time, shared ammo damage, and swept collision.
	for speed in [30.0, 300.0, 1000.0]:
		var shooter := SCActor.new(1, "shooter", "red", Vector2(2.5, 2.5))
		var target := SCActor.new(2, "target", "blue", Vector2(12.5, 2.5))
		zero_error(shooter)
		shooter.weapon.ammunition.speed_mps = speed
		var shot := SCCombat.create_shot(shooter, target.position, shooter.muzzle_height, rng)
		check(shot.hit_actor_id == null and shot.travelled == 0, "Shot deals instant damage")
		var frames := 0
		while not shot.finished and frames < 300:
			SCCombat.advance_shot(shot, 1.0 / 60.0, grid, [shooter, target], rng)
			frames += 1
		var expected := ceili((10.0 - target.radius) / speed * 60.0)
		check(frames == expected and shot.hit_actor_id == 2, "Wrong flight time / tunneling at " + str(speed))
		check(shot.damage > 0 and shooter.weapon.ammo == 29, "Ammo damage/consumption missing")
	# A fast target crossing the ray inside one step must also be hit.
	var shooter := SCActor.new(1, "shooter", "red", Vector2(2.5, 2.5))
	var moving := SCActor.new(2, "target", "blue", Vector2(5, 1.5))
	moving.position = Vector2(5, 3.5)
	zero_error(shooter)
	var crossing := SCCombat.create_shot(shooter, Vector2(12.5, 2.5), shooter.muzzle_height, rng)
	SCCombat.advance_shot(crossing, 1.0 / 60.0, grid, [shooter, moving], rng)
	check(crossing.hit_actor_id == 2, "Moving target crossed a bullet undetected")
	# A wall before the actor must stop the whole swept path.
	grid.set_cell(Vector2i(7, 2), SCGrid.feature("wall", 3, true, true, true))
	shooter.weapon.cooldown = 0
	shooter.weapon.recoil_offset_degrees = Vector2.ZERO
	shooter.weapon.ammunition.speed_mps = 1000
	var behind := SCActor.new(3, "behind", "blue", Vector2(12.5, 2.5))
	var blocked := SCCombat.create_shot(shooter, behind.position, shooter.muzzle_height, rng)
	SCCombat.advance_shot(blocked, 1.0 / 60.0, grid, [shooter, behind], rng)
	check(blocked.blocked and blocked.hit_actor_id == null, "Bullet ignored wall")
	# Compare the live preview's two weapons, including rebuilding its rig.
	var scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	for weapon_index in range(2):
		scene.reset()
		for frame in range(3):
			scene.step(1.0 / 60.0, Vector2.ZERO)
			await process_frame
		scene.set_trigger(true, false)
		for frame in range(60):
			scene.step(1.0 / 60.0, Vector2.ZERO)
			await process_frame
		scene.set_trigger(false, false)
		check(scene.shots_fired == (11 if weapon_index == 0 else 5), "Configured weapon cadence not applied")
		check(scene.units[0].effects.tracer_length == 2.0, "Configured longer tracer missing")
		check(scene.units[0].effects.bullet_speed == 300.0, "Shared ammo speed missing")
		if weapon_index == 0:
			scene.weapon_button.pressed.emit()
			await process_frame
	check(scene.character.weapon.definition.item.id == "rifle", "Weapon switch failed")
	for index in range(3):
		scene.select_character(index)
		check(scene.character.character_id == scene.character_choices[index], "Character switch failed")
	scene.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures}
	var file := FileAccess.open("res://../.art-preview-local/configuration-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("CONFIGURATION: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
