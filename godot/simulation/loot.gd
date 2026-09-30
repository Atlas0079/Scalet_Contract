class_name SCLoot
extends RefCounted

var _world: WeakRef
var world:
	get:
		return _world.get_ref()
var objects: Dictionary = {}
var reservations: Dictionary = {}
var searchers: Dictionary = {}
var results: Dictionary = {}
var notifications: Array = []
var counter: int = 0


func _init(w):
	_world = weakref(w)
	for a in w.actors:
		a.equipped_id = "weapon:%d" % a.id


func item(kind: String, quantity: int = 1, ammo: int = 30) -> Dictionary:
	counter += 1
	return {
		"id": "item:%d" % counter,
		"kind": kind,
		"quantity": quantity,
		"weapon": SCData.weapon(kind, ammo, 0) if SCData.catalog.weapons.has(kind) else null
	}


static func item_name(i: Dictionary) -> String:
	var label = SCData.catalog.loot_kinds[i.kind][0]
	return label + (" · 弹匣 %d" % i.weapon.ammo if i.weapon != null else "")


static func item_weight(i: Dictionary) -> float:
	return (
		SCData.catalog.loot_kinds[i.kind][1] * i.quantity
		+ (i.weapon.ammunition.mass * (i.weapon.ammo + i.weapon.reserve_ammo) if i.weapon != null else 0.0)
	)


func add(
	id: String,
	label: String,
	kind: String,
	cell: Vector2i,
	items: Array = [],
	discovered: bool = false
) -> Dictionary:
	var obj = {
		"id": id,
		"name": label,
		"kind": kind,
		"cell": cell,
		"items": {},
		"discovered": discovered,
		"visible": false,
		"opened": false,
		"searched": kind == "ground",
		"known": {},
		"seen_at": 0.0
	}
	for i in items:
		obj.items[i.id] = i
	objects[id] = obj
	if discovered and obj.searched:
		remember(obj)
	return obj


func remember(obj: Dictionary):
	obj.known = obj.items.duplicate(true)
	obj.seen_at = world.time


func refresh():
	for obj in objects.values():
		var center = SCData.center(obj.cell)
		var points = [center]
		if obj.kind == "container":
			for delta in SCGrid.DIRS.values():
				points.append(center + Vector2(delta) * 0.501)
		obj.visible = false
		for a in world.actors:
			if not a.alive or a.team != "red":
				continue
			if points.any(func(point): return world.perception.point_visible(world, a, point)):
				obj.visible = true
				break
		if obj.visible:
			obj.discovered = true
			if obj.searched:
				remember(obj)


func weight(a) -> float:
	var result = a.weapon.definition.item.mass + a.weapon.ammunition.mass * (a.weapon.ammo + a.weapon.reserve_ammo)
	for kind in a.quantities:
		if SCData.catalog.loot_kinds.has(kind):
			result += SCData.catalog.loot_kinds[kind][1] * a.quantities[kind]
	for i in a.cargo.values():
		result += item_weight(i)
	return result


func reserved_weight(id: int, excluding: Array = []) -> float:
	var result = 0.0
	for token in reservations:
		if token not in excluding and reservations[token].actor_id == id:
			result += reservations[token].weight
	return result


func interaction_cells(obj: Dictionary) -> Array:
	var g = world.grid
	var cells = []
	if obj.kind != "container" and g.walkable(obj.cell):
		cells.append(obj.cell)
	for delta in SCGrid.DIRS.values():
		var c = obj.cell + delta
		var edge = g.edge_between(c, obj.cell)
		if g.walkable(c) and (edge == null or not edge.blocks_movement):
			cells.append(c)
	return cells


func approach(a, obj: Dictionary, start = null):
	var occupied = SCMovement.occupied(a, world.actors)
	var reserved = SCMovement.reserved(a, world.actors)
	var choices = []
	for c in interaction_cells(obj):
		if occupied.has(c) or reserved.has(c):
			continue
		var route = world.planner.path(a, c, {"start": start} if start != null else {})
		if not route.is_empty():
			choices.append([world.grid.path_cost(route), c.y, c.x, 0, c])
	choices.sort_custom(SCGrid.heap_less)
	return null if choices.is_empty() else choices[0][4]


func at_object(a, obj: Dictionary) -> bool:
	return a.mode in ["standing", "acting"] and a.occupied_cell in interaction_cells(obj)


func search_error(a, id, start = null) -> String:
	if not a.alive:
		return "执行者已阵亡"
	var obj = objects.get(id)
	if obj == null or not obj.discovered:
		return "尚未发现此对象"
	if approach(a, obj, start) == null:
		return "没有可达的交互位置（不能隔墙操作）"
	return ""


