class_name SCRoomTasks
extends RefCounted


static func room_angle(room: String, c: Vector2i) -> float:
	var r = SCData.mission.rects[room]
	var delta = Vector2((r[0] + r[2] + 1) / 2.0, (r[1] + r[3] + 1) / 2.0) - SCData.center(c)
	return delta.angle() if delta.length_squared() > 0 else -PI / 2.0


static func fill_slots(g, candidates: Array, base: Vector2i, zone: String, radius: float) -> Array:
	var allowed = g.zones[zone].cells
	var pool = allowed.keys().filter(func(c): return g.walkable(c))
	pool.sort_custom(
		func(a, b):
			var da = Vector2(a).distance_squared_to(Vector2(base))
			var db = Vector2(b).distance_squared_to(Vector2(base))
			return da < db or da == db and SCData.cell_less(a, b)
	)
	var result = []
	for candidate in candidates:
		var nearby = pool.filter(
			func(c): return Vector2(c).distance_to(Vector2(candidate)) <= radius
		)
		nearby.sort_custom(
			func(a, b):
				var da = Vector2(a).distance_squared_to(Vector2(candidate))
				var db = Vector2(b).distance_squared_to(Vector2(candidate))
				return da < db or da == db and SCData.cell_less(a, b)
		)
		var options = [candidate]
		options.append_array(nearby)
		for c in options:
			if (
				c not in result
				and allowed.has(c)
				and g.walkable(c)
				and not g.find_path(base, c, allowed).is_empty()
			):
				result.append(c)
				break
	for c in pool:
		if result.size() >= 4:
			break
		if c not in result and Vector2(c).distance_to(Vector2(base)) <= 3.0:
			result.append(c)
	return result.slice(0, 4)


