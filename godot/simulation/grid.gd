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
const CHUNK_SIZE := 32
const CACHE_LIMIT_BYTES := 64 * 1024 * 1024
var default_terrain: Dictionary = {}
# Only authored differences are stored here; ordinary cells share default_terrain.
var cells: Dictionary = {}
var navigation_revision := 0
var knowledge_revision := 0
var navigation_chunks: Dictionary = {}
var known_chunks: Dictionary = {}
var _dirty_navigation: Dictionary = {}
var _path_cache_bytes := 0
var _cache_clock := 0
var _path_cache_sizes: Dictionary = {}
var _path_cache_used: Dictionary = {}
var _entity_cells: Dictionary = {}
var _entity_ray_cells: Dictionary = {}
var _entity_rects: Dictionary = {}
var _entity_geometry_rects: Dictionary = {}
var _actor_index_signatures: Dictionary = {}
var _observed_navigation: Dictionary = {}
var _observed_door_states: Dictionary = {}
var _navigation_serial := 0
var _known_minimum_cost := 1.0
var _dynamic_buckets: Dictionary = {}
var _entity_buckets: Dictionary = {}
var _entity_order: Dictionary = {}
var _next_entity_order := 0
var _indexes_ready := false
var _loading := false
var _passages: Dictionary = {}
var _actor_passages: Dictionary = {}
var _lane_keys: Dictionary = {}
var _lane_revision := -1
var _coarse_cache: Dictionary = {}
var _minimum_unit_cost := 1.0
var entities: Dictionary = {}
var width: int = 48
var height: int = 36
var edge_features: Dictionary = {}
var cell_features: Dictionary = {}
var interactables: Dictionary = {}
var zones: Dictionary = {}
var zone_cells: Dictionary = {}
var _geometry_versions: Dictionary = {}
var _ray_entry_cells: Dictionary = {}
var entrances: Dictionary = {}
var revision: int = 0
var path_cache: Dictionary = {}
var _ray_geometry_revision := -1
var _ray_buckets: Dictionary = {}
var _ray_entity_count := -1
var _ray_characters := {"sight":[],"projectile":[]}
var _walk_buckets: Dictionary = {}
var _neighbor_cache: Dictionary = {}


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


func terrain_at(c: Vector2i) -> Dictionary:
	return cells.get(c, default_terrain)


func ground_at(c: Vector2i) -> float:
	return float(terrain_at(c).get("ground_height_m", 0.0))


func terrain_multiplier(c: Vector2i) -> float:
	return float(terrain_at(c).get("movement_multiplier", 1.0))


func all_cells() -> Array:
	var result: Array = []
	for y in range(floori(bounds.position.y), ceili(bounds.end.y)):
		for x in range(floori(bounds.position.x), ceili(bounds.end.x)):
			result.append(Vector2i(x,y))
	return result


func walkable(c) -> bool:
	if c == null or not in_bounds(c) or not terrain_at(c).get("passable",true): return false
	if cell_features.get(c, {}).get("blocks_movement", false): return false
	_ensure_ray_geometry()
	for entry in _walk_buckets.get(c,[]):
		if entry.entity.blocks("movement") and entry.footprint.has_point(SCData.center(c)):
			return false
	return true


func _chunk(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x)/CHUNK_SIZE),floori(float(c.y)/CHUNK_SIZE))


func _slot(c: Vector2i) -> int:
	return posmod(c.y,CHUNK_SIZE)*CHUNK_SIZE+posmod(c.x,CHUNK_SIZE)


func _new_navigation_chunk() -> Dictionary:
	var flags := PackedByteArray(); flags.resize(CHUNK_SIZE*CHUNK_SIZE)
	var speeds := PackedFloat32Array(); speeds.resize(CHUNK_SIZE*CHUNK_SIZE); speeds.fill(1.0)
	_navigation_serial+=1
	return {"flags":flags,"speeds":speeds,"version":_navigation_serial}


func _real_navigation_flags(c: Vector2i) -> int:
	if not in_bounds(c): return 0
	var flags := 1 | (2 if walkable(c) else 0)
	var bit := 4
	for direction in DIRS:
		var edge = edge_at(c,direction)
		if in_bounds(c+DIRS[direction]) and (edge == null or not edge.blocks_movement): flags |= bit
		bit <<= 1
	return flags


func _refresh_navigation():
	if _dirty_navigation.is_empty(): return
	var edited := {}
	for c: Vector2i in _dirty_navigation:
		if not in_bounds(c): continue
		var key := _chunk(c)
		if not edited.has(key):
			var previous: Dictionary = navigation_chunks.get(key,{})
			edited[key] = _new_navigation_chunk() if previous.is_empty() else {"flags":previous.flags.duplicate(),"speeds":previous.speeds.duplicate()}
		var chunk: Dictionary = edited[key]
		chunk.flags[_slot(c)] = _real_navigation_flags(c)
		chunk.speeds[_slot(c)] = terrain_multiplier(c)
	for key in edited:
		_navigation_serial+=1;edited[key].version=_navigation_serial
		navigation_chunks[key]=edited[key]
	_dirty_navigation.clear()


func _navigation_changed(rect: Rect2):
	navigation_revision += 1
	for y in range(floori(rect.position.y)-1,ceili(rect.end.y)+2):
		for x in range(floori(rect.position.x)-1,ceili(rect.end.x)+2):
			var c := Vector2i(x,y)
			if in_bounds(c):
				_dirty_navigation[c]=true
	_neighbor_cache.clear()


class ObservationBlock extends RefCounted:
	var stamps:=PackedInt32Array()
	func _init():stamps.resize(1024)


