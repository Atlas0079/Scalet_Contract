extends SkeletonModifier3D

# Preview locomotion. Authored aim/shoot/reload stays in the upper body;
# grounded, direction-aware foot targets replace the unsuitable sideways walk.
var direction := Vector2.ZERO
var speed := 0.0
var phase := 0.0
var weight := 0.0
var turn_amount := 0.0
var foot_error := 0.0
var twist_degrees := 0.0
var planted := {}
var last_feet := {}
var reference_feet := {}
var reference_bases := {}
var nominal_speed := 2.0
var recoil := Vector2.ZERO
var recoil_velocity := Vector2.ZERO
var recoil_impulses := 0
var grip_pose := Transform3D.IDENTITY
var support_pose := Transform3D.IDENTITY
var aim_enabled := false
var aim_target := Vector3.ZERO
var gun_bind := Transform3D.IDENTITY
var gun_muzzle := Vector3.ZERO
var waist_limit: float
var aim_limit: float
var recoil_settings: Dictionary
var shooter: SCActor
var pitch_limit: float
var pose_context: Dictionary = {}

func kick(elapsed_since_shot := 0.0, lateral_fraction := 0.0):
	recoil_impulses += 1
	# Add the impulse at its actual age without advancing the existing spring
	# twice when the shot falls between two display frames.
	var impulse := Vector2(recoil_settings.position_impulse_m, 0.0)
	var impulse_velocity := Vector2(recoil_settings.velocity_impulse, lateral_fraction * recoil_settings.side_impulse)
	var response: Vector2 = impulse_velocity + impulse * recoil_settings.frequency
	var decay := exp(-recoil_settings.frequency * elapsed_since_shot)
	recoil += (impulse + response * elapsed_since_shot) * decay
	recoil_velocity += (impulse_velocity - response * recoil_settings.frequency * elapsed_since_shot) * decay
	recoil.x = minf(recoil.x, recoil_settings.max_displacement_m)
	recoil.y = clampf(recoil.y, -recoil_settings.max_side_displacement_m, recoil_settings.max_side_displacement_m)

func clear_recoil():
	recoil = Vector2.ZERO
	recoil_velocity = Vector2.ZERO
	recoil_impulses = 0

func advance_recoil(delta: float):
	# Exact critically damped spring: stable at different display frame rates.
	var decay := exp(-recoil_settings.frequency * delta)
	var response: Vector2 = recoil_velocity + recoil * recoil_settings.frequency
	recoil = (recoil + response * delta) * decay
	recoil_velocity = (recoil_velocity - response * recoil_settings.frequency * delta) * decay
	if recoil.x > recoil_settings.max_displacement_m:
		recoil.x = recoil_settings.max_displacement_m
		recoil_velocity.x = minf(recoil_velocity.x, 0.0)
	recoil.y = clampf(recoil.y, -recoil_settings.max_side_displacement_m, recoil_settings.max_side_displacement_m)

func configure():
	var sk := get_skeleton()
	for side in ["l", "r"]:
		var idx := sk.find_bone("foot_" + side)
		reference_feet[side] = sk.get_bone_global_pose(idx).origin
		reference_bases[side] = sk.get_bone_global_pose(idx).basis

func advance_gait(delta: float, local_velocity: Vector2, turning: float):
	advance_recoil(delta)
	speed = local_velocity.length()
	if speed > 0.001:
		direction = local_velocity.normalized()
	turn_amount = turning
	var target_weight := clampf(speed / 0.25, 0.0, 1.0)
	if speed < 0.02 and turning > 0.08:
		target_weight = minf(turning, 0.6)
	weight = move_toward(weight, target_weight, delta * 7.0)
	var period := lerpf(0.60, 0.32, absf(direction.x))
	phase = fposmod(phase + delta * (speed / nominal_speed + (turning * 0.4 if speed < 0.02 else 0.0)) / period, 1.0)

func yaw_of(sk: Skeleton3D, bone: String) -> float:
	var idx := sk.find_bone(bone)
	var delta_basis := sk.get_bone_global_pose(idx).basis * sk.get_bone_global_rest(idx).basis.inverse()
	var forward := delta_basis * Vector3.BACK
	return atan2(forward.x, forward.z)

