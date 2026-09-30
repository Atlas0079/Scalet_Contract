extends SceneTree

const FIXTURE = preload("res://tests/study_fixture.gd")

var failures: Array[String] = []
var checks := 0
var report := {}
const FX = preload("res://presentation/tactical/tactical_fire_fx.gd")

func _initialize(): call_deferred("verify")

func check(ok: bool, message: String):
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

func precise(actor):
	FIXTURE.zero_aim(actor)
	actor.weapon.definition.accuracy_degrees = [0.0, 0.0]
	actor.weapon.ammunition.accuracy_degrees = [0.0, 0.0]

func grid() -> SCGrid:
	var g := SCGrid.new()
	g.width = 100
	g.height = 100
	return g

func flight(origin: Vector3, direction: Vector3, actor) -> Dictionary:
	var shot := SCCombat.projectile(origin, direction, actor.weapon)
	shot.team = actor.team
	shot.shooter_id = actor.id
	return shot

func verify():
	check(SCData.ensure_valid(self), "New configuration is invalid")
	var a := SCActor.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 917
	for mutation in ["ammo", "aim", "recoil", "attachment", "height"]:
		var c := SCData.catalog.duplicate(true)
		match mutation:
			"ammo": c.ammunition.rifle_ammo.accuracy_degrees = [-1, 2]
			"aim": c.ability_rules.base.aim_settled_degrees = [20, 20]
			"recoil": c.weapons.rifle.recoil.max_offset_degrees = [NAN, 2]
			"attachment": c.weapons.rifle.attachments = ["missing"]
			"height": c.characters.human.muzzle_height_m = 3
		check(not SCData.validate(c).is_empty(), "Bad shooting config accepted: " + mutation)
	SCCombat.advance_aim(a, 0.5 / a.capabilities.values.aim_gain_per_second, true)
	check(is_equal_approx(a.aim_progress, 0.5), "Aim is not normalized progress")
	var half_width := SCCombat.aim_width(a)
	SCCombat.advance_aim(a, 0.5 / a.capabilities.values.aim_gain_per_second, true)
	check(a.aim_progress == 1.0 and SCCombat.aim_width(a).x < half_width.x, "Aim failed to settle")
	SCCombat.advance_aim(a, 0.2, true, 2.0)
	check(a.aim_progress < 1.0, "Movement failed to destabilize aim")
	var before := a.aim_progress
	SCCombat.advance_aim(a, 0.2, true, 0.0, 180.0)
	check(a.aim_progress < before, "Fast turning failed to destabilize aim")
	SCCombat.advance_aim(a, 4.0, false)
	check(a.aim_progress == 0, "Idle aim failed to decay")
	a.aim_progress = 1.0
	var plain := SCCombat.weapon_accuracy(a.weapon)
	a.weapon.definition.attachments = ["precision_barrel"]
	check(SCCombat.weapon_accuracy(a.weapon).is_equal_approx(plain * 0.7), "Attachment not applied to gun accuracy")
	var radius: Vector2 = SCCombat.error_envelope(a).radius
	check(radius.is_equal_approx(plain * 0.7 + SCCombat.pair(a.weapon.ammunition.accuracy_degrees) + SCCombat.aim_width(a)), "Attachment incorrectly scaled ammo or aim error")
	# First shot reads pre-recoil state, second shot reads the accumulated kick.
	a = SCActor.new()
	precise(a)
	a.aim_progress = 1.0
	var first := SCCombat.create_shot(a, Vector2(10, 0), a.muzzle_height, rng)
	check(first.direction_3d.is_equal_approx(Vector3.RIGHT), "First shot received its own recoil")
	check(a.weapon.recoil_offset_degrees==Vector2.ZERO and a.weapon.recoil_velocity_degrees_per_second.y>0,"Shot must impart velocity after emission")
	SCCombat.advance_recoil(a,a.weapon.definition.fire_interval)
	var inherited:float=a.weapon.recoil_offset_degrees.y
	var second:=SCCombat.create_shot(a,Vector2(10,0),a.muzzle_height,rng)
	check(inherited>0 and absf(rad_to_deg(asin(second.direction_3d.y))-inherited)<.0001,"Second shot lost first-shot motion")
	check(a.aim_progress==1,"Shooting reset independent aim progress")
	for i in range(200):
		SCCombat.record_shot(a,rng,false)
		SCCombat.advance_recoil(a,.01)
	check(absf(a.weapon.recoil_offset_degrees.y)<=18 and absf(a.weapon.recoil_offset_degrees.x)<=12,"Recoil exceeded limits")
	SCCombat.advance_recoil(a,10)
	check(a.weapon.recoil_offset_degrees.length()<.001,"Recoil failed to recover")
	# Every component can independently produce both yaw and pitch variation.
	for source in ["weapon", "ammo"]:
		a = SCActor.new()
		precise(a)
		match source:
			"weapon": a.weapon.definition.accuracy_degrees = [1.0, 2.0]
			"ammo": a.weapon.ammunition.accuracy_degrees = [1.0, 2.0]
		var minimum := Vector2(100, 100)
		var maximum := -minimum
		for i in range(500):
			var error := SCCombat.shot_error(a, rng)
			minimum = minimum.min(error)
			maximum = maximum.max(error)
			check(absf(error.x) <= 1 and absf(error.y) <= 2, "Scatter escaped configured angular limits")
		check(minimum.x < -0.5 and maximum.x > 0.5 and minimum.y < -1 and maximum.y > 1, "Missing axis or variation: " + source)
	# A 300 m/s projectile travels three actual meters in 10 ms at every pitch.
	a = SCActor.new()
	for pitch in [-80, -30, 0, 30, 80]:
		var direction := SCCombat.shot_direction(Vector3.RIGHT, Vector2(0, pitch))
		var shot := flight(Vector3(30, 25, 30), direction, a)
		SCCombat.advance_shot(shot, 0.01, grid(), [], rng)
		var displacement := Vector3(shot.end.x - 30, shot.height - 25, shot.end.y - 30)
		check(absf(displacement.length() - 3.0) < 0.00001, "Speed is incorrectly treated as horizontal speed")
		check(absf(shot.height - (25 + sin(deg_to_rad(pitch)) * 3)) < 0.00001, "Pitch did not determine height")
	# Clear the front face, then hit the top inside a filled cell.
	var g := grid()
	g.set_cell(Vector2i(5, 2), SCGrid.feature("cover", 1.0, true, false, true))
	var top := g.raycast(Vector2(4.5, 2.5), Vector2(6.5, 2.5), 1.3, 0.5, "projectile")
	check(top[1] != null and absf(top[0] - 0.375) < 0.00001, "Descending bullet tunneled through cover top")
	for fps in [20, 30, 60, 144]:
		var shot := flight(Vector3(4.5, 1.3, 2.5), Vector3(2, -0.8, 0).normalized(), a)
		for frame in range(20):
			if not shot.finished: SCCombat.advance_shot(shot, 1.0 / fps, g, [], rng)
		check(shot.blocked and absf(shot.height - 1.0) < 0.00001 and absf(shot.end.x - 5.25) < 0.00001, "FPS changed cover collision")
	var above := g.raycast(Vector2(4.5, 2.5), Vector2(6.5, 2.5), 1.3, 1.3, "projectile")
	check(above[1] == null, "A bullet above cover was blocked")
	g.set_cell(Vector2i(5, 2), SCGrid.feature("window", 0.9, true, false, true))
	for h in [0.8, 1.4, 2.4]:
		var hit := g.raycast(Vector2(4.5, 2.5), Vector2(6.5, 2.5), h, h, "projectile")
		check((hit[1] == null) == (h == 1.4), "Window sill/opening/lintel interval is wrong")
	var lintel := g.raycast(Vector2(4.5, 2.5), Vector2(6.5, 2.5), 1.8, 3.0, "projectile")
	check(lintel[1] != null and absf(lintel[0] - 1.0 / 3.0) < 0.00001, "Rising bullet tunneled through lintel")
	var cylinder := SCCombat.cylinder_hit_fraction(Vector2(-2, 0), Vector2(2, 0), 3, 1, Vector2.ZERO, Vector2.ZERO, 0.5, 0, 1.8)
	check(absf(cylinder - 0.6) < 0.00001, "Actor top hit was lost after clearing side")
	check(SCCombat.cylinder_hit_fraction(Vector2(-2, 0), Vector2(2, 0), 2, 2, Vector2.ZERO, Vector2.ZERO, 0.5, 0, 1.8) < 0, "Bullet above actor caused a hit")
	var grounded := flight(Vector3(5, 0.25, 5), Vector3(1, -1, 0).normalized(), a)
	SCCombat.advance_shot(grounded, 1, grid(), [], rng)
	check(grounded.blocked and absf(grounded.height) < 0.00001 and absf(grounded.end.x - 5.25) < 0.00001, "Ground collision failed")
	# Expiring halfway through a tick must not advance the target a full tick.
	var crossing := SCActor.new(10, "crossing", "blue", Vector2(0.9, 0.8))
	crossing.position = Vector2(0.9, -0.2)
	crossing.radius = 0.1
	var short_shot := flight(Vector3(0, 1.25, 0), Vector3.RIGHT, a)
	short_shot.range = 1.0
	short_shot.speed = 10.0
	SCCombat.advance_shot(short_shot, 1.0, grid(), [crossing], rng)
	check(short_shot.hit_actor_id == null, "Range expiry swept the target beyond the bullet's flight time")
	var retained := SCCombat.create_shot(a, Vector2(8, 0), a.muzzle_height, rng)
	a.weapon.ammunition.speed_mps = 1000.0
	a.weapon.ammunition.damage = 0.0
	check(retained.speed == 300 and retained.damage_value > 0, "In-flight shot changed with ammunition state")
	# The displayed envelope bounds independent samples on the actual aim plane.
	a = SCActor.new()
	a.aim_progress = 0.3
	a.weapon.recoil_offset_degrees = Vector2(1, 2)
	var muzzle := Vector3(1, 1.35, 2)
	var target := Vector3(1, 1.25, -4)
	var planar := Vector2.UP.rotated(0.12)
	var barrel := SCCombat.shot_direction(Vector3(planar.x * 6, -0.1, planar.y * 6), SCCombat.holding_error(a))
	var bounds := SCCombat.reticle_bounds(a, muzzle, barrel, target)
	check(bounds.valid, "Reticle unexpectedly invalid")
	var side: Vector2 = bounds.axis
	var low: float = (bounds.left - Vector2(target.x, target.z)).dot(side)
	var high: float = (bounds.right - Vector2(target.x, target.z)).dot(side)
	for i in range(1000):
		var dir := SCCombat.shot_direction(barrel, SCCombat.mechanical_error(a.weapon, rng))
		var travel := 6.0 / Vector2(dir.x, dir.z).dot(Vector2.UP)
		var impact := muzzle + dir * travel
		var lateral := Vector2(impact.x - target.x, impact.z - target.z).dot(side)
		check(lateral >= low - 0.00001 and lateral <= high + 0.00001 and impact.y >= bounds.height_min - 0.00001 and impact.y <= bounds.height_max + 0.00001, "Actual shot escaped bracket / altitude envelope")
	var wide: float = bounds.left.distance_to(bounds.right)
	a.aim_progress = 1.0
	var narrow := SCCombat.reticle_bounds(a, muzzle, barrel, target)
	check(narrow.left.distance_to(narrow.right) < wide, "Aim did not shrink reticle")
	a.weapon.recoil_offset_degrees = Vector2(4,6)
	var burst := SCCombat.reticle_bounds(a, muzzle, barrel, target)
	check(burst.left.distance_to(burst.right) > narrow.left.distance_to(narrow.right), "Burst did not expand reticle")
	# Preview and formal combat share 3D direction, and preview cover is real.
	for cover in [0.0, 0.8, 1.3, 1.8]:
		var fx = FX.new(SCData.weapon("test_carbine"))
		FIXTURE.configure_fx(fx)
		if cover > 0:
			fx.obstacles.append({"id":"cover", "label":"掩体", "kind":"cover", "rect":Rect2(-0.65,-1.33,1.3,0.16), "height":cover})
		fx.emit_shot(Vector3(0, 1.25, 0), Vector3(0, 1.25, 0), Vector3.FORWARD, Vector2.RIGHT)
		fx.advance(0.02)
		check(fx.total_hits == (1 if cover < 1.25 else 0) and fx.total_blocked == (0 if cover < 1.25 else 1), "Study cover height had no effect")
	var scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	for frame in range(70):
		scene.step(1.0 / 60.0, Vector2.ZERO)
		await process_frame
	check(scene.character.aim_progress == 1.0 and scene.units[0].effects.reticle.valid, "Live aim / reticle never settled")
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_H
	scene._unhandled_input(event)
	check(scene.units[0].aim_height == 0.65 and scene.character.aim_progress < 1.0, "Aim-height control failed")
	event.physical_keycode = KEY_C
	scene._unhandled_input(event)
	check(scene.lane_index == 1 and scene.target.is_equal_approx(Vector2(6,-1.2)), "Range lane control failed")
	scene.queue_free()
	await process_frame
	report = {"checks": checks, "failures": failures, "reticle_samples": 1000, "model": "yaw/pitch + bounded independent errors + accumulated recoil"}
	FileAccess.open("res://../.art-preview-local/shooting-model-verification.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SHOOTING_MODEL: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
