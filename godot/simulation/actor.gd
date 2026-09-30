class_name SCActor
extends RefCounted

var id: int
var actor_name: String
var team: String
var position: Vector2
var previous_position: Vector2
var facing: float
var weapon: Dictionary
var character_id: String
var definition: Dictionary
var body_definition: Dictionary
var identity: String
var skill_registry: Dictionary
var consciousness: Dictionary = {}
var chip: Dictionary = {}
var pilot = null
var control_mode := "self"
var control: Dictionary = {}
var states: Dictionary = {}
var sources: Array = []
var innate_sources: Array = []
var initial_skills: Dictionary
var ability_time := 0.0
var ability_revision := 0
var capabilities: Dictionary = {}
var training_enabled := true
var reaction_seconds: float:
	get: return capabilities.values.response_delay_seconds
var parts: Dictionary = {}
var quantities: Dictionary = {"flashbang": 1, "bandage": 1}
var reservations: Dictionary = {}
var cargo: Dictionary = {}
var capacity: float:
	get: return capabilities.values.carry_capacity_kg
var equipped_id: String = ""
var mode: String = "standing"
var occupied_cell = null
var reserved_cell = null
var route: Array = []
var move_from = null
var move_to = null
var move_progress: float = 0.0
var crowd_slow_remaining: float = 0.0
var target_id = null
var target_cell = null
var heard_position = null
var heard_timer: float = 0.0
var under_fire_timer: float = 0.0
var under_fire_angle = null
var response: String = ""
var _current_action = null
var current_action:
	get: return _current_action
	set(value):
		if _current_action != null and value == null and training_enabled:
			var action: Dictionary = _current_action
			if action.type == "bandage" and action.has("experience_id"):
				if SCSkills.settle(skill_registry,action.experience_id,"medicine",action.timer*SCData.catalog.skills.experience.work_per_second,action.learners,action.sia_learning): refresh_capabilities()
		_current_action = value
var aim_target_id = null
var aim_progress := 0.0
var aim_clock := 0.0
var aim_heading := 0.0
var aim_has_heading := false
var fire_mode: String = "aimed_shot"
var fire_reason: String = "警戒"
var radius: float = 0.32
var height: float = 1.8
var eye_height: float = 1.65
var muzzle_height: float = 1.35
var speed: float:
	get: return capabilities.values.move_speed_mps
var turn_speed: float:
	get: return capabilities.values.turn_speed_radps
var view_distance: float:
	get: return capabilities.values.view_distance_m
var view_angle: float:
	get: return capabilities.values.view_angle_rad
var stunned: float = 0.0
var guard_angle = null
var guard_explicit: bool = false
var visible: Dictionary = {}
var recognized: Dictionary = {}
var identification: Dictionary = {}
var memory: Dictionary = {}
var reaction: float = 0.0
var recent_attackers: Dictionary = {}
var last_known_timer: float = 0.0
var ai_state: String = "guard"
var ai_enabled: bool = false
var home_cell = null
var home_angle: float = 0.0
var patrol: Array = []
var patrol_index: int = 0
var ai_goal = null
var ai_until: float = 0.0
var ai_wait: float = 0.0
var report_time: float = -1.0
var queue: Array = []
var blocked_reason: String = ""
var hit_flash: float = 0.0
var death_anchor = null
var turn_tick: int = -1
var turn_used: float = 0.0

var alive: bool:
	get:
		return mode != "dead" and not body_dead()


