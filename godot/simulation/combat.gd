class_name SCCombat
extends RefCounted


static func segment_distance(point: Vector2, start: Vector2, end: Vector2) -> Array:
	var delta = end - start
	if delta.length_squared() <= 0.00001:
		return [point.distance_to(start), 0.0]
	var t = clampf((point - start).dot(delta) / delta.length_squared(), 0.0, 1.0)
	return [point.distance_to(start + delta * t), t]


static func body_region(h: float, actor, rng: RandomNumberGenerator) -> String:
	for band in actor.body_definition.hit_bands:
		if h / actor.height < band.min_height_fraction: continue
		var total := 0.0
		for weight in band.regions.values(): total += weight
		var roll := rng.randf() * total
		for region in band.regions:
			roll -= band.regions[region]
			if roll <= 0: return region
		return band.regions.keys().back()
	return actor.body_definition.regions[0].id


# All angular pairs are (horizontal/yaw, vertical/pitch), in degrees.
# Each accuracy pair is a hard half-width, not a hit probability or diameter.
static func pair(values: Array) -> Vector2:
	return Vector2(values[0], values[1])


static func weapon_accuracy(weapon: Dictionary) -> Vector2:
	var result := pair(weapon.definition.accuracy_degrees)
	for id in weapon.definition.attachments:
		result *= pair(SCData.catalog.attachments[id].accuracy_multiplier)
	return result


static func aim_width(actor) -> Vector2:
	var spec: Dictionary = actor.capabilities.values
	return spec.aim_settled_degrees.lerp(spec.aim_unsettled_degrees, pow(1.0 - actor.aim_progress, spec.curve_power))


static func advance_aim(actor, dt: float, tracking: bool, speed := 0.0, turn_rate_degrees := 0.0):
	var spec: Dictionary = actor.capabilities.values
	actor.aim_clock += dt
	var gain: float = spec.aim_gain_per_second if tracking and actor.capabilities.permissions.can_aim else -spec.idle_decay_per_second
	actor.aim_progress = clampf(actor.aim_progress + dt * (gain - speed * spec.movement_loss_per_m - absf(turn_rate_degrees) * spec.turn_loss_per_degree), 0.0, 1.0)


static func reset_recoil(weapon: Dictionary):
	weapon.recoil_offset_degrees = Vector2.ZERO
	weapon["recoil_velocity_degrees_per_second"] = Vector2.ZERO
	weapon["recoil_compensation"] = 0.0
	weapon["recoil_burst_age"] = 0.0
	weapon["recoil_since_shot"] = 1000.0
	weapon["recoil_expected_impulse"] = Vector2.ZERO


static func advance_recoil(actor, dt: float):
	var weapon:Dictionary=actor.weapon
	var spec:Dictionary=weapon.definition.recoil
	var control:Dictionary=SCData.catalog.ability_rules.recoil_control
	var ability:Dictionary=actor.capabilities.values
	if weapon.recoil_offset_degrees==Vector2.ZERO and weapon.recoil_velocity_degrees_per_second==Vector2.ZERO and weapon.recoil_compensation<.000001:
		weapon.recoil_compensation=0.0
		weapon.recoil_since_shot+=dt
		return
	var remaining:=dt
	# Small bounded integration steps, independent of render frequency. Passive
	# support is integrated analytically; active correction has a force limit.
	while remaining>0.000000001:
		var h:=minf(remaining,1.0/480.0)
		remaining-=h
		var gap:float=maxf(control.burst_gap_seconds,weapon.definition.fire_interval*1.5)
		var continuing:bool=weapon.recoil_since_shot<gap
		if continuing:
			weapon.recoil_burst_age+=h
			if weapon.recoil_burst_age>=ability.recoil_response_delay_seconds:
				weapon.recoil_compensation=1-(1-weapon.recoil_compensation)*exp(-h/ability.recoil_compensation_build_seconds)
		else:
			weapon.recoil_compensation*=exp(-h/control.memory_decay_seconds)
		var angle:Vector2=weapon.recoil_offset_degrees
		var velocity:Vector2=weapon.recoil_velocity_degrees_per_second
		var expectation:Vector2=weapon.recoil_expected_impulse/weapon.definition.fire_interval if weapon.recoil_since_shot<weapon.definition.fire_interval else Vector2.ZERO
		var frequency:float=control.return_frequency
		var correction:Vector2=-frequency*frequency*angle-2*frequency*velocity-expectation
		var limit:float=ability.recoil_control_acceleration
		correction=correction.clamp(Vector2(-limit,-limit),Vector2(limit,limit))*weapon.recoil_compensation
		var passive:float=spec.passive_return_frequency*maxf(.25,ability.recoil_recovery_scale)
		var equilibrium:=correction/(passive*passive)
		var relative:=angle-equilibrium
		var response:=velocity+passive*relative
		var decay:=exp(-passive*h)
		angle=equilibrium+(relative+response*h)*decay
		velocity=(velocity-passive*response*h)*decay
		var bounds:=pair(spec.max_offset_degrees)
		for axis in range(2):
			if absf(angle[axis])>bounds[axis]:
				angle[axis]=clampf(angle[axis],-bounds[axis],bounds[axis])
				if velocity[axis]*angle[axis]>0: velocity[axis]=0
		if not continuing and angle.length()<.00001 and velocity.length()<.00001:
			angle=Vector2.ZERO
			velocity=Vector2.ZERO
		weapon.recoil_offset_degrees=angle
		weapon.recoil_velocity_degrees_per_second=velocity
		weapon.recoil_since_shot+=h


