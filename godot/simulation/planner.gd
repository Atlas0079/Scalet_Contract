class_name SCPlanner
extends RefCounted

const LABELS = {
	"move": "移动",
	"guard": "定点警戒",
	"face": "调整朝向",
	"attack": "指定攻击",
	"reload": "换弹",
	"bandage": "自行包扎",
	"throw": "投掷",
	"wait": "等待信号",
	"task": "房间行动",
	"move_face": "定向移动",
	"loot_search": "搜索物品",
	"loot_take": "到场拿取",
	"loot_drop": "放下物品",
	"loot_equip": "装备武器"
}
const STAGES = {
	"queued": "排队",
	"stack": "门外集结",
	"wait": "等待信号",
	"door": "操作门",
	"throw": "使用物品",
	"blast": "等待起爆",
	"enter": "依次进入",
	"search": "检查威胁",
	"blocked": "已挂起",
	"done": "完成",
	"loot": "搜索物资",
	"allocation": "等待物资分配"
}
var _world: WeakRef
var world:
	get:
		return _world.get_ref()
var tasks: Dictionary = {}
var next_id: int = 1
var release_requests: Dictionary = {}
var stalls: Dictionary = {}
var entrance_error: String = ""


func _init(w):
	_world = weakref(w)


func actor(id):
	return world.actor(id)


func position_cell(a):
	return (
		a.move_to
		if a.move_to != null
		else (a.occupied_cell if a.occupied_cell != null else SCData.cell_of(a.position))
	)


func origin(a, append: bool = false):
	var c = position_cell(a)
	if append:
		for n in a.queue:
			if n.cell != null and n.kind in ["move", "guard", "move_face"]:
				c = n.cell
			if tasks.has(n.task_id):
				c = tasks[n.task_id].draft.entries.get(a.id, c)
	return c


func path(a, goal, options: Dictionary = {}) -> Array:
	var g = world.grid
	var allowed = null
	if options.get("zone") != null:
		allowed = g.zones[options.zone].cells
	elif options.get("exclude") != null:
		allowed = g.zone_cells.duplicate()
		for c in g.zones[options.exclude].cells:
			allowed.erase(c)
	var start = options.get("start", position_cell(a))
	var known = world.perception.doors if options.get("known", true) and a.team == "red" else null
	return g.find_path(start, goal, allowed, known)


func releasing(a) -> Array:
	var tokens = []
	for n in a.queue:
		tokens.append(n.token)
		if tasks.has(n.task_id):
			tokens.append(tasks[n.task_id].token)
	return tokens


func micro_append(a, append: bool) -> bool:
	return append and not a.queue.any(func(n): return tasks.has(n.task_id))


func available(a, item: String, append: bool) -> int:
	return a.available(item, [] if append else releasing(a))


func item_error(a, item: String, kind: String, append: bool = false, cell = null) -> String:
	append = micro_append(a, append)
	if not a.alive:
		return "执行者死亡"
	if not SCData.catalog.items.has(item):
		return "未知物品"
	if kind == "reload":
		if a.weapon.ammo >= a.weapon.definition.magazine_size:
			return "弹匣已满"
		return "储备弹药耗尽" if a.weapon.reserve_ammo <= 0 else ""
	if available(a, item, append) < 1:
		return "物品不足（可能已预约）"
	if kind == "bandage" and a.treatment_part() == null:
		return "没有可治疗伤口"
	if kind == "throw" and cell != null:
		return throw_error(a, item, cell, origin(a, append))
	return ""


func throw_error(a, item: String, cell, from = null, room = null, opening_door = null) -> String:
	var g = world.grid
	if not g.walkable(cell):
		return "落点被家具或墙占用"
	if room == null and a.team == "red" and not world.perception.explored.has(cell):
		return "区域未探索"
	if room != null and g.zone_id(cell) != room:
		return "落点必须在目标房间"
	var use = SCData.use_for(item)
	var start = SCData.center(from) if from != null else a.position
	var end = SCData.center(cell)
	if start.distance_to(end) > use.range + 0.000001:
		return "超出 %s 格" % str(use.range)
	for pair in g.ray_features(start, end):
		var f = pair[1]
		if opening_door != null and f.interactive_id == opening_door:
			continue
		if f.blocks_projectile and f.height >= 2.0:
			return "被墙阻挡"
	return ""