func _init(
	identity: int = 0,
	label: String = "",
	faction: String = "red",
	pos: Vector2 = Vector2.ZERO,
	angle: float = 0.0,
	unit_template: String = "operator",
	registry: Dictionary = {}
):
	id = identity
	skill_registry = SCSkills.registry() if registry.is_empty() else registry
	skill_registry.sequence += 1
	self.identity = "actor:%d:%d" % [id,skill_registry.sequence]
	actor_name = label
	team = faction
	position = pos
	previous_position = pos
	facing = angle
	occupied_cell = SCData.cell_of(pos)
	guard_angle = angle
	var template: Dictionary = SCData.catalog.units[unit_template]
	initial_skills = template.skills.duplicate(true)
	configure_character(template.character)
	for source_id in template.sources: add_source(source_id)
	quantities = template.items.duplicate(true)
	weapon = SCData.weapon(template.weapon, -1, int(template.reserve_ammo))


func configure_character(kind: String):
	character_id = kind
	definition = SCData.catalog.characters[kind].duplicate(true)
	body_definition = SCData.catalog.bodies[definition.body].duplicate(true)
	radius = definition.radius_m
	height = definition.height_m
	eye_height = definition.eye_height_m
	muzzle_height = definition.muzzle_height_m
	aim_progress = 0.0
	aim_clock = 0.0
	aim_has_heading = false
	states = definition.state_defaults.duplicate(true)
	parts.clear()
	for region in body_definition.regions:
		for spec in region.parts:
			var part_definition: Dictionary = spec.duplicate(true)
			SCAbilityRules.freeze(part_definition)
			parts[spec.id] = {"definition":part_definition,"hp":float(spec.max_hp),"instance_id":identity+":part:"+kind+":"+spec.id,"installed_at":ability_time}
	var attributes := {}
	for key in SCAbilityRules.MIND_ATTRIBUTES[definition.species]: attributes[key] = definition.attributes[key]
	consciousness = {}
	chip = {}
	pilot = null
	control = {}
	control_mode = "inactive" if kind == "robot" else "self"
	if kind != "robot":
		var mind_id := identity+":mind:"+kind
		if not skill_registry.consciousness.has(mind_id): skill_registry.consciousness[mind_id] = SCSkills.holder("consciousness",mind_id,definition.species,attributes,initial_skills)
		consciousness = skill_registry.consciousness[mind_id]
	else:
		var chip_id := identity+":chip"
		if not skill_registry.chips.has(chip_id):
			var xp := initial_skills.duplicate(true)
			xp.psionics = 0.0
			xp.sia_control = 0.0
			skill_registry.chips[chip_id] = SCSkills.holder("chip",chip_id,"robot",{},xp)
		chip = skill_registry.chips[chip_id]
	innate_sources.clear()
	for attr in definition.recipes:
		for slot in definition.recipes[attr]:
			if slot != "innate": continue
			var entry := SCAbilityRules.contribution(attr,"attribute",attr,definition.attributes[attr]*definition.recipes[attr][slot],"base")
			var source := SCAbilityRules.source(identity+":innate:"+attr,"actor",identity,"innate","body",[entry])
			SCAbilityRules.freeze(source)
			innate_sources.append(source)
	SCAbilityRules.freeze(definition)
	SCAbilityRules.freeze(body_definition)
	refresh_capabilities()


func parts_by_instance() -> Dictionary:
	var result := {}
	for part in parts.values(): result[part.instance_id] = part
	return result


func body_sources() -> Array:
	var result: Array = innate_sources.duplicate()
	for attr in definition.recipes:
		for slot in definition.recipes[attr]:
			if slot == "innate" or not parts.has(slot): continue
			var part: Dictionary = parts[slot]
			var entry := SCAbilityRules.contribution(attr,"attribute",attr,part.definition.attributes[attr]*definition.recipes[attr][slot],"base")
			result.append(SCAbilityRules.source(part.instance_id+":"+attr,"part",part.instance_id,"structural_part","body",[entry]))
	for source in sources:
		if source.scope == "body": result.append(source)
	for part in parts.values():
		for source_id in part.definition.bonus_sources:
			result.append(SCAbilityRules.instantiate_source(source_id,part.instance_id+":bonus:"+source_id,"part",part.instance_id,part.installed_at))
	return result