static func preview(
	p, ids: Array, door: String, room: String, method: String, options: Dictionary
) -> Array:
	var w = p.world
	var g = w.grid
	var units = []
	var append = options.get("append", false)
	for id in ids:
		var a = p.actor(id)
		if a == null or not a.alive:
			return [null, "先选择存活队员"]
		if a not in units:
			units.append(a)
	if units.is_empty():
		return [null, "先选择存活队员"]
	var room_action = method in ["direct", "breach", "flash"]
	if room_action and units.size() < 2:
		return [null, "需要至少两名队员"]
	if not g.zones.has(room) or room_action and room in ["S", "C"]:
		return [null, "目标不是房间"]
	if not g.entrances.has(door):
		return [null, "无效入口"]
	var e = g.entrances[door]
	if room not in [e.zone_a, e.zone_b]:
		return [null, "入口不通向该房间"]
	var outside = e.b if e.zone_a == room else e.a
	var inside = e.a if e.zone_a == room else e.b
	var normal = inside - outside
	var tangent = Vector2i(-normal.y, normal.x)
	var angle = Vector2(normal).angle()
	var stack_seeds = []
	var entry_seeds = []
	for v in [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(-1, -1)
	]:
		stack_seeds.append(outside + normal * v.x + tangent * v.y)
	for v in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(2, 1), Vector2i(2, -1)]:
		entry_seeds.append(inside + normal * v.x + tangent * v.y)
	var stacks = fill_slots(g, stack_seeds, outside, g.zone_id(outside), 0.0)
	var entries = fill_slots(g, entry_seeds, inside, room, 2.0)
	if stacks.size() < units.size() or entries.size() < units.size():
		return [null, "入口没有足够槽位"]
	if method in ["open", "kick"]:
		var reachable = []
		for a in units:
			var route = p.path(a, outside, {"start": p.origin(a, append)})
			if not route.is_empty():
				reachable.append([g.path_cost(route), a.id, a])
		reachable.sort_custom(func(a, b): return a[0] < b[0] or a[0] == b[0] and a[1] < b[1])
		if reachable.is_empty():
			return [null, "无可达交互格"]
		units = [reachable[0][2]]
		stacks = [outside]
	for i in range(units.size()):
		var opts = {"start": p.origin(units[i], append)}
		if room_action:
			opts.exclude = room
		if p.path(units[i], stacks[i], opts).is_empty():
			return [null, "无可达集结侧，请切换入口方向"]
	var known = w.perception.doors.get(door, "unknown")
	if known == "locked" and method in ["open", "direct"]:
		return [null, "门已锁，请选破门方式"]
	if known in ["open", "broken"] and method in ["open", "kick", "breach"]:
		return [null, "门已打开，请选直接突入"]
	var sync = options.get("sync")
	for a in units:
		if append and a.queue.size() >= 8:
			return [null, "队列已满"]
		if sync != null and p.has_sync(a, append):
			return [null, "该队员已有同步等待"]
	var item = null
	var thrower = null
	var landing = null
	if method == "flash":
		item = options.get("item", "flashbang")
		if item == null:
			item = "flashbang"
		var candidates = units.filter(func(a): return p.available(a, item, append) > 0)
		if candidates.is_empty():
			return [null, "没有可用道具"]
		thrower = options.get("thrower", candidates[0].id)
		if thrower == null:
			thrower = candidates[0].id
		if not candidates.any(func(a): return a.id == thrower):
			return [null, "指定执行者没有可用道具"]
		landing = options.get("landing")
	var opening = options.get("opening")
	if opening == null:
		opening = "kick" if method in ["kick", "breach"] or known == "locked" else "open"
	var d = {
		"actors": [],
		"door": door,
		"room": room,
		"method": method,
		"outside": outside,
		"inside": inside,
		"stacks": {},
		"entries": {},
		"angle": angle,
		"item": item,
		"thrower": thrower,
		"landing": landing,
		"sync": sync,
		"opening": opening,
		"after_entry": options.get("after_entry", "hold"),
		"stack_overrides": options.get("stack_overrides", {}).duplicate(),
		"entry_overrides": options.get("entry_overrides", {}).duplicate(),
		"stack_angles": options.get("stack_angles", {}).duplicate(),
		"entry_angles": options.get("entry_angles", {}).duplicate()
	}
	for i in range(units.size()):
		d.actors.append(units[i].id)
		d.stacks[units[i].id] = stacks[i]
		d.entries[units[i].id] = entries[i]
	if d.after_entry not in ["hold", "search"]:
		return [null, "无效的突入后行动"]
	for mapping in [d.stack_overrides, d.entry_overrides, d.stack_angles, d.entry_angles]:
		for id in mapping:
			if id not in d.actors:
				return [null, "站位或朝向包含未参与的队员"]
	for phase in ["stack", "entry"]:
		var overrides = d.stack_overrides if phase == "stack" else d.entry_overrides
		var slots = d.stacks if phase == "stack" else d.entries
		var zone = g.zone_id(outside) if phase == "stack" else room
		slots.merge(overrides, true)
		var occupied = {}
		for c in slots.values():
			if occupied.has(c):
				return [null, "同一阶段的队员站位不能重叠"]
			occupied[c] = true
		for id in overrides:
			var c = overrides[id]
			if not g.walkable(c) or g.zone_id(c) != zone:
				return [null, "站位必须在对应房间的可行走格"]
			if phase == "entry":
				if c == inside:
					return [null, "进门后站位不能占住入口通道"]
				if p.path(p.actor(id), c, {"start": inside, "zone": room}).is_empty():
					return [null, "入口无法到达指定就位点"]
			elif (
				p
				. path(p.actor(id), c, {"start": p.origin(p.actor(id), append), "exclude": room})
				. is_empty()
			):
				return [null, "无法到达指定集结点"]
	for mapping in [d.stack_angles, d.entry_angles]:
		for a in mapping.values():
			if not is_finite(a):
				return [null, "无效朝向"]
	if item != null and landing != null:
		var error = p.throw_error(p.actor(thrower), item, landing, d.stacks[thrower], room, door)
		if not error.is_empty():
			return [d, error]
	return [d, ""]


static func choose(p, ids: Array, door, room, method: String, append: bool):
	var choices = []
	var errors = []
	for e in p.world.grid.entrances.values():
		if door != null and e.id != door:
			continue
		for target in [e.zone_a, e.zone_b]:
			if room != null and target != room:
				continue
			var result = preview(p, ids, e.id, target, method, {"append": append})
			if not result[1].is_empty():
				if result[1] not in errors:
					errors.append(result[1])
				continue
			var d = result[0]
			var cost = 0.0
			for id in d.stacks:
				cost += p.world.grid.path_cost(
					p.path(p.actor(id), d.stacks[id], {"start": p.origin(p.actor(id), append)})
				)
			choices.append([cost, e.id, target, d])
	choices.sort_custom(
		func(a, b):
			return a[0] < b[0] or a[0] == b[0] and (a[1] < b[1] or a[1] == b[1] and a[2] < b[2])
	)
	p.entrance_error = "；".join(errors) if not errors.is_empty() else "没有通向该区域的入口"
	return null if choices.is_empty() else choices[0][3]