func open_result(obj: Dictionary, a = null, n = null):
	if not results.has(obj.id):
		results[obj.id] = {
			"object_id": obj.id,
			"actor_id": a.id if a != null else null,
			"task_id": n.task_id if n != null else null,
			"token": n.token if n != null else "",
			"completed_at": world.time
		}
	if obj.id not in notifications:
		notifications.append(obj.id)
		notifications.sort_custom(
			func(a, b):
				return (
					results[a].completed_at < results[b].completed_at
					or results[a].completed_at == results[b].completed_at and a < b
				)
		)
	world.pause_requested = true


func release(token: String):
	reservations.erase(token)
	for id in searchers.keys():
		if searchers[id] == token:
			searchers.erase(id)
	for id in results.keys():
		if results[id].token == token:
			results.erase(id)
	notifications = notifications.filter(func(id): return results.has(id))


func take_error(a, token: String, onsite: bool = false) -> String:
	var r = reservations.get(token)
	if r == null or r.actor_id != a.id:
		return "拿取预约已失效"
	var obj = objects.get(r.object_id)
	if obj == null or not obj.items.has(r.item_id):
		return "来源物品已不存在"
	if not a.alive:
		return "执行者已阵亡"
	if onsite and not at_object(a, obj):
		return "必须到达物品的交互位置"
	if weight(a) + item_weight(obj.items[r.item_id]) > a.capacity + 0.000000001:
		return "携带容量不足"
	return ""


func pickup_reservation(id: String, item_id: String) -> Array:
	for token in reservations:
		var r = reservations[token]
		if r.object_id == id and r.item_id == item_id:
			return [token, r]
	return [null, null]


func pickup_task(id: String, item_id: String):
	var old = pickup_reservation(id, item_id)
	if old[0] != null:
		for t in world.planner.tasks.values():
			if t.jobs.values().any(func(n): return n.token == old[0]):
				return t
			for nodes in t.pickups.values():
				if nodes.any(func(n): return n.token == old[0]):
					return t
	var result = results.get(id)
	var task = world.planner.tasks.get(result.task_id) if result != null else null
	return task if task != null and task.draft.method == "loot" else null


func cancel_pickup(token: String):
	var p = world.planner
	for a in world.actors:
		for index in range(a.queue.size()):
			if a.queue[index].token == token:
				p.delete_node(a, index)
				break
	for t in p.tasks.values():
		for id in t.jobs.keys():
			if t.jobs[id].token != token:
				continue
			t.jobs.erase(id)
			var a = world.actor(id)
			if not a.queue.is_empty() and a.queue[0].task_id == t.id:
				if a.current_action != null and a.current_action.owner_token == token:
					a.current_action = null
					if a.mode == "acting":
						a.mode = "standing"
				a.clear_movement()
				a.blocked_reason = ""
				p.stalls.erase(id)
		for id in t.pickups:
			t.pickups[id] = t.pickups[id].filter(func(n): return n.token != token)
	release(token)
	world.completed.erase(token)


func allocation_error(id: String, assignments: Dictionary) -> String:
	var obj = objects.get(id)
	if obj == null or not obj.discovered or not obj.searched:
		return "物品尚未搜索"
	var weights = {}
	var counts = {}
	var outgoing = []
	for item_id in assignments:
		var actor_id = assignments[item_id]
		if actor_id == null:
			continue
		var a = world.actor(actor_id)
		var i = obj.known.get(item_id)
		if a == null or not a.alive or a.team != "red":
			return "请选择存活的在场队员"
		if i == null:
			return "物品记录不存在"
		if not obj.items.has(item_id):
			return "物品已离开来源，不能改派"
		var old = pickup_reservation(id, item_id)
		if old[1] != null and old[1].actor_id == actor_id:
			continue
		if old[0] != null:
			outgoing.append(old[0])
		var error = search_error(a, id)
		if not error.is_empty():
			return a.actor_name + "：" + error
		weights[actor_id] = weights.get(actor_id, 0.0) + item_weight(i)
		counts[actor_id] = counts.get(actor_id, 0) + 1
	for actor_id in weights:
		var a = world.actor(actor_id)
		var excess = (
			weight(a) + reserved_weight(actor_id, outgoing) + weights[actor_id] - a.capacity
		)
		if excess > 0.000000001:
			return (
				"%s 超出 %.0f kg 携带上限，缺少 %.2f kg 空间 · 先完成放下再安排拿取；整堆不能拆分"
				% [a.actor_name, a.capacity, excess]
			)
		if counts[actor_id] > 8:
			return a.actor_name + " 一次最多安排 8 次拿取"
		var internal = true
		for item_id in assignments:
			if assignments[item_id] != actor_id:
				continue
			var t = pickup_task(id, item_id)
			if t == null or actor_id not in t.draft.actors:
				internal = false
		var remaining = a.queue.filter(func(n): return n.token not in outgoing)
		if (
			not internal
			and not remaining.is_empty()
			and remaining.all(
				func(n): return n.kind == "loot_take" and n.object_id == id and n.task_id == null
			)
		):
			if remaining.size() + counts[actor_id] > 8:
				return a.actor_name + " 最多安排 8 次拿取"
	return ""


