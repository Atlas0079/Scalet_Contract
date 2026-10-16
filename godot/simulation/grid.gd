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
var bounds := Rect2(0,0,48,36)
var cells: Dictionary = {}
var entities: Dictionary = {}
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
	return bounds.has_point(SCData.center(c))


func zone_id(c):
	return zone_cells.get(c)


func walkable(c) -> bool:
	if c == null or not in_bounds(c) or not cells.get(c,{"passable":true}).passable: return false
	if cell_features.get(c, {}).get("blocks_movement", false): return false
	for entity in entities.values():
		if entity.actor == null and entity.blocks("movement") and entity.footprint().has_point(SCData.center(c)): return false
	return true


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
		for side in [Vector2i(b.x,a.y),Vector2i(a.x,b.y)]:
			if not walkable(side) or not can_move(a,side,known_doors) or not can_move(side,b,known_doors): return false
		return true
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
	for entity in entities.values():
		if entity.actor!=null or not entity.exists or not entity.blocks("projectile"): continue
		var box: AABB = entity.collision_box()
		var h: float = box.position.y+box.size.y*.5
		var hit: float = entity.ray_fraction(Vector3(start.x,h,start.y),Vector3(end.x,h,end.y))
		if hit<0 or seen.has(entity.definition.id): continue
		var kind: String = "door" if not entity.door.is_empty() else ("wall" if entity.definition.id.begins_with("wall_") else "entity")
		var entity_feature := feature(kind,entity.height(),entity.blocks("movement"),entity.blocks("sight"),entity.blocks("projectile"),entity.definition.id if kind=="door" else null)
		entity_feature.id=entity.definition.id
		result.append([hit,entity_feature])
	result.sort_custom(func(a,b): return a[0]<b[0])
	return result


func raycast(
	start: Vector2,
	end: Vector2,
	start_height: float = 1.65,
	end_height: float = 1.65,
	kind: String = "sight",
	ignore_targets := false
) -> Array:
	var origin := Vector3(start.x,start_height,start.y)
	var finish := Vector3(end.x,end_height,end.y)
	var best := 1.0
	var found = null
	for cell in cells:
		var spec: Dictionary = cells[cell]
		if spec.cover_height_m <= 0 or not spec.get("blocks_"+kind,false): continue
		var box := AABB(Vector3(cell.x,spec.ground_height_m,cell.y),Vector3(1,spec.cover_height_m,1))
		var hit := SCCombat.box_hit_fraction(origin,finish,box)
		if hit>=0 and hit<=best: best=hit; found=spec
	for cell in cell_features:
		var f: Dictionary = cell_features[cell]
		if not f.get("blocks_"+kind,false): continue
		var ground: float = cells.get(cell,{}).get("ground_height_m",0.0)
		var hit := SCCombat.box_hit_fraction(origin,finish,AABB(Vector3(cell.x,ground,cell.y),Vector3(1,f.height,1)))
		if hit>=0 and hit<=best: best=hit; found=f
	var seen := {}
	for f in edge_features.values():
		if seen.has(f.id) or f.kind=="door" or not f.get("blocks_"+kind,false): continue
		seen[f.id] = true
		var rect := edge_rect(f.cell,f.direction)
		var hit := SCCombat.box_hit_fraction(origin,finish,AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,f.height,rect.size.y)))
		if hit>=0 and hit<=best: best=hit; found=f
	for entity in entities.values():
		if entity.actor != null or ignore_targets and entity.definition.get("kind","")=="target" or not entity.blocks("sight" if kind=="sight" else "projectile"): continue
		var hit: float = entity.ray_fraction(origin,finish)
		if hit>=0 and hit<=best: best=hit; found=entity.definition
	return [best,found]



func open_door(id: String, broken: bool = false):
	var target: SCEntity = interactables[id].entity
	if broken:
		target.door.locked = false
		target.door.faulted = false
	target.request_door(true)
	revision += 1
	path_cache.clear()


static func edge_rect(cell: Vector2i, direction: String) -> Rect2:
	match direction:
		"N": return Rect2(cell.x,cell.y-.025,1,.05)
		"S": return Rect2(cell.x,cell.y+.975,1,.05)
		"W": return Rect2(cell.x-.025,cell.y,.05,1)
	return Rect2(cell.x+.975,cell.y,.05,1)