static func error_envelope(actor) -> Dictionary:
	var weapon: Dictionary = actor.weapon
	return {"center": weapon.recoil_offset_degrees,
		"radius": aim_width(actor) + weapon_accuracy(weapon) + pair(weapon.ammunition.accuracy_degrees)}


static func scatter(width: Vector2, rng: RandomNumberGenerator) -> Vector2:
	# Bounded triangular distribution: denser near the center, no unbounded
	# tails outside the bracket. Weapon, ammo and recoil are independent draws.
	return Vector2(rng.randf() - rng.randf(), rng.randf() - rng.randf()) * width


static func drift_sample(time:float, seed:int) -> float:
	var index:=floori(time)
	var a:=float(posmod(hash(Vector2i(index,seed)),20001))/10000.0-1.0
	var b:=float(posmod(hash(Vector2i(index+1,seed)),20001))/10000.0-1.0
	return lerpf(a,b,smoothstep(0,1,time-index))


static func holding_error(actor) -> Vector2:
	# Bounded, continuous irregular aim drift. No oscillators and no extra
	# burst sway: the weapon's angle/velocity now explain burst instability.
	var t:float=actor.aim_clock/actor.capabilities.values.drift_interval_seconds
	var drift:=Vector2(drift_sample(t,actor.id+17),drift_sample(t*.79,actor.id+491))
	return drift*aim_width(actor)+actor.weapon.recoil_offset_degrees


static func mechanical_error(weapon: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	return scatter(weapon_accuracy(weapon), rng) + scatter(pair(weapon.ammunition.accuracy_degrees), rng)


static func shot_error(actor, rng: RandomNumberGenerator) -> Vector2:
	return holding_error(actor) + mechanical_error(actor.weapon, rng)


static func record_shot(actor, rng: RandomNumberGenerator, consume_ammo := true) -> Vector2:
	var weapon: Dictionary = actor.weapon
	# Called only AFTER this shot has sampled the old state.
	if consume_ammo: weapon.ammo -= 1
	weapon.cooldown = weapon.definition.fire_interval
	weapon.shots_fired += 1
	var spec: Dictionary = weapon.definition.recoil
	var impulse:=pair(spec.impulse_degrees_per_second)*float(actor.capabilities.values.recoil_kick_scale)
	var control:Dictionary=SCData.catalog.ability_rules.recoil_control
	if weapon.recoil_since_shot>maxf(control.burst_gap_seconds,weapon.definition.fire_interval*1.5): weapon.recoil_burst_age=0.0
	var applied:=Vector2(rng.randf_range(-impulse.x,impulse.x),impulse.y)
	weapon.recoil_velocity_degrees_per_second+=applied
	weapon.recoil_expected_impulse=Vector2(0,impulse.y)
	weapon.recoil_since_shot=0.0
	return applied


static func shot_direction(forward: Vector3, error_degrees: Vector2) -> Vector3:
	var horizontal := Vector2(forward.x, forward.z).length()
	var yaw := atan2(forward.z, forward.x) + deg_to_rad(error_degrees.x)
	var pitch := clampf(atan2(forward.y, horizontal) + deg_to_rad(error_degrees.y), deg_to_rad(-89.0), deg_to_rad(89.0))
	return Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))