func allocate(id: String, assignments: Dictionary, finish: bool = true) -> String:
	var error = allocation_error(id, assignments)
	if not error.is_empty():
		return error
	var p = world.planner
	var obj = objects[id]
	var source_result = results.get(id)
	var changes = {}
	var external = {}
	for item_id in assignments:
		var actor_id = assignments[item_id]
		if actor_id == null:
			continue
		var old = pickup_reservation(id, item_id)
		if old[1] != null and old[1].actor_id == actor_id:
			continue
		var t = pickup_task(id, item_id)
		if t != null and actor_id not in t.draft.actors:
			t = null
		changes[item_id] = [actor_id, old[0], t]
		if t == null:
			external[actor_id] = true
	var replacing = []
	for actor_id in external:
		var a = world.actor(actor_id)
		if (
			a.queue.is_empty()
			or not a.queue.all(
				func(n): return n.kind == "loot_take" and n.object_id == id and n.task_id == null
			)
		):
			replacing.append(actor_id)
	for change in changes.values():
		if change[1] != null:
			cancel_pickup(change[1])
	p.cancel_related(replacing)
	for actor_id in replacing:
		p.cancel_actor(world.actor(actor_id))
	for item_id in changes:
		var change = changes[item_id]
		var actor_id = change[0]
		var t = change[2]
		var token = "node:%d" % p.next_id
		p.next_id += 1
		var task_id = t.id if t != null and p.tasks.has(t.id) else null
		var n = SCData.node(
			token, "loot_take", {"object_id": id, "cargo_id": item_id, "task_id": task_id}
		)
		reservations[token] = {
			"object_id": id,
			"item_id": item_id,
			"actor_id": actor_id,
			"weight": item_weight(obj.known[item_id])
		}
		if task_id != null:
			if not t.pickups.has(actor_id):
				t.pickups[actor_id] = []
			t.pickups[actor_id].append(n)
		else:
			world.actor(actor_id).queue.append(n)
	if finish:
		results.erase(id)
	elif source_result != null:
		results[id] = source_result
	notifications.erase(id)
	if not changes.is_empty():
		world.message("%s：已安排／改派 %d 件 · 到场后拿取" % [obj.name, changes.size()])
	return ""


func action_error(a, kind: String, token: String, object_id = null, cargo_id = null) -> String:
	var obj = objects.get(object_id)
	if kind == "search_loot":
		if obj == null or not at_object(a, obj):
			return "必须到达搜索对象旁"
		if searchers.get(object_id) != null and searchers[object_id] != token:
			return "另一名队员正在搜索此对象"
	elif kind == "transfer_item":
		return take_error(a, token, true)
	elif kind in ["drop_item", "equip_item"]:
		if not carried(a).has(cargo_id):
			return "物品已不在此人身上"
		if kind == "equip_item" and (not a.cargo.has(cargo_id) or a.cargo[cargo_id].weapon == null):
			return "只能装备携带中的武器"
	return ""


func carried(a) -> Dictionary:
	var items = a.cargo.duplicate()
	for kind in ["flashbang", "bandage"]:
		var count = a.available(kind)
		if count > 0:
			items["supply:" + kind] = {
				"id": "supply:" + kind, "kind": kind, "quantity": count, "weapon": null
			}
	if a.weapon.reserve_ammo > 0:
		var ammunition: String = a.weapon.definition.ammunition
		items["supply:" + ammunition] = {
			"id": "supply:" + ammunition,
			"kind": ammunition,
			"quantity": int(a.weapon.reserve_ammo),
			"weapon": null
		}
	return items


func remove_carried(a, id: String) -> Dictionary:
	if a.cargo.has(id):
		var i = a.cargo[id]
		a.cargo.erase(id)
		return i
	var kind = id.get_slice(":", 1)
	var count = 0
	if kind == a.weapon.definition.ammunition:
		count = int(a.weapon.reserve_ammo)
		a.weapon.reserve_ammo = 0
	else:
		count = a.available(kind)
		a.quantities[kind] -= count
	return item(kind, count)