static func submit(p, d: Dictionary, append: bool) -> String:
	var options = d.duplicate(true)
	options.append = append
	var result = preview(p, d.actors, d.door, d.room, d.method, options)
	if not result[1].is_empty():
		return result[1]
	var fresh = result[0]
	if fresh.item != null and fresh.landing == null:
		return "请设置道具落点"
	var id = p.next_id
	p.next_id += 1
	if not append:
		p.cancel_related(fresh.actors)
	for i in fresh.actors:
		var a = p.actor(i)
		if not append:
			p.cancel_actor(a)
		elif not a.queue.is_empty() and a.queue.back().kind == "guard":
			a.queue.back().kind = "move_face"
	var task = SCData.task(id, fresh)
	p.tasks[id] = task
	if fresh.item != null:
		p.actor(fresh.thrower).reserve(task.token, fresh.item)
	for i in fresh.actors:
		p.actor(i).queue.append(SCData.node(task.token, "task", {"task_id": id}))
		p.actor(i).blocked_reason = ""
	p.world.message("%s：%s" % [str(fresh.actors), p.task_label(task)])
	return ""


static func retry(p, id: int) -> String:
	if not p.tasks.has(id):
		return "行动已结束"
	var t = p.tasks[id]
	var d = t.draft
	for i in d.actors:
		if p.actor(i).stunned > 0 or p.actor(i).under_fire_timer > p.world.time:
			return "等待震撼或受袭搜索结束"
	if d.method == "loot":
		if not d.actors.any(func(i): return not t.guards.has(i)):
			return "已无搜索者，请取消后重新分工"
		t.phase = "loot"
		t.reason = ""
		for i in d.actors:
			p.actor(i).blocked_reason = ""
		for job in t.jobs.values():
			job.started = false
		return ""
	if d.method in ["direct", "breach", "flash"] and d.actors.size() < 2:
		return "不足两人，请取消并使用单人指令"
	if d.item != null and not t.flash_released:
		if d.thrower not in d.actors:
			return "道具执行者已退出，请重新下达"
		if not p.actor(d.thrower).reservations.has(t.token):
			return "物品预约失效，请重新下达"
		var error = p.throw_error(
			p.actor(d.thrower), d.item, d.landing, d.stacks[d.thrower], d.room, d.door
		)
		if not error.is_empty():
			return error
	if p.world.perception.doors.get(d.door) == "locked" and d.opening != "kick":
		return "门已锁，请重新选择破门方式"
	var goals = d.entries if t.resume_phase in ["enter", "search"] and d.sync == null else d.stacks
	for i in d.actors:
		if p.path(p.actor(i), goals[i]).is_empty():
			return "执行位置不可达，请修改方案"
	t.phase = t.resume_phase if t.resume_phase not in ["blocked", "queued"] else "stack"
	if d.sync != null:
		t.phase = "stack"
		t.enter_index = 0
		t.entered.clear()
	t.reason = ""
	t.action_started = false
	for i in d.actors:
		p.stalls.erase(i)
		p.actor(i).blocked_reason = ""
	if t.phase == "search":
		assign_search(p, t)
	return ""


static func observations(p, room: String) -> Array:
	var r = SCData.mission.rects[room]
	var seeds = [
		Vector2i(r[0] + 1, r[1] + 1),
		Vector2i(r[2] - 1, r[1] + 1),
		Vector2i(r[2] - 1, r[3] - 1),
		Vector2i(r[0] + 1, r[3] - 1),
		Vector2i(int((r[0] + r[2] + 1) / 2), int((r[1] + r[3] + 1) / 2))
	]
	var cells = p.world.grid.zones[room].cells.keys().filter(
		func(c): return p.world.grid.walkable(c)
	)
	var result = []
	for seed in seeds:
		cells.sort_custom(
			func(a, b):
				var da = Vector2(a).distance_squared_to(Vector2(seed))
				var db = Vector2(b).distance_squared_to(Vector2(seed))
				return da < db or da == db and SCData.cell_less(a, b)
		)
		if not cells.is_empty() and cells[0] not in result:
			result.append(cells[0])
	return result


static func assign_search(p, t: Dictionary):
	var ids = t.draft.actors.filter(func(i): return not t.guards.has(i))
	var remaining = []
	if ids.is_empty():
		return
	if not t.searches.is_empty():
		for points in t.searches.values():
			for c in points:
				if c not in remaining:
					remaining.append(c)
	else:
		remaining = observations(p, t.draft.room)
	var costs = {}
	var ends = {}
	t.searches = {}
	t.observations = {}
	for id in ids:
		costs[id] = 0.0
		ends[id] = p.position_cell(p.actor(id))
		t.searches[id] = []
		t.observations[id] = 0.0
	for point in remaining:
		var selected = ids[0]
		for id in ids:
			if costs[id] < costs[selected]:
				selected = id
		costs[selected] += p.world.grid.path_cost(
			p.path(p.actor(selected), point, {"start": ends[selected], "zone": t.draft.room})
		)
		t.searches[selected].append(point)
		ends[selected] = point