func global_rotation(sk: Skeleton3D, idx: int, basis: Basis):
	var parent := sk.get_bone_parent(idx)
	var local_basis := basis
	if parent >= 0:
		local_basis = sk.get_bone_global_pose(parent).basis.inverse() * basis
	sk.set_bone_pose_rotation(idx, local_basis.orthonormalized().get_rotation_quaternion())

func solve_leg(sk: Skeleton3D, side: String, goal: Vector3):
	var upper := sk.find_bone("thigh_" + side)
	var lower := sk.find_bone("calf_" + side)
	var foot := sk.find_bone("foot_" + side)
	var a := sk.get_bone_global_pose(upper)
	var b := sk.get_bone_global_pose(lower)
	var c := sk.get_bone_global_pose(foot)
	var l1 := a.origin.distance_to(b.origin)
	var l2 := b.origin.distance_to(c.origin)
	var axis := (goal - a.origin).normalized()
	var distance := clampf(a.origin.distance_to(goal), absf(l1 - l2) + 0.0001, l1 + l2 - 0.0001)
	var along := (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
	var spread := sqrt(maxf(0.0, l1 * l1 - along * along))
	var preferred := Vector3(0.14 if side == "l" else -0.14, 0.0, 1.0)
	var bend := (preferred - axis * preferred.dot(axis)).normalized()
	var knee := a.origin + axis * along + bend * spread
	var q := Quaternion((b.origin - a.origin).normalized(), (knee - a.origin).normalized())
	global_rotation(sk, upper, Basis(q) * a.basis)
	b = sk.get_bone_global_pose(lower)
	c = sk.get_bone_global_pose(foot)
	q = Quaternion((c.origin - b.origin).normalized(), (goal - b.origin).normalized())
	global_rotation(sk, lower, Basis(q) * b.basis)
	global_rotation(sk, foot, reference_bases[side])
	foot_error = maxf(foot_error, sk.get_bone_global_pose(foot).origin.distance_to(goal))
	last_feet[side] = sk.get_bone_global_pose(foot).origin

func _process_modification_with_delta(_delta: float):
	if reference_feet.is_empty():
		return
	var sk := get_skeleton()
	foot_error = 0.0
	# Keep the original rifle stance. Clamp only when an authored action exceeds
	# the preview's waist budget, restoring upper globals so grips stay intact.
	var hip := sk.find_bone("pelvis")
	var difference := angle_difference(yaw_of(sk, "pelvis"), yaw_of(sk, "spine_03"))
	if absf(difference) > deg_to_rad(waist_limit):
		var upper_poses := {}
		for i in range(sk.get_bone_count()):
			var name := sk.get_bone_name(i)
			if name.begins_with("spine") or name.begins_with("neck") or name == "Head" or name.begins_with("clavicle") or name.contains("arm_") or name.begins_with("hand_"):
				upper_poses[i] = sk.get_bone_global_pose(i).basis
		var correction := difference - clampf(difference, -deg_to_rad(waist_limit), deg_to_rad(waist_limit))
		global_rotation(sk, hip, Basis(Vector3.UP, correction) * sk.get_bone_global_pose(hip).basis)
		for i in upper_poses:
			global_rotation(sk, i, upper_poses[i])
	twist_degrees = rad_to_deg(absf(angle_difference(yaw_of(sk, "pelvis"), yaw_of(sk, "spine_03"))))
	var hip_position := sk.get_bone_pose_position(hip)
	var lower := Vector3.DOWN * weight * (0.07 + 0.009 * (1.0 - cos(phase * TAU * 2.0)))
	var parent := sk.get_bone_parent(hip)
	hip_position += sk.get_bone_global_pose(parent).basis.inverse() * lower
	sk.set_bone_pose_position(hip, hip_position)
	var side_amount := absf(direction.x)
	var period := lerpf(0.60, 0.32, side_amount)
	var travel := nominal_speed * period * 0.5
	for side in ["l", "r"]:
		var p := fposmod(phase + (0.0 if side == "l" else 0.5), 1.0)
		var along: float
		var lift := 0.0
		if p < 0.5:
			along = travel * (0.5 - p * 2.0)
		else:
			var t := (p - 0.5) * 2.0
			along = travel * (-0.5 + smoothstep(0.0, 1.0, t))
			lift = sin(t * PI) * 0.075
		var stance: Vector3 = reference_feet[side]
		stance.x = (1.0 if side == "l" else -1.0) * lerpf(0.15, 0.185, side_amount)
		stance.z = 0.025
		var goal := stance + Vector3(direction.x, 0, direction.y) * along
		if speed < 0.02:
			goal = stance
		goal.y = 0.104 + lift
		goal = sk.get_bone_global_pose(sk.find_bone("foot_" + side)).origin.lerp(goal, weight)
		planted[side] = p < 0.5 and weight > 0.99 and speed > 0.02
		solve_leg(sk, side, goal)
	# Translate the shared upper body for the kick, then solve its orientation.
	# Holding error is applied to the rig itself, never secretly to a projectile.
	var spine := sk.find_bone("spine_01")
	var parent_basis := sk.get_bone_global_pose(sk.get_bone_parent(spine)).basis
	var offset := Vector3(recoil.y * 0.5, 0, -recoil.x)
	sk.set_bone_pose_position(spine, sk.get_bone_pose_position(spine) + parent_basis.inverse() * offset)
	var waist := angle_difference(yaw_of(sk, "pelvis"), yaw_of(sk, "spine_03"))
	var upper := sk.find_bone("spine_03")
	var upper_forward := (sk.get_bone_global_pose(upper).basis * sk.get_bone_global_rest(upper).basis.inverse()) * Vector3.BACK
	var pelvis_forward := (sk.get_bone_global_pose(hip).basis * sk.get_bone_global_rest(hip).basis.inverse()) * Vector3.BACK
	pose_context = {
		"constrain_waist":true,
		"gun":sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r")) * gun_bind,
		"pivot":sk.global_transform * sk.get_bone_global_pose(spine).origin,
		"upper_forward":(sk.global_basis * upper_forward).normalized(),
		"pelvis_forward":(sk.global_basis * pelvis_forward).normalized(),
		"low":maxf(-deg_to_rad(aim_limit), -deg_to_rad(waist_limit - 1.0) - waist),
		"high":minf(deg_to_rad(aim_limit), deg_to_rad(waist_limit - 1.0) - waist)}
	if aim_enabled:
		var solved := solve_aim(pose_context, sk.global_transform * aim_target, Vector2.ZERO)
		var local_rotation: Basis = sk.global_basis.inverse() * solved.rotation * sk.global_basis
		global_rotation(sk, spine, local_rotation * sk.get_bone_global_pose(spine).basis)
	# Stable torso aims at the requested target. Only the hands/gun carry error.
	var right_hand := sk.get_bone_global_pose(sk.find_bone("hand_r"))
	var left_hand := sk.get_bone_global_pose(sk.find_bone("hand_l"))
	var upper_left := sk.get_bone_global_pose(sk.find_bone("upperarm_l")).origin
	var elbow_left := sk.get_bone_global_pose(sk.find_bone("lowerarm_l")).origin
	pose_context = {
		"constrain_waist":false,
		"gun":sk.global_transform * right_hand * gun_bind,
		"pivot":sk.global_transform * right_hand.origin,
		"support":sk.global_transform * left_hand.origin,
		"shoulder":sk.global_transform * upper_left,
		"reach":(upper_left.distance_to(elbow_left)+elbow_left.distance_to(left_hand.origin))*sk.global_basis.get_scale().x,
		"low":-deg_to_rad(aim_limit),"high":deg_to_rad(aim_limit)}
	if aim_enabled:
		var solved := solve_aim(pose_context,sk.global_transform * aim_target,SCCombat.holding_error(shooter))
		var pivot:Vector3=pose_context.pivot
		var delta:=Transform3D(solved.rotation,pivot-solved.rotation*pivot)
		var local_delta:=sk.global_transform.affine_inverse()*delta*sk.global_transform
		solve_arm(sk,"r",local_delta*right_hand)
		solve_arm(sk,"l",local_delta*left_hand)
	grip_pose = sk.get_bone_global_pose(sk.find_bone("hand_r"))
	support_pose = sk.get_bone_global_pose(sk.find_bone("hand_l"))
	twist_degrees = rad_to_deg(absf(angle_difference(yaw_of(sk, "pelvis"), yaw_of(sk, "spine_03"))))


func solve_aim(context: Dictionary, target: Vector3, error: Vector2) -> Dictionary:
	# The same constrained solution drives visible bones and sub-frame shots.
	# Re-solve after rotating the offset muzzle, including target elevation.
	var gun: Transform3D = context.gun
	var pivot: Vector3 = context.pivot
	var barrel := gun.basis.y.normalized()
	var neutral_pitch := atan2(barrel.y, Vector2(barrel.x,barrel.z).length())
	var pitch_axis := barrel.cross(Vector3.UP).normalized()
	var rotation := Basis.IDENTITY
	var moved := gun
	for iteration in range(12):
		var muzzle := moved * gun_muzzle
		var to_target := target - muzzle
		if to_target.length_squared() < 0.000001: break
		var desired := SCCombat.shot_direction(to_target,error)
		var pitch := clampf(atan2(desired.y,Vector2(desired.x,desired.z).length()),-deg_to_rad(pitch_limit),deg_to_rad(pitch_limit))
		var pitch_rotation := Basis(pitch_axis,pitch-neutral_pitch)
		var pitched_barrel := pitch_rotation * barrel
		var pitched_offset := pitch_rotation * (gun * gun_muzzle-pivot)
		var planar := Vector2(pitched_barrel.x,pitched_barrel.z).normalized().rotated(-deg_to_rad(error.x))
		var target_offset := Vector2(target.x-pivot.x,target.z-pivot.z)
		var convergence := asin(clampf(planar.cross(Vector2(pitched_offset.x,pitched_offset.z))/maxf(target_offset.length(),0.00001),-1,1))
		var yaw := clampf(wrapf(convergence-planar.angle_to(target_offset),-PI,PI),context.low,context.high)
		rotation = Basis(Vector3.UP,yaw) * pitch_rotation
		if context.constrain_waist:
			var upper: Vector3 = rotation * context.upper_forward
			var pelvis: Vector3 = context.pelvis_forward
			var twist := angle_difference(atan2(pelvis.x,pelvis.z),atan2(upper.x,upper.z))
			var excess := twist-clampf(twist,-deg_to_rad(waist_limit),deg_to_rad(waist_limit))
			rotation = Basis(Vector3.UP,-excess) * rotation
		moved = Transform3D(rotation,pivot-rotation*pivot) * gun
	if not context.constrain_waist:
		# Restrict the shared rigid grip before IK; never stretch an arm to follow.
		var support:Vector3=context.support-pivot
		if (pivot+rotation*support).distance_to(context.shoulder)>context.reach:
			var lo:=0.0
			var hi:=1.0
			var wanted:=rotation.get_rotation_quaternion()
			for step in range(16):
				var mid:float=(lo+hi)*.5
				var candidate:=Basis(Quaternion.IDENTITY.slerp(wanted,mid))
				if (pivot+candidate*support).distance_to(context.shoulder)<=context.reach: lo=mid
				else: hi=mid
			rotation=Basis(Quaternion.IDENTITY.slerp(wanted,lo))
			moved=Transform3D(rotation,pivot-rotation*pivot)*gun
	return {"rotation":rotation,"gun":moved}


func solve_arm(sk:Skeleton3D,side:String,goal:Transform3D):
	var upper:=sk.find_bone("upperarm_"+side)
	var lower:=sk.find_bone("lowerarm_"+side)
	var hand:=sk.find_bone("hand_"+side)
	var a:=sk.get_bone_global_pose(upper)
	var b:=sk.get_bone_global_pose(lower)
	var c:=sk.get_bone_global_pose(hand)
	var l1:=a.origin.distance_to(b.origin)
	var l2:=b.origin.distance_to(c.origin)
	var axis:Vector3=(goal.origin-a.origin).normalized()
	var distance:=clampf(goal.origin.distance_to(a.origin),absf(l1-l2)+.000001,l1+l2)
	var along:float=(l1*l1-l2*l2+distance*distance)/(2*distance)
	var preferred:=b.origin-a.origin
	var bend:Vector3=(preferred-axis*preferred.dot(axis)).normalized()
	if bend.length_squared()<.01: bend=axis.cross(Vector3.UP).normalized()
	var elbow:=a.origin+axis*along+bend*sqrt(maxf(0,l1*l1-along*along))
	global_rotation(sk,upper,Basis(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized()))*a.basis)
	b=sk.get_bone_global_pose(lower)
	c=sk.get_bone_global_pose(hand)
	global_rotation(sk,lower,Basis(Quaternion((c.origin-b.origin).normalized(),(goal.origin-b.origin).normalized()))*b.basis)
	global_rotation(sk,hand,goal.basis)