func movement_targets(ids: Array, cell, append: bool = false) -> Array:
	var g = world.grid
	var units = []
	var occupied = {}
	var assigned = {}
	for id in ids:
		var a = actor(id)
		if a == null or not a.alive:
			return [{}, "先选择存活队员"]
		if a not in units:
			units.append(a)
	if units.is_empty():
		return [{}, "先选择存活队员"]
	if cell == null or not g.walkable(cell):
		return [{}, "目标不可通行"]
	for a in world.actors:
		if a.alive and a.id not in ids and a.occupied_cell != null:
			occupied[a.occupied_cell] = true
	units.sort_custom(func(a, b): return a.id < b.id)
	for a in units:
		var candidates = [cell]
		if units.size() > 1:
			candidates = g.zones[g.zone_id(cell)].cells.keys().filter(
				func(c): return Vector2(c).distance_to(Vector2(cell)) <= 2 and g.walkable(c)
			)
		var choices = []
		for c in candidates:
			if occupied.has(c):
				continue
			var route = path(a, c, {"start": origin(a, micro_append(a, append))})
			if not route.is_empty():
				choices.append(
					[Vector2(c).distance_squared_to(Vector2(cell)), g.path_cost(route), c.y, c.x, c]
				)
		choices.sort_custom(SCGrid.heap_less)
		if choices.is_empty():
			return [{}, "路径被占位或关闭的门阻断"]
		assigned[a.id] = choices[0][4]
		occupied[choices[0][4]] = true
	return [assigned, ""]


func submit(ids: Array, kind: String, options: Dictionary = {}) -> String:
	var units = []
	var appends = {}
	var append = options.get("append", false)
	var cell = options.get("cell")
	var sync = options.get("sync")
	for id in ids:
		var a = actor(id)
		if a == null or not a.alive:
			return "先选择存活队员"
		if a not in units:
			units.append(a)
			appends[id] = micro_append(a, append)
	if units.is_empty():
		return "先选择存活队员"
	if kind in ["loot_search", "loot_drop", "loot_equip"]:
		if units.size() != 1:
			return "请选择一名执行者"
		var a = units[0]
		var error = ""
		if kind == "loot_search":
			error = world.loot.search_error(a, options.get("object_id"), origin(a, appends[a.id]))
		else:
			error = world.loot.action_error(
				a,
				"drop_item" if kind == "loot_drop" else "equip_item",
				"",
				null,
				options.get("cargo_id")
			)
		if not error.is_empty():
			return error
	for a in units:
		if appends[a.id] and a.queue.size() >= 8:
			return "队列已满（最多 8 项）"
		if sync != null and has_sync(a, appends[a.id]):
			return "该队员已有同步等待"
	if kind == "wait" and sync not in ["A", "B"]:
		return "请选择同步 A 或 B"
	var assigned = {}
	if kind in ["move", "guard", "move_face"]:
		var result = movement_targets(ids, cell, append)
		if not result[1].is_empty():
			return result[1]
		assigned = result[0]
	var chosen = options.get(
		"item", {"reload": "rifle", "bandage": "bandage", "throw": "flashbang"}.get(kind)
	)
	for a in units:
		if kind in ["reload", "bandage", "throw"]:
			var error = item_error(a, chosen, kind, appends[a.id], cell)
			if not error.is_empty():
				return error
		if kind == "attack" and not world.perception.player_visible.has(options.get("target_id")):
			return "目标已失去视野"
	cancel_related(ids)
	for a in units:
		if not appends[a.id]:
			cancel_actor(a)
		elif not a.queue.is_empty() and a.queue.back().kind == "guard":
			a.queue.back().kind = "move_face"
		var token = "node:%d" % next_id
		next_id += 1
		var values = options.duplicate()
		values.erase("append")
		values.cell = assigned.get(a.id, cell)
		values.item = chosen
		var n = SCData.node(token, kind, values)
		if chosen != null and kind != "reload":
			a.reserve(token, chosen)
		a.queue.append(n)
		a.blocked_reason = ""
	world.message("%s：%s" % [str(ids), LABELS.get(kind, kind)])
	return ""


func has_sync(a, append: bool) -> bool:
	if not append:
		return false
	for n in a.queue:
		if n.sync != null or tasks.has(n.task_id) and tasks[n.task_id].draft.sync != null:
			return true
	return false


func related_tasks(ids: Array) -> Array:
	var found = {}
	for id in ids:
		if actor(id) == null:
			continue
		for n in actor(id).queue:
			if tasks.has(n.task_id):
				found[n.task_id] = true
	var result = found.keys()
	result.sort()
	return result


