class_name SCWorld
extends RefCounted

var grid: SCGrid
var actors: Array = []
var actor_index: Dictionary = {}
var skill_registry: Dictionary = SCSkills.registry()
var planner: SCPlanner
var perception: SCPerception
var loot: SCLoot
var rng = RandomNumberGenerator.new()
var config: String = "A"
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
var stats: Dictionary = {"rounds": 0, "friendly_hits": 0, "friendly_stuns": 0, "items": {}}


func _init(configuration: String = "A"):
	config = configuration if configuration in ["A", "B", "C"] else "A"
	grid = SCGrid.new()
	grid.create_greyport()
	rng.seed = int(SCData.mission.seeds[config])
	var labels = ["先锋", "侧翼", "支援", "后卫"]
	for i in range(4):
		actors.append(SCActor.new(i + 1, labels[i], "red", Vector2(33.5 + i * 2, 32.5), -PI / 2, SCData.mission.unit_templates.squad, skill_registry))
	var index = 0
	for room in SCData.mission.spawns:
		var count = int(SCData.mission.counts[config][index])
		index += 1
		for i in range(count):
			var spawn = SCData.mission.spawns[room][i]
			var cell = SCData.cell(spawn[0])
			var a = SCActor.new(
				101 + actors.size() - 4, "敌人", "blue", SCData.center(cell), float(spawn[1]), SCData.mission.unit_templates.enemy, skill_registry
			)
			a.home_cell = cell
			a.home_angle = a.facing
			a.ai_enabled = true
			if i == 0 and SCData.mission.patrols.has(room):
				for c in SCData.mission.patrols[room]:
					a.patrol.append(SCData.cell(c))
			a.ai_state = "patrol" if not a.patrol.is_empty() else "guard"
			actors.append(a)
	for a in actors:
		actor_index[a.id] = a
	planner = SCPlanner.new(self)
	perception = SCPerception.new()
	loot = SCLoot.new(self)
	perception.refresh(self, 0.0, true)
	loot.add(
		"case:S",
		"现场补给箱",
		"case",
		Vector2i(35, 31),
		[loot.item("rifle", 1, 17), loot.item("bandage", 2), loot.item("rifle_ammo", 30)]
	)
	var caches = {
		"R": Vector2i(33, 27),
		"O": Vector2i(37, 20),
		"A": Vector2i(35, 11),
		"M": Vector2i(26, 3),
		"W": Vector2i(12, 19),
		"L": Vector2i(8, 27),
		"U": Vector2i(3, 15),
		"N": Vector2i(17, 5)
	}
	for room in caches:
		loot.add(
			"cache:" + room,
			grid.zones[room].label + "物资柜",
			"container",
			caches[room],
			[
				loot.item("intel" if room == "A" else "parts"),
				loot.item("bandage"),
				loot.item("rifle_ammo", 20)
			]
		)
	loot.add("drop:S", "地面物品", "ground", Vector2i(37, 31), [loot.item("flashbang")])
	loot.refresh()


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
	if paused or winner != null:
		return
	var step = 1.0 / 60.0
	accumulator += maxf(0.0, dt)
	var count = 0
	while accumulator + 0.000000001 >= step and count < 5 and not paused and winner == null:
		accumulator -= step
		tick(step)
		count += 1
	if accumulator >= step:
		var remainder = fmod(accumulator, step)
		discarded_time += accumulator - remainder
		accumulator = remainder