static func finish(p, t: Dictionary):
	for id in t.draft.actors:
		var a = p.actor(id)
		a.reservations.erase(t.token)
		a.queue = a.queue.filter(func(n): return n.task_id != t.id)
		a.blocked_reason = ""
		a.clear_movement()
	t.phase = "done"
	p.world.message(p.task_label(t) + " · 完成")
	p.tasks.erase(t.id)


static func resolve_slot(p, t: Dictionary, a, cell, assigned: Array, zone):
	var occupied = {}
	for other in p.world.actors:
		if (
			other.alive
			and other.id != a.id
			and other.occupied_cell != null
			and other.route.is_empty()
		):
			occupied[other.occupied_cell] = true
	if not occupied.has(cell):
		return cell
	var g = p.world.grid
	var room = g.zone_id(cell)
	var choices = []
	for c in g.zones[room].cells:
		if (
			occupied.has(c)
			or c != cell and c in assigned
			or not g.walkable(c)
			or Vector2(c).distance_to(Vector2(cell)) > 2
		):
			continue
		var opts = {}
		if zone != null:
			opts.zone = zone
		if t.phase in ["stack", "wait"]:
			opts.exclude = t.draft.room
		var route = p.path(a, c, opts)
		if not route.is_empty():
			choices.append(
				[Vector2(c).distance_squared_to(Vector2(cell)), g.path_cost(route), c.y, c.x, c]
			)
	choices.sort_custom(SCGrid.heap_less)
	return cell if choices.is_empty() else choices[0][4]


