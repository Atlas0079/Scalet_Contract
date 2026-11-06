class_name SCWorld
extends RefCounted

var grid: SCGrid
var controlled_ids: Array = []
var squads: Dictionary = {}
var _actor_buckets: Dictionary = {}
var _detail_needed: Dictionary = {}
var _contact_dirty := true
var _largest_view_distance := 0.0
var _largest_actor_step := 0.0
var _largest_actor_radius := 0.0
var _largest_operation_range := 0.0
var _actor_order: Dictionary = {}
var _phase := 0
const CPU_PHASE_NAMES := ["advance_state","actions","perception_pre","ai_planner_population","movement_indices","perception_post","shots_combat","finish"]
var runtime_phases := OS.get_cmdline_user_args().has("--runtime-phases")
var cpu_phase_usec: Array = [0,0,0,0,0,0,0,0]
var _cpu_phase_started := 0
var frame_steps := 0
var active_detail_count := 0
var active_combat_count := 0
var unpaused_wall_time := 0.0
var simulated_duration := 0.0
var actors: Array = []
var actor_index: Dictionary = {}
var skill_registry: Dictionary = SCSkills.registry()
var planner: SCPlanner
var perception: SCPerception
var loot: SCLoot
var rng = RandomNumberGenerator.new()
var time: float = 0.0
var tick_index: int = 0
var paused: bool = true
var pause_requested: bool = false
var pause_count: int = 0
var accumulator: float = 0.0
var discarded_time: float = 0.0
var winner = null
var combat_cleared: bool = false
var auto_contact: bool = false
var room_checked: Dictionary = {}
var shots: Array = []
var sounds: Array = []
var explosions: Array = []
var projectiles: Array = []
var events: Array = []
var audio_events: Array = []
var completed: Dictionary = {}
var deaths_processed: Dictionary = {}
var stats: Dictionary = {"rounds": 0, "controlled_rounds":0, "hits":0, "deaths":0, "deaths_by_team":{}, "friendly_hits": 0, "friendly_stuns": 0, "items": {}}


var scene_definition: Dictionary
var entities: Dictionary = {}
var manual_control := false
var weapon_clock_external := false

func _init(scene_name: String = "field", controlled := false):
	manual_control = controlled
	assert(SCData.scenes.has(scene_name),"Unknown scene: "+scene_name)
	scene_definition = SCData.scenes[scene_name].duplicate(true)
	grid = SCGrid.new()
	rng.seed = int(scene_definition.seed)
	for spec in scene_definition.entities:
		entities[spec.id] = SCEntity.new(spec)
		for operation in spec.get("operations",[]): _largest_operation_range=maxf(_largest_operation_range,float(operation.get("range_m",0)))
	for spec in scene_definition.actors:
		var character := SCActor.new(int(spec.id),spec.label,spec.team,SCCombat.pair(spec.position_m),spec.facing_radians,spec.unit,skill_registry)
		character.armed = bool(spec.get("armed",true))
		character.ai_enabled = bool(spec.get("ai_enabled",false))
		character.squad_id = str(spec.get("squad","actor:"+str(character.id)))
		for point in spec.get("patrol",[]): character.patrol.append(SCData.cell(point))
		if not character.patrol.is_empty(): character.home_cell=character.patrol[0]
		if bool(spec.get("controlled",false)): controlled_ids.append(character.id)
		add_actor(character)
		if not squads.has(character.squad_id): squads[character.squad_id]=[]
		squads[character.squad_id].append(character)
	grid.load_scene(scene_definition,entities)
	planner = SCPlanner.new(self)
	perception = SCPerception.new()
	loot = SCLoot.new(self)
	paused = false
	_refresh_population_index()
	_refresh_detail_requirements()
	_finish_detail_handoffs()

func add_actor(character: SCActor):
	character.world = self
	_actor_order[character.id]=actors.size()
	actors.append(character)
	actor_index[character.id] = character
	entities[character.identity] = SCEntity.new({"id":character.identity,"label":character.actor_name,"classification":"dropped","position_m":[character.position.x,character.position.y],"blocks_movement":true,"blocks_sight":false,"blocks_projectile":true},character)
	entities[character.identity].space=weakref(grid)

func move_actor(character: SCActor, offset: Vector2) -> Vector2:
	if paused or not character.capabilities.permissions.can_move: return character.position
	character.previous_position = character.position
	var terrain: Dictionary = grid.terrain_at(SCData.cell_of(character.position))
	character.position = grid.move_body(character.position,offset*terrain.movement_multiplier,character.radius,character.height,character)
	character.occupied_cell = SCData.cell_of(character.position)
	grid.update_actor(entities[character.identity])
	return character.position

func operate_door(id: String, character: SCActor, opened: bool) -> String:
	if character.world!=self or not entities.has(id): return "目标不属于当前世界"
	var entity: SCEntity = entities[id]
	if not character.capabilities.permissions.can_operate: return "无法操作"
	if character.position.distance_to(entity.position)>1.65: return "距离过远"
	if not opened:
		for other in grid.entities_in_rect(entity.footprint()):
			if other==entity or not other.exists: continue
			if other.actor==null and other.definition.classification!="dropped": continue
			if entity.footprint().intersects(other.footprint()): return "先移开门内实体"
	return entity.request_door(opened)

