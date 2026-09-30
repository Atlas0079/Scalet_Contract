extends SceneTree

const FIXTURE=preload("res://tests/study_fixture.gd")
var checks:=0
var failures:Array=[]
var max_head_motion:=0.0
func _initialize(): call_deferred("verify")
func check(ok:bool,message:String):
	checks+=1
	if not ok and not message in failures:
		failures.append(message)
		push_error(message)

func verify():
	var scene=load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.demo=false
	FIXTURE.reset(scene)
	scene.target=Vector2(0,-6)
	for frame in range(4):
		scene.step(1.0/60,Vector2.ZERO)
		await process_frame
	var unit=scene.units[0]
	var sk:Skeleton3D=unit.skeleton
	var head_id:=sk.find_bone("Head")
	var spine_id:=sk.find_bone("spine_03")
	var head:Transform3D=sk.get_bone_global_pose(head_id)
	var spine:Transform3D=sk.get_bone_global_pose(spine_id)
	var first_barrel:Vector3=Vector3.ZERO
	var max_gun_motion:=0.0
	var spread:=SCCombat.weapon_accuracy(scene.character.weapon)+SCCombat.pair(scene.character.weapon.ammunition.accuracy_degrees)
	for state in [Vector3(0,0,0),Vector3(0,0,1),Vector3(-12,10,.2),Vector3(20,25,.2)]:
		var first_bounds:Dictionary={}
		for frame in range(90):
			scene.character.aim_progress=state.z
			scene.character.aim_clock=frame*.037
			scene.character.weapon.recoil_offset_degrees=Vector2(state.x,state.y)
			scene.step(0,Vector2.ZERO)
			await process_frame
			var h:=sk.get_bone_global_pose(head_id)
			max_head_motion=maxf(max_head_motion,h.origin.distance_to(head.origin))
			check(h.is_equal_approx(head),"Holding error moved the head")
			check(sk.get_bone_global_pose(spine_id).is_equal_approx(spine),"Holding error moved the torso")
			var gun:Transform3D=sk.global_transform*unit.gait.grip_pose*unit.weapon.transform
			var barrel:Vector3=gun.basis.y.normalized()
			if first_barrel==Vector3.ZERO: first_barrel=barrel
			max_gun_motion=maxf(max_gun_motion,barrel.angle_to(first_barrel))
			var bounds:Dictionary=unit.effects.reticle
			check(bounds.valid,"Forward target lost its bounds")
			if not bounds.valid: continue
			check(((bounds.left+bounds.right)*.5).is_equal_approx(scene.target),"Bracket center left intended target")
			check(bounds.center.is_equal_approx(scene.target),"Target marker moved")
			if first_bounds.is_empty(): first_bounds=bounds.duplicate(true)
			check(bounds.left.is_equal_approx(first_bounds.left) and bounds.right.is_equal_approx(first_bounds.right),"Bracket shakes with holding phase")
			var side:Vector2=bounds.axis
			var normal:=Vector2(side.y,-side.x)
			var half_width:float=bounds.left.distance_to(bounds.right)*.5
			for x in [-1,0,1]:
				for y in [-1,0,1]:
					var direction:=SCCombat.shot_direction(barrel,Vector2(x,y)*spread)
					var planar:=Vector2(direction.x,direction.z)
					var start:Vector3=unit.last_muzzle
					var t:float=(scene.target-Vector2(start.x,start.z)).dot(normal)/planar.dot(normal)
					check(t>0,"Actual shot cannot reach aim plane")
					var hit:=start+direction*t
					check(absf((Vector2(hit.x,hit.z)-scene.target).dot(side))<=half_width+.00001,"Projectile escaped fixed target bracket")
					check(hit.y>=bounds.height_min-.00001 and hit.y<=bounds.height_max+.00001,"Projectile escaped altitude bounds")
	check(max_gun_motion>deg_to_rad(1),"Gun lost visible holding motion")
	# Normal clock/animation advancement must also leave idle torso still.
	scene.character.weapon.recoil_offset_degrees=Vector2.ZERO
	for frame in range(90):
		scene.step(1.0/60,Vector2.ZERO)
		await process_frame
		check(sk.get_bone_global_pose(head_id).is_equal_approx(head),"Idle animation keeps rocking the head")
		check(sk.get_bone_global_pose(spine_id).is_equal_approx(spine),"Idle animation keeps rocking the torso")
	var report:Dictionary={"checks":checks,"failures":failures,"max_head_motion_m":max_head_motion}
	print("STABLE_AIM: ",JSON.stringify(report))
	FileAccess.open("res://../.art-preview-local/stable-aim-verification.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if failures.is_empty() else 1)
