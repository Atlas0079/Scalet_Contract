extends SceneTree

const FIXTURE = preload("res://tests/study_fixture.gd")

var failures: Array[String] = []
var checks := 0
var report := {"cadence": {}, "spread_range_degrees": 0.0, "max_normal_repack_error": 0.0}
const FX = preload("res://presentation/tactical/tactical_fire_fx.gd")

func _initialize(): call_deferred("verify")

func check(ok: bool, message: String):
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

func verify():
	var scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	for frame in range(3):
		scene.step(1.0 / 60.0, Vector2.ZERO)
		await process_frame
	var original: Array = scene.units[0].rig.find_children("*", "MeshInstance3D", true, false)
	var styled: Array = scene.units[1].rig.find_children("*", "MeshInstance3D", true, false)
	check(original.size() == styled.size(), "Style added replacement geometry")
	for i in range(original.size()):
		check(styled[i].visible, "Style hid original geometry")
		for surface in range(original[i].mesh.get_surface_count()):
			var a: Array = original[i].mesh.surface_get_arrays(surface)
			var b: Array = styled[i].mesh.surface_get_arrays(surface)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
				check(a[channel] == b[channel], "Style modified silhouette or skinning channel " + str(channel))
			# Godot packs normals again when adding the color stream. Allow only
			# the small quantization error; geometry and weights above are exact.
			for n in range(a[Mesh.ARRAY_NORMAL].size()):
				report.max_normal_repack_error = maxf(report.max_normal_repack_error, a[Mesh.ARRAY_NORMAL][n].distance_to(b[Mesh.ARRAY_NORMAL][n]))
			if styled[i] != scene.units[1].weapon:
				check(b[Mesh.ARRAY_COLOR].size() == a[Mesh.ARRAY_VERTEX].size(), "Missing palette")
				check(styled[i].mesh.surface_get_material(surface) is ShaderMaterial, "Missing toon shader")
	check(report.max_normal_repack_error < 0.0002, "Style changed normals beyond packing precision")
	for mutation in ["shade", "outline", "palette", "weapon_color"]:
		var c := SCData.catalog.duplicate(true)
		match mutation:
			"shade": c.presentation.characters.humanoid.style.shade_bands = 1
			"outline": c.presentation.characters.humanoid.style.outline_pixels = 3
			"palette": c.presentation.characters.humanoid.style.bone_colors.Head = "garbage"
			"weapon_color": c.presentation.weapons.rifle.style.color = 123
		check(not SCData.validate(c).is_empty(), "Invalid style accepted: " + mutation)
	# Shared direction sampler preserves formal combat's exact three samples.
	var shooter := SCActor.new()
	shooter.weapon.recoil_offset_degrees = Vector2(1.0, 4.0)
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 612
	r2.seed = 612
	var expected := SCCombat.shot_direction(Vector3.FORWARD, SCCombat.shot_error(shooter, r1))
	var actual := SCCombat.create_shot(shooter, shooter.position + Vector2.UP * 10.0, shooter.muzzle_height, r2)
	check(expected.is_equal_approx(actual.direction_3d), "Combat does not share the direction sampler")
	var reference: Array[float] = []
	var reference_vertical: Array[float] = []
	var reference_recoil := Vector2.ZERO
	for fps in [20, 30, 37, 60, 144]:
		FIXTURE.reset(scene)
		scene.set_trigger(true, false)
		var samples: Array[float] = []
		var vertical: Array[float] = []
		var fractional_shots := 0
		for frame in range(fps * 2):
			scene.step(1.0 / fps, Vector2.ZERO)
			check(scene.units[0].pending_shots == scene.units[1].pending_shots, "A/B sampled different shots")
			for shot in scene.units[0].pending_shots:
				samples.append(shot.error.x)
				vertical.append(shot.error.y)
				if shot.age > 0.000001 and shot.age < 1.0 / fps - 0.000001: fractional_shots += 1
			await process_frame
			var a = scene.units[0].effects
			var b = scene.units[1].effects
			check(a.total_hits == b.total_hits and a.bullets.size() == b.bullets.size(), "A/B collisions differ")
			for i in range(a.bullets.size()):
				check(a.bullets[i].start.is_equal_approx(b.bullets[i].start) and a.bullets[i].direction.is_equal_approx(b.bullets[i].direction), "Style changed the muzzle or shot direction")
				check(a.bullets[i].direction_3d.is_equal_approx(b.bullets[i].direction_3d) and is_equal_approx(a.bullets[i].height, b.bullets[i].height), "A/B changed vertical ballistics")
		check(samples.size() == 21 and scene.shots_fired == 21, "Wrong cadence at " + str(fps))
		if reference_recoil == Vector2.ZERO: reference_recoil = scene.units[0].gait.recoil
		else: check(reference_recoil.distance_to(scene.units[0].gait.recoil) < 0.00001, "Frame rate changed recoil phase")
		if reference.is_empty():
			reference = samples.duplicate()
			reference_vertical = vertical.duplicate()
		else:
			for i in range(mini(reference.size(), samples.size())):
				check(absf(reference[i] - samples[i]) < 0.00001, "Frame rate changed ballistic error")
				check(absf(reference_vertical[i] - vertical[i]) < 0.00001, "Frame rate changed pitch error")
		if fps in [37, 144]: check(fractional_shots > 0, "Shot timing still quantized to frames")
		report.cadence[str(fps)] = {"shots": samples.size(), "fractional_shots": fractional_shots}
		scene.set_trigger(false, false)
		for frame in range(fps * 3):
			scene.step(1.0 / fps, Vector2.ZERO)
			await process_frame
		check(scene.character.weapon.recoil_offset_degrees.length()<.001,"Ballistic recoil did not recover")
	report.spread_range_degrees = reference.max() - reference.min()
	check(report.spread_range_degrees > 0.5, "Configured spread/recoil did not affect shots")
	# Arrival and afterglow are elapsed-time quantities, including the birth frame.
	for fps in [20, 30, 60, 144]:
		var fx = FX.new(SCData.weapon("test_carbine"))
		FIXTURE.configure_fx(fx)
		fx.emit_shot(Vector3(0, 1.25, 0), Vector3(0, 1.25, 0), Vector3.FORWARD, Vector2.RIGHT, 0.004)
		check(fx.total_hits == 0 and absf(fx.bullets[0].travelled - 1.2) < 0.00001, "Birth-frame flight is delayed")
		var age := 0.004
		var hit_time: float = (2.5 - fx.targets[0].radius) / 300.0
		while age < 0.04:
			var dt := minf(1.0 / fps, 0.04 - age)
			fx.advance(dt)
			age += dt
		check(fx.total_hits == 1 and fx.bullets.size() == 1, "Swept collision or retention failed")
		check(absf(fx.bullets[0].travelled - 2.27) < 0.00001, "Tracer endpoint disagrees with impact")
		check(absf(fx.bullets[0].afterglow - (0.04 - hit_time)) < 0.00001, "Afterglow depends on frame rate")
		fx.advance(0.02)
		check(fx.bullets.is_empty(), "Afterglow exceeded configured lifetime")
	# Multiple emissions in one slow frame have distinct ages and directions.
	FIXTURE.reset(scene)
	scene.set_trigger(true, false)
	scene.step(0.25, Vector2.ZERO)
	check(scene.units[0].pending_shots.size() == 3, "Slow frame dropped scheduled shots")
	var queue: Array = scene.units[0].pending_shots
	check(absf(queue[0].age - 0.25) < 0.00001 and absf(queue[1].age - 0.15) < 0.00001 and absf(queue[2].age - 0.05) < 0.00001, "Slow-frame shot ages collapsed")
	await process_frame
	scene.queue_free()
	await process_frame
	report.checks = checks
	report.failures = failures
	FileAccess.open("res://../.art-preview-local/shader-ballistics-verification.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SHADER_BALLISTICS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