func inspect(character: SCActor) -> String:
	if character.world!=self or not character.capabilities.permissions.can_operate: return "无法查看现场"
	var found = null
	var nearest := INF
	for entity in grid.entities_near(character.position,_largest_operation_range):
		if not entity.exists: continue
		for operation in entity.definition.get("operations",[]):
			var distance := character.position.distance_to(entity.position)
			if operation.kind=="inspect" and distance<=operation.range_m and distance<nearest:
				var ray := grid.raycast(character.position,entity.position,character.eye_height,character.eye_height,"sight")
				if ray[1]!=null and ray[1].get("id","")!=entity.definition.id: continue
				nearest=distance; found={"entity":entity,"operation":operation}
	if found==null: return "靠近工作台、配电区或出口，再按 E 查看现场。"
	return found.entity.definition.label+"\n"+found.operation.text

func advance_state(dt: float):
	if paused: return
	time += dt
	tick_index += 1
	for entry in grid.interactables.values():
		var entity: SCEntity = entry.entity
		var previous: float = entity.door.get("progress",0.0)
		var was_blocking: bool = entity.blocks("movement")
		if not entity.door.is_empty() and entity.door.state=="closing":
			for other in grid.entities_in_rect(entity.footprint()):
				if other==entity or not other.exists or other.actor==null and other.definition.classification!="dropped": continue
				if entity.footprint().intersects(other.footprint()): entity.door.state="stopped"; break
		entity.advance(dt)
		if entity.door.get("progress",0.0)!=previous: grid.invalidate_entity(entity,was_blocking!=entity.blocks("movement"))
	for door in grid.interactables.values():
		door.state=door.entity.door.state
		door.locked=door.entity.door.locked
		if door.entity.door.placement=="edge":
			var f = grid.edge_at(SCData.cell(door.entity.definition.edge_cell),door.entity.definition.edge_direction)
			for kind in ["movement","sight","projectile"]: f["blocks_"+kind]=door.entity.blocks(kind)
	for character in actors:
		if not character.alive:
			if not deaths_processed.has(character.id):
				deaths_processed[character.id]=true
				planner.cancel_actor(character)
				loot.corpse(character)
			continue
		SCEquipment.advance(character,dt)
		if not weapon_clock_external: SCWeaponRules.advance(character,dt)
		var before_revision: int = character.ability_revision
		character.refresh_capabilities(time)
		if before_revision!=character.ability_revision: _contact_dirty=true



func actor(id):
	return actor_index.get(id)


func message(text: String, sound: String = "confirm"):
	events.append([time, text])
	if events.size() > 100:
		events.pop_front()
	if not sound.is_empty():
		audio_events.append(sound)


func set_paused(value: bool):
	if value and not paused:
		pause_count += 1
	paused = value
	accumulator = 0.0


func door_state(id: String) -> String:
	var door = grid.interactables[id]
	return ("locked" if door.locked else "closed") if door.state == "closed" else door.state


func update(dt: float):
	if runtime_phases:
		cpu_phase_usec=[0,0,0,0,0,0,0,0]
		_cpu_phase_started=Time.get_ticks_usec()
	planner.pump_requests()
	if runtime_phases: _record_cpu_phase(3)
	frame_steps = 0
	if paused or winner != null:
		return
	unpaused_wall_time += maxf(0.0,dt)
	if manual_control:
		if runtime_phases: _cpu_phase_started=Time.get_ticks_usec()
		advance_state(dt)
		if runtime_phases: _record_cpu_phase(0)
		simulated_duration += dt
		frame_steps=1
		return
	var step = 1.0 / 60.0
	accumulator += maxf(0.0, dt)
	var count = 0
	while accumulator + 0.000000001 >= step and count < 5 and not paused and winner == null:
		accumulator -= step
		tick(step)
		count += 1
		frame_steps += 1
		simulated_duration += step
	if accumulator >= step:
		var remainder = fmod(accumulator, step)
		discarded_time += accumulator - remainder
		accumulator = remainder


func _record_cpu_phase(index: int):
	var now := Time.get_ticks_usec()
	cpu_phase_usec[index]+=now-_cpu_phase_started
	_cpu_phase_started=now