static func tick(p, t: Dictionary, dt: float):
	var w = p.world
	var d = t.draft
	if d.method == "loot":
		w.loot.tick_task(t, dt)
		return
	if t.phase == "blocked":
		return
	var units = []
	for id in d.actors:
		var a = p.actor(id)
		if a.queue.is_empty() or a.queue[0].task_id != t.id:
			return
		units.append(a)
	if t.phase == "queued":
		t.phase = "stack"
	for other in p.tasks.values():
		if (
			other.id < t.id
			and other.draft.door == d.door
			and other.phase not in ["search", "done", "cancelled"]
			and t.phase in ["stack", "wait", "door"]
		):
			p.suspend_task(t, "门被行动 %d 占用" % other.id)
			return
	for a in units:
		if not a.blocked_reason.is_empty():
			p.suspend_task(t, a.blocked_reason)
			return
	if t.phase in ["stack", "wait"]:
		var ready = true
		for i in range(units.size()):
			var a = units[i]
			if not d.stack_overrides.has(a.id):
				d.stacks[a.id] = resolve_slot(p, t, a, d.stacks[a.id], d.stacks.values(), null)
			var facing = d.stack_angles.get(a.id, d.angle if i < 3 else d.angle + PI)
			ready = p.drive(a, d.stacks[a.id], dt, facing) and ready
		if ready and not t.ready and d.sync != null:
			w.message("行动 %d · 同步 %s 就绪" % [t.id, d.sync], "ready")
		t.ready = ready
		if not ready:
			return
		if d.method in ["stack", "guarddoor"]:
			finish(p, t)
			return
		if d.sync != null and not t.released:
			t.phase = "wait"
			return
		t.phase = "door"
	if t.phase == "door":
		if w.door_state(d.door) in ["open", "broken"]:
			w.completed.erase(t.token)
			if d.method in ["open", "kick"]:
				finish(p, t)
				return
			t.phase = "throw" if d.item != null and not t.flash_released else "enter"
			t.action_started = false
		else:
			var a = units[0]
			if not p.drive(a, d.outside, dt, d.angle):
				return
			if w.door_state(d.door) == "locked" and d.opening != "kick":
				p.suspend_task(t, "门已锁，重新选择破门方式")
				return
			if not t.action_started:
				var error = w.start_action(
					a,
					"kick_door" if d.opening == "kick" else "open_door",
					1.4 if d.opening == "kick" else 0.8,
					t.token,
					{"door": d.door, "cell": d.inside}
				)
				if not error.is_empty():
					p.suspend_task(t, error)
				else:
					t.action_started = true
			return
	if t.phase == "throw":
		if t.flash_released:
			w.completed.erase(t.token)
			t.phase = "blast"
			return
		var a = p.actor(d.thrower)
		if a.stunned > 0:
			return
		if a.mode != "standing" or a.occupied_cell != d.stacks[a.id]:
			if not p.drive(a, d.stacks[a.id], dt):
				return
		if not t.action_started:
			var error = p.throw_error(a, d.item, d.landing, null, d.room)
			if not error.is_empty():
				p.suspend_task(t, error)
				return
			error = w.start_action(
				a,
				"throw_grenade",
				SCData.use_for(d.item).duration,
				t.token,
				{"item": d.item, "cell": d.landing}
			)
			if not error.is_empty():
				p.suspend_task(t, error)
				return
			t.action_started = true
		return
	if t.phase == "blast":
		if w.time < t.blast_at:
			return
		t.phase = "enter"
	if t.phase == "enter":
		for i in range(t.enter_index):
			var a = units[i]
			if not d.entry_overrides.has(a.id):
				d.entries[a.id] = resolve_slot(p, t, a, d.entries[a.id], d.entries.values(), null)
			if p.drive(
				a,
				d.entries[a.id],
				dt,
				d.entry_angles.get(a.id, room_angle(d.room, d.entries[a.id]))
			):
				t.entered[a.id] = true
		if t.enter_index < units.size():
			var a = units[t.enter_index]
			var previous = units[t.enter_index - 1] if t.enter_index > 0 else null
			var clear = (
				previous == null
				or (
					w.grid.zone_id(p.position_cell(previous)) == d.room
					and previous.occupied_cell != d.inside
					and previous.move_to != d.inside
					and previous.move_from != d.inside
				)
			)
			if clear and w.time - t.released_at >= 0.25:
				p.drive(
					a,
					d.entries[a.id],
					dt,
					d.entry_angles.get(a.id, room_angle(d.room, d.entries[a.id]))
				)
				t.enter_index += 1
				t.released_at = w.time
		elif t.entered.size() == units.size():
			if d.after_entry == "hold":
				finish(p, t)
			else:
				t.phase = "search"
				assign_search(p, t)
		return
	if t.phase == "search":
		var done = true
		for a in units:
			var points = t.searches.get(a.id, [])
			if points.is_empty():
				continue
			var assigned = t.finals.values()
			for values in t.searches.values():
				assigned.append_array(values)
			points[0] = resolve_slot(p, t, a, points[0], assigned, d.room)
			done = false
			if p.drive(a, points[0], dt, room_angle(d.room, points[0]), d.room):
				t.observations[a.id] = t.observations.get(a.id, 0.0) + dt
				if t.observations[a.id] >= 0.4:
					t.finals[a.id] = points.pop_front()
					t.observations[a.id] = 0.0
			else:
				t.observations[a.id] = 0.0
		if done and not units.any(func(a): return w.has_threat(a)):
			for a in units:
				for memory in a.memory.values():
					if (
						w.grid.zone_id(SCData.cell_of(memory[0])) == d.room
						and w.time - memory[1] < 5
					):
						return
			for i in range(units.size()):
				var a = units[i]
				a.guard_angle = (
					(SCData.center(d.inside) - a.position).angle()
					if i == units.size() - 1
					else room_angle(d.room, p.position_cell(a))
				)
			w.room_checked[d.room] = w.time
			finish(p, t)


static func submit_loot(p, ids: Array, room: String, guards: Array) -> String:
	if ids.is_empty():
		return "请选择存活队员"
	if not p.world.grid.zones.has(room):
		return "无效区域"
	for id in ids:
		var a = p.actor(id)
		if a == null or not a.alive:
			return "请选择存活队员"
		if p.world.grid.zone_id(p.position_cell(a)) != room:
			return "请先让参与者进入目标区域"
	if ids.all(func(id): return id in guards):
		return "至少需要一名搜索者"
	p.cancel_related(ids)
	for id in ids:
		p.cancel_actor(p.actor(id))
	var id = p.next_id
	p.next_id += 1
	var positions = {}
	for i in ids:
		positions[i] = p.position_cell(p.actor(i))
	var anchor = positions[ids[0]]
	var d = {
		"actors": ids.duplicate(),
		"door": null,
		"room": room,
		"method": "loot",
		"outside": anchor,
		"inside": anchor,
		"stacks": positions.duplicate(),
		"entries": positions.duplicate(),
		"angle": 0.0,
		"item": null,
		"thrower": null,
		"landing": null,
		"sync": null
	}
	var t = SCData.task(id, d)
	for i in guards:
		if i in ids:
			t.guards[i] = true
	assign_search(p, t)
	p.tasks[id] = t
	for i in ids:
		p.actor(i).queue.append(SCData.node(t.token, "task", {"task_id": id}))
	p.world.message(p.task_label(t) + " · 已下达")
	return ""