func observe_navigation(visible: Dictionary, doors: Dictionary) -> bool:
	_refresh_navigation()
	# Door knowledge can change without changing real geometry (for example
	# first observing an already-open doorway). Refresh just its two sides.
	var door_ids: Array=doors.keys()
	for id in _observed_door_states:
		if not doors.has(id):door_ids.append(id)
	for id in door_ids:
		if _observed_door_states.get(id)==doors.get(id):continue
		var entrance: Dictionary=entrances.get(id,{})
		if entrance.is_empty():continue
		for cell: Vector2i in [entrance.a,entrance.b]:
			var stamps: ObservationBlock=_observed_navigation.get(_chunk(cell))
			if stamps!=null:stamps.stamps[_slot(cell)]=0
	_observed_door_states=doors.duplicate()
	var edited := {}
	var observed: Array=[]
	for c: Vector2i in visible:
		if not in_bounds(c): continue
		var key := _chunk(c)
		var actual: Dictionary = navigation_chunks.get(key,{})
		if actual.is_empty(): continue
		var slot := _slot(c)
		if not _observed_navigation.has(key):_observed_navigation[key]=ObservationBlock.new()
		var stamps: ObservationBlock=_observed_navigation[key]
		if stamps.stamps[slot]==actual.version:continue
		stamps.stamps[slot]=actual.version;observed.append(c)
		var flags: int = actual.flags[slot]
		# A doorway is not a known open connection until observed as open.
		var bit := 4
		for direction in DIRS:
			var edge = edge_at(c,direction)
			if edge != null and edge.interactive_id != null and doors.get(edge.interactive_id) not in ["open","broken"]: flags &= ~bit
			bit <<= 1
		var previous: Dictionary = edited.get(key,known_chunks.get(key,{}))
		if not previous.is_empty() and previous.flags[slot]==flags and previous.speeds[slot]==actual.speeds[slot]: continue
		if not edited.has(key): edited[key]=_new_navigation_chunk() if previous.is_empty() else {"flags":previous.flags.duplicate(),"speeds":previous.speeds.duplicate()}
		edited[key].flags[slot]=flags
		edited[key].speeds[slot]=actual.speeds[slot]
		_known_minimum_cost=minf(_known_minimum_cost,1.0/float(actual.speeds[slot]))
	for c: Vector2i in observed:
		if not in_bounds(c):continue
		var source: Dictionary=edited.get(_chunk(c),known_chunks.get(_chunk(c),{}))
		if source.is_empty():continue
		var bit:=4;var index:=0
		for direction in DIRS:
			var other: Vector2i=c+DIRS[direction];var key:=_chunk(other)
			var previous: Dictionary=edited.get(key,known_chunks.get(key,{}))
			if not previous.is_empty() and int(previous.flags[_slot(other)])&1!=0:
				var opposite:=4<<((index+2)%4);var old_flags: int=previous.flags[_slot(other)]
				var flags: int=(old_flags|opposite) if int(source.flags[_slot(c)])&bit!=0 else (old_flags&~opposite)
				if flags!=old_flags:
					if not edited.has(key):edited[key]={"flags":previous.flags.duplicate(),"speeds":previous.speeds.duplicate()}
					edited[key].flags[_slot(other)]=flags
			bit<<=1;index+=1
	for key in edited:
		_navigation_serial+=1;edited[key].version=_navigation_serial
		known_chunks[key]=edited[key]
	if not edited.is_empty(): knowledge_revision += 1
	return not edited.is_empty()


func capture_navigation(knowledge = null) -> Dictionary:
	_refresh_navigation()
	return {"chunks":(known_chunks if knowledge != null else navigation_chunks).duplicate(),"version":knowledge_revision if knowledge != null else navigation_revision,"knowledge":knowledge != null,"minimum_cost":_known_minimum_cost if knowledge!=null else _minimum_unit_cost,"bounds":bounds}


func snapshot_flags(snapshot: Dictionary, c: Vector2i) -> int:
	var chunk: Dictionary = snapshot.chunks.get(_chunk(c),{})
	return 0 if chunk.is_empty() else int(chunk.flags[_slot(c)])


func snapshot_walkable(snapshot: Dictionary, c: Vector2i) -> bool:
	return snapshot_flags(snapshot,c)&3 == 3


func snapshot_speed(snapshot: Dictionary, c: Vector2i) -> float:
	var chunk: Dictionary = snapshot.chunks.get(_chunk(c),{})
	return 1.0 if chunk.is_empty() else float(chunk.speeds[_slot(c)])


func allowed_cell(allowed, c: Vector2i) -> bool:
	if allowed==null:return true
	if allowed.has("__zone"):return zone_id(c)==allowed.__zone
	if allowed.has("__exclude"):return zone_id(c)!=allowed.__exclude
	return allowed.has(c)


func snapshot_can_move(snapshot: Dictionary, a: Vector2i, b: Vector2i, allowed = null, blocked: Dictionary = {}, goal = null) -> bool:
	if not snapshot_walkable(snapshot,b) or not allowed_cell(allowed,a) or not allowed_cell(allowed,b): return false
	if blocked.has(b) and b != goal: return false
	var delta := b-a
	if delta not in MOVE_DIRS: return false
	if delta.x != 0 and delta.y != 0:
		for side in [Vector2i(b.x,a.y),Vector2i(a.x,b.y)]:
			if not snapshot_can_move(snapshot,a,side,allowed,blocked,goal) or not snapshot_can_move(snapshot,side,b,allowed,blocked,goal): return false
		return true
	var index := DIRS.values().find(delta)
	return snapshot_flags(snapshot,a) & (4 << index) != 0


func snapshot_step_cost(snapshot: Dictionary, a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))*(0.5/snapshot_speed(snapshot,a)+0.5/snapshot_speed(snapshot,b))


func edge_key(c: Vector2i, direction: String) -> String:
	return "%d,%d,%s" % [c.x, c.y, direction]


func set_edge(c: Vector2i, direction: String, f: Dictionary):
	var previous=edge_features.get(edge_key(c,direction))
	if _indexes_ready and previous!=null:_remove_ray_key("edge:"+previous.id)
	f.id = "%s:%d:%d:%s" % [f.kind, c.x, c.y, direction]
	f.cell = c
	f.direction = direction
	f.placement = "edge"
	edge_features[edge_key(c, direction)] = f
	var other = c + DIRS[direction]
	if in_bounds(other):
		edge_features[edge_key(other, OPPOSITE[direction])] = f
	revision += 1
	if not _loading:
		_navigation_changed(Rect2(Vector2(c),Vector2.ONE));_touch_geometry(Rect2(Vector2(c),Vector2.ONE))
		if _indexes_ready and f.kind!="door":
			var rect:=edge_rect(c,direction)
			_cache_ray_box("edge:"+f.id,AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,f.height,rect.size.y)),f)