func micro_controls_motion(a) -> bool:
	if not a.alive or a.team != "red" or a.queue.is_empty() or not a.blocked_reason.is_empty():
		return false
	var n = a.queue[0]
	if n.task_id != null or n.status == "blocked":
		return false
	return (
		n.kind in ["move", "move_face", "face"]
		or n.kind == "guard" and not n.started
		or n.kind in ["loot_search", "loot_take"] and not n.started and n.status != "allocation"
	)


func takeover_text(ids: Array) -> String:
	var names = []
	var members = {}
	for id in related_tasks(ids):
		names.append(task_label(tasks[id]))
		for i in tasks[id].draft.actors:
			members[i] = true
	return "" if names.is_empty() else "将取消 %s · 影响 %s 号" % [" / ".join(names), str(members.keys())]


func cancel_related(ids: Array):
	for id in related_tasks(ids):
		cancel_task(id)


func suspend_task(task: Dictionary, reason: String):
	if task.phase != "blocked":
		task.resume_phase = task.phase
	task.phase = "blocked"
	task.reason = reason
	task.ready = false
	task.action_started = false
	if task.draft.sync != null:
		task.released = false
		release_requests.erase(task.draft.sync)
	var tokens = [task.token]
	for job in task.jobs.values():
		tokens.append(job.token)
	for id in task.draft.actors:
		var a = actor(id)
		if not a.queue.is_empty() and a.queue[0].task_id == task.id:
			a.clear_movement()
		if a.current_action != null and a.current_action.owner_token in tokens:
			a.current_action = null
			if a.alive:
				a.mode = "standing"
		if task.jobs.has(id):
			task.jobs[id].started = false


func suspend_actor(a, reason: String):
	a.clear_movement()
	if not a.queue.is_empty():
		var n = a.queue[0]
		if tasks.has(n.task_id):
			suspend_task(tasks[n.task_id], reason)
		else:
			n.status = "blocked"
			n.reason = reason
			n.started = false
			a.blocked_reason = reason
	if a.current_action != null:
		a.current_action = null
		if a.alive:
			a.mode = "standing"


func cancel_actor(a):
	var affected = related_tasks([a.id])
	for n in a.queue:
		a.reservations.erase(n.token)
		world.loot.release(n.token)
	a.queue.clear()
	a.current_action = null
	if a.mode == "acting":
		a.mode = "standing"
	a.clear_movement()
	a.blocked_reason = ""
	a.guard_angle = a.facing
	a.guard_explicit = false
	for id in affected:
		if not tasks.has(id):
			continue
		var t = tasks[id]
		var jobs = t.pickups.get(a.id, []).duplicate()
		if t.jobs.has(a.id):
			jobs.append(t.jobs[a.id])
		t.jobs.erase(a.id)
		t.pickups.erase(a.id)
		for job in jobs:
			world.loot.release(job.token)
			if job.kind == "loot_search":
				t.seen_loot.erase(job.object_id)
		var index = t.draft.actors.find(a.id)
		if index >= 0:
			if index < t.enter_index:
				t.enter_index -= 1
			t.draft.actors.erase(a.id)
		t.entered.erase(a.id)
		t.draft.stacks.erase(a.id)
		t.draft.entries.erase(a.id)
		a.reservations.erase(t.token)
		if t.draft.actors.is_empty():
			tasks.erase(id)
		else:
			if t.draft.method == "loot" and t.draft.actors.any(func(i): return not t.guards.has(i)):
				assign_search(t)
			suspend_task(t, "成员阵亡，请继续或取消")


func cancel_task(id):
	if not tasks.has(id):
		return
	var task = tasks[id]
	tasks.erase(id)
	world.completed.erase(task.token)
	for job in task.jobs.values():
		world.loot.release(job.token)
	for nodes in task.pickups.values():
		for n in nodes:
			world.loot.release(n.token)
	for a in world.actors:
		var index = -1
		for j in range(a.queue.size()):
			if a.queue[j].task_id == id:
				index = j
				break
		a.reservations.erase(task.token)
		a.queue = a.queue.filter(func(n): return n.task_id != id)
		if index == 0:
			a.current_action = null
			if a.mode == "acting":
				a.mode = "standing"
			a.clear_movement()
			a.blocked_reason = ""
			a.guard_angle = a.facing
			a.guard_explicit = false
			if not a.queue.is_empty():
				suspend_actor(a, "前置宏观已取消，请继续或重下")
		elif index >= 0 and index < a.queue.size():
			var n = a.queue[index]
			if tasks.has(n.task_id):
				suspend_task(tasks[n.task_id], "前置宏观已取消，请继续或重下")
			else:
				n.status = "blocked"
				n.reason = "前置宏观已取消，请继续或重下"
	world.message("行动 %d 已取消" % id)


