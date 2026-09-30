class_name SCGrid
extends RefCounted

const DIRS = {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const OPPOSITE = {"N": "S", "S": "N", "E": "W", "W": "E"}
const MOVE_DIRS = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1)
]
var width: int = 48
var height: int = 36
var edge_features: Dictionary = {}
var cell_features: Dictionary = {}
var interactables: Dictionary = {}
var zones: Dictionary = {}
var zone_cells: Dictionary = {}
var terrain_speed: Dictionary = {}
var entrances: Dictionary = {}
var revision: int = 0
var path_cache: Dictionary = {}


static func feature(
	kind: String, h: float, movement: bool, sight: bool, projectile: bool, door = null
) -> Dictionary:
	return {
		"id": "",
		"kind": kind,
		"height": h,
		"blocks_movement": movement,
		"blocks_sight": sight,
		"blocks_projectile": projectile,
		"interactive_id": door,
		"cell": Vector2i.ZERO,
		"direction": "",
		"placement": "cell"
	}


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func zone_id(c):
	return zone_cells.get(c)


func walkable(c) -> bool:
	return c != null and in_bounds(c) and not cell_features.get(c, {}).get("blocks_movement", false)


func edge_key(c: Vector2i, direction: String) -> String:
	return "%d,%d,%s" % [c.x, c.y, direction]


func set_edge(c: Vector2i, direction: String, f: Dictionary):
	f.id = "%s:%d:%d:%s" % [f.kind, c.x, c.y, direction]
	f.cell = c
	f.direction = direction
	f.placement = "edge"
	edge_features[edge_key(c, direction)] = f
	var other = c + DIRS[direction]
	if in_bounds(other):
		edge_features[edge_key(other, OPPOSITE[direction])] = f
	revision += 1
	path_cache.clear()


func set_cell(c: Vector2i, f: Dictionary):
	f.id = "%s:%d:%d" % [f.kind, c.x, c.y]
	f.cell = c
	cell_features[c] = f
	revision += 1
	path_cache.clear()


func edge_at(c: Vector2i, direction: String):
	if not in_bounds(c):
		var f = feature("boundary", 3.0, true, true, true)
		f.id = "boundary"
		return f
	return edge_features.get(edge_key(c, direction))


func edge_between(a: Vector2i, b: Vector2i):
	for direction in DIRS:
		if b - a == DIRS[direction]:
			return edge_at(a, direction)
	return feature("boundary", 3.0, true, true, true)


func can_move(a, b, known_doors = null, allow_doors: bool = false) -> bool:
	if a == null or not in_bounds(a) or not walkable(b):
		return false
	var delta = b - a
	if delta not in MOVE_DIRS:
		return false
	if delta.x != 0 and delta.y != 0:
		for side in [Vector2i(b.x, a.y), Vector2i(a.x, b.y)]:
			if walkable(side) and can_move(a, side, known_doors) and can_move(side, b, known_doors):
				return true
		return false
	var edge = edge_between(a, b)
	if edge != null and edge.interactive_id != null and known_doors != null:
		if known_doors.get(edge.interactive_id) not in ["open", "broken"]:
			return false
	return edge == null or not edge.blocks_movement or allow_doors and edge.interactive_id != null


func neighbors(c: Vector2i, known_doors = null) -> Array:
	var result = []
	for delta in MOVE_DIRS:
		if can_move(c, c + delta, known_doors):
			result.append(c + delta)
	return result


func step_cost(a: Vector2i, b: Vector2i) -> float:
	return (
		Vector2(a).distance_to(Vector2(b))
		* (0.5 / terrain_speed.get(a, 1.0) + 0.5 / terrain_speed.get(b, 1.0))
	)


func path_cost(path: Array) -> float:
	if path.is_empty():
		return INF
	var result = 0.0
	for i in range(1, path.size()):
		result += step_cost(path[i - 1], path[i])
	return result


static func heap_less(a: Array, b: Array) -> bool:
	for i in range(4):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


static func heap_push(heap: Array, entry: Array):
	heap.append(entry)
	var i = heap.size() - 1
	while i > 0:
		var parent = (i - 1) >> 1
		if not heap_less(entry, heap[parent]):
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = entry


static func heap_pop(heap: Array) -> Array:
	var first = heap[0]
	var last = heap.pop_back()
	if heap.is_empty():
		return first
	var i = 0
	while i * 2 + 1 < heap.size():
		var child = i * 2 + 1
		if child + 1 < heap.size() and heap_less(heap[child + 1], heap[child]):
			child += 1
		if not heap_less(heap[child], last):
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return first


