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
	actor.weapon.reaim_tracking = tracking
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
	weapon["recoil_active"] = false
	weapon["recoil_overshoot_phase"] = "ready"
	weapon["recoil_overshoot_elapsed"] = 0.0
	weapon["recoil_overshoot_count"] = 0
	weapon["recoil_overshoot_target"] = 0.0
	weapon["reaim_offset_degrees"] = Vector2.ZERO
	weapon["reaim_tracking"] = false


static func stop_firing(actor):
	var weapon: Dictionary = actor.weapon
	if not weapon.recoil_active: return
	# Preserve the visible direction while handing motion to aiming. Old
	# recoil velocity/compensation never survives into the next burst.
	var offset: Vector2 = weapon.recoil_offset_degrees + weapon.reaim_offset_degrees
	var tracking: bool = weapon.reaim_tracking
	reset_recoil(weapon)
	weapon.reaim_offset_degrees = offset
	weapon.reaim_tracking = tracking


static func _advance_realignment(actor, dt: float):
	var weapon: Dictionary = actor.weapon
	if not weapon.reaim_tracking or not actor.capabilities.permissions.can_aim: return
	var ability: Dictionary = actor.capabilities.values
	var speed: float = ability.aim_gain_per_second * ability.realignment_degrees_per_progress
	weapon.reaim_offset_degrees = weapon.reaim_offset_degrees.move_toward(Vector2.ZERO,speed*dt)


static func advance_recoil(actor, dt: float):
	var weapon: Dictionary = actor.weapon
	var control: Dictionary = SCData.catalog.ability_rules.recoil_control
	if not actor.capabilities.permissions.can_aim: stop_firing(actor)
	var remaining := dt
	var gap: float = maxf(control.burst_gap_seconds,weapon.definition.fire_interval*1.5)
	while remaining > 0.000000001:
		if not weapon.recoil_active:
			_advance_realignment(actor,remaining)
			weapon.recoil_since_shot += remaining
			return
		if weapon.recoil_since_shot >= gap-0.000000001:
			stop_firing(actor)
			continue
		var h := minf(minf(remaining,1.0/480.0),gap-weapon.recoil_since_shot)
		_advance_recoil_step(actor,h,control)
		weapon.recoil_since_shot += h
		remaining -= h


static func _advance_recoil_step(actor, dt: float, control: Dictionary):
	var weapon: Dictionary = actor.weapon
	var ability: Dictionary = actor.capabilities.values
	weapon.recoil_burst_age += dt
	if weapon.recoil_burst_age >= ability.recoil_response_delay_seconds:
		weapon.recoil_compensation = 1-(1-weapon.recoil_compensation)*exp(-dt/ability.recoil_compensation_build_seconds)
		if weapon.recoil_overshoot_phase == "ready":
			weapon.recoil_overshoot_target = ability.recoil_overshoot_degrees
			weapon.recoil_overshoot_phase = "push" if weapon.recoil_overshoot_target > 0 else "done"
			if weapon.recoil_overshoot_phase == "push": weapon.recoil_overshoot_count += 1
	var target := Vector2.ZERO
	var effort: float = weapon.recoil_compensation
	if weapon.recoil_overshoot_phase == "push":
		target.y = -weapon.recoil_overshoot_target
		effort = minf(1.0,effort*(1+weapon.recoil_overshoot_target*control.overshoot_effort_per_degree))
		weapon.recoil_overshoot_elapsed += dt
		if weapon.recoil_overshoot_elapsed >= control.overshoot_push_seconds:
			weapon.recoil_overshoot_phase = "return"
	var angle: Vector2 = weapon.recoil_offset_degrees
	var velocity: Vector2 = weapon.recoil_velocity_degrees_per_second
	var prediction: Vector2 = weapon.recoil_expected_impulse/weapon.definition.fire_interval*ability.recoil_prediction_scale if weapon.recoil_since_shot < weapon.definition.fire_interval else Vector2.ZERO
	var frequency: float = ability.recoil_control_frequency
	var correction := -frequency*frequency*(angle-target)-2*frequency*velocity-prediction
	var limit: float = ability.recoil_control_acceleration
	# The one-time downward target cannot bypass the same physical force limit.
	correction = correction.clamp(Vector2(-limit,-limit),Vector2(limit,limit))*effort
	var support: float = weapon.definition.recoil.support_frequency*ability.recoil_support_scale
	if support > 0:
		var equilibrium := correction/(support*support)
		var relative := angle-equilibrium
		var response := velocity+support*relative
		var decay := exp(-support*dt)
		angle = equilibrium+(relative+response*dt)*decay
		velocity = (velocity-support*response*dt)*decay
	else:
		angle += velocity*dt+correction*dt*dt*.5
		velocity += correction*dt
	if weapon.recoil_overshoot_phase == "return" and angle.y >= 0:
		weapon.recoil_overshoot_phase = "done"
	# After the single excursion, correction may reach the aim point but
	# cannot generate another downward crossing or an oscillating spring.
	if weapon.recoil_overshoot_phase in ["ready","done"] and angle.y < 0 and weapon.recoil_offset_degrees.y >= 0:
		angle.y = 0.0
		velocity.y = maxf(0.0,velocity.y)
	var bounds := pair(weapon.definition.recoil.max_offset_degrees)
	for axis in range(2):
		if absf(angle[axis]) > bounds[axis]:
			angle[axis] = clampf(angle[axis],-bounds[axis],bounds[axis])
			if velocity[axis]*angle[axis] > 0: velocity[axis] = 0
	weapon.recoil_offset_degrees = angle
	weapon.recoil_velocity_degrees_per_second = velocity


