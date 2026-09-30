class_name SCPerception
extends RefCounted

var player_visible: Dictionary = {}
var player_raw: Dictionary = {}
var identified: Dictionary = {}
var visible_cells: Dictionary = {}
var explored: Dictionary = {}
var last_seen: Dictionary = {}
var doors: Dictionary = {}
var cells_by_actor: Dictionary = {}
var cell_keys: Dictionary = {}
var first_contact: bool = false


func point_visible(w, a, point: Vector2) -> bool:
	if a.stunned > 0:
		return false
	var delta = point - a.position
	var distance = delta.length()
	if distance > a.view_distance:
		return false
	if distance > 0.01 and absf(angle_difference(a.facing, delta.angle())) > a.view_angle * 0.5:
		return false
	var result = w.grid.raycast(a.position, point)
	return result[1] == null or result[0] >= 1.0 - 0.0000001


func refresh(w, dt: float, force: bool = false):
	player_raw.clear()
	player_visible.clear()
	visible_cells.clear()
	for a in w.actors:
		a.visible.clear()
		if not a.alive:
			continue
		for target in w.actors:
			if target.team == a.team:
				continue
			if point_visible(w, a, target.position):
				a.visible[target.id] = true
				a.identification[target.id] = a.identification.get(target.id, 0.0) + dt * a.capabilities.values.identification_rate
				if a.identification[target.id] >= 0.2:
					a.recognized[target.id] = true
					if a.team == "red":
						identified[target.id] = true
				if a.recognized.has(target.id) and target.alive:
					a.memory[target.id] = [target.position, w.time]
				elif not target.alive:
					a.memory.erase(target.id)
			else:
				a.identification.erase(target.id)
		for id in a.memory.keys():
			if w.time - a.memory[id][1] >= 5:
				a.memory.erase(id)
		if a.team != "red":
			continue
		player_raw.merge(a.visible, true)
		a.recognized.merge(identified, true)
		var key = [a.position, a.facing, a.stunned > 0, w.grid.revision, a.view_distance, a.view_angle]
		if force or cell_keys.get(a.id) != key:
			var cells = {}
			if a.stunned <= 0:
				var radius = a.view_distance
				for y in range(
					maxi(0, floori(a.position.y - radius)),
					mini(w.grid.height, ceili(a.position.y + radius))
				):
					for x in range(
						maxi(0, floori(a.position.x - radius)),
						mini(w.grid.width, ceili(a.position.x + radius))
					):
						var c = Vector2i(x, y)
						if point_visible(w, a, SCData.center(c)):
							cells[c] = true
			cells_by_actor[a.id] = cells
			cell_keys[a.id] = key
		visible_cells.merge(cells_by_actor.get(a.id, {}), true)
		for id in w.grid.entrances:
			var e = w.grid.entrances[id]
			if point_visible(w, a, (SCData.center(e.a) + SCData.center(e.b)) * 0.5):
				doors[id] = w.door_state(id)
	explored.merge(visible_cells, true)
	for id in player_raw:
		if identified.has(id):
			player_visible[id] = true
	for a in w.actors:
		if a.team == "red":
			a.recognized.merge(identified, true)
		elif player_visible.has(a.id):
			last_seen[a.id] = [a.position, w.time]
	for id in last_seen.keys():
		if w.time - last_seen[id][1] >= 5:
			last_seen.erase(id)
	if not first_contact and player_visible.keys().any(func(id): return w.actor(id).alive):
		first_contact = true
		w.message("发现敌人 · 空格暂停，逐人调整行动", "ready")
		if w.auto_contact:
			w.pause_requested = true


func hear(w, event: Dictionary):
	var area = Vector2i(3 * floori(event.position.x / 3), 3 * floori(event.position.y / 3))
	event.area = area
	for a in w.actors:
		if not a.alive:
			continue
		var distance = a.position.distance_to(event.position)
		if distance > event.radius:
			continue
		var penalty = 0.0
		for pair in w.grid.ray_features(event.position, a.position):
			var f = pair[1]
			if f.blocks_projectile and f.height >= 2 and f.kind in ["wall", "door", "boundary"]:
				penalty += 4.0
		if distance + penalty > event.radius:
			continue
		if a.team == "red":
			event.audible = true
		if a.team != event.team:
			var center = Vector2(area) + Vector2(1.5, 1.5)
			var changed = a.heard_position != center
			a.heard_position = center
			a.heard_timer = w.time + (6.0 if a.ai_enabled else 1.0)
			if changed and a.ai_enabled and a.ai_state not in ["combat", "search"]:
				a.ai_goal = null
				a.ai_state = "investigate"