func find_path(start, goal, allowed = null, known_doors = null, blocked: Dictionary = {}) -> Array:
	if start == null or goal == null or not in_bounds(start) or not walkable(goal):
		return []
	if allowed != null and (not allowed.has(start) or not allowed.has(goal)):
		return []
	if start == goal:
		return [start]
	var key = [revision, start, goal, hash(allowed), hash(known_doors), hash(blocked)]
	if path_cache.has(key):
		return path_cache[key].duplicate()
	var frontier = []
	var costs = {start: 0.0}
	var parents = {start: null}
	heap_push(frontier, [Vector2(start).distance_to(Vector2(goal)), 0.0, start.y, start.x])
	while not frontier.is_empty():
		var entry = heap_pop(frontier)
		var current = Vector2i(entry[3], entry[2])
		var cost = entry[1]
		if cost > costs[current] + 0.000000001:
			continue
		if current == goal:
			break
		for next in neighbors(current, known_doors):
			if allowed != null and not allowed.has(next):
				continue
			if current.x != next.x and current.y != next.y:
				var clear = false
				for side in [Vector2i(next.x, current.y), Vector2i(current.x, next.y)]:
					if (
						not blocked.has(side)
						and (allowed == null or allowed.has(side))
						and walkable(side)
						and can_move(current, side, known_doors)
						and can_move(side, next, known_doors)
					):
						clear = true
						break
				if not clear:
					continue
			if blocked.has(next) and next != goal:
				continue
			var value = cost + step_cost(current, next)
			if value >= costs.get(next, INF) - 0.000000001:
				continue
			costs[next] = value
			parents[next] = current
			heap_push(
				frontier, [value + Vector2(next).distance_to(Vector2(goal)), value, next.y, next.x]
			)
	var result = []
	if parents.has(goal):
		var current = goal
		while current != null:
			result.append(current)
			current = parents[current]
		result.reverse()
	if path_cache.size() >= 2048:
		path_cache.clear()
	path_cache[key] = result.duplicate()
	return result


func ray_features(start: Vector2, end: Vector2) -> Array:
	var delta = end - start
	var c = SCData.cell_of(start)
	var sx = 1 if delta.x >= 0 else -1
	var sy = 1 if delta.y >= 0 else -1
	var tx = ((c.x + 1 if sx > 0 else c.x) - start.x) / delta.x if delta.x != 0 else INF
	var ty = ((c.y + 1 if sy > 0 else c.y) - start.y) / delta.y if delta.y != 0 else INF
	var stepx = absf(1.0 / delta.x) if delta.x != 0 else INF
	var stepy = absf(1.0 / delta.y) if delta.y != 0 else INF
	var seen = {}
	var result = []
	var f = cell_features.get(c)
	if f != null:
		seen[f.id] = true
		result.append([0.0, f])
	while minf(tx, ty) <= 1.0:
		var t = maxf(0.0, minf(tx, ty))
		var crossx = tx <= ty + 0.0000000001
		var crossy = ty <= tx + 0.0000000001
		var directions = []
		if crossx:
			directions.append("E" if sx > 0 else "W")
		if crossy:
			directions.append("S" if sy > 0 else "N")
		for direction in directions:
			f = edge_at(c, direction)
			if f != null and not seen.has(f.id):
				seen[f.id] = true
				result.append([t, f])
		if crossx:
			c.x += sx
			tx += stepx
		if crossy:
			c.y += sy
			ty += stepy
		if not in_bounds(c):
			break
		f = cell_features.get(c)
		if f != null and not seen.has(f.id):
			seen[f.id] = true
			result.append([t, f])
	return result