func set_cell(c: Vector2i, f: Dictionary):
	f.id = "%s:%d:%d" % [f.kind, c.x, c.y]
	f.cell = c
	cell_features[c] = f
	revision += 1
	if not _loading:
		_navigation_changed(Rect2(Vector2(c),Vector2.ONE));_touch_geometry(Rect2(Vector2(c),Vector2.ONE))
		if _indexes_ready:_cache_ray_box("cell:"+str(c),AABB(Vector3(c.x,ground_at(c),c.y),Vector3(1,f.height,1)),f)


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
	_ensure_ray_geometry()
	var key := [c,hash(known_doors)]
	if _neighbor_cache.has(key): return _neighbor_cache[key].duplicate()
	var result = []
	for delta in MOVE_DIRS:
		if can_move(c, c + delta, known_doors):
			result.append(c + delta)
	_neighbor_cache[key]=result.duplicate()
	return result


func step_cost(a: Vector2i, b: Vector2i) -> float:
	return (
		Vector2(a).distance_to(Vector2(b))
		* (0.5 / terrain_multiplier(a) + 0.5 / terrain_multiplier(b))
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


class SearchBlock extends RefCounted:
	var costs := PackedFloat64Array()
	var parents := PackedInt32Array()
	var closed := PackedByteArray()
	var heap_positions := PackedInt32Array()
	func _init():
		costs.resize(1024); costs.fill(INF)
		parents.resize(1024); parents.fill(-1)
		closed.resize(1024)
		heap_positions.resize(1024);heap_positions.fill(-1)


class NavigationSearch extends RefCounted:
	var grid: SCGrid
	var snapshot: Dictionary
	var start: Vector2i
	var goals: Array
	var allowed
	var blocked: Dictionary
	var blocks: Dictionary = {}
	var heap_ids := PackedInt32Array()
	var heap_costs := PackedFloat64Array()
	var heap_priorities := PackedFloat64Array()
	var remaining: Dictionary = {}
	var settled: Dictionary = {}
	var state := "planning"
	var expanded := 0
	var reconstruction: Array = []
	var reconstruction_id := -1
	var reconstruction_goal = null
	var goal_center:=Vector2.ZERO
	var goal_radius:=0.0
	var coarse_ready:=false
	var coarse_frontier: Array=[]
	var coarse_costs: Dictionary={}
	func _init(g: SCGrid, nav: Dictionary, origin: Vector2i, destinations: Array, region = null, exclusions: Dictionary = {}):
		grid=g; snapshot=nav; start=origin; goals=destinations; allowed=region; blocked=exclusions
		if not goals.is_empty():
			goal_center=Vector2(goals[0])
			for goal in goals:goal_radius=maxf(goal_radius,Vector2(goal).distance_to(goal_center))
		for goal in goals:
			if grid.snapshot_walkable(snapshot,goal) and grid.allowed_cell(allowed,goal):
				remaining[goal]=true
				var sector:=grid._chunk(goal)
				if not coarse_costs.has(sector):coarse_costs[sector]=0.0;SCGrid.heap_push(coarse_frontier,[0.0,0.0,sector.y,sector.x])
		if remaining.is_empty() or not grid.in_bounds(start) or not grid.allowed_cell(allowed,start): state="complete"; return
		if Vector2(start).distance_to(goal_center)<CHUNK_SIZE*1.5:
			coarse_ready=true;coarse_costs.clear();coarse_frontier.clear()
		var initial := _block(start); initial.costs[grid._slot(start)]=0.0
		_push(_id(start),0.0,_heuristic(start))
	func _id(c: Vector2i) -> int:
		return (c.y-floori(grid.bounds.position.y))*grid.width+c.x-floori(grid.bounds.position.x)
	func _cell(id: int) -> Vector2i:
		return Vector2i(id%grid.width+floori(grid.bounds.position.x),id/grid.width+floori(grid.bounds.position.y))
	func _block(c: Vector2i) -> SearchBlock:
		var key := grid._chunk(c)
		if not blocks.has(key): blocks[key]=SearchBlock.new()
		return blocks[key]
	func cost(c: Vector2i) -> float:
		var block: SearchBlock=blocks.get(grid._chunk(c))
		return INF if block==null else block.costs[grid._slot(c)]
	func _heuristic(c: Vector2i) -> float:
		# Distance to a disk containing every target is a consistent lower bound
		# for every target, so one exact search remains directed on long journeys.
		return maxf(maxf(0.0,Vector2(c).distance_to(goal_center)-goal_radius)*float(snapshot.minimum_cost),float(coarse_costs.get(grid._chunk(c),0.0)))
	func _less(i: int,j: int) -> bool:
		if heap_priorities[i]!=heap_priorities[j]: return heap_priorities[i]<heap_priorities[j]
		if heap_costs[i]!=heap_costs[j]: return heap_costs[i]<heap_costs[j]
		return heap_ids[i]<heap_ids[j]
	func _swap(i: int,j: int):
		var id:=heap_ids[i];heap_ids[i]=heap_ids[j];heap_ids[j]=id
		var ci:=_cell(heap_ids[i]);var cj:=_cell(heap_ids[j])
		_block(ci).heap_positions[grid._slot(ci)]=i;_block(cj).heap_positions[grid._slot(cj)]=j
		var value:=heap_costs[i];heap_costs[i]=heap_costs[j];heap_costs[j]=value
		value=heap_priorities[i];heap_priorities[i]=heap_priorities[j];heap_priorities[j]=value
	func _push(id: int,value: float,priority: float):
		var cell:=_cell(id);var block:=_block(cell);var slot:=grid._slot(cell)
		var i: int=block.heap_positions[slot]
		if i<0:
			heap_ids.append(id);heap_costs.append(value);heap_priorities.append(priority);i=heap_ids.size()-1;block.heap_positions[slot]=i
		else:heap_costs[i]=value;heap_priorities[i]=priority
		while i>0:
			var parent: int=(i-1)>>1
			if not _less(i,parent):break
			_swap(i,parent);i=parent
	func _pop() -> Array:
		var result: Array=[heap_ids[0],heap_costs[0]]
		var last:=heap_ids.size()-1
		_swap(0,last);heap_ids.resize(last);heap_costs.resize(last);heap_priorities.resize(last)
		var removed:=_cell(result[0]);_block(removed).heap_positions[grid._slot(removed)]=-1
		var i:=0
		while i*2+1<last:
			var child:=i*2+1
			if child+1<last and _less(child+1,child):child+=1
			if not _less(child,i):break
			_swap(i,child);i=child
		return result
	func _advance_coarse(deadline_usec: int):
		# Each crossing is a real known crossing; travelling inside a sector is
		# free in this relaxed graph, so its distances are admissible lower bounds.
		while not coarse_frontier.is_empty():
			var entry: Array=SCGrid.heap_pop(coarse_frontier);var sector:=Vector2i(entry[3],entry[2])
			if float(entry[1])>float(coarse_costs.get(sector,INF))+.000000001:continue
			for connection in grid.coarse_neighbors(snapshot,sector):
				var value: float=float(entry[1])+float(connection[1]);var next: Vector2i=connection[0]
				if value>=float(coarse_costs.get(next,INF))-.000000001:continue
				coarse_costs[next]=value;SCGrid.heap_push(coarse_frontier,[value,value,next.y,next.x])
			if Time.get_ticks_usec()>=deadline_usec:return
		coarse_ready=true
		if not coarse_costs.has(grid._chunk(start)):state="complete"
		elif not heap_priorities.is_empty():heap_priorities[0]=_heuristic(start)
	func advance(deadline_usec: int):
		if not coarse_ready and state=="planning":
			_advance_coarse(deadline_usec)
			if not coarse_ready or state!="planning" or Time.get_ticks_usec()>=deadline_usec:return
		var batch:=0
		while state=="planning" and not heap_ids.is_empty():
			var entry:=_pop();var current:=_cell(entry[0]);var block:=_block(current);var slot:=grid._slot(current)
			if entry[1]>block.costs[slot]+0.000000001 or block.closed[slot]!=0:continue
			block.closed[slot]=1;expanded+=1
			if remaining.has(current):
				settled[current]=block.costs[slot];remaining.erase(current)
				if remaining.is_empty():state="complete";break
			for delta: Vector2i in MOVE_DIRS:
				var next:=current+delta
				if not grid.snapshot_can_move(snapshot,current,next,allowed,blocked,next if remaining.has(next) else null):continue
				var value: float=entry[1]+grid.snapshot_step_cost(snapshot,current,next)
				if value>=cost(next)-0.000000001:continue
				var next_block:=_block(next);var next_slot:=grid._slot(next)
				next_block.costs[next_slot]=value;next_block.parents[next_slot]=int(entry[0])
				_push(_id(next),value,value+_heuristic(next))
			batch+=1
			if batch>=64:
				batch=0
				if Time.get_ticks_usec()>=deadline_usec:return
		if heap_ids.is_empty():state="complete"
	func parent_of(cell: Vector2i):
		var parent: int=_block(cell).parents[grid._slot(cell)]
		return _cell(parent) if parent>=0 else null
	func path_to(goal: Vector2i) -> Array:
		if not settled.has(goal):return []
		var result: Array=[];var id:=_id(goal)
		while id>=0:
			var c:=_cell(id);result.append(c)
			id=_block(c).parents[grid._slot(c)]
		result.reverse();return result
	func bytes_used() -> int:
		return blocks.size()*17408+heap_ids.size()*20+coarse_costs.size()*96+coarse_frontier.size()*80


func coarse_neighbors(snapshot: Dictionary, sector: Vector2i) -> Array:
	var dependencies: Array=[snapshot.knowledge,sector]
	for delta: Vector2i in [Vector2i.ZERO]+MOVE_DIRS:
		dependencies.append(snapshot.chunks.get(sector+delta,{}).get("version",0))
	if _coarse_cache.has(dependencies):return _coarse_cache[dependencies]
	var result: Array=[]
	for delta: Vector2i in MOVE_DIRS:
		var next:=sector+delta
		if not snapshot.chunks.has(next):continue
		var best:=INF
		if delta.x!=0 and delta.y!=0:
			var c:=sector*CHUNK_SIZE+Vector2i(CHUNK_SIZE-1 if delta.x>0 else 0,CHUNK_SIZE-1 if delta.y>0 else 0)
			if snapshot_can_move(snapshot,c,c+delta):best=snapshot_step_cost(snapshot,c,c+delta)
		else:
			for offset in range(CHUNK_SIZE):
				var c:=sector*CHUNK_SIZE+(Vector2i(CHUNK_SIZE-1 if delta.x>0 else 0,offset) if delta.x!=0 else Vector2i(offset,CHUNK_SIZE-1 if delta.y>0 else 0))
				if snapshot_can_move(snapshot,c,c+delta):best=minf(best,snapshot_step_cost(snapshot,c,c+delta))
		if is_finite(best):result.append([next,best])
	if _coarse_cache.size()>=2048:_coarse_cache.clear()
	_coarse_cache[dependencies]=result
	return result


func begin_search(start: Vector2i, goals: Array, snapshot: Dictionary, allowed = null, blocked: Dictionary = {}) -> NavigationSearch:
	return NavigationSearch.new(self,snapshot,start,goals,allowed,blocked)


func cache_path(key: Array, route: Array):
	var bytes: int=route.size()*16+192
	if bytes>CACHE_LIMIT_BYTES:return
	while _path_cache_bytes+bytes>CACHE_LIMIT_BYTES or path_cache.size()>=2048:
		if _path_cache_used.is_empty():path_cache.clear();_path_cache_bytes=0;break
		var oldest=_path_cache_used.keys()[0]
		for candidate in _path_cache_used:
			if _path_cache_used[candidate]<_path_cache_used[oldest]:oldest=candidate
		_path_cache_bytes-=int(_path_cache_sizes.get(oldest,0));path_cache.erase(oldest);_path_cache_sizes.erase(oldest);_path_cache_used.erase(oldest)
	if path_cache.has(key):_path_cache_bytes-=int(_path_cache_sizes.get(key,0))
	path_cache[key]=route.duplicate();_path_cache_sizes[key]=bytes;_path_cache_bytes+=bytes;_cache_clock+=1;_path_cache_used[key]=_cache_clock


func cached_path(key: Array):
	if not path_cache.has(key):return null
	_cache_clock+=1;_path_cache_used[key]=_cache_clock
	return path_cache[key].duplicate()


func find_path(start, goal, allowed = null, known_doors = null, blocked: Dictionary = {}) -> Array:
	if start==null or goal==null:return []
	var snapshot:=capture_navigation(known_doors)
	var key: Array=[snapshot.knowledge,snapshot.version,start,goal,hash(allowed),hash(blocked)]
	var cached=cached_path(key)
	if cached!=null:return cached
	var search:=begin_search(start,[goal],snapshot,allowed,blocked)
	while search.state=="planning":search.advance(Time.get_ticks_usec()+2000)
	var route:=search.path_to(goal);cache_path(key,route)
	return route


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
	for entity in _segment_entities(start,end):
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


func _touch_geometry(rect: Rect2):
	var first:=_chunk(SCData.cell_of(rect.position-Vector2.ONE*.00001))
	var last:=_chunk(SCData.cell_of(rect.end+Vector2.ONE*.00001))
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var key:=Vector2i(x,y);_geometry_versions[key]=int(_geometry_versions.get(key,0))+1


func _passage_key(from: Vector2i, to: Vector2i) -> String:
	var delta:=to-from
	if abs(delta.x)+abs(delta.y)!=1:return ""
	var edge=edge_between(from,to)
	if edge!=null and edge.interactive_id!=null:return "door:"+str(edge.interactive_id)
	if _lane_revision!=navigation_revision:_lane_keys.clear();_lane_revision=navigation_revision
	var axis:=Vector2i(1,0) if delta.x!=0 else Vector2i(0,1)
	var lookup: Array=[to,axis]
	if _lane_keys.has(lookup):return _lane_keys[lookup]
	var side:=Vector2i(-axis.y,axis.x)
	if walkable(to+side) or walkable(to-side):_lane_keys[lookup]="";return ""
	var members: Array=[to]
	for direction in [-1,1]:
		var cell: Vector2i=to+axis*direction
		while in_bounds(cell) and walkable(cell) and not walkable(cell+side) and not walkable(cell-side):
			members.append(cell);cell+=axis*direction
	members.sort_custom(SCData.cell_less)
	var key: String="lane:"+str(members[0])+":"+str(axis)
	for cell in members:_lane_keys[[cell,axis]]=key
	return key


func release_passage(actor):
	var key: String=str(_actor_passages.get(actor.id,""))
	if key!="" and _passages.has(key):_passages[key].active.erase(actor.id)
	_actor_passages.erase(actor.id)


func request_passage(actor, from: Vector2i, to: Vector2i) -> bool:
	# Detailed actors retain the established intermediate-cell passing rule.
	if actor.simulation_detail or str(actor.squad_id).is_empty():release_passage(actor);return true
	var key:=_passage_key(from,to)
	if str(_actor_passages.get(actor.id,""))!=key:release_passage(actor)
	if key.is_empty():return true
	var now: float=actor.world.time
	if not _passages.has(key):_passages[key]={"owner":"","direction":Vector2i.ZERO,"active":{},"queue":[],"last":now}
	var passage: Dictionary=_passages[key];var group: String=str(actor.squad_id);var direction:=to-from
	for id in passage.active.keys():
		var member=actor.world.actor(id)
		if member==null or not member.alive or not _actor_passages.has(id):passage.active.erase(id)
	passage.queue=passage.queue.filter(func(ticket):return now-float(ticket.seen)<1.0)
	if passage.owner==group and passage.direction==direction:
		passage.active[actor.id]=true;passage.last=now;_actor_passages[actor.id]=key;return true
	var waiting: Dictionary={}
	for ticket in passage.queue:
		if ticket.group==group and ticket.direction==direction:waiting=ticket;break
	if waiting.is_empty():waiting={"group":group,"direction":direction,"seen":now};passage.queue.append(waiting)
	else:waiting.seen=now
	if passage.active.is_empty() and (passage.owner=="" or now-float(passage.last)>=.3):
		var next: Dictionary=passage.queue.pop_front();passage.owner=next.group;passage.direction=next.direction;passage.last=now
	if passage.owner==group and passage.direction==direction:
		passage.active[actor.id]=true;_actor_passages[actor.id]=key;return true
	return false


func geometry_key(point: Vector2, radius: float) -> Array:
	var result: Array=[]
	var first:=_chunk(SCData.cell_of(point-Vector2.ONE*radius));var last:=_chunk(SCData.cell_of(point+Vector2.ONE*radius))
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var key:=Vector2i(x,y);result.append(key);result.append(_geometry_versions.get(key,0))
	return result


func _remove_ray_key(key: String):
	for cell in _ray_entry_cells.get(key,[]):
		if _ray_buckets.has(cell):_ray_buckets[cell]=_ray_buckets[cell].filter(func(entry):return entry.key!=key)
	_ray_entry_cells.erase(key)


func _segment_entities(start: Vector2, end: Vector2) -> Array:
	_ensure_ray_geometry()
	var found: Dictionary={};var delta:=end-start;var cell:=SCData.cell_of(start)
	var sx:=1 if delta.x>=0 else -1;var sy:=1 if delta.y>=0 else -1
	var tx: float=((cell.x+1 if sx>0 else cell.x)-start.x)/delta.x if delta.x!=0 else INF
	var ty: float=((cell.y+1 if sy>0 else cell.y)-start.y)/delta.y if delta.y!=0 else INF
	var stepx: float=absf(1.0/delta.x) if delta.x!=0 else INF;var stepy: float=absf(1.0/delta.y) if delta.y!=0 else INF
	while true:
		for entry in _ray_buckets.get(cell,[]):
			if entry.entity!=null:found[entry.entity.definition.id]=entry.entity
		if minf(tx,ty)>1.0:break
		var crossx:=tx<=ty+.0000000001;var crossy:=ty<=tx+.0000000001
		if crossx:cell.x+=sx;tx+=stepx
		if crossy:cell.y+=sy;ty+=stepy
	return found.values()


func _cache_ray_box(key: String, box: AABB, feature_data: Dictionary, entity: SCEntity = null, order := -1):
	_remove_ray_key(key)
	_ray_entry_cells[key]=[]
	var entry := {"key":key,"box":box,"feature":feature_data,"entity":entity,"order":order}
	# Include boundary-touching cells so grazing and corner rays retain the
	# same exact AABB intersections as the full geometry query.
	for y in range(floori(box.position.z-.00001),floori(box.end.z+.00001)+1):
		for x in range(floori(box.position.x-.00001),floori(box.end.x+.00001)+1):
			var cell := Vector2i(x,y)
			if not _ray_buckets.has(cell): _ray_buckets[cell]=[]
			_ray_buckets[cell].append(entry)
			_ray_entry_cells[key].append(cell)
			if entity!=null:
				if not _entity_ray_cells.has(entity.definition.id):_entity_ray_cells[entity.definition.id]=[]
				_entity_ray_cells[entity.definition.id].append(cell)


func _ensure_ray_geometry():
	if _indexes_ready:return
	_indexes_ready=true
	for cell: Vector2i in cells:
		var spec: Dictionary=terrain_at(cell)
		if spec.get("cover_height_m",0)>0 and (spec.get("blocks_sight",false) or spec.get("blocks_projectile",false)):
			_cache_ray_box("terrain:"+str(cell),AABB(Vector3(cell.x,ground_at(cell),cell.y),Vector3(1,spec.cover_height_m,1)),spec)
	for cell: Vector2i in cell_features:
		var data: Dictionary=cell_features[cell]
		_cache_ray_box("cell:"+str(cell),AABB(Vector3(cell.x,ground_at(cell),cell.y),Vector3(1,data.height,1)),data)
	var seen: Dictionary={}
	for data in edge_features.values():
		if seen.has(data.id) or data.kind=="door":continue
		seen[data.id]=true
		var rect:=edge_rect(data.cell,data.direction)
		_cache_ray_box("edge:"+data.id,AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,data.height,rect.size.y)),data)
	for entity: SCEntity in entities.values():_index_entity(entity)