func load_scene(spec: Dictionary, scene_entities: Dictionary):
	var b: Array = spec.bounds_m
	bounds = Rect2(b[0],b[1],b[2],b[3])
	width = ceili(bounds.size.x)
	height = ceili(bounds.size.y)
	entities = scene_entities
	for entity in entities.values(): entity.space=weakref(self)
	for y in range(floori(bounds.position.y),ceili(bounds.end.y)):
		for x in range(floori(bounds.position.x),ceili(bounds.end.x)):
			var c := Vector2i(x,y)
			cells[c] = spec.terrain.duplicate(true)
			terrain_speed[c] = float(spec.terrain.movement_multiplier)
	for entry in spec.cells:
		var c := SCData.cell(entry.cell)
		cells[c].merge(entry,true)
		terrain_speed[c] = float(cells[c].movement_multiplier)
	for entry in spec.edges:
		set_edge(SCData.cell(entry.cell),entry.direction,feature("edge",entry.height_m,entry.blocks_movement,entry.blocks_sight,entry.blocks_projectile))
	for id in spec.zones:
		var zone: Dictionary = spec.zones[id]
		var v: Array = zone.rect_m
		var rect := Rect2(v[0],v[1],v[2],v[3])
		var members := {}
		for c in cells:
			if rect.has_point(SCData.center(c)): members[c]=true; zone_cells[c]=id
		zones[id] = {"id":id,"label":zone.label,"cells":members,"rect":[v[0],v[1],v[0]+v[2]-1,v[1]+v[3]-1]}
	for entity in entities.values():
		if entity.door.is_empty(): continue
		var door: Dictionary = entity.door
		var cell := SCData.cell_of(entity.position)
		if door.placement=="edge":
			cell=SCData.cell(entity.definition.edge_cell)
			var direction: String = entity.definition.edge_direction
			var feature := feature("door",entity.height(),entity.blocks("movement"),entity.blocks("sight"),entity.blocks("projectile"),entity.definition.id)
			set_edge(cell,direction,feature)
			entrances[entity.definition.id]={"id":entity.definition.id,"a":cell,"b":cell+DIRS[direction],"zone_a":zone_id(cell),"zone_b":zone_id(cell+DIRS[direction])}
		interactables[entity.definition.id] = {"id":entity.definition.id,"kind":"door","state":door.state,"locked":door.locked,"cell":cell,"entity":entity}

func move_body(origin: Vector2, offset: Vector2, radius: float, body_height: float, ignored_actor = null) -> Vector2:
	var at := origin
	for axis in [Vector2(offset.x,0),Vector2(0,offset.y)]:
		if axis.length_squared()<.000000001: continue
		var fraction := 1.0
		var boxes: Array[AABB] = []
		for c in cells:
			if not cells[c].passable: boxes.append(AABB(Vector3(c.x,-100,c.y),Vector3(1,200,1)))
		for c in cell_features:
			if cell_features[c].blocks_movement: boxes.append(AABB(Vector3(c.x,0,c.y),Vector3(1,cell_features[c].height,1)))
		var seen := {}
		for f in edge_features.values():
			if seen.has(f.id) or f.kind=="door" or not f.blocks_movement: continue
			seen[f.id] = true
			var rect := edge_rect(f.cell,f.direction)
			boxes.append(AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,f.height,rect.size.y)))
		var ground: float = cells.get(SCData.cell_of(at),{}).get("ground_height_m",0.0)
		for entity in entities.values():
			if entity.actor==ignored_actor and ignored_actor!=null or not entity.blocks("movement"): continue
			var hit: float = entity.move_fraction(at,at+axis,radius,body_height,ground)
			if hit>=0: fraction=minf(fraction,maxf(0,hit-.0001))
		for box in boxes:
			if box.position.y>=ground+body_height or box.end.y<=ground: continue
			var expanded := AABB(box.position-Vector3(radius,0,radius),box.size+Vector3(radius*2,0,radius*2))
			var hit := SCCombat.box_hit_fraction(Vector3(at.x,clampf(ground+body_height*.5,box.position.y,box.end.y),at.y),Vector3(at.x+axis.x,clampf(ground+body_height*.5,box.position.y,box.end.y),at.y+axis.y),expanded)
			if hit>=0: fraction=minf(fraction,maxf(0,hit-.0001))
		at += axis*fraction
	var allowed := bounds.grow(-radius)
	return at.clamp(allowed.position,allowed.end)