func stop(ids: Array):
	cancel_related(ids)
	for id in ids:
		if actor(id) != null:
			cancel_actor(actor(id))


func delete_node(a, index: int):
	if index < 0 or index >= a.queue.size():
		return
	var n = a.queue[index]
	if tasks.has(n.task_id):
		cancel_task(n.task_id)
		return
	a.reservations.erase(n.token)
	world.loot.release(n.token)
	a.queue.remove_at(index)
	if index == 0:
		a.current_action = null
		if a.mode == "acting":
			a.mode = "standing"
		a.clear_movement()
		a.blocked_reason = ""


func retry_node(a, n: Dictionary) -> String:
	if not a.alive:
		return "执行者死亡"
	if a.stunned > 0 or a.under_fire_timer > world.time:
		return "等待震撼或受袭搜索结束"
	if n.cell != null and n.kind in ["move", "move_face", "guard"] and path(a, n.cell).is_empty():
		return "路径仍不可达"
	if n.kind in ["throw", "bandage"] and not world.completed.has(n.token):
		if not a.reservations.has(n.token):
			return "物品预约失效，请重新下达"
		if n.kind == "throw":
			var error = throw_error(a, n.item, n.cell)
			if not error.is_empty():
				return error
		elif a.treatment_part() == null:
			return "没有可治疗伤口"
	n.status = "queued"
	n.reason = ""
	n.started = false
	a.blocked_reason = ""
	stalls.erase(a.id)
	return ""


func drive(a, cell, dt: float, angle = null, zone = null) -> bool:
	if a.stunned > 0 or a.current_action != null:
		return false
	if world.has_threat(a) and not micro_controls_motion(a):
		a.clear_movement()
		stalls.erase(a.id)
		return false
	if a.mode == "standing" and a.occupied_cell == cell:
		stalls.erase(a.id)
		a.clear_movement()
		if angle != null:
			a.guard_angle = angle
			a.guard_explicit = true
			return absf(angle_difference(a.facing, angle)) <= 0.087267
		return true
	var state = stalls.get(a.id, [a.position, 0.0, false])
	var elapsed = state[1] + dt if state[0].distance_to(a.position) < 0.000001 else 0.0
	if elapsed >= 5.0:
		a.blocked_reason = "5 秒无移动进展"
		a.clear_movement()
		return false
	if elapsed >= 2.0 and not state[2]:
		a.clear_movement()
		state[2] = true
	stalls[a.id] = [a.position, elapsed, state[2]]
	if a.target_cell != cell or a.route.is_empty() and a.mode == "standing":
		var route = path(a, cell, {"zone": zone} if zone != null else {})
		if not route.is_empty():
			a.route = route
			a.target_cell = cell
			a.reserved_cell = cell
		else:
			a.blocked_reason = "路径暂不可达"
	return false


func sync_status(label: String) -> Array:
	var result = []
	for task in tasks.values():
		if task.draft.sync == label and not task.released:
			result.append([task_label(task), task.phase == "wait" and task.ready])
	for a in world.actors:
		for n in a.queue:
			if n.kind == "wait" and n.sync == label:
				result.append(
					[
						a.actor_name,
						n == a.queue[0] and n.status == "waiting" and not world.has_threat(a)
					]
				)
	return result


func release(label: String) -> String:
	var entries = sync_status(label)
	if entries.is_empty() or not entries.all(func(e): return e[1]):
		return "尚未全员就绪"
	release_requests[label] = true
	return ""


func task_label(t: Dictionary) -> String:
	var d = t.draft
	var label = (
		{
			"loot": "搜索物资",
			"direct": "直接突入",
			"breach": "破门突入",
			"flash": "闪光突入",
			"stack": "门外集结",
			"guarddoor": "守住门口",
			"open": "开门",
			"kick": "踹开"
		}
		. get(d.method, d.method)
	)
	if d.method in ["direct", "breach", "flash"]:
		label += "并就位" if d.after_entry == "hold" else "并检查威胁"
	return label + " · " + world.grid.zones[d.room].label