func _remove_entity_index(entity: SCEntity):
	var id: String=entity.definition.id
	_remove_ray_key("entity:"+id)
	for cell in _entity_cells.get(id,[]):
		if _entity_buckets.has(cell):_entity_buckets[cell]=_entity_buckets[cell].filter(func(other):return other!=entity)
		if _walk_buckets.has(cell):_walk_buckets[cell]=_walk_buckets[cell].filter(func(entry):return entry.entity!=entity)
		if _dynamic_buckets.has(cell):_dynamic_buckets[cell]=_dynamic_buckets[cell].filter(func(other):return other!=entity)
	for cell in _entity_ray_cells.get(id,[]):
		if _ray_buckets.has(cell):_ray_buckets[cell]=_ray_buckets[cell].filter(func(entry):return entry.entity!=entity)
	_entity_cells.erase(id);_entity_ray_cells.erase(id)


func _index_entity(entity: SCEntity, actor_signature: Array = []):
	var id: String=entity.definition.id
	if not _entity_order.has(id):_entity_order[id]=_next_entity_order;_next_entity_order+=1
	var rect:=entity.footprint()
	_entity_rects[id]=rect;_entity_geometry_rects[id]=rect
	var occupied: Array=[]
	for y in range(floori(rect.position.y),floori(rect.end.y)+1):
		for x in range(floori(rect.position.x),floori(rect.end.x)+1):
			var cell:=Vector2i(x,y);occupied.append(cell)
			if not _entity_buckets.has(cell):_entity_buckets[cell]=[]
			_entity_buckets[cell].append(entity)
			if entity.actor!=null:
				if not _dynamic_buckets.has(cell):_dynamic_buckets[cell]=[]
				_dynamic_buckets[cell].append(entity)
			elif entity.blocks("movement"):
				if not _walk_buckets.has(cell):_walk_buckets[cell]=[]
				_walk_buckets[cell].append({"entity":entity,"footprint":rect})
	_entity_cells[id]=occupied
	if entity.blocks("sight") or entity.blocks("projectile"):_cache_ray_entity(entity,_entity_order[id])
	if entity.actor!=null:_actor_index_signatures[id]=actor_signature if not actor_signature.is_empty() else _actor_space_signature(entity)