func tick(dt: float):
	if runtime_phases: _cpu_phase_started=Time.get_ticks_usec()
	_phase=0
	advance_state(dt)
	if runtime_phases: _record_cpu_phase(0)
	for shot in shots:
		if shot.finished: shot.timer -= dt
	shots = shots.filter(func(shot): return not shot.finished or shot.timer > 0)
	for group in [sounds, explosions]:
		for event in group:
			event.timer -= dt
		for i in range(group.size() - 1, -1, -1):
			if group[i].timer <= 0:
				group.remove_at(i)
	for a in actors:
		a.previous_position = a.position
		a.stunned = maxf(0.0, a.stunned - dt)
		a.refresh_capabilities(time)
		if a.simulation_detail: SCCombat.advance_recoil(a, dt)
		a.hit_flash = maxf(0.0, a.hit_flash - dt)
		if a.current_action != null:
			if (
				planner.micro_controls_motion(a)
				and a.current_action.owner_token.begins_with("auto:")
			):
				interrupt(a, "微操接管自动换弹")
			else:
				update_action(a, dt)
	if runtime_phases: _record_cpu_phase(1)
	_refresh_population_index()
	if _contact_dirty or tick_index%6==0: _refresh_detail_requirements()
	if runtime_phases: _record_cpu_phase(4)
	_phase=1
	for i in range(projectiles.size() - 1, -1, -1):
		if time >= projectiles[i].explode_at:
			flash(projectiles[i])
			projectiles.remove_at(i)
	if runtime_phases: _record_cpu_phase(1)
	_phase=2
	perception.refresh(self, dt)
	loot.refresh()
	if runtime_phases: _record_cpu_phase(2)
	if tick_index % 6 == 0:
		for a in actors:
			if a.ai_enabled and a.simulation_detail:
				SCPerception.update_enemy(self, a)
	_advance_population_tasks()
	planner.tick(dt)
	if runtime_phases: _record_cpu_phase(3)
	_phase=3
	for a in actors:
		if a.alive and is_controlled(a) and has_threat(a) and not planner.micro_controls_motion(a):
			a.clear_movement()
	for a in actors:
		if not a.simulation_detail and not a.route.is_empty(): a.facing=SCMovement.movement_direction(a).angle()
	var distances = SCMovement.allowances(actors, grid, dt)
	for a in actors:
		if not a.alive:
			continue
		if a.current_action == null:
			var before = a.position
			SCMovement.update(a, grid, actors, dt, distances[a.id])
			grid.update_actor(entities[a.identity])
			if a.simulation_detail: observe(a, dt, a.position - before)
	_refresh_population_index()
	if runtime_phases: _record_cpu_phase(4)
	_phase=4
	perception.refresh(self, 0.0)
	if runtime_phases: _record_cpu_phase(5)
	for shot in shots:
		if not shot.finished:
			_activate_projectile_contacts(shot,dt)
			SCCombat.advance_shot(shot, dt, grid, actors, rng)
			process_shot(shot)
	_phase=5
	for a in actors:
		if a.simulation_detail and a.detail_ready_tick<=tick_index: combat(a, dt)
	if runtime_phases: _record_cpu_phase(6)
	for a in actors:
		if not a.alive and not deaths_processed.has(a.id):
			deaths_processed[a.id] = true
			planner.cancel_actor(a)
			loot.corpse(a)
			if is_controlled(a):
				message("%d %s 阵亡" % [a.id, a.actor_name], "hit")
				pause_requested = true
	_phase=6
	_finish_detail_handoffs()
	if pause_requested and winner == null:
		set_paused(true)
	pause_requested = false
	if audio_events.size() > 64:
		audio_events = audio_events.slice(audio_events.size() - 64)
	if runtime_phases: _record_cpu_phase(7)


func visible_targets(a) -> Array:
	var result = []
	for id in a.visible:
		if a.recognized.has(id) and actor(id) != null and actor(id).alive:
			result.append(actor(id))
	return result


func has_threat(a) -> bool:
	if a.under_fire_timer > time:
		return true
	if a.fire_mode == "hold_fire" and not (not a.queue.is_empty() and a.queue[0].kind == "attack"):
		return false
	if not visible_targets(a).is_empty():
		a.last_known_timer = time
		return true
	return a.last_known_timer > 0 and time - a.last_known_timer < 1


func face(a, angle, dt: float):
	if angle == null or a.stunned > 0:
		return
	if a.turn_tick != tick_index:
		a.turn_used = 0.0
		a.turn_tick = tick_index
	var budget = maxf(0.0, a.turn_speed * dt - a.turn_used)
	var change = minf(absf(angle_difference(a.facing, angle)), budget)
	a.facing = rotate_toward(a.facing, angle, budget)
	a.turn_used += change


func observe(a, dt: float, motion: Vector2):
	a.response = ""
	if a.stunned > 0:
		return
	if planner.micro_controls_motion(a):
		var n = a.queue[0]
		var angle = (
			n.angle
			if n.angle != null
			else (motion.angle() if motion.length() > 0.000001 else a.guard_angle)
		)
		face(a, angle, dt)
		if n.angle == null and motion.length() > 0.000001:
			a.guard_angle = a.facing
		a.response = "执行微操 · 受袭" if a.under_fire_timer > time else "执行微操"
		return
	if (
		not visible_targets(a).is_empty()
		and (a.fire_mode != "hold_fire" or not a.queue.is_empty() and a.queue[0].kind == "attack")
	):
		a.response = "交战"
		return
	var n = a.queue[0] if not a.queue.is_empty() else null
	var planned = (
		n.angle if n != null and n.kind in ["move", "move_face", "guard", "face"] else null
	)
	var macro = n != null and planner.tasks.has(n.task_id)
	var angle = a.guard_angle
	if a.under_fire_timer > time:
		a.response = "受袭搜索"
		angle = a.under_fire_angle
	elif planned != null:
		angle = planned
	elif (
		is_controlled(a)
		and not macro
		and not a.guard_explicit
		and a.heard_timer > time
		and a.heard_position != null
	):
		a.response = "听声观察"
		angle = (a.heard_position - a.position).angle()
	elif motion.length() > 0.000001:
		angle = motion.angle()
	face(a, angle, dt)
	if a.response.is_empty() and planned == null and motion.length() > 0.000001:
		a.guard_angle = a.facing