static func error_envelope(actor) -> Dictionary:
	var weapon: Dictionary = actor.weapon
	return {"center": weapon.recoil_offset_degrees+weapon.reaim_offset_degrees,
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
	return drift*aim_width(actor)+actor.weapon.recoil_offset_degrees+actor.weapon.reaim_offset_degrees


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
	if not weapon.recoil_active:
		weapon.recoil_offset_degrees += weapon.reaim_offset_degrees
		weapon.reaim_offset_degrees = Vector2.ZERO
		weapon.recoil_active = true
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
		"range": weapon.definition.range, "speed": SCData.projectile_speed(weapon), "damage_value": weapon.ammunition.damage, "attack_category":"kinetic", "penetration":weapon.ammunition.penetration,
		"timer": tracer.fade_seconds, "duration": tracer.fade_seconds,
		"tracer_length": tracer.length_m, "tracer_brightness": tracer.brightness,
		"tracer_visible": (int(weapon.shots_fired) - 1) % int(weapon.ammunition.tracer_every_n_shots) == 0,
		"penetrated_parts": {}, "impacts": [],
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


static func remaining_penetration(incoming: float, resistance: float) -> float:
	if resistance<=0: return incoming
	return incoming-resistance if incoming>resistance else -1.0

# Non-mutating line-of-fire query; it conservatively uses the current structure.
static func projectile_obstruction(grid: SCGrid, start: Vector2, end: Vector2, h0: float, h1: float, penetration: float) -> Variant:
	var ignored: Dictionary = {}
	while true:
		var collision := grid.raycast(start,end,h0,h1,"projectile",false,ignored)
		if collision[1]==null: return null
		var feature: Dictionary = collision[1]
		var part: Dictionary = feature.get("ray_hit",{})
		if not grid.entities.has(feature.get("id","")) or part.is_empty(): return feature
		var next := remaining_penetration(penetration,part.protection)
		if next<0: return feature
		penetration=next
		ignored[part.contact_key]=true
	return null

# Both combat and the range consume this path. Parts are charged once per straight projectile.
static func advance_path(shot: Dictionary, dt: float, grid: SCGrid, targets: Array) -> Dictionary:
	shot.age+=dt
	var remaining := dt
	var elapsed := 0.0
	var result: Dictionary = {}
	while remaining>0.000000001 and not shot.finished:
		var start: Vector2 = shot.end
		var distance: float = minf(shot.speed*remaining,maxf(0.0,shot.range-shot.travelled))
		if distance<=0.000000001:
			shot.finished=true
			break
		var segment_time: float = distance/shot.speed
		var end: Vector2 = start+shot.direction*shot.horizontal_factor*distance
		var h0: float = shot.height
		var h1: float = h0+shot.direction_3d.y*distance
		var collision: Array = grid.raycast(start,end,h0,h1,"projectile",true,shot.penetrated_parts)
		var best: float = collision[0]
		var blocked: bool = collision[1]!=null
		var ground: float = ground_fraction(h0,h1)
		if ground>=0 and ground<=best:
			best=ground
			collision=[ground,{"label":"地面"}]
			blocked=true
		var target: Dictionary = {}
		for entry in targets:
			var p0: Vector2 = entry.previous.lerp(entry.position,clampf(elapsed/maxf(dt,.000000001),0,1))
			var p1: Vector2 = entry.previous.lerp(entry.position,clampf((elapsed+segment_time)/maxf(dt,.000000001),0,1))
			var at: float = cylinder_hit_fraction(start,end,h0,h1,p0,p1,entry.radius,0,entry.height)
			if at>=0 and (at<best or not blocked and at<=best):
				best=at
				target=entry
				blocked=false
		var used: float = segment_time*best
		shot.end=start.lerp(end,best)
		shot.height=lerpf(h0,h1,best)
		shot.travelled+=distance*best
		elapsed+=used
		remaining=maxf(0.0,remaining-used)
		if not target.is_empty():
			shot.finished=true
			result={"target":target,"blocked":false,"label":target.label,"position":shot.end,"height":shot.height}
			break
		if blocked:
			var feature: Dictionary = collision[1]
			var entity: SCEntity = grid.entities.get(feature.get("id",""))
			var penetrated := false
			var part: Dictionary = feature.get("ray_hit",{})
			if entity!=null and not part.is_empty():
				var resistance: float = part.protection
				var incoming: float = shot.penetration
				var damage: float = shot.damage_value
				var before: bool = entity.ruined
				entity.damage(damage)
				if before!=entity.ruined:
					grid.revision+=1
					grid.path_cache.clear()
				var next_penetration := remaining_penetration(incoming,resistance)
				if next_penetration>=0:
					penetrated=true
					shot.penetrated_parts[part.contact_key]=true
					shot.penetration=next_penetration
					if incoming>0: shot.damage_value=damage*(shot.penetration/incoming)
				shot.impacts.append({"entity_id":entity.definition.id,"part_id":part.part_id,"position":shot.end,"height":shot.height,"penetrated":penetrated,"protection":resistance,"remaining_penetration":shot.penetration,"remaining_damage":shot.damage_value})
			if not penetrated:
				shot.finished=true
				shot.blocked=true
				result={"target":{},"blocked":true,"label":feature.get("label","地形"),"position":shot.end,"height":shot.height}
				break
			continue
		remaining=maxf(0.0,remaining-segment_time+used)
		if shot.travelled>=shot.range-.00000001: shot.finished=true
	if shot.finished:
		shot.afterglow=maxf(0.0,dt-elapsed)
		shot.timer=maxf(0.0,shot.duration-shot.afterglow)
		if not result.is_empty(): result["age"]=shot.afterglow
	return result

static func advance_shot(shot: Dictionary, dt: float, grid, actors: Array, rng: RandomNumberGenerator):
	var start: Vector2 = shot.end
	var old_distance: float = shot.travelled
	var targets: Array = []
	for a in actors:
		if a.id==shot.shooter_id or not a.alive: continue
		targets.append({"actor":a,"previous":a.previous_position,"position":a.position,"radius":a.radius,"height":a.height,"label":a.actor_name})
	var result := advance_path(shot,dt,grid,targets)
	if not result.is_empty() and not result.target.is_empty():
		var best: SCActor = result.target.actor
		var hit: Dictionary = best.resolve_hit(body_region(shot.height,best,rng),shot.damage_value,rng,shot.attack_category,shot.penetration)
		best.hit_flash=.12
		if not best.alive and best.world!=null and best.world.loot!=null: best.world.loot.corpse(best)
		shot.hit_actor_id=best.id
		shot.hit_part=hit.part_id
		shot.damage=hit.damage
	shot.near_misses=[]
	var fraction: float = clampf((shot.travelled-old_distance)/maxf(shot.speed*dt,.000000001),0,1)
	for a in actors:
		if not a.alive or a.id==shot.shooter_id or a.id==shot.hit_actor_id or a.id in shot.suppressed: continue
		var actor_end: Vector2 = a.previous_position.lerp(a.position,fraction)
		var h0: float = shot.height-shot.direction_3d.y*(shot.travelled-old_distance)
		var miss := cylinder_hit_fraction(start,shot.end,h0,shot.height,a.previous_position,actor_end,a.radius+.2,0,a.height+.2)
		if miss>=0:
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

# Static-target laboratory trajectories use the same grid and collision primitives
# as actor combat. Renderers consume this result to draw impacts and target paper.
static func advance_training_shot(shot: Dictionary, dt: float, grid: SCGrid, targets: Array) -> Dictionary:
	if shot.finished:
		shot.afterglow+=dt
		return {}
	var descriptors: Array = []
	for entry in targets:
		descriptors.append({"entry":entry,"previous":entry.position,"position":entry.position,"radius":entry.radius,"height":entry.height,"label":entry.label})
	var result := advance_path(shot,dt,grid,descriptors)
	if not result.is_empty():
		if not result.target.is_empty():
			result.target=result.target.entry
			shot["hit_target_id"]=result.target.id
		shot["stop_label"]=result.label+"截停"
	return result