func complete_action(a, action: Dictionary) -> String:
	var error = action_error(a, action.type, action.owner_token, action.object_id, action.cargo_id)
	if not error.is_empty():
		return error
	var obj = objects.get(action.object_id)
	if action.type == "search_loot":
		obj.searched = true
		remember(obj)
		searchers.erase(obj.id)
	elif action.type == "transfer_item":
		var i = obj.items[action.cargo_id]
		obj.items.erase(action.cargo_id)
		if i.kind in ["flashbang", "bandage"]:
			a.quantities[i.kind] = a.quantities.get(i.kind, 0) + i.quantity
		elif i.kind == a.weapon.definition.ammunition:
			a.weapon.reserve_ammo += i.quantity
		else:
			a.cargo[i.id] = i
		reservations.erase(action.owner_token)
		remember(obj)
		world.message("%s 已拿取 %s ×%d" % [a.actor_name, item_name(i), i.quantity])
		if obj.kind == "ground" and obj.items.is_empty():
			objects.erase(obj.id)
	elif action.type == "drop_item":
		var i = remove_carried(a, action.cargo_id)
		var pile = null
		for o in objects.values():
			if o.kind == "ground" and o.cell == a.occupied_cell:
				pile = o
				break
		if pile == null:
			counter += 1
			pile = add("ground:%d" % counter, "地面物品", "ground", a.occupied_cell, [], true)
		pile.items[i.id] = i
		remember(pile)
		world.message(a.actor_name + " 已放下 " + item_name(i))
	elif action.type == "equip_item":
		var i = a.cargo[action.cargo_id]
		a.cargo.erase(action.cargo_id)
		var old = {
			"id": a.equipped_id,
			"kind": a.weapon.definition.item.id,
			"quantity": 1,
			"weapon": a.weapon
		}
		var reserve = 0
		if old.weapon.definition.ammunition == i.weapon.definition.ammunition:
			reserve = old.weapon.reserve_ammo
			old.weapon.reserve_ammo = 0
		a.weapon = i.weapon
		a.weapon.reserve_ammo += reserve
		a.equipped_id = i.id
		a.cargo[old.id] = old
		world.message(a.actor_name + " 已装备 " + item_name(i))
	return ""


func tick_node(a, n: Dictionary, dt: float) -> bool:
	var w = world
	var p = w.planner
	var obj = objects.get(n.object_id)
	if n.kind == "loot_search" and n.status == "allocation":
		return not results.has(n.object_id)
	if w.completed.has(n.token):
		w.completed.erase(n.token)
		if n.kind == "loot_search" and obj != null:
			n.status = "allocation"
			open_result(obj, a, n)
			return false
		return true
	if n.started or a.current_action != null or a.stunned > 0:
		return false
	var kind = ""
	if n.kind in ["loot_drop", "loot_equip"]:
		if a.mode != "standing":
			return false
		kind = "drop_item" if n.kind == "loot_drop" else "equip_item"
	else:
		if obj == null:
			a.blocked_reason = "目标物品已不存在"
			return false
		if n.kind == "loot_search" and obj.searched:
			n.status = "allocation"
			open_result(obj, a, n)
			return false
		if (
			n.kind == "loot_search"
			and searchers.get(obj.id) != null
			and searchers[obj.id] != n.token
		):
			n.reason = "等待另一名搜索者"
			return false
		var target = a.occupied_cell if at_object(a, obj) else approach(a, obj)
		if target == null:
			a.blocked_reason = "没有可达且空闲的交互位置"
			return false
		n.cell = target
		if not p.drive(a, target, dt):
			return false
		kind = "search_loot" if n.kind == "loot_search" else "transfer_item"
	var duration = (
		(2.0 if obj != null and obj.kind == "corpse" else 3.0) if kind == "search_loot" else 0.6
	)
	var error = w.start_action(
		a, kind, duration, n.token, {"object_id": n.object_id, "cargo_id": n.cargo_id}
	)
	if not error.is_empty():
		a.blocked_reason = error
	else:
		n.started = true
		if kind == "search_loot":
			obj.opened = true
			searchers[obj.id] = n.token
	return false