func receive_attack(a, shot: Dictionary, attacker, hit: bool = false):
	activate_actor(a)
	a.recent_attackers[attacker.id] = time
	var was_under_fire = a.under_fire_timer > time
	var known = (
		perception.player_visible.has(attacker.id)
		if is_controlled(a)
		else a.visible.has(attacker.id) and a.recognized.has(attacker.id)
	)
	var friendly_known = (
		friendly(attacker,a)
		and (is_controlled(a) or perception.point_visible(self, a, attacker.position))
	)
	var unknown = not known and not friendly_known
	if (
		unknown
		or (
			hostile(attacker,a)
			and not (a.visible.has(attacker.id) and a.recognized.has(attacker.id))
		)
	):
		a.under_fire_angle = (shot.start - shot.end).angle()
		a.under_fire_timer = time + 2.0
	if unknown:
		if planner.micro_controls_motion(a):
			if not was_under_fire:
				message("%d 号受袭 · 继续执行微操" % a.id, "hit")
			return
		var already = (
			not a.queue.is_empty()
			and (
				a.queue[0].status == "blocked"
				or (
					planner.tasks.has(a.queue[0].task_id)
					and planner.tasks[a.queue[0].task_id].phase == "blocked"
				)
			)
		)
		planner.suspend_actor(a, "%d 号受到未确认方向来弹" % a.id)
		if is_controlled(a) and not already:
			message("%d 号受袭搜索" % a.id + (" · 关联计划已挂起" if not a.queue.is_empty() else ""), "hit")
	elif hit:
		interrupt(a, "受到攻击，动作中断")


func update_aim(a, dt: float, tracking: bool, heading = null):
	var desired: float = a.facing if heading == null else heading
	var turn_rate := absf(rad_to_deg(angle_difference(a.aim_heading, desired))) / maxf(dt, 0.000001) if a.aim_has_heading else 0.0
	a.aim_heading = desired
	a.aim_has_heading = true
	SCCombat.advance_aim(a, dt, tracking, a.position.distance_to(a.previous_position) / maxf(dt, 0.000001), turn_rate)


func combat(a, dt: float):
	if not a.armed:
		SCCombat.stop_firing(a)
		return
	if not a.alive or a.stunned > 0 or a.current_action != null:
		SCCombat.stop_firing(a)
		update_aim(a, dt, false)
		return
	if planner.micro_controls_motion(a):
		SCCombat.stop_firing(a)
		a.reaction = 0.0
		a.aim_target_id = null
		a.fire_reason = "微操优先"
		update_aim(a, dt, false)
		return
	var explicit = (
		a.queue[0].target_id if not a.queue.is_empty() and a.queue[0].kind == "attack" else null
	)
	if a.fire_mode == "hold_fire" and explicit == null:
		SCCombat.stop_firing(a)
		update_aim(a, dt, false)
		return
	var candidates = visible_targets(a)
	if explicit != null:
		var chosen = actor(explicit)
		candidates=[chosen] if chosen!=null and chosen.alive and a.recognized.has(explicit) and perception.point_visible(self,a,chosen.position) else []
	if candidates.is_empty():
		SCCombat.stop_firing(a)
		a.reaction = 0.0
		a.aim_target_id = null
		a.fire_reason = "警戒"
		update_aim(a, dt, false)
		return
	candidates.sort_custom(
		func(x, y):
			var hx = time - a.recent_attackers.get(x.id, -100.0) < 0.5
			var hy = time - a.recent_attackers.get(y.id, -100.0) < 0.5
			if hx != hy:
				return hx
			var dx = a.position.distance_to(x.position)
			var dy = a.position.distance_to(y.position)
			return dx < dy or dx == dy and x.id < y.id
	)
	var target = candidates[0]
	if a.aim_target_id != target.id:
		SCCombat.stop_firing(a)
		a.aim_target_id = target.id
		a.reaction = 0.0
		a.aim_progress *= a.capabilities.values.switch_retention
	a.reaction += dt
	if a.mode != "standing":
		SCCombat.stop_firing(a)
		update_aim(a, dt, false)
		return
	var desired = (target.position - a.position).angle()
	face(a, desired, dt)
	update_aim(a, dt, true, desired)
	if absf(angle_difference(a.facing, desired)) > 0.087267:
		SCCombat.stop_firing(a)
		return
	if a.reaction < a.reaction_seconds or a.aim_progress < a.capabilities.values.minimum_fire_progress:
		SCCombat.stop_firing(a)
		return
	if a.weapon.definition.attack_category!="kinetic":
		attack(a,target)
		return
	if a.position.distance_to(target.position) > a.weapon.definition.range:
		SCCombat.stop_firing(a)
		return
	if a.weapon.definition.attack_category=="kinetic" and a.weapon.ammo == 0:
		SCCombat.stop_firing(a)
		if a.weapon.reserve_ammo > 0:
			start_action(
				a,
				"reload",
				a.weapon.definition.reload_time,
				"auto:%d:%d" % [a.id, tick_index],
				{"item": a.weapon.definition.item.id}
			)
		else:
			a.fire_reason = "弹药耗尽"
		return
	if SCCombat.projectile_obstruction(grid,a.position,target.position,a.muzzle_height,target.height*target.definition.chest_height_fraction,a.weapon.ammunition.penetration)!=null:
		SCCombat.stop_firing(a)
		a.fire_reason = "射线被遮挡"
		return
	for other in actors:
		if other.id == a.id or not other.alive or not friendly(other,a):
			continue
		var distance = SCCombat.segment_distance(other.position, a.position, target.position)
		if distance[1] > 0 and distance[1] < 1 and distance[0] <= other.radius + 0.1:
			SCCombat.stop_firing(a)
			a.fire_reason = "友军挡线"
			return
	a.fire_reason = "交战"
	if not a.capabilities.permissions.can_aim:
		SCCombat.stop_firing(a)
		return
	if not SCWeaponRules.can_attack(a): return
	var event = SCCombat.create_shot(a, target.position, target.height * target.definition.chest_height_fraction, rng)
	SCSkills.award(a,"shooting",SCData.catalog.skills.experience.shooting_per_shot,"%s:shot:%d:%d" % [a.identity,tick_index,a.weapon.shots_fired])
	shots.append(event)
	emit_sound(a.position, a.team, a.weapon.definition.gunshot_radius, a.weapon.definition.category)
	