func invalidate_entity(entity: SCEntity, navigation_changed: bool = true):
	if not _indexes_ready:return
	var previous: Rect2=_entity_rects.get(entity.definition.id,entity.footprint())
	var previous_geometry: Rect2=_entity_geometry_rects.get(entity.definition.id,previous)
	_remove_entity_index(entity);_index_entity(entity)
	_touch_geometry(previous_geometry.merge(_entity_geometry_rects.get(entity.definition.id,entity.footprint())))
	revision+=1
	if navigation_changed and entity.actor==null:_navigation_changed(previous.merge(entity.footprint()))


func _actor_space_signature(entity: SCEntity) -> Array:
	return [entity.position,entity.facing,entity.actor.facing,entity.actor.radius,entity.height(),entity.bottom(),entity.exists,entity.actor.alive,entity.blocks("movement"),entity.blocks("sight"),entity.blocks("projectile")]


func update_actor(entity: SCEntity):
	if not _indexes_ready:return
	var signature:=_actor_space_signature(entity)
	if _actor_index_signatures.get(entity.definition.id)==signature:return
	_remove_entity_index(entity);_index_entity(entity,signature)


func entities_near(point: Vector2, radius: float) -> Array:
	_ensure_ray_geometry()
	return entities_in_rect(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2))