static func enemy_move(w, a, cell) -> bool:
	if a.occupied_cell == cell:
		return true
	if a.target_cell != cell or a.route.is_empty() and a.mode == "standing":
		var route = w.planner.path(
			a, cell, {"known": false, "zone": w.grid.zone_id(w.planner.position_cell(a))}
		)
		if not route.is_empty():
			a.route = route
			a.target_cell = cell
			a.reserved_cell = cell
	return false


static func update_enemy(w, a):
	if not a.alive or a.stunned > 0 or a.current_action != null:
		return
	if a.under_fire_timer > w.time:
		a.clear_movement()
		return
	var visible = []
	for id in a.visible:
		if a.recognized.has(id) and w.actor(id).alive:
			visible.append(w.actor(id))
	var g = w.grid
	var p = w.planner
	var zone = g.zone_id(p.position_cell(a))
	if not visible.is_empty():
		visible.sort_custom(
			func(x, y):
				var dx = a.position.distance_to(x.position)
				var dy = a.position.distance_to(y.position)
				return dx < dy or dx == dy and x.id < y.id
		)
		var target = visible[0]
		if a.ai_state != "combat":
			a.ai_state = "combat"
			a.ai_goal = null
			if zone != null:
				var choices = []
				for c in g.zones[zone].cells:
					if not g.walkable(c) or SCData.center(c).distance_to(a.position) > 3:
						continue
					if w.actors.any(
						func(other):
							return other.id != a.id and other.alive and other.occupied_cell == c
					):
						continue
					if not SCGrid.DIRS.values().any(
						func(delta): return g.cell_features.has(c + delta)
					):
						continue
					if (
						g.raycast(SCData.center(c), target.position, 1.65, 1.25, "projectile")[1]
						!= null
					):
						continue
					var route = p.path(a, c, {"zone": zone, "known": false})
					if not route.is_empty():
						choices.append(
							[
								g.path_cost(route),
								SCData.center(c).distance_to(target.position),
								c.y,
								c.x,
								c,
								route
							]
						)
				choices.sort_custom(SCGrid.heap_less)
				if not choices.is_empty():
					a.ai_goal = choices[0][4]
					a.route = choices[0][5]
					a.reserved_cell = a.ai_goal
					a.target_cell = a.ai_goal
		if w.time - a.report_time >= 0.5:
			a.report_time = w.time
			for other in w.actors:
				if (
					other.ai_enabled
					and other.alive
					and other.id != a.id
					and g.zone_id(p.position_cell(other)) == zone
					and other.position.distance_to(a.position) <= 8
				):
					other.heard_position = target.position
					other.heard_timer = w.time + 6.0
		return
	if a.ai_state == "combat":
		a.clear_movement()
		a.ai_state = "search"
		a.ai_until = w.time + 6
		a.ai_goal = null
		var recent = -INF
		for mem in a.memory.values():
			if mem[1] > recent:
				recent = mem[1]
				a.heard_position = mem[0]
	if a.ai_state in ["search", "investigate"] or a.heard_timer > w.time:
		if a.ai_state not in ["search", "investigate"]:
			a.ai_state = "investigate"
			a.ai_until = a.heard_timer
			a.ai_goal = null
		var deadline = a.ai_until if a.ai_state == "search" else a.heard_timer
		if deadline > w.time and a.heard_position != null and zone != null:
			if a.ai_goal == null:
				var candidates = g.zones[zone].cells.keys().filter(func(c): return g.walkable(c))
				candidates.sort_custom(
					func(x, y):
						var dx = SCData.center(x).distance_to(a.heard_position)
						var dy = SCData.center(y).distance_to(a.heard_position)
						return dx < dy or dx == dy and SCData.cell_less(x, y)
				)
				for c in candidates:
					if not p.path(a, c, {"zone": zone, "known": false}).is_empty():
						a.ai_goal = c
						break
			if a.ai_goal != null and enemy_move(w, a, a.ai_goal):
				a.guard_angle = (a.heard_position - a.position).angle()
				a.ai_wait += 0.1
				if a.ai_wait < 1:
					return
			else:
				return
		a.ai_state = "return"
		a.ai_goal = null
		a.ai_wait = 0.0
		a.heard_timer = 0.0
	if not a.patrol.is_empty():
		var target = a.patrol[a.patrol_index]
		if enemy_move(w, a, target):
			a.ai_wait += 0.1
			var next = a.patrol[(a.patrol_index + 1) % a.patrol.size()]
			a.guard_angle = Vector2(next - target).angle()
			if a.ai_wait >= 1:
				a.patrol_index = (a.patrol_index + 1) % a.patrol.size()
				a.ai_wait = 0.0
		a.ai_state = "patrol"
	elif a.home_cell != null:
		if enemy_move(w, a, a.home_cell):
			a.guard_angle = a.home_angle
		a.ai_state = "guard"