func tick(dt: float):
	time += dt
	tick_index += 1
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
		a.weapon.cooldown = maxf(0.0, a.weapon.cooldown - dt)
		a.stunned = maxf(0.0, a.stunned - dt)
		a.refresh_capabilities(time)
		SCCombat.advance_recoil(a, dt)
		a.hit_flash = maxf(0.0, a.hit_flash - dt)
		if a.current_action != null:
			if (
				planner.micro_controls_motion(a)
				and a.current_action.owner_token.begins_with("auto:")
			):
				interrupt(a, "微操接管自动换弹")
			else:
				update_action(a, dt)
	for i in range(projectiles.size() - 1, -1, -1):
		if time >= projectiles[i].explode_at:
			flash(projectiles[i])
			projectiles.remove_at(i)
	perception.refresh(self, dt)
	loot.refresh()
	if tick_index % 6 == 0:
		for a in actors:
			if a.ai_enabled:
				SCPerception.update_enemy(self, a)
	planner.tick(dt)
	for a in actors:
		if a.alive and a.team == "red" and has_threat(a) and not planner.micro_controls_motion(a):
			a.clear_movement()
	var distances = SCMovement.allowances(actors, grid, dt)
	for a in actors:
		if not a.alive:
			continue
		if a.current_action == null:
			var before = a.position
			SCMovement.update(a, grid, actors, dt, distances[a.id])
			observe(a, dt, a.position - before)
	perception.refresh(self, 0.0)
	for shot in shots:
		if not shot.finished:
			SCCombat.advance_shot(shot, dt, grid, actors, rng)
			process_shot(shot)
	for a in actors:
		combat(a, dt)
	for a in actors:
		if not a.alive and not deaths_processed.has(a.id):
			deaths_processed[a.id] = true
			planner.cancel_actor(a)
			loot.corpse(a)
			if a.team == "red":
				message("%d %s 阵亡" % [a.id, a.actor_name], "hit")
				pause_requested = true
	check_winner()
	if pause_requested and winner == null:
		set_paused(true)
	pause_requested = false
	if audio_events.size() > 64:
		audio_events = audio_events.slice(audio_events.size() - 64)


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
		a.team == "red"
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
	a.recent_attackers[attacker.id] = time
	var was_under_fire = a.under_fire_timer > time
	var known = (
		perception.player_visible.has(attacker.id)
		if a.team == "red"
		else a.visible.has(attacker.id) and a.recognized.has(attacker.id)
	)
	var friendly = (
		attacker.team == a.team
		and (a.team == "red" or perception.point_visible(self, a, attacker.position))
	)
	var unknown = not known and not friendly
	if (
		unknown
		or (
			attacker.team != a.team
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
		if a.team == "red" and not already:
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
	if not a.alive or a.stunned > 0 or a.current_action != null:
		update_aim(a, dt, false)
		return
	if planner.micro_controls_motion(a):
		a.reaction = 0.0
		a.aim_target_id = null
		a.fire_reason = "微操优先"
		update_aim(a, dt, false)
		return
	var explicit = (
		a.queue[0].target_id if not a.queue.is_empty() and a.queue[0].kind == "attack" else null
	)
	if a.fire_mode == "hold_fire" and explicit == null:
		update_aim(a, dt, false)
		return
	var candidates = visible_targets(a)
	if explicit != null:
		candidates = candidates.filter(func(t): return t.id == explicit)
	if candidates.is_empty():
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
		a.aim_target_id = target.id
		a.reaction = 0.0
		a.aim_progress *= a.capabilities.values.switch_retention
	a.reaction += dt
	if a.mode != "standing":
		update_aim(a, dt, false)
		return
	var desired = (target.position - a.position).angle()
	face(a, desired, dt)
	update_aim(a, dt, true, desired)
	if absf(angle_difference(a.facing, desired)) > 0.087267:
		return
	if a.reaction < a.reaction_seconds or a.aim_progress < a.capabilities.values.minimum_fire_progress:
		return
	if a.position.distance_to(target.position) > a.weapon.definition.range:
		return
	if a.weapon.ammo == 0:
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
	if a.weapon.cooldown > 0:
		return
	if grid.raycast(a.position, target.position, a.muzzle_height, target.height * target.definition.chest_height_fraction, "projectile")[1] != null:
		a.fire_reason = "射线被遮挡"
		return
	for other in actors:
		if other.id == a.id or not other.alive or other.team != a.team:
			continue
		var distance = SCCombat.segment_distance(other.position, a.position, target.position)
		if distance[1] > 0 and distance[1] < 1 and distance[0] <= other.radius + 0.1:
			a.fire_reason = "友军挡线"
			return
	a.fire_reason = "交战"
	if not a.capabilities.permissions.can_aim: return
	var event = SCCombat.create_shot(a, target.position, target.height * target.definition.chest_height_fraction, rng)
	SCSkills.award(a,"shooting",SCData.catalog.skills.experience.shooting_per_shot,"%s:shot:%d:%d" % [a.identity,tick_index,a.weapon.shots_fired])
	shots.append(event)
	emit_sound(a.position, a.team, a.weapon.definition.gunshot_radius, a.weapon.definition.category)
	if a.team == "red":
		stats.rounds += 1
	

func process_shot(event: Dictionary):
	var a = actor(event.shooter_id)
	if event.hit_actor_id != null:
		var hit = actor(event.hit_actor_id)
		receive_attack(hit, event, a, true)
		if hit.team == a.team and a.team == "red":
			stats.friendly_hits += 1
		if hit.team == "red" or perception.player_visible.has(hit.id):
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
		mini(int(a.weapon.definition.magazine_size - a.weapon.ammo), int(a.weapon.reserve_ammo)),
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
		if a.team == "red":
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
	if a.team == "red":
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
		a.stunned = maxf(a.stunned, 2.5 if front else 0.8)
		a.reaction = 0.0
		a.aim_progress = 0.0
		interrupt(a, "受到闪光震撼")
		if a.team == "red" and projectile.team == "red":
			stats.friendly_stuns += 1


func check_winner():
	var red = actors.any(func(a): return a.alive and a.team == "red")
	var blue = actors.any(func(a): return a.alive and a.team == "blue")
	if not red:
		winner = "blue"
	elif not blue and not combat_cleared:
		winner = "red"
	if winner != null:
		message(
			"任务完成 · 全部敌人已消灭" if winner == "red" else "任务失败 · 小队全灭",
			"ready" if winner == "red" else "reject"
		)


func continue_looting():
	if winner != "red":
		return
	combat_cleared = true
	winner = null
	set_paused(true)
	message("威胁清除 · 可以继续搜索和整理携带物品")