func entities_in_rect(rect: Rect2) -> Array:
	_ensure_ray_geometry()
	var found: Dictionary={}
	for y in range(floori(rect.position.y),floori(rect.end.y)+1):
		for x in range(floori(rect.position.x),floori(rect.end.x)+1):
			var cell:=Vector2i(x,y)
			for entity: SCEntity in _entity_buckets.get(cell,[]):found[entity.definition.id]=entity
			for entry in _walk_buckets.get(cell,[]):found[entry.entity.definition.id]=entry.entity
			for entity: SCEntity in _dynamic_buckets.get(cell,[]):found[entity.definition.id]=entity
			for entry in _ray_buckets.get(cell,[]):
				if entry.entity!=null:found[entry.entity.definition.id]=entry.entity
	return found.values()


func _cache_ray_entity(entity: SCEntity, order: int):
	var at := entity.position
	var box := entity.collision_box()
	box.position.x-=at.x
	box.position.z-=at.y
	# Include parts that extend beyond the movement footprint. This box only
	# rejects impossible hits; the original part/cylinder query decides the hit.
	var size := entity.footprint().size
	var bottom := entity.bottom()
	for part in entity.solid_parts():
		var offset: Array=part.offset_m
		var dimensions: Array=part.size_m
		box=box.merge(AABB(Vector3(float(offset[0])-size.x*.5,bottom+float(offset[1]),float(offset[2])-size.y*.5),Vector3(dimensions[0],dimensions[1],dimensions[2])))
	if entity.definition.get("shape","")=="cylinder":
		var radius: float=entity.definition.radius_m
		box=box.merge(AABB(Vector3(-radius,bottom,-radius),Vector3(radius*2,entity.height(),radius*2)))
	var bounds := AABB(Vector3(at.x,box.position.y,at.y),Vector3(0,box.size.y,0))
	for x: float in [box.position.x,box.end.x]:
		for y: float in [box.position.z,box.end.z]:
			var corner := at+Vector2(x,y).rotated(entity.facing)
			bounds=bounds.expand(Vector3(corner.x,box.position.y,corner.y))
			bounds=bounds.expand(Vector3(corner.x,box.end.y,corner.y))
	_entity_geometry_rects[entity.definition.id]=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
	_cache_ray_box("entity:"+entity.definition.id,bounds.grow(.00001),{},entity,order)


