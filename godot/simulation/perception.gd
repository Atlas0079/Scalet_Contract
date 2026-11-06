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
var known_entities: Dictionary = {}
var knowledge_version := 0
var visibility_version := 0
var _query_cache: Dictionary = {}
var _last_visible: Dictionary = {}
var _last_player_raw: Dictionary = {}
var _last_player_visible: Dictionary = {}
var _entity_candidates: Dictionary = {}
var _map_observer_inputs: Array = []
var _navigation_observation_key: Array = []
var _entity_observation_key: Array = []
var _entity_neighborhoods: Dictionary = {}




func point_visible(w, a, point: Vector2) -> bool:
	if a.stunned > 0 or not a.alive: return false
	var delta: Vector2 = point-a.position
	var squared := delta.length_squared()
	if squared>a.view_distance*a.view_distance: return false
	if squared>.0001 and absf(angle_difference(a.facing,delta.angle()))>a.view_angle*.5: return false
	var key: Array=[a.position,a.facing,a.view_distance,a.view_angle,a.stunned>0]
	var cache: Dictionary=_query_cache.get(a.id,{})
	# A global revision is only a cheap signal to inspect this observer's local
	# dependency. Unrelated changes do not discard completed exact ray queries.
	if cache.get("key")!=key or cache.get("checked_revision",-1)!=w.grid.revision:
		var geometry: Array=w.grid.geometry_key(a.position,a.view_distance)
		if cache.get("key")!=key or cache.get("geometry")!=geometry:
			cache={"key":key,"geometry":geometry,"points":{}}
			_query_cache[a.id]=cache
		cache["checked_revision"]=w.grid.revision
	if cache.points.has(point): return cache.points[point]
	if cache.points.size()>512: cache.points.clear()
	var result: Array=w.grid.raycast(a.position,point)
	var visible: bool=result[1]==null or result[0]>=1.0-.0000001
	cache.points[point]=visible
	return visible


func refresh(w, dt: float, force: bool = false):
	player_raw.clear()
	player_visible.clear()
	var map_inputs: Array=[]
	var map_observers: Array=[]
	for a in w.actors:
		a.visible.clear()
		if not a.alive or not a.simulation_detail: continue
		var seen := {}
		for target in w.actors_near(a.position,a.view_distance):
			if target==a or w.is_controlled(a) and w.is_controlled(target): continue
			if not w.is_controlled(a) and not w.hostile(a,target): continue
			if not point_visible(w,a,target.position): continue
			seen[target.id]=true
			if w.hostile(a,target): a.visible[target.id]=true
			a.identification[target.id]=a.identification.get(target.id,0.0)+dt*a.capabilities.values.identification_rate
			if a.identification[target.id]>=.2:
				a.recognized[target.id]=true
				if w.is_controlled(a): identified[target.id]=true
			if a.recognized.has(target.id) and target.alive: a.memory[target.id]=[target.position,w.time]
			elif not target.alive: a.memory.erase(target.id)
			if w.is_controlled(a): player_raw[target.id]=true
		for id in a.identification.keys():
			if not seen.has(id): a.identification.erase(id)
		for id in a.memory.keys():
			if w.time-a.memory[id][1]>=5: a.memory.erase(id)
		if not w.is_controlled(a): continue
		a.recognized.merge(identified,true)
		var key: Array=[a.position,a.facing,a.stunned>0,w.grid.geometry_key(a.position,a.view_distance),a.view_distance,a.view_angle]
		map_inputs.append([a.id,key])
		map_observers.append(a)
		if force or cell_keys.get(a.id)!=key:
			var cells := {}
			if a.stunned<=0:
				var radius: float=a.view_distance
				var origin: Vector2=a.position
				var facing: float=a.facing
				var half_angle: float=a.view_angle*.5
				var bounds: Rect2=w.grid.bounds
				for y in range(maxi(floori(bounds.position.y),floori(origin.y-radius)),mini(ceili(bounds.end.y),ceili(origin.y+radius))):
					for x in range(maxi(floori(bounds.position.x),floori(origin.x-radius)),mini(ceili(bounds.end.x),ceili(origin.x+radius))):
						var c := Vector2i(x,y)
						var point := SCData.center(c)
						var delta := point-origin
						if delta.length_squared()>radius*radius: continue
						if delta.length_squared()>.0001 and absf(angle_difference(facing,delta.angle()))>half_angle: continue
						var result: Array=w.grid.raycast(origin,point)
						if result[1]==null or result[0]>=1.0-.0000001: cells[c]=true
			cells_by_actor[a.id]=cells
			cell_keys[a.id]=key
		for id in w.grid.entrances:
			var e: Dictionary=w.grid.entrances[id]
			if point_visible(w,a,(SCData.center(e.a)+SCData.center(e.b))*.5): doors[id]=w.door_state(id)
	var map_changed: bool=force or map_inputs!=_map_observer_inputs
	if map_changed:
		visible_cells.clear()
		for observer in map_observers: visible_cells.merge(cells_by_actor.get(observer.id,{}),true)
		explored.merge(visible_cells,true)
		_map_observer_inputs=map_inputs
	for id in player_raw:
		if identified.has(id): player_visible[id]=true
	for a in w.actors:
		if w.is_controlled(a): a.recognized.merge(identified,true)
		elif player_visible.has(a.id): last_seen[a.id]=[a.position,w.time]
	for id in last_seen.keys():
		if w.time-last_seen[id][1]>=5: last_seen.erase(id)
	if visible_cells!=_last_visible or player_raw!=_last_player_raw or player_visible!=_last_player_visible:
		visibility_version+=1
		_last_visible=visible_cells.duplicate()
		_last_player_raw=player_raw.duplicate()
		_last_player_visible=player_visible.duplicate()
	# Actor identification and memory above still run at both semantic points.
	# Observing unchanged map facts is a separate, reusable pure operation.
	var navigation_key: Array=[_map_observer_inputs,doors.hash()]
	if force or navigation_key!=_navigation_observation_key:
		if w.grid.observe_navigation(visible_cells,doors): knowledge_version+=1
		_navigation_observation_key=navigation_key
	_observe_entities(w,map_observers,map_changed,force)
	if not first_contact and player_visible.keys().any(func(id): return w.actor(id).alive and w.hostile(w.actor(w.controlled_ids[0]),w.actor(id)) if not w.controlled_ids.is_empty() else false):
		first_contact=true
		w.message("发现敌人 · 空格暂停，逐人调整行动","ready")
		if w.auto_contact: w.pause_requested=true