func process_shot(event: Dictionary):
	var a = actor(event.shooter_id)
	if event.hit_actor_id != null:
		var hit = actor(event.hit_actor_id)
		receive_attack(hit, event, a, true)
		if hit.team == a.team and is_controlled(a):
			stats.friendly_hits += 1
		if is_controlled(hit) or perception.player_visible.has(hit.id):
			audio_events.append("hit")
	for id in event.near_misses:
		receive_attack(actor(id), event, a)


func emit_sound(pos: Vector2, team: String, radius: float, kind: String):
	var event = {
		"position": pos,
		"team": team,
		"radius": radius,
		"timer": 2.0,
		"kind": kind,
		"audible": false,
		"area": Vector2i.ZERO
	}
	perception.hear(self, event)
	sounds.append(event)
	if event.audible:
		audio_events.append(kind)


func start_action(
	a, kind: String, duration: float, token: String, options: Dictionary = {}
) -> String:
	if not a.alive:
		return "执行者死亡"
	if a.stunned > 0:
		return "等待震撼结束"
	if a.mode != "standing" or a.current_action != null:
		return "执行者尚未站定"
	if a.operation_rate(kind) <= 0.0:
		return "操作部件已失效"
	var part = null
	var cell = options.get("cell")
	if kind in ["search_loot", "transfer_item", "drop_item", "equip_item"]:
		var error = loot.action_error(
			a, kind, token, options.get("object_id"), options.get("cargo_id")
		)
		if not error.is_empty():
			return error
	if kind == "reload":
		if a.weapon.definition.attack_category!="kinetic": return "该武器不使用弹药"
		if a.weapon.reserve_ammo <= 0:
			return "储备弹药耗尽"
		duration = a.weapon.definition.reload_time
	if kind == "bandage":
		part = a.treatment_part()
		if part == null:
			return "没有可治疗伤口"
	if kind in ["bandage", "throw_grenade"] and not a.reservations.has(token):
		return "物品未预约"
	if kind == "throw_grenade":
		var error = planner.throw_error(a, options.item, cell, null, grid.zone_id(cell))
		if not error.is_empty():
			return error
	if kind in ["open_door", "kick_door"]:
		if cell == null:
			return "缺少门目标"
		var edge = grid.edge_between(a.occupied_cell, cell)
		if edge == null or edge.interactive_id == null:
			return "不在门边"
		if options.get("door") != null and edge.interactive_id != options.door:
			return "门目标不匹配"
	SCCombat.stop_firing(a)
	skill_registry.sequence += 1
	a.current_action = {
		"type": kind,
		"duration": duration,
		"timer": 0.0,
		"experience_id": "%s:action:%d" % [a.identity,skill_registry.sequence],
		"learners": SCSkills.learners(a),
		"sia_learning": a.control_mode == "sia",
		"target_position": SCData.center(cell) if cell != null else null,
		"door_id": options.get("door"),
		"item_id": options.get("item"),
		"part_id": part,
		"owner_token": token,
		"refill":
		mini(int(a.weapon.definition.magazine_size - a.weapon.ammo), int(a.weapon.reserve_ammo)) if a.weapon.definition.attack_category=="kinetic" else 0,
		"object_id": options.get("object_id"),
		"cargo_id": options.get("cargo_id")
	}
	a.mode = "acting"
	a.clear_movement()
	if kind == "reload":
		audio_events.append("reload")
	return ""