func raycast(
	start: Vector2,
	end: Vector2,
	start_height: float = 1.65,
	end_height: float = 1.65,
	kind: String = "sight",
	ignore_targets := false,
	ignored_parts: Dictionary = {}
) -> Array:
	var origin := Vector3(start.x,start_height,start.y)
	var finish := Vector3(end.x,end_height,end.y)
	var best := 1.0
	var found = null
	var best_entity_order := -1
	var entity_kind := "sight" if kind=="sight" else "projectile"
	_ensure_ray_geometry()
	# Traverse front to back. A cell beyond the nearest exact hit cannot
	# contain an earlier hit; keep boundary ties for the entity ordering below.
	var delta := end-start
	var cell := SCData.cell_of(start)
	var sx := 1 if delta.x>=0 else -1
	var sy := 1 if delta.y>=0 else -1
	var tx: float=((cell.x+1 if sx>0 else cell.x)-start.x)/delta.x if delta.x!=0 else INF
	var ty: float=((cell.y+1 if sy>0 else cell.y)-start.y)/delta.y if delta.y!=0 else INF
	var step_x: float=absf(1.0/delta.x) if delta.x!=0 else INF
	var step_y: float=absf(1.0/delta.y) if delta.y!=0 else INF
	var seen := {}
	while true:
		for entry in _ray_buckets.get(cell,[]):
			if seen.has(entry.key): continue
			seen[entry.key]=true
			var entity: SCEntity=entry.entity
			if entity != null:
				if not entity.blocks(entity_kind) or entity.actor!=null and entity.actor.alive or ignore_targets and entity.definition.get("kind","")=="target": continue
				var near := SCCombat.box_hit_fraction(origin,finish,entry.box)
				if near<0 or near>best: continue
				var result := entity.ray_hit(origin,finish,entity_kind,ignored_parts)
				if not result.is_empty() and (result.fraction<best or result.fraction==best and entry.order>best_entity_order):
					best=result.fraction
					best_entity_order=entry.order
					found=entity.definition.duplicate(false)
					found["ray_hit"]=result
				continue
			var f: Dictionary=entry.feature
			if not f.get("blocks_"+kind,false):continue
			var hit := SCCombat.box_hit_fraction(origin,finish,entry.box)
			if hit>=0 and (hit<best or hit==best and best_entity_order<0): best=hit; found=f;best_entity_order=-1
		if minf(tx,ty)>best+.0000000001:break
		var cross_x := tx<=ty+.0000000001
		var cross_y := ty<=tx+.0000000001
		if cross_x:cell.x+=sx;tx+=step_x
		if cross_y:cell.y+=sy;ty+=step_y
	return [best,found]



func open_door(id: String, broken: bool = false):
	var target: SCEntity = interactables[id].entity
	if broken:
		target.door.locked = false
		target.door.faulted = false
	target.request_door(true)
	invalidate_entity(target,false)


static func edge_rect(cell: Vector2i, direction: String) -> Rect2:
	match direction:
		"N": return Rect2(cell.x,cell.y-.025,1,.05)
		"S": return Rect2(cell.x,cell.y+.975,1,.05)
		"W": return Rect2(cell.x-.025,cell.y,.05,1)
	return Rect2(cell.x+.975,cell.y,.05,1)