static func projectile(origin: Vector3, direction: Vector3, weapon: Dictionary) -> Dictionary:
	var tracer: Dictionary = SCData.catalog.presentation.tracers[weapon.ammunition.tracer_presentation]
	var planar := Vector2(direction.x, direction.z)
	return {
		"start": Vector2(origin.x, origin.z), "end": Vector2(origin.x, origin.z),
		"start_height": origin.y, "height": origin.y, "direction_3d": direction,
		"direction": planar.normalized(), "horizontal_factor": planar.length(), "travelled": 0.0,
		"range": weapon.definition.range, "speed": SCData.projectile_speed(weapon), "damage_value": weapon.ammunition.damage,
		"timer": tracer.fade_seconds, "duration": tracer.fade_seconds,
		"tracer_length": tracer.length_m, "tracer_brightness": tracer.brightness,
		"tracer_visible": (int(weapon.shots_fired) - 1) % int(weapon.ammunition.tracer_every_n_shots) == 0,
		"finished": false, "blocked": false, "age": 0.0, "afterglow": 0.0,
		"hit_actor_id": null, "hit_part": null, "damage": 0.0, "near_misses": [], "suppressed": []
	}


static func create_shot(shooter, target: Vector2, target_height: float, rng: RandomNumberGenerator) -> Dictionary:
	var origin := Vector3(shooter.position.x, shooter.muzzle_height, shooter.position.y)
	var direction := shot_direction(Vector3(target.x, target_height, target.y) - origin, shot_error(shooter, rng))
	record_shot(shooter, rng)
	var shot := projectile(origin, direction, shooter.weapon)
	shot.team = shooter.team
	shot.shooter_id = shooter.id
	return shot


static func cylinder_hit_fraction(start: Vector2, end: Vector2, h0: float, h1: float, center_start: Vector2, center_end: Vector2, radius: float, bottom: float, top: float) -> float:
	# Intersect the full planar interval AND the height interval. A descending
	# bullet may enter the top after passing the cylinder's side boundary.
	var relative := start - center_start
	var delta := (end - start) - (center_end - center_start)
	var enter := 0.0
	var leave := 1.0
	var a := delta.length_squared()
	if a < 0.00000001:
		if relative.length_squared() > radius * radius: return -1.0
	else:
		var b := relative.dot(delta)
		var disc := b * b - a * (relative.length_squared() - radius * radius)
		if disc < 0.0: return -1.0
		enter = maxf(enter, (-b - sqrt(disc)) / a)
		leave = minf(leave, (-b + sqrt(disc)) / a)
	var dh := h1 - h0
	if absf(dh) < 0.00000001:
		if h0 < bottom or h0 > top: return -1.0
	else:
		var low := (bottom - h0) / dh
		var high := (top - h0) / dh
		enter = maxf(enter, minf(low, high))
		leave = minf(leave, maxf(low, high))
	return enter if enter <= leave and leave >= 0.0 and enter <= 1.0 else -1.0


static func box_hit_fraction(start: Vector3, end: Vector3, box: AABB) -> float:
	var enter := 0.0
	var leave := 1.0
	var delta := end - start
	for axis in range(3):
		if absf(delta[axis]) < 0.00000001:
			if start[axis] < box.position[axis] or start[axis] > box.end[axis]: return -1.0
		else:
			var a := (box.position[axis] - start[axis]) / delta[axis]
			var b := (box.end[axis] - start[axis]) / delta[axis]
			enter = maxf(enter, minf(a, b))
			leave = minf(leave, maxf(a, b))
	return enter if enter <= leave else -1.0


static func ground_fraction(h0: float, h1: float) -> float:
	if h0 <= 0.0: return 0.0
	return h0 / (h0 - h1) if h1 <= 0.0 else -1.0