func tick(dt: float):
	for label in release_requests.keys():
		var entries = sync_status(label)
		if not entries.is_empty() and entries.all(func(e): return e[1]):
			for t in tasks.values():
				if t.draft.sync == label and not t.released:
					t.released = true
			for a in world.actors:
				if (
					not a.queue.is_empty()
					and a.queue[0].kind == "wait"
					and a.queue[0].sync == label
				):
					a.queue.pop_front()
			world.message("同步 %s · 已放行" % label)
		else:
			world.message("同步 %s · 就绪状态变化" % label)
		release_requests.erase(label)
	for t in tasks.values():
		if tasks.has(t.id):
			SCRoomTasks.tick(self, t, dt)
	for a in world.actors:
		if not a.alive or a.queue.is_empty():
			continue
		var n = a.queue[0]
		if n.kind == "task" or n.status == "blocked":
			continue
		if not a.blocked_reason.is_empty():
			n.status = "blocked"
			n.reason = a.blocked_reason
			continue
		if n.status != "allocation":
			n.status = "running"
		var done = false
		if n.kind.begins_with("loot_"):
			done = world.loot.tick_node(a, n, dt)
		elif n.kind in ["move", "guard", "move_face"]:
			a.guard_explicit = n.angle != null
			var arrived = drive(a, n.cell, dt, n.angle)
			if arrived and n.kind == "guard":
				n.started = true
			done = arrived and n.kind != "guard"
		elif n.kind == "face":
			if a.mode == "standing" and a.stunned <= 0 and a.current_action == null:
				a.guard_angle = n.angle
				a.guard_explicit = true
				done = absf(angle_difference(a.facing, n.angle)) <= 0.087267
		elif n.kind == "attack":
			a.target_id = n.target_id
			n.elapsed = 0.0 if a.visible.has(n.target_id) else n.elapsed + dt
			var target = actor(n.target_id)
			done = (
				n.elapsed >= 2.0
				or target != null and not target.alive and a.visible.has(n.target_id)
			)
		elif n.kind == "wait":
			a.clear_movement()
			if (
				a.mode == "standing"
				and a.current_action == null
				and a.stunned <= 0
				and not world.has_threat(a)
			):
				n.status = "waiting"
		elif n.kind in ["reload", "bandage", "throw"]:
			if world.completed.has(n.token):
				world.completed.erase(n.token)
				done = true
			elif (
				not n.started
				and a.mode == "standing"
				and a.stunned <= 0
				and a.current_action == null
			):
				if n.kind == "reload" and a.weapon.ammo >= a.weapon.definition.magazine_size:
					done = true
				else:
					var error = world.start_action(
						a,
						{"reload": "reload", "bandage": "bandage", "throw": "throw_grenade"}[
							n.kind
						],
						SCData.use_for(n.item).duration,
						n.token,
						{"item": n.item, "cell": n.cell}
					)
					if not error.is_empty():
						n.status = "blocked"
						n.reason = error
					else:
						n.started = true
		if done:
			a.reservations.erase(n.token)
			world.loot.release(n.token)
			if not a.queue.is_empty() and a.queue[0].token == n.token:
				a.queue.pop_front()
			a.blocked_reason = ""


func preview_task(
	ids: Array, door: String, room: String, method: String, options: Dictionary = {}
) -> Array:
	return SCRoomTasks.preview(self, ids, door, room, method, options)


func choose_entrance(
	ids: Array, door = null, room = null, method: String = "direct", append: bool = false
):
	return SCRoomTasks.choose(self, ids, door, room, method, append)


func submit_task(d: Dictionary, append: bool = false) -> String:
	return SCRoomTasks.submit(self, d, append)


func retry_task(id: int) -> String:
	return SCRoomTasks.retry(self, id)


func assign_search(t: Dictionary):
	SCRoomTasks.assign_search(self, t)


func room_angle(room: String, c: Vector2i) -> float:
	return SCRoomTasks.room_angle(room, c)


func finish_task(t: Dictionary):
	SCRoomTasks.finish(self, t)


func resolve_slot(t: Dictionary, a, c, assigned: Array, zone = null):
	return SCRoomTasks.resolve_slot(self, t, a, c, assigned, zone)


func submit_loot_task(ids: Array, room: String, guards: Array = []) -> String:
	return SCRoomTasks.submit_loot(self, ids, room, guards)
