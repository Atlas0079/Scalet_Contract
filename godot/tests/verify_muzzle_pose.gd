extends SceneTree

const FIXTURE = preload("res://tests/study_fixture.gd")
var failures: Array = []
var checks := 0
var maximum_error := 0.0

func _initialize(): call_deferred("verify")

func check(ok: bool, message: String):
	checks += 1
	if not ok and not message in failures:
		failures.append(message)
		push_error(message)

func barrel(unit) -> Vector3:
	return (unit.skeleton.global_transform * unit.gait.grip_pose * unit.weapon.transform).basis.y.normalized()

func verify():
	var scene=load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo=false
	FIXTURE.zero_aim(scene.character)
	var weapon:Dictionary=scene.character.weapon
	weapon.definition.accuracy_degrees=[0.0,0.0]
	weapon.ammunition.accuracy_degrees=[0.0,0.0]
	# Three-dimensional convergence, not just the screen-space barrel projection.
	for distance in [1.25,3.0,12.0]:
		for height in [.65,1.25,1.65]:
			FIXTURE.reset(scene)
			scene.target=Vector2(0,-distance)
			for unit in scene.units: unit.aim_height=height
			for frame in range(4):
				scene.step(1.0/60,Vector2.ZERO)
				await process_frame
			var unit=scene.units[0]
			var direction:=barrel(unit)
			var desired:Vector3=(Vector3(0,height,-distance)-unit.last_muzzle).normalized()
			var error:float=rad_to_deg(direction.angle_to(desired))
			if distance>=3:
				maximum_error=maxf(maximum_error,error)
				check(error<.02,"Unconstrained elevation aim failed: "+str([distance,height,error]))
			check(absf(rad_to_deg(asin(direction.y)))<=35.001,"Pitch exceeded anatomical limit")
	# At each emission, a zero-dispersion bullet must match the actual visible
	# 3D barrel, even when holding error is large or anatomy prevents convergence.
	scene.character.sources.clear()
	scene.character.refresh_capabilities()
	for fps in [20,37,60,144]:
		for error in [Vector2(-20,25),Vector2(20,25),Vector2(80,80)]:
			FIXTURE.reset(scene)
			scene.target=Vector2(0,-12)
			for unit in scene.units: unit.aim_height=1.25
			scene.character.aim_progress=0
			weapon.recoil_offset_degrees=error
			for frame in range(2):
				scene.step(1.0/fps,Vector2.ZERO)
				await process_frame
			var unit=scene.units[0]
			var direction:=barrel(unit)
			var origin:Vector3=unit.last_muzzle
			var grip:Vector3=unit.gait.grip_pose.affine_inverse()*unit.gait.support_pose.origin
			scene.fire()
			scene.step(1.0/fps,Vector2.ZERO)
			await process_frame
			check(not unit.effects.bullets.is_empty(),"Missing extreme-error projectile")
			if not unit.effects.bullets.is_empty():
				var shot:Dictionary=unit.effects.bullets[0]
				check(rad_to_deg(shot.direction_3d.angle_to(direction))<.002,"Projectile secretly diverged from emission barrel at FPS "+str(fps))
				check(Vector3(shot.start.x,shot.start_height,shot.start.y).distance_to(origin)<.00002,"Emission muzzle and projectile origin disagree")
			check(grip.distance_to(unit.gait.grip_pose.affine_inverse()*unit.gait.support_pose.origin)<.003,"Holding sway broke the two-hand grip")
			check(unit.gait.twist_degrees<35.01,"Sway bypassed the waist limit")
			check(barrel(unit).is_equal_approx(barrel(scene.units[1])),"Original/stylized barrels disagree")
	# Sway changes continuously while no shot is emitted; no RNG is consulted.
	FIXTURE.reset(scene)
	scene.character.aim_progress=0
	var sampled:Array=[]
	for frame in range(120):
		scene.character.aim_progress=0
		scene.step(1.0/120,Vector2.ZERO)
		await process_frame
		sampled.append(barrel(scene.units[0]))
		if sampled.size()>1: check(sampled[-1].angle_to(sampled[-2])<deg_to_rad(2),"Holding pose teleported")
	check(sampled[0].angle_to(sampled[60])>deg_to_rad(1),"Gun stayed still while aim was unstable")
	check(scene.shots_fired==0,"Holding animation unexpectedly fired")
	var invalid:=SCData.catalog.duplicate(true)
	invalid.presentation.characters.humanoid.aim_pitch_limit_degrees=90
	check(not SCData.validate(invalid).is_empty(),"Invalid pitch limit accepted")
	var report:Dictionary={"checks":checks,"failures":failures,"max_unconstrained_aim_error_degrees":maximum_error}
	print("MUZZLE_POSE: ",JSON.stringify(report))
	FileAccess.open("res://../.art-preview-local/muzzle-pose-verification.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if failures.is_empty() else 1)