func load_scene(spec: Dictionary, scene_entities: Dictionary):
	_loading=true
	var b: Array=spec.bounds_m
	bounds=Rect2(b[0],b[1],b[2],b[3]);width=ceili(bounds.size.x);height=ceili(bounds.size.y)
	entities=scene_entities
	for entity in entities.values():entity.space=weakref(self)
	default_terrain=spec.terrain.duplicate(true)
	_minimum_unit_cost=1.0/float(default_terrain.movement_multiplier)
	for entry in spec.cells:
		var c:=SCData.cell(entry.cell);var data:=default_terrain.duplicate();data.merge(entry,true);cells[c]=data
		_minimum_unit_cost=minf(_minimum_unit_cost,1.0/float(data.movement_multiplier))
	for entry in spec.edges:set_edge(SCData.cell(entry.cell),entry.direction,feature("edge",entry.height_m,entry.blocks_movement,entry.blocks_sight,entry.blocks_projectile))
	for id in spec.zones:
		var zone: Dictionary=spec.zones[id];var v: Array=zone.rect_m;var rect:=Rect2(v[0],v[1],v[2],v[3]);var members: Dictionary={}
		for y in range(maxi(floori(bounds.position.y),floori(rect.position.y)),mini(ceili(bounds.end.y),ceili(rect.end.y))):
			for x in range(maxi(floori(bounds.position.x),floori(rect.position.x)),mini(ceili(bounds.end.x),ceili(rect.end.x))):
				var c:=Vector2i(x,y)
				if rect.has_point(SCData.center(c)):members[c]=true;zone_cells[c]=id
		zones[id]={"id":id,"label":zone.label,"cells":members,"rect":[v[0],v[1],v[0]+v[2]-1,v[1]+v[3]-1]}
	for entity in entities.values():
		if entity.door.is_empty():continue
		var door: Dictionary=entity.door;var cell:=SCData.cell_of(entity.position)
		if door.placement=="edge":
			cell=SCData.cell(entity.definition.edge_cell);var direction: String=entity.definition.edge_direction
			set_edge(cell,direction,feature("door",entity.height(),entity.blocks("movement"),entity.blocks("sight"),entity.blocks("projectile"),entity.definition.id))
			entrances[entity.definition.id]={"id":entity.definition.id,"a":cell,"b":cell+DIRS[direction],"zone_a":zone_id(cell),"zone_b":zone_id(cell+DIRS[direction])}
		interactables[entity.definition.id]={"id":entity.definition.id,"kind":"door","state":door.state,"locked":door.locked,"cell":cell,"entity":entity}
	_loading=false
	_ensure_ray_geometry()
	# Fill ordinary terrain in packed blocks. Only boundaries and authored
	# obstacles need script-level exact cell/edge/entity queries at load time.
	var first:=_chunk(SCData.cell_of(bounds.position));var last:=_chunk(SCData.cell_of(bounds.end-Vector2.ONE*.00001))
	var default_flags:=63 if default_terrain.get("passable",true) else 61
	var dirty: Dictionary={}
	for cy in range(first.y,last.y+1):
		for cx in range(first.x,last.x+1):
			var key:=Vector2i(cx,cy);var chunk:=_new_navigation_chunk()
			chunk.flags.fill(default_flags);chunk.speeds.fill(float(default_terrain.movement_multiplier));navigation_chunks[key]=chunk
			var origin:=key*CHUNK_SIZE
			if origin.x<bounds.position.x or origin.y<bounds.position.y or origin.x+CHUNK_SIZE>bounds.end.x or origin.y+CHUNK_SIZE>bounds.end.y:
				for ly in range(CHUNK_SIZE):
					for lx in range(CHUNK_SIZE):
						var c:=origin+Vector2i(lx,ly)
						if not in_bounds(c):chunk.flags[ly*CHUNK_SIZE+lx]=0
	var low:=SCData.cell_of(bounds.position);var high:=SCData.cell_of(bounds.end-Vector2.ONE*.00001)
	for x in range(low.x,high.x+1):dirty[Vector2i(x,low.y)]=true;dirty[Vector2i(x,high.y)]=true
	for y in range(low.y,high.y+1):dirty[Vector2i(low.x,y)]=true;dirty[Vector2i(high.x,y)]=true
	for c in cells:dirty[c]=true
	for c in cell_features:dirty[c]=true
	for c in _walk_buckets:dirty[c]=true
	var processed_edges: Dictionary={}
	for edge in edge_features.values():
		if processed_edges.has(edge.id):continue
		processed_edges[edge.id]=true;dirty[edge.cell]=true;dirty[edge.cell+DIRS[edge.direction]]=true
	for c: Vector2i in dirty:
		if not in_bounds(c):continue
		var chunk: Dictionary=navigation_chunks[_chunk(c)]
		chunk.flags[_slot(c)]=_real_navigation_flags(c);chunk.speeds[_slot(c)]=terrain_multiplier(c)
	navigation_revision+=1

func move_body(origin: Vector2, offset: Vector2, radius: float, body_height: float, ignored_actor = null) -> Vector2:
	var at:=origin
	for axis in [Vector2(offset.x,0),Vector2(0,offset.y)]:
		if axis.length_squared()<.000000001:continue
		var fraction:=1.0;var boxes: Array[AABB]=[]
		var sweep:=Rect2(at,axis).abs().grow(radius+.001)
		var seen: Dictionary={}
		for y in range(floori(sweep.position.y),floori(sweep.end.y)+1):
			for x in range(floori(sweep.position.x),floori(sweep.end.x)+1):
				var c:=Vector2i(x,y)
				if not terrain_at(c).get("passable",true):boxes.append(AABB(Vector3(c.x,-100,c.y),Vector3(1,200,1)))
				if cell_features.get(c,{}).get("blocks_movement",false):boxes.append(AABB(Vector3(c.x,ground_at(c),c.y),Vector3(1,cell_features[c].height,1)))
				for direction in DIRS:
					var f=edge_at(c,direction)
					if f==null or seen.has(f.id) or f.kind=="door" or not f.blocks_movement:continue
					seen[f.id]=true;var rect:=edge_rect(f.cell,f.direction)
					boxes.append(AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,f.height,rect.size.y)))
		var ground:=ground_at(SCData.cell_of(at))
		for entity: SCEntity in entities_in_rect(sweep):
			if entity.actor==ignored_actor and ignored_actor!=null or not entity.blocks("movement"):continue
			var hit: float=entity.move_fraction(at,at+axis,radius,body_height,ground)
			if hit>=0:fraction=minf(fraction,maxf(0,hit-.0001))
		for box in boxes:
			if box.position.y>=ground+body_height or box.end.y<=ground:continue
			var expanded:=AABB(box.position-Vector3(radius,0,radius),box.size+Vector3(radius*2,0,radius*2))
			var h:=clampf(ground+body_height*.5,box.position.y,box.end.y)
			var hit:=SCCombat.box_hit_fraction(Vector3(at.x,h,at.y),Vector3(at.x+axis.x,h,at.y+axis.y),expanded)
			if hit>=0:fraction=minf(fraction,maxf(0,hit-.0001))
		at+=axis*fraction
	var allowed:=bounds.grow(-radius)
	return at.clamp(allowed.position,allowed.end)