func interrupt(a, reason: String):
	if a.current_action == null:
		return
	if a.current_action.owner_token.begins_with("auto:"):
		a.current_action = null
		if a.alive:
			a.mode = "standing"
		return
	planner.suspend_actor(a, reason)


func update_action(a, dt: float):
	if not a.alive or a.stunned > 0:
		return
	var action = a.current_action
	action.timer = minf(action.duration, action.timer + dt * a.operation_rate(action.type))
	if action.timer + 0.000000001 < action.duration:
		return
	var token = action.owner_token
	var kind = action.type
	if kind in ["search_loot", "transfer_item", "drop_item", "equip_item"]:
		var error = loot.complete_action(a, action)
		if not error.is_empty():
			interrupt(a, error)
			return
	elif kind == "reload":
		var refill = mini(
			action.refill,
			mini(int(a.weapon.reserve_ammo), int(a.weapon.definition.magazine_size - a.weapon.ammo))
		)
		a.weapon.ammo += refill
		a.weapon.reserve_ammo -= refill
	elif kind == "bandage":
		var part = a.parts.get(action.part_id)
		if part == null or part.hp <= 0 or part.hp >= part.definition.max_hp:
			interrupt(a, "治疗部位失效")
			return
		if not a.consume(token):
			interrupt(a, "物品不足")
			return
		part.hp = minf(part.definition.max_hp, part.hp + 22.0)
		a.invalidate_body(part.definition.region)
		a.refresh_capabilities(time)
		item_used(a, action.item_id)
	elif kind == "throw_grenade":
		var cell = SCData.cell_of(action.target_position)
		var error = planner.throw_error(a, action.item_id, cell, null, grid.zone_id(cell))
		if not error.is_empty():
			interrupt(a, error)
			return
		if not a.consume(token):
			interrupt(a, "物品不足")
			return
		projectiles.append(
			{
				"start": a.position,
				"end": action.target_position,
				"release": time,
				"explode_at": time + 1.0,
				"item": action.item_id,
				"radius": SCData.use_for(action.item_id).radius,
				"team": a.team,
				"actor": a.id
			}
		)
		for task in planner.tasks.values():
			if task.token == token:
				task.flash_released = true
				task.blast_at = time + 1.15
		item_used(a, action.item_id)
	elif kind in ["open_door", "kick_door"]:
		var dest = SCData.cell_of(action.target_position)
		var f = grid.edge_between(a.occupied_cell, dest)
		if f == null or f.interactive_id == null:
			interrupt(a, "门目标失效")
			return
		if door_state(f.interactive_id) == "locked" and kind != "kick_door":
			interrupt(a, "门已锁")
			return
		grid.open_door(f.interactive_id, kind == "kick_door")
		if is_controlled(a):
			perception.doors[f.interactive_id] = door_state(f.interactive_id)
		emit_sound(
			a.position,
			a.team,
			8.0 if kind == "kick_door" else 3.0,
			"kick" if kind == "kick_door" else "door"
		)
	a.current_action = null
	if a.alive:
		a.mode = "standing"
	if not token.is_empty() and not token.begins_with("auto:"):
		completed[token] = true


func item_used(a, item: String):
	if is_controlled(a):
		stats.items[item] = stats.items.get(item, 0) + 1


func flash(projectile: Dictionary):
	var pos = projectile.end
	var radius = projectile.radius
	explosions.append({"position": pos, "radius": radius, "timer": 0.45, "duration": 0.45})
	emit_sound(pos, projectile.team, 12, "flash")
	for a in actors:
		var distance = a.position.distance_to(pos)
		if (
			not a.alive
			or distance > radius
			or grid.raycast(pos, a.position, 1.65, 1.65, "flash")[1] != null
		):
			continue
		var front = (
			distance < 0.0000001
			or absf(angle_difference(a.facing, (pos - a.position).angle())) <= PI / 3
		)
		activate_actor(a)
		a.stunned = maxf(a.stunned, 2.5 if front else 0.8)
		a.refresh_capabilities(time)
		actor_state_changed(a)
		a.reaction = 0.0
		a.aim_progress = 0.0
		interrupt(a, "受到闪光震撼")
		if is_controlled(a) and projectile.team == a.team:
			stats.friendly_stuns += 1