static func advance_shot(shot: Dictionary, dt: float, grid, actors: Array, rng: RandomNumberGenerator):
	var start: Vector2 = shot.end
	var length := minf(shot.speed * dt, shot.range - shot.travelled)
	var delta: Vector2 = shot.direction * shot.horizontal_factor * length
	var end := start + delta
	var h0: float = shot.height
	var h1: float = h0 + shot.direction_3d.y * length
	var wall: Array = grid.raycast(start, end, h0, h1, "projectile")
	var best_t: float = wall[0]
	var blocked: bool = wall[1] != null
	var ground := ground_fraction(h0, h1)
	if ground >= 0.0 and ground <= best_t:
		best_t = ground
		blocked = true
	var best = null
	var flight_fraction := length / maxf(shot.speed * dt, 0.000001)
	for a in actors:
		if not a.alive or a.id == shot.shooter_id: continue
		var actor_end: Vector2 = a.previous_position.lerp(a.position, flight_fraction)
		var t := cylinder_hit_fraction(start, end, h0, h1, a.previous_position, actor_end, a.radius, 0.0, a.height)
		if t >= 0.0 and (t < best_t or not blocked and t <= best_t):
			best_t = t
			best = a
	shot.end = start + delta * best_t
	shot.travelled += length * best_t
	shot.height = lerpf(h0, h1, best_t)
	shot.age += dt
	shot.near_misses = []
	if best != null:
		var hit: Dictionary = best.resolve_hit(body_region(shot.height, best, rng), shot.damage_value, rng)
		best.hit_flash = 0.12
		shot.hit_actor_id = best.id
		shot.hit_part = hit.part_id
		shot.damage = hit.damage
		shot.finished = true
	elif blocked:
		shot.blocked = true
		shot.finished = true
	elif shot.travelled >= shot.range - 0.000001:
		shot.finished = true
	if shot.finished:
		shot.afterglow = maxf(0.0, dt - length * best_t / shot.speed)
		shot.timer = maxf(0.0, shot.duration - shot.afterglow)
	for a in actors:
		if not a.alive or a.id == shot.shooter_id or a.id == shot.hit_actor_id or a.id in shot.suppressed: continue
		var actor_end: Vector2 = a.previous_position.lerp(a.position, flight_fraction * best_t)
		var miss := cylinder_hit_fraction(start, shot.end, h0, shot.height, a.previous_position, actor_end, a.radius + 0.2, 0.0, a.height + 0.2)
		if miss >= 0.0:
			shot.near_misses.append(a.id)
			shot.suppressed.append(a.id)


static func reticle_bounds(actor, muzzle: Vector3, forward: Vector3, target: Vector3, gun_reach := 0.0) -> Dictionary:
	# Target-anchored envelope over ALL holding phases, not the current phase.
	var point:=Vector2(target.x,target.z)
	var offset:=point-Vector2(muzzle.x,muzzle.z)
	var distance:=offset.length()
	if distance<.01: return {"valid":false,"center":point}
	var envelope:=error_envelope(actor)
	var radius:Vector2=envelope.radius+envelope.center.abs()
	var holding:Vector2=aim_width(actor)+envelope.center.abs()
	# Rotating around the grip also moves the offset muzzle. Include its whole
	# displacement bound rather than feeding instantaneous jitter back to UI.
	var motion:=2*gun_reach*sin(minf(PI,deg_to_rad(holding.length()))*.5)
	var yaw:=rad_to_deg(angle_difference(offset.angle(),Vector2(forward.x,forward.z).angle()))
	if absf(yaw)+radius.x>=89: return {"valid":false,"center":point}
	var low:=deg_to_rad(yaw-radius.x)
	var high:=deg_to_rad(yaw+radius.x)
	var margin:float=motion*(1+maxf(absf(tan(low)),absf(tan(high))))
	var half_width:float=maxf(absf(distance*tan(low)),absf(distance*tan(high)))+margin
	var pitch:=atan2(forward.y,Vector2(forward.x,forward.z).length())
	var pitch_low:=clampf(pitch-deg_to_rad(radius.y),deg_to_rad(-89),deg_to_rad(89))
	var pitch_high:=clampf(pitch+deg_to_rad(radius.y),deg_to_rad(-89),deg_to_rad(89))
	var heights:Array[float]=[]
	for bearing in [low,high,clampf(0,low,high)]:
		for elevation in [pitch_low,pitch_high]:
			for travel in [maxf(0,distance-motion),distance+motion]:
				heights.append(muzzle.y+travel/cos(bearing)*tan(elevation))
	var side:=Vector2(-offset.y,offset.x).normalized()
	return {"valid":true,"center":point,"left":point-side*half_width,"right":point+side*half_width,
		"axis":side,"height_min":heights.min()-motion,"height_max":heights.max()+motion,"aim":actor.aim_progress}