func controller() -> Dictionary:
	if control_mode == "self": return consciousness
	if control_mode == "sia" and pilot != null and pilot.definition.species == "human" and pilot.control_mode == "self" and pilot.alive and pilot.stunned<=0:
		return pilot.consciousness
	return {}


func control_sources() -> Array:
	var person := controller()
	if person.is_empty(): return []
	var result: Array = person.sources.duplicate()
	var owner = self if control_mode == "self" else pilot
	for source in owner.sources:
		if source.scope == "controller": result.append(source)
	return result


func bind_controller(operator, connection: Dictionary) -> bool:
	if definition.species == "human" or operator == null or operator.definition.species != "human" or operator.control_mode != "self" or not operator.alive: return false
	if not is_same(skill_registry,operator.skill_registry): return false
	for key in ["connected","quality","latency","sync_base","sync_ceiling"]:
		if not connection.has(key): return false
	if not connection.connected is bool: return false
	for key in ["quality","latency","sync_base","sync_ceiling"]:
		if not (connection[key] is int or connection[key] is float): return false
	for key in ["quality","sync_base","sync_ceiling"]:
		if not is_finite(float(connection[key])) or connection[key]<0 or connection[key]>1: return false
	if connection.sync_base>connection.sync_ceiling or connection.latency<0 or not is_finite(float(connection.latency)): return false
	pilot = operator
	control = connection.duplicate(true)
	control_mode = "sia"
	aim_progress = 0.0
	refresh_capabilities()
	return true


func add_source(definition_id: String, instance_id := "") -> String:
	if not SCData.catalog.attribute_sources.has(definition_id): return ""
	var spec: Dictionary = SCData.catalog.attribute_sources[definition_id]
	var owner := controller() if spec.scope == "controller" else {}
	if spec.scope == "controller" and owner.is_empty(): return ""
	var destination: Array = sources if owner.is_empty() else owner.sources
	skill_registry.sequence += 1
	var source_id := identity+":source:"+str(skill_registry.sequence) if instance_id.is_empty() else instance_id
	for existing in destination:
		if existing.source_id == source_id: return ""
	var entry := SCAbilityRules.instantiate_source(definition_id,source_id,"actor" if owner.is_empty() else owner.kind,identity if owner.is_empty() else owner.id,ability_time)
	destination.append(entry)
	refresh_capabilities()
	return source_id


func remove_source(source_id: String):
	sources = sources.filter(func(s): return s.source_id != source_id)
	var owner := controller()
	if not owner.is_empty(): owner.sources = owner.sources.filter(func(s): return s.source_id != source_id or s.origin_kind=="innate")
	refresh_capabilities()


func replace_part(slot: String, spec: Dictionary) -> bool:
	var errors := PackedStringArray()
	if not parts.has(slot) or not SCData.fields(spec,{"id":"string","region":"string","max_hp":"positive","hit_weight":"positive","tags":"list","damage_multiplier":"nonnegative","attributes":"dict","bonus_sources":"list"},"replacement",errors): return false
	if spec.id != slot or spec.region != parts[slot].definition.region: return false
	for attr in definition.recipes:
		if definition.recipes[attr].has(slot):
			if not SCData.fields(spec.attributes,{attr:"nonnegative"},"replacement",errors) or spec.attributes[attr]>1000: return false
	for source_id in spec.bonus_sources:
		if not SCData.catalog.attribute_sources.has(source_id): return false
		var source: Dictionary = SCData.catalog.attribute_sources[source_id]
		if source.origin_kind != "part_bonus" or source.scope != "body": return false
	var replacement := spec.duplicate(true)
	SCAbilityRules.freeze(replacement)
	skill_registry.sequence += 1
	parts[slot] = {"definition":replacement,"hp":float(spec.max_hp),"instance_id":identity+":part:"+str(skill_registry.sequence),"installed_at":ability_time}
	refresh_capabilities()
	return true