func attack(shooter: SCActor, target: SCActor) -> String:
	if not shooter.armed: return "没有装备武器"
	activate_actor(shooter)
	activate_actor(target)
	if shooter.world!=self or target.world!=self: return "角色不在当前世界"
	if shooter.position.distance_to(target.position)>shooter.weapon.definition.range: return "超出攻击距离"
	if shooter.weapon.definition.attack_category=="thermal":
		SCWeaponRules.begin_trigger(shooter,true)
		if shooter.weapon.startup_elapsed<shooter.weapon.definition.startup_seconds: return "启动中"
	if not SCWeaponRules.can_attack(shooter): return "武器当前不可用"
	if shooter.weapon.definition.attack_category=="kinetic":
		shots.append(SCCombat.create_shot(shooter,target.position,target.height*.7,rng))
	elif shooter.weapon.definition.attack_category=="melee":
		SCWeaponRules.consume(shooter)
		shooter.weapon.action={"kind":"melee","target":target,"elapsed":0.0,"remaining":shooter.weapon.definition.fire_interval,"hit":false}
	else:
		SCWeaponRules.consume(shooter)
		resolve_attack(shooter,target)
	return ""

func resolve_attack(shooter: SCActor, target: SCActor) -> Dictionary:
	var profile := SCWeaponRules.attack_profile(shooter.weapon)
	if shooter.position.distance_to(target.position)>shooter.weapon.definition.range: return {"damage":0.0,"reason":"超出攻击距离"}
	var origin := Vector3(shooter.position.x,shooter.muzzle_height,shooter.position.y)
	var aim := Vector3(target.position.x,target.height*.7,target.position.y)
	var width := SCCombat.weapon_accuracy(shooter.weapon)
	var direction := SCCombat.shot_direction(aim-origin,SCCombat.holding_error(shooter)+SCCombat.scatter(width,rng)) if profile.category=="thermal" else (aim-origin).normalized()
	var finish: Vector3 = origin+direction*shooter.weapon.definition.range
	var hit := grid.raycast(shooter.position,Vector2(finish.x,finish.z),origin.y,finish.y,"projectile")
	var best: float = hit[0]
	var victim: SCActor
	for other in projectile_candidates(shooter.position,Vector2(finish.x,finish.z)):
		if other==shooter: continue
		var fraction := SCCombat.cylinder_hit_fraction(shooter.position,Vector2(finish.x,finish.z),origin.y,finish.y,other.position,other.position,other.radius,0,entities[other.identity].height())
		if fraction>=0 and fraction<best: best=fraction; victim=other
	if victim==null: return {"damage":0.0,"reason":"未命中"}
	return victim.resolve_hit(SCCombat.body_region(lerpf(origin.y,finish.y,best),victim,rng),profile.damage,rng,profile.category,profile.penetration)


func controlled_movement(character: SCActor, input: Vector2, desired_facing: float, dt: float) -> Dictionary:
	var before_facing := character.facing
	if paused or dt<=0: return {"angle":0.0,"speed_factor":1.0,"before_facing":before_facing}
	if not character.capabilities.permissions.can_move:
		character.velocity=Vector2.ZERO
		return {"angle":0.0,"speed_factor":0.0,"before_facing":before_facing}
	character.facing=rotate_toward(character.facing,desired_facing,character.turn_speed*dt)
	var angle := absf(angle_difference(character.facing,input.angle())) if input.length_squared()>0 else 0.0
	var factor := SCData.angle_speed(character.capabilities.values.move_angle_curve,angle)
	character.velocity=character.velocity.move_toward(input.limit_length()*character.speed*factor,dt*character.capabilities.values.acceleration_mps2)
	var before := character.position
	move_actor(character,character.velocity*dt)
	character.velocity=(character.position-before)/dt
	return {"angle":angle,"speed_factor":factor,"before_facing":before_facing}


func is_controlled(character) -> bool:
	return character!=null and controlled_ids.has(character.id)


func relation(a, b) -> String:
	if a==null or b==null: return "neutral"
	if a.team==b.team: return "friendly"
	var relations: Dictionary=scene_definition.get("faction_relations",{})
	return str(relations.get(a.team,{}).get(b.team,relations.get(b.team,{}).get(a.team,"neutral")))


func hostile(a, b) -> bool:
	return relation(a,b)=="hostile"


func friendly(a, b) -> bool:
	return relation(a,b)=="friendly"


func actor_visible(character) -> bool:
	return is_controlled(character) or perception.player_raw.has(character.id)


func _bucket_key(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/8.0),floori(point.y/8.0))


func _refresh_population_index():
	_actor_buckets.clear()
	_largest_view_distance=0.0
	_largest_actor_step=0.0
	_largest_actor_radius=0.0
	for character in actors:
		var key := _bucket_key(character.position)
		if not _actor_buckets.has(key): _actor_buckets[key]=[]
		_actor_buckets[key].append(character)
		_largest_actor_step=maxf(_largest_actor_step,character.position.distance_to(character.previous_position))
		_largest_actor_radius=maxf(_largest_actor_radius,character.radius)
		if character.alive: _largest_view_distance=maxf(_largest_view_distance,character.view_distance)


func actors_near(point: Vector2, radius: float) -> Array:
	var result: Array = []
	var lo := _bucket_key(point-Vector2.ONE*radius)
	var hi := _bucket_key(point+Vector2.ONE*radius)
	var squared := radius*radius
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			for character in _actor_buckets.get(Vector2i(x,y),[]):
				if character.position.distance_squared_to(point)<=squared: result.append(character)
	result.sort_custom(func(a,b): return _actor_order[a.id]<_actor_order[b.id])
	return result