func tick_task(t: Dictionary, dt: float):
	var w = world
	var p = w.planner
	var units = []
	if t.phase == "blocked":
		return
	for id in t.draft.actors:
		var a = w.actor(id)
		if a.queue.is_empty() or a.queue[0].task_id != t.id:
			return
		if not a.blocked_reason.is_empty():
			p.suspend_task(t, a.blocked_reason)
			return
		units.append(a)
	t.phase = "loot"
	var claimed = {}
	for other in p.tasks.values():
		for job in other.jobs.values():
			claimed[job.object_id] = true
	for a in units:
		var job = t.jobs.get(a.id)
		if job != null:
			if job.status != "blocked" and tick_node(a, job, dt):
				release(job.token)
				t.jobs.erase(a.id)
			continue
		var pickups = t.pickups.get(a.id, [])
		if not pickups.is_empty():
			t.jobs[a.id] = pickups.pop_front()
			continue
		if t.guards.has(a.id):
			continue
		var choices = []
		for obj in objects.values():
			if (
				not obj.discovered
				or t.seen_loot.has(obj.id)
				or claimed.has(obj.id)
				or w.grid.zone_id(obj.cell) != t.draft.room
			):
				continue
			if obj.searched and obj.known.is_empty():
				continue
			var c = approach(a, obj)
			if c != null:
				choices.append([w.grid.path_cost(p.path(a, c)), obj.id])
		choices.sort_custom(func(a, b): return a[0] < b[0] or a[0] == b[0] and a[1] < b[1])
		if not choices.is_empty():
			var id = choices[0][1]
			var token = "node:%d" % p.next_id
			p.next_id += 1
			t.jobs[a.id] = SCData.node(token, "loot_search", {"object_id": id, "task_id": t.id})
			t.seen_loot[id] = true
			claimed[id] = true
			continue
		var points = t.searches.get(a.id, [])
		if (
			not points.is_empty()
			and p.drive(a, points[0], dt, p.room_angle(t.draft.room, points[0]), t.draft.room)
		):
			t.observations[a.id] = t.observations.get(a.id, 0.0) + dt
			if t.observations[a.id] >= 0.4:
				points.pop_front()
				t.observations[a.id] = 0.0
	if t.jobs.values().any(func(job): return job.status == "allocation"):
		t.phase = "allocation"
	if (
		t.jobs.is_empty()
		and t.pickups.values().all(func(nodes): return nodes.is_empty())
		and t.searches.values().all(func(points): return points.is_empty())
	):
		t.loot_idle += dt
		if t.loot_idle >= 0.5:
			p.finish_task(t)
	else:
		t.loot_idle = 0.0


func corpse(a):
	var id = "corpse:%d" % a.id
	if objects.has(id):
		return
	var g = world.grid
	var anchor = a.death_anchor if a.death_anchor != null else SCData.cell_of(a.position)
	if not g.walkable(anchor):
		var cells = g.zone_cells.keys().filter(func(c): return g.walkable(c))
		cells.sort_custom(
			func(c, d):
				var dc = SCData.center(c).distance_to(a.position)
				var dd = SCData.center(d).distance_to(a.position)
				return dc < dd or dc == dd and SCData.cell_less(c, d)
		)
		anchor = cells[0]
	var occupied = {}
	for obj in objects.values():
		if obj.kind == "corpse":
			occupied[obj.cell] = true
	var frontier = []
	var distances = {anchor: 0.0}
	var choices = []
	SCGrid.heap_push(frontier, [0.0, anchor.y, anchor.x, 0, anchor])
	while not frontier.is_empty():
		var entry = SCGrid.heap_pop(frontier)
		var c = entry[4]
		var cost = entry[0]
		if cost > distances[c] + 0.000000001:
			continue
		if not occupied.has(c):
			choices.append(entry)
		for next in g.neighbors(c):
			var distance = cost + Vector2(c).distance_to(Vector2(next))
			if distance <= 2.0 + 0.000000001 and distance < distances.get(next, INF) - 0.000000001:
				distances[next] = distance
				SCGrid.heap_push(frontier, [distance, next.y, next.x, 0, next])
	choices.sort_custom(SCGrid.heap_less)
	var cell = anchor if choices.is_empty() else choices[0][4]
	var items = a.cargo.values()
	a.cargo.clear()
	var gun = a.weapon
	var reserve = int(gun.reserve_ammo)
	gun.reserve_ammo = 0
	items.append(
		{"id": a.equipped_id, "kind": gun.definition.item.id, "quantity": 1, "weapon": gun}
	)
	a.equipped_id = ""
	if reserve > 0:
		items.append(item(gun.definition.ammunition, reserve))
	for kind in a.quantities:
		if a.quantities[kind] > 0:
			items.append(item(kind, a.quantities[kind]))
	a.quantities.clear()
	a.reservations.clear()
	a.weapon = SCData.weapon(gun.definition.item.id, 0, 0)
	a.position = SCData.center(cell)
	add(id, a.actor_name + "的尸体", "corpse", cell, items, a.team == "red")
	g.terrain_speed[cell] = 0.6
	g.revision += 1
	g.path_cache.clear()