func _observe_entities(w, observers: Array, map_changed: bool, force: bool):
	var observation_key: Array=[]
	for character in observers:
		if character.stunned>0: continue
		var key: Array=[character.position,character.view_distance,w.grid.geometry_key(character.position,character.view_distance+2.0)]
		observation_key.append([character.id,key])
		var neighborhood: Dictionary=_entity_neighborhoods.get(character.id,{})
		if force or neighborhood.get("key")!=key:
			var candidates: Array=[]
			for entity in w.grid.entities_near(character.position,character.view_distance+2.0):
				if entity.actor==null: candidates.append(entity)
			_entity_neighborhoods[character.id]={"key":key,"entities":candidates}
	if not force and not map_changed and observation_key==_entity_observation_key: return
	_entity_observation_key=observation_key
	_entity_candidates.clear()
	for character in observers:
		if character.stunned>0: continue
		for entity in _entity_neighborhoods.get(character.id,{}).get("entities",[]): _entity_candidates[entity.definition.id]=entity
	for id in _entity_candidates:
		var entity: SCEntity=_entity_candidates[id]
		var rect: Rect2=entity.footprint()
		var observed := false
		for y in range(floori(rect.position.y),ceili(rect.end.y)):
			for x in range(floori(rect.position.x),ceili(rect.end.x)):
				if visible_cells.has(Vector2i(x,y)): observed=true;break
			if observed: break
		if not observed: continue
		var snapshot := {"position":entity.position,"facing":entity.facing,"door_progress":float(entity.door.get("progress",0)),"exists":entity.exists,"ruined":entity.ruined,"definition":entity.definition}
		var previous: Dictionary=known_entities.get(id,{})
		if previous.is_empty() or previous.position!=snapshot.position or previous.facing!=snapshot.facing or previous.door_progress!=snapshot.door_progress or previous.exists!=snapshot.exists or previous.ruined!=snapshot.ruined:
			snapshot.definition=entity.definition.duplicate(true)
			known_entities[id]=snapshot
			knowledge_version+=1


func hear(w, event: Dictionary):
	var area = Vector2i(3 * floori(event.position.x / 3), 3 * floori(event.position.y / 3))
	event.area = area
	for a in w.actors_near(event.position,event.radius):
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
		w.activate_actor(a)
		if w.is_controlled(a):
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
	if not a.alive or not a.armed or a.stunned > 0 or a.current_action != null:
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
		if a.ai_state != "combat" or a.ai_goal == null:
			a.ai_state = "combat"
			a.ai_goal = null
			if zone != null:
				var candidates: Array=[]
				var origin: Vector2i=SCData.cell_of(a.position)
				for y in range(origin.y-3,origin.y+4):
					for x in range(origin.x-3,origin.x+4):
						var c:=Vector2i(x,y)
						if g.zone_id(c)!=zone or not g.walkable(c) or SCData.center(c).distance_to(a.position)>3: continue
						if w.actors_near(SCData.center(c),1.0).any(func(other): return other.id!=a.id and other.alive and other.occupied_cell==c): continue
						if not SCGrid.DIRS.values().any(func(delta): return g.cell_features.has(c+delta)): continue
						var obstruction = SCCombat.projectile_obstruction(g,SCData.center(c),target.position,1.65,1.25,a.weapon.ammunition.penetration) if a.weapon.definition.attack_category=="kinetic" else g.raycast(SCData.center(c),target.position,1.65,1.25,"projectile")[1]
						if obstruction==null: candidates.append(c)
				var options: Dictionary={"zone":zone,"known":false}
				var search: Dictionary=p.cost_query(a,candidates,options)
				if search.state=="complete":
					var choices: Array=[]
					for c in candidates:
						if search.costs.has(c): choices.append([search.costs[c],SCData.center(c).distance_to(target.position),c.y,c.x,c])
					choices.sort_custom(SCGrid.heap_less)
					if not choices.is_empty():
						a.ai_goal=choices[0][4]
						a.route=p.path(a,a.ai_goal,options)
						a.reserved_cell=a.ai_goal
						a.target_cell=a.ai_goal

		if a.ai_goal!=null and a.route.is_empty() and a.occupied_cell!=a.ai_goal:
			a.route=p.path(a,a.ai_goal,{"zone":zone,"known":false})
		if w.time - a.report_time >= 0.5:
			a.report_time = w.time
			for other in w.actors_near(a.position,8.0):
				if (
					other.ai_enabled
					and other.alive
					and other.id != a.id
					and w.friendly(a,other)
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
				var search: Dictionary=p.cost_query(a,candidates,{"zone":zone,"known":false})
				if search.state!="complete": return
				for c in candidates:
					if search.costs.has(c):
						a.ai_goal=c
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
	if a.coarse_wait_until>w.time: return
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