func projectile_candidates(start: Vector2, finish: Vector2) -> Array:
	return actors_near((start+finish)*.5,start.distance_to(finish)*.5+_largest_actor_step+_largest_actor_radius+.2)


func activate_actor(character):
	if character==null: return
	for member in squads.get(character.squad_id,[character]):
		if not member.simulation_detail and _phase>=4: member.detail_ready_tick=tick_index+1
		member.simulation_detail=true
		member.detail_until=maxf(member.detail_until,time+2.0)
		member.refresh_capabilities(time)
		_detail_needed[member.id]=true


func actor_state_changed(character):
	_contact_dirty=true
	if grid!=null and entities.has(character.identity): grid.update_actor(entities[character.identity])


func _refresh_detail_requirements():
	_contact_dirty=false
	_detail_needed.clear()
	for character in actors:
		if not character.alive: continue
		var locked: bool = is_controlled(character) or character.current_action!=null or not character.equipment_action.is_empty() or not character.weapon.action.is_empty() or character.stunned>0 or character.under_fire_timer>time or character.heard_timer>time
		if locked: activate_actor(character)
		var radius: float = maxf(character.view_distance,_largest_view_distance)+maxf(1.0,character.speed)*.2+character.radius*2
		for other in actors_near(character.position,radius):
			if other==character or not other.alive or other.squad_id==character.squad_id: continue
			var distance: float = character.position.distance_to(other.position)
			var reach: float = character.radius+other.radius+.3+(character.speed+other.speed)*.2
			if hostile(character,other): reach=maxf(reach,maxf(character.view_distance,other.view_distance)+(character.speed+other.speed)*.2)
			elif is_controlled(character): reach=maxf(reach,character.view_distance+(character.speed+other.speed)*.2)
			elif is_controlled(other): reach=maxf(reach,other.view_distance+(character.speed+other.speed)*.2)
			if distance<=reach:
				activate_actor(character)
				activate_actor(other)
		if not character.queue.is_empty() and character.queue[0].kind not in ["move","move_face","face","guard"]: activate_actor(character)


func _finish_detail_handoffs():
	active_detail_count=0
	active_combat_count=0
	for members in squads.values():
		var can_exit := true
		for member in members:
			if is_controlled(member) or _detail_needed.has(member.id) or member.detail_until>time or member.current_action!=null or not member.equipment_action.is_empty() or not member.weapon.action.is_empty(): can_exit=false
		if can_exit:
			for member in members:
				member.simulation_detail=false
				SCCombat.stop_firing(member)
		for member in members:
			if member.simulation_detail and member.alive: active_detail_count+=1
			if member.aim_target_id!=null and member.alive: active_combat_count+=1


func _activate_projectile_contacts(shot: Dictionary, dt: float):
	var start: Vector2=shot.end
	var length: float=minf(shot.speed*dt,maxf(0,shot.range-shot.travelled))
	var finish: Vector2=start+shot.direction*shot.horizontal_factor*length
	for character in projectile_candidates(start,finish):
		if character.alive and not character.simulation_detail: activate_actor(character)


func _advance_population_tasks():
	# Abstract actors keep real route progress and occupancy. Decisions and path
	# requests are shared/issued only at arrival or the low-frequency task check.
	for members in squads.values():
		var leader = null
		for member in members:
			if member.alive and not member.patrol.is_empty(): leader=member;break
		if leader==null: continue
		for member in members:
			if not member.alive or is_controlled(member) or member.simulation_detail and member.ai_enabled: continue
			if member.current_action!=null or member.stunned>0 or not member.route.is_empty() or time<member.coarse_wait_until: continue
			if member.patrol.is_empty(): continue
			var target: Vector2i = member.patrol[member.patrol_index%member.patrol.size()]
			if member.position.distance_to(SCData.center(target))<.05:
				member.patrol_index=(member.patrol_index+1)%member.patrol.size()
				member.coarse_wait_until=time+1.0
				continue
			var options := {"known":false,"zone":null}
			var route: Array = []
			if member!=leader and not leader.route.is_empty() and leader.route.size()<=64:
				var offset: Vector2i = target-leader.patrol[leader.patrol_index%leader.patrol.size()]
				var previous = planner.position_cell(member)
				var legal := true
				for point in leader.route:
					var shifted: Vector2i=point+offset
					if shifted==previous: continue
					if not grid.can_move(previous,shifted): legal=false;break
					route.append(shifted);previous=shifted
				if not legal: route.clear()
			if route.is_empty(): route=planner.path(member,target,options)
			if not route.is_empty():
				member.route=route
				member.target_cell=target
				member.reserved_cell=target
				member.guard_angle=(SCData.center(target)-member.position).angle()
				if not member.simulation_detail: member.facing=member.guard_angle
			member.coarse_wait_until=time+1.0