func raycast(
	start: Vector2,
	end: Vector2,
	start_height: float = 1.65,
	end_height: float = 1.65,
	kind: String = "sight"
) -> Array:
	# Traverse in the same order as ray_features, but stop at the first collision.
	# Sight rays usually hit a nearby wall; enumerating geometry beyond it dominates
	# the cost of updating the four squad members' fields of view.
	var delta = end - start
	var c = SCData.cell_of(start)
	var sx = 1 if delta.x >= 0 else -1
	var sy = 1 if delta.y >= 0 else -1
	var tx = ((c.x + 1 if sx > 0 else c.x) - start.x) / delta.x if delta.x != 0 else INF
	var ty = ((c.y + 1 if sy > 0 else c.y) - start.y) / delta.y if delta.y != 0 else INF
	var stepx = absf(1.0 / delta.x) if delta.x != 0 else INF
	var stepy = absf(1.0 / delta.y) if delta.y != 0 else INF
	var f = cell_features.get(c)
	var entered := 0.0
	while true:
		# Test the whole interval inside this cell, including a descending ray
		# that clears the front face but then hits the top of a low obstacle.
		var leaving := minf(1.0, minf(tx, ty))
		var hit := height_hit(f, start_height, end_height, entered, leaving, kind)
		if hit >= 0.0: return [hit, f]
		if minf(tx, ty) > 1.0: break
		var t = maxf(0.0, minf(tx, ty))
		var h = lerpf(start_height, end_height, t)
		var crossx = tx <= ty + 0.0000000001
		var crossy = ty <= tx + 0.0000000001
		if crossx:
			f = edge_at(c, "E" if sx > 0 else "W")
			if ray_blocked(f, h, kind):
				return [t, f]
		if crossy:
			f = edge_at(c, "S" if sy > 0 else "N")
			if ray_blocked(f, h, kind):
				return [t, f]
		if crossx:
			c.x += sx
			tx += stepx
		if crossy:
			c.y += sy
			ty += stepy
		if not in_bounds(c):
			break
		f = cell_features.get(c)
		entered = t
	return [1.0, null]


static func height_hit(f, h0: float, h1: float, enter: float, leave: float, kind: String) -> float:
	if f == null: return -1.0
	if ray_blocked(f, lerpf(h0, h1, enter), kind): return enter
	if kind == "flash": return -1.0
	var blocks: bool = f.blocks_sight if kind == "sight" else f.blocks_projectile
	if not blocks: return -1.0
	var delta := h1 - h0
	if delta < -0.00000001:
		var top: float = (f.height - h0) / delta
		if top >= enter and top <= leave: return top
	if delta > 0.00000001 and f.kind == "window":
		var lintel := (2.2 - h0) / delta
		if lintel >= enter and lintel <= leave: return lintel
	return -1.0


static func ray_blocked(f, height: float, kind: String) -> bool:
	if f == null:
		return false
	if kind == "flash":
		return f.blocks_projectile and f.height >= 2.0
	var blocks = f.blocks_sight if kind == "sight" else f.blocks_projectile
	return blocks and (height <= f.height or f.kind == "window" and height >= 2.2)


func open_door(id: String, broken: bool = false):
	var door = interactables[id]
	door.state = "broken" if broken else "open"
	var f = door.feature
	f.blocks_movement = false
	f.blocks_sight = false
	f.blocks_projectile = false
	f.height = 0.0
	revision += 1
	path_cache.clear()


func create_greyport():
	var data = SCData.mission
	for key in data.rects:
		var rect = data.rects[key]
		var cells = {}
		for y in range(int(rect[1]), int(rect[3]) + 1):
			for x in range(int(rect[0]), int(rect[2]) + 1):
				var c = Vector2i(x, y)
				cells[c] = true
				zone_cells[c] = key
		zones[key] = {"id": key, "label": data.labels[key], "cells": cells, "rect": rect}
	for y in range(height):
		for x in range(width):
			var c = Vector2i(x, y)
			if not zone_cells.has(c):
				set_cell(c, feature("full_cover", 2.2, true, true, true))
			for direction in ["E", "S"]:
				if zone_id(c) != zone_id(c + DIRS[direction]):
					set_edge(c, direction, feature("wall", 2.2, true, true, true))
	for d in data.doors:
		var id = "door_" + d[0]
		var c = SCData.cell(d[1])
		var direction = d[2]
		var other = c + DIRS[direction]
		var f = feature("door", 2.2, true, true, true, id)
		set_edge(c, direction, f)
		interactables[id] = {
			"id": id,
			"kind": "door",
			"state": "closed",
			"locked": d[3],
			"cell": c,
			"direction": direction,
			"feature": f
		}
		entrances[id] = {
			"id": id, "a": c, "b": other, "zone_a": zone_id(c), "zone_b": zone_id(other)
		}
	for x in [26, 27, 28]:
		edge_features.erase(edge_key(Vector2i(x, 25), "N"))
		edge_features.erase(edge_key(Vector2i(x, 24), "S"))
	set_edge(Vector2i(30, 23), "E", feature("window", 1.2, true, false, false))
	set_edge(Vector2i(29, 10), "N", feature("window", 1.2, true, false, false))
	for room in data.furniture:
		for layer in range(2):
			for rect in data.furniture[room][layer]:
				for y in range(int(rect[1]), int(rect[3]) + 1):
					for x in range(int(rect[0]), int(rect[2]) + 1):
						set_cell(
							Vector2i(x, y),
							feature(
								"low_cover" if layer == 0 else "full_cover",
								1.0 if layer == 0 else 2.2,
								true,
								layer == 1,
								true
							)
						)