func refresh_capabilities(at := -1.0):
	if at >= 0: ability_time = at
	capabilities = SCAbilityRules.evaluate(self)
	ability_revision = capabilities.revision


func operation_rate(kind: String) -> float:
	if not capabilities.permissions.can_operate: return 0.0
	match kind:
		"reload": return capabilities.values.reload_rate
		"bandage": return capabilities.values.treatment_rate
		"repair": return capabilities.values.repair_rate
		"hack": return capabilities.values.hacking_rate
	return capabilities.values.manipulation_rate


func region_fraction(region: String) -> float:
	var current = 0.0
	var maximum = 0.0
	for entry in body_definition.regions:
		if entry.id != region: continue
		for spec in entry.parts:
			var part: Dictionary = parts.get(spec.id,{})
			current += part.get("hp",0.0)
			maximum += part.definition.max_hp if not part.is_empty() else spec.max_hp
	return current / maximum if maximum > 0 else 1.0


func body_dead() -> bool:
	for id in body_definition.fatal_parts:
		if not parts.has(id) or parts[id].hp <= 0: return true
	for region in body_definition.fatal_regions:
		if region_fraction(region) <= 0: return true
	return false


func body_function(kind: String) -> float:
	var rule: Dictionary = body_definition.capabilities[kind]
	var total := 0.0
	var weights := 0.0
	for region in rule.regions:
		total += region_fraction(region) * rule.regions[region]
		weights += rule.regions[region]
	return total / weights if weights>0 else 0.0


func treatment_part():
	var found = null
	var missing = 0.0
	for key in parts:
		var p = parts[key]
		var loss = p.definition.max_hp - p.hp
		if (
			"bleeds" in p.definition.tags
			and p.hp > 0
			and (loss > missing or loss == missing and found != null and key < found)
		):
			found = key
			missing = loss
	return found


func resolve_hit(region: String, damage: float, rng: RandomNumberGenerator) -> Dictionary:
	var pool = []
	var total = 0.0
	for p in parts.values():
		if p.definition.region == region:
			pool.append(p)
			total += maxf(0.0, p.definition.hit_weight)
	var roll = rng.randf_range(0.0, total)
	var chosen = pool.back()
	for p in pool:
		roll -= maxf(0.0, p.definition.hit_weight)
		if roll <= 0:
			chosen = p
			break
	var amount = damage * chosen.definition.damage_multiplier
	chosen.hp = maxf(0.0, chosen.hp - amount)
	mark_dead_if_needed()
	refresh_capabilities()
	return {"part_id": chosen.definition.id, "damage": amount}


func mark_dead_if_needed():
	if not body_dead():
		return
	var anchors = []
	for c in [occupied_cell, move_from, move_to]:
		if c != null:
			anchors.append(c)
	anchors.sort_custom(
		func(a, b):
			var da = SCData.center(a).distance_squared_to(position)
			var db = SCData.center(b).distance_squared_to(position)
			return da < db or da == db and SCData.cell_less(a, b)
	)
	if not anchors.is_empty():
		death_anchor = anchors[0]
	mode = "dead"
	occupied_cell = null
	move_from = null
	move_to = null
	move_progress = 0.0
	clear_movement()
	target_id = null
	current_action = null


func clear_movement():
	route.clear()
	reserved_cell = null
	target_cell = null


func available(item: String, releasing: Array = []) -> int:
	var held = 0
	for token in reservations:
		if token not in releasing and reservations[token][0] == item:
			held += reservations[token][1]
	return int(quantities.get(item, 0)) - held


func reserve(token: String, item: String) -> bool:
	if reservations.has(token) or available(item) < 1:
		return false
	reservations[token] = [item, 1]
	return true


func consume(token: String) -> bool:
	if not reservations.has(token):
		return false
	var r = reservations[token]
	if quantities.get(r[0], 0) < r[1]:
		return false
	quantities[r[0]] -= r[1]
	reservations.erase(token)
	return true
