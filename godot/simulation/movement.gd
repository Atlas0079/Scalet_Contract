class_name SCMovement
extends RefCounted


static func occupied(actor, actors: Array) -> Dictionary:
	var result = {}
	for other in actors:
		if (
			other.alive
			and other.id != actor.id
			and other.mode in ["standing", "acting"]
			and other.occupied_cell != null
		):
			result[other.occupied_cell] = true
	return result


static func reserved(actor, actors: Array) -> Dictionary:
	var result = {}
	for other in actors:
		if other.alive and other.id != actor.id and other.reserved_cell != null:
			result[other.reserved_cell] = true
	return result


static func speed(actor, grid, actors: Array) -> float:
	if not actor.capabilities.permissions.can_move or actor.stunned > 0 or actor.current_action != null:
		return 0.0
	if actor.mode == "moving":
		if actor.move_from == null or actor.move_to == null:
			return 0.0
	elif actor.mode == "standing" and not actor.route.is_empty():
		var target = null
		for c in actor.route:
			if c != actor.occupied_cell:
				target = c
				break
		if target == null or not grid.can_move(actor.occupied_cell, target):
			return 0.0
		if target == actor.reserved_cell and occupied(actor, actors).has(target):
			return 0.0
	else:
		return 0.0
	return maxf(
		0.0,
		(
			actor.speed
			* SCData.angle_speed(actor.capabilities.values.move_angle_curve, angle_difference(actor.facing, movement_direction(actor).angle()))
			* grid.terrain_speed.get(SCData.cell_of(actor.position), 1.0)
		)
	)


static func movement_direction(actor) -> Vector2:
	if actor.mode == "moving":
		return Vector2(actor.move_to - actor.move_from).normalized()
	for cell in actor.route:
		if cell != actor.occupied_cell:
			return (SCData.center(cell) - actor.position).normalized()
	return Vector2.from_angle(actor.facing)


static func allowances(actors: Array, grid, dt: float) -> Dictionary:
	var speeds = {}
	var slowed = {}
	var distances = {}
	for a in actors:
		speeds[a.id] = speed(a, grid, actors)
	for i in range(actors.size()):
		var a = actors[i]
		if not a.alive:
			continue
		for j in range(i + 1, actors.size()):
			var b = actors[j]
			if not b.alive or a.position.distance_to(b.position) >= a.radius + b.radius + 0.18:
				continue
			var ca = SCData.cell_of(a.position)
			var cb = SCData.cell_of(b.position)
			if ca != cb and not grid.can_move(ca, cb):
				continue
			if speeds[a.id] <= 0 and speeds[b.id] <= 0:
				continue
			var slow = a
			if speeds[a.id] <= 0:
				slow = b
			elif (
				speeds[b.id] > 0
				and (speeds[b.id] < speeds[a.id] or speeds[a.id] == speeds[b.id] and b.id > a.id)
			):
				slow = b
			slowed[slow.id] = true
	for a in actors:
		if not a.alive:
			a.crowd_slow_remaining = 0.0
		var slow_time = 0.0
		if slowed.has(a.id):
			a.crowd_slow_remaining = 0.5
			slow_time = dt
		else:
			slow_time = minf(dt, a.crowd_slow_remaining)
			a.crowd_slow_remaining = maxf(0.0, a.crowd_slow_remaining - dt)
			if a.crowd_slow_remaining < 0.000000001:
				a.crowd_slow_remaining = 0.0
		var distance = speeds[a.id] * (0.45 * slow_time + dt - slow_time)
		if a.mode == "moving" and a.move_to != null:
			distance = minf(distance, a.position.distance_to(SCData.center(a.move_to)))
		distances[a.id] = distance
	return distances


static func begin_step(a):
	if a.route.is_empty() or a.mode == "moving" and a.move_to != null:
		return
	var start = (
		a.occupied_cell
		if a.occupied_cell != null
		else (a.move_from if a.move_from != null else SCData.cell_of(a.position))
	)
	if a.route[0] == start:
		a.route.pop_front()
	if a.route.is_empty():
		a.mode = "standing"
		a.occupied_cell = start
		a.position = SCData.center(start)
		a.move_from = null
		a.move_to = null
		a.move_progress = 0.0
		a.clear_movement()
		return
	a.mode = "moving"
	a.occupied_cell = null
	a.move_from = start
	a.move_to = a.route[0]
	a.move_progress = 0.0
	a.position = SCData.center(start)


static func update(a, grid, actors: Array, dt: float, distance: float):
	if not a.alive or a.stunned > 0:
		return
	if a.mode == "standing" and not a.route.is_empty():
		var next = null
		for c in a.route:
			if c != a.occupied_cell:
				next = c
				break
		if next == null:
			a.clear_movement()
			return
		if not grid.can_move(a.occupied_cell, next):
			return
		if next == a.reserved_cell and occupied(a, actors).has(next):
			return
		begin_step(a)
	if a.mode != "moving":
		if a.route.is_empty():
			a.target_cell = null
			a.reserved_cell = null
		return
	var start = SCData.center(a.move_from)
	var end = SCData.center(a.move_to)
	a.move_progress = minf(1.0, a.move_progress + distance / maxf(0.0001, start.distance_to(end)))
	# Vector2 uses single precision in the standard Godot build.
	if a.move_progress >= 1.0 - 0.000001 or a.position.distance_squared_to(end) < 0.0000000001:
		a.move_progress = 1.0
	a.position = start.lerp(end, a.move_progress)
	if a.move_progress < 1.0:
		return
	var arrived = a.move_to
	var taken = occupied(a, actors)
	if taken.has(arrived):
		var onward = a.route.filter(func(c): return c != arrived)
		if not onward.is_empty() and grid.can_move(arrived, onward[0]):
			a.route = onward
			a.mode = "standing"
			a.occupied_cell = arrived
			a.move_from = null
			a.move_to = null
			a.move_progress = 0.0
			begin_step(a)
			return
		var forward = arrived - a.move_from
		var reservations = reserved(a, actors)
		var candidates = grid.neighbors(arrived).filter(
			func(c): return not taken.has(c) and not reservations.has(c)
		)
		candidates.sort_custom(
			func(c, d):
				var dc = Vector2(c - arrived).dot(Vector2(forward))
				var dd = Vector2(d - arrived).dot(Vector2(forward))
				return dc > dd or dc == dd and SCData.cell_less(c, d)
		)
		if not candidates.is_empty():
			a.position = SCData.center(arrived)
			a.move_from = arrived
			a.move_to = candidates[0]
			a.move_progress = 0.0
			a.clear_movement()
			return
		a.move_progress = 0.95
		a.position = start.lerp(end, 0.95)
		return
	if not a.route.is_empty() and a.route[0] == arrived:
		a.route.pop_front()
	a.mode = "standing"
	a.occupied_cell = arrived
	a.position = SCData.center(arrived)
	a.move_from = null
	a.move_to = null
	a.move_progress = 0.0
	if a.route.is_empty():
		a.clear_movement()
