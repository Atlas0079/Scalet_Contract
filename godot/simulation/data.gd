class_name SCData
extends RefCounted

static var errors: PackedStringArray = []
static var catalog: Dictionary = load_catalog()
static var mission: Dictionary = read_document("res://data/greyport.json")
static var study: Dictionary = read_document("res://data/tactical_study.json")


static func read_document(path: String) -> Dictionary:
	var json := JSON.new()
	var error := json.parse(FileAccess.get_file_as_string(path))
	if error != OK or not json.data is Dictionary:
		errors.append("%s:%d %s (expected object)" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data


static func load_catalog() -> Dictionary:
	var result := read_document("res://data/catalog.json")
	for category in ["weapons", "ammunition", "attachments", "characters", "bodies", "presentation", "units", "skills", "attribute_sources"]:
		result[category] = read_document("res://data/%s.json" % category)
	var character_document: Dictionary = result.characters
	result.characters = character_document.get("profiles", {})
	result.ability_rules = character_document.get("rules", {})
	# Item/loot views are derived from the owning definitions, never re-entered.
	if not result.get("items") is Dictionary or not result.get("loot_kinds") is Dictionary: return result
	for id in result.weapons:
		var w = result.weapons[id]
		if not w is Dictionary or not w.get("item") is Dictionary: continue
		if not w.item.has("name") or not w.item.has("mass"): continue
		result.items[id] = {"item": w.item, "order": 10, "uses": [{
			"id": "reload", "label": "换弹", "target": "self", "cost": 0,
			"range": 0.0, "radius": 0.0, "breach": false, "effect": ""
		}]}
		result.loot_kinds[id] = [w.item.name, w.item.mass]
	for id in result.ammunition:
		var a = result.ammunition[id]
		if a is Dictionary and a.has("name") and a.has("mass"):
			result.loot_kinds[id] = [a.name, a.mass]
	return result


static func ensure_valid(tree: SceneTree) -> bool:
	var problems := errors.duplicate()
	problems.append_array(validate(catalog))
	if not mission.get("unit_templates") is Dictionary:
		problems.append("greyport.json.unit_templates: expected object")
	else:
		for key in ["squad", "enemy"]:
			if not catalog.units.has(mission.unit_templates.get(key, "")):
				problems.append("greyport.json.unit_templates.%s: unknown unit" % key)
	if not catalog.units.has(study.get("unit", "")):
		problems.append("tactical_study.json.unit: unknown unit")
	for pair in [["character_choices", "characters"], ["weapon_choices", "weapons"]]:
		if not study.get(pair[0]) is Array or study[pair[0]].is_empty():
			problems.append("tactical_study.json.%s: expected nonempty array" % pair[0])
		else:
			for id in study[pair[0]]:
				if not catalog[pair[1]].has(id): problems.append("tactical_study.json.%s: unknown %s" % [pair[0], id])
	if fields(study.get("target"), {"radius_m":"positive", "height_m":"positive", "aim_heights_m":"array"}, "tactical_study.target", problems):
		for h in study.target.aim_heights_m: fields({"height":h}, {"height":"positive"}, "tactical_study.target.aim_heights_m", problems)
	validate_range(study.get("range"), problems)
	if problems.is_empty():
		var initial: Dictionary = catalog.units[study.unit]
		if not initial.character in study.character_choices or not initial.weapon in study.weapon_choices:
			problems.append("tactical_study.json: choices must include the initial unit's character and weapon")
	if not problems.is_empty():
		for problem in problems: push_error("Configuration: " + problem)
		tree.quit(1)
		return false
	return true


static func fields(value, schema: Dictionary, path: String, problems: PackedStringArray) -> bool:
	var before := problems.size()
	if not value is Dictionary:
		problems.append(path + ": expected object")
		return false
	for key in schema:
		var v = value.get(key)
		var kind: String = schema[key]
		var valid := false
		match kind:
			"color": valid = v is String and Color.html_is_valid(v)
			"string": valid = v is String and not v.is_empty()
			"dict": valid = v is Dictionary
			"array": valid = v is Array and not v.is_empty()
			"list": valid = v is Array
			_:
				if (v is int or v is float) and is_finite(float(v)):
					match kind:
						"positive": valid = v > 0
						"nonnegative": valid = v >= 0
						"integer": valid = v > 0 and v == floor(v)
						"count": valid = v >= 0 and v == floor(v)
						"unit": valid = v >= 0 and v <= 1
		if not valid: problems.append(path + "." + key + ": expected " + kind)
	return problems.size() == before


static func validate(c: Dictionary) -> PackedStringArray:
	var p: PackedStringArray = []
	if not fields(c, {"weapons":"dict", "ammunition":"dict", "attachments":"dict", "characters":"dict", "bodies":"dict", "presentation":"dict", "units":"dict", "skills":"dict", "attribute_sources":"dict", "ability_rules":"dict", "items":"dict", "loot_kinds":"dict"}, "catalog", p): return p
	if not fields(c.presentation, {"weapons":"dict", "characters":"dict", "tracers":"dict"}, "presentation", p): return p
	for id in c.presentation.tracers:
		fields(c.presentation.tracers[id], {"length_m":"positive", "brightness":"unit", "fade_seconds":"positive"}, "presentation.tracers." + id, p)
	for id in c.presentation.characters:
		var v = c.presentation.characters[id]
		if fields(v, {"waist_limit_degrees":"positive", "aim_limit_degrees":"positive", "aim_pitch_limit_degrees":"positive", "style":"dict"}, "presentation.characters." + id, p):
			if v.waist_limit_degrees > 180 or v.aim_limit_degrees > v.waist_limit_degrees or v.aim_pitch_limit_degrees >= 89: p.append("presentation.characters." + id + ": invalid twist limits")
			var path: String = "presentation.characters." + id + ".style"
			if fields(v.style, {"shade_bands":"integer", "shadow_floor":"unit", "outline_pixels":"count", "outline_color":"color", "body_color":"color", "joint_color":"color", "bone_colors":"dict", "shadow":"dict"}, path, p):
				if v.style.shade_bands < 2 or v.style.shade_bands > 4 or v.style.outline_pixels > 2: p.append(path + ": invalid bands or outline width")
				if fields(v.style.shadow, {"color":"color", "opacity":"unit", "offset_pixels":"array"}, path + ".shadow", p):
					coordinates(v.style.shadow.offset_pixels, 2, path + ".shadow.offset_pixels", p)
				for prefix in v.style.bone_colors:
					fields(v.style.bone_colors, {prefix:"color"}, path + ".bone_colors", p)
	for id in c.presentation.weapons:
		var v = c.presentation.weapons[id]
		var path := "presentation.weapons." + str(id)
		if not fields(v, {"rig":"string", "clips":"dict", "casing_socket_source_units":"array", "recoil":"dict", "flash":"dict", "casings":"dict"}, path, p): continue
		if not ResourceLoader.exists(v.rig): p.append(path + ".rig: missing resource")
		fields(v.get("style"), {"color":"color", "flash_strength":"unit"}, path + ".style", p)
		fields(v.clips, {"aim":"string", "reload":"string"}, path + ".clips", p)
		if v.casing_socket_source_units.size() != 3: p.append(path + ".casing_socket_source_units: expected 3 numbers")
		for number in v.casing_socket_source_units:
			if not (number is float or number is int) or not is_finite(float(number)): p.append(path + ".casing_socket_source_units: invalid number")
		fields(v.recoil, {"frequency":"positive", "position_impulse_m":"nonnegative", "velocity_impulse":"nonnegative", "side_impulse":"nonnegative", "max_displacement_m":"positive", "max_side_displacement_m":"positive"}, path + ".recoil", p)
		fields(v.flash, {"life_seconds":"positive", "length_m":"positive", "width_m":"positive"}, path + ".flash", p)
		if fields(v.casings, {"maximum":"integer", "gravity_mps2":"positive", "ejection_min_mps":"positive", "ejection_max_mps":"positive", "fade_start_seconds":"nonnegative", "life_seconds":"positive"}, path + ".casings", p):
			if v.casings.fade_start_seconds >= v.casings.life_seconds or v.casings.ejection_min_mps > v.casings.ejection_max_mps: p.append(path + ".casings: invalid interval")
	for id in c.attachments:
		var v = c.attachments[id]
		if fields(v, {"name":"string", "accuracy_multiplier":"array"}, "attachments." + id, p):
			validate_pair(v.accuracy_multiplier, "attachments." + id + ".accuracy_multiplier", p, 10.0)
	for id in c.ammunition:
		var a = c.ammunition[id]
		if not fields(a, {"name":"string", "mass":"nonnegative", "speed_mps":"positive", "damage":"nonnegative", "tracer_every_n_shots":"integer", "tracer_presentation":"string", "accuracy_degrees":"array"}, "ammunition." + id, p): continue
		validate_pair(a.accuracy_degrees, "ammunition." + id + ".accuracy_degrees", p, 45.0)
		if not c.presentation.tracers.has(a.tracer_presentation): p.append("ammunition." + id + ": unknown tracer presentation")
		if not c.loot_kinds.has(id): p.append("ammunition." + id + ": missing loot definition")
	for id in c.weapons:
		var w = c.weapons[id]
		if not fields(w, {"item":"dict", "ammunition":"string", "presentation":"string", "category":"string", "muzzle_velocity_multiplier":"positive", "fire_interval":"positive", "magazine_size":"integer", "reload_time":"positive", "range":"positive", "gunshot_radius":"positive", "accuracy_degrees":"array", "attachments":"list", "recoil":"dict"}, "weapons." + id, p): continue
		validate_pair(w.accuracy_degrees, "weapons." + id + ".accuracy_degrees", p, 45.0)
		for attachment in w.attachments:
			if not attachment is String or not c.attachments.has(attachment): p.append("weapons." + id + ": unknown attachment")
		if fields(w.recoil, {"impulse_degrees_per_second":"array", "max_offset_degrees":"array", "passive_return_frequency":"positive"}, "weapons." + id + ".recoil", p):
			for key in ["impulse_degrees_per_second", "max_offset_degrees"]:
				validate_pair(w.recoil[key], "weapons." + id + ".recoil." + key, p, 1000.0 if key=="impulse_degrees_per_second" else 89.0)
		fields(w.item, {"id":"string", "name":"string", "mass":"nonnegative"}, "weapons." + id + ".item", p)
		if w.item.get("id") != id: p.append("weapons." + id + ": item ID must match definition key")
		if not c.ammunition.has(w.ammunition): p.append("weapons." + id + ": unknown ammunition")
		if not c.presentation.weapons.has(w.presentation): p.append("weapons." + id + ": unknown presentation")
		if not c.items.has(id) or not c.loot_kinds.has(id): p.append("weapons." + id + ": missing item/loot definition")
	for id in c.bodies:
		validate_body(c.bodies[id], "bodies." + id, p)
	validate_ability_rules(c, p)
	for id in c.characters: validate_character(c.characters[id], "characters."+id, c, p)
	for id in c.attribute_sources: validate_source(c.attribute_sources[id], "attribute_sources."+id, c, p)
	var stack_groups := {}
	for source in c.attribute_sources.values():
		if not source is Dictionary or not source.get("contributions") is Array: continue
		for entry in source.contributions:
			if not entry is Dictionary or not entry.has_all(["stack_group","target_kind","target_id","stack_policy"]): continue
			var signature := [entry.target_kind,entry.target_id,entry.stack_policy,source.get("scope")]
			if stack_groups.has(entry.stack_group) and stack_groups[entry.stack_group]!=signature: p.append("attribute_sources: inconsistent stack group "+str(entry.stack_group))
			stack_groups[entry.stack_group]=signature
	for body in c.bodies.values():
		if not body is Dictionary or not body.get("regions") is Array: continue
		for region in body.regions:
			if not region is Dictionary or not region.get("parts") is Array: continue
			for part in region.parts:
				if not part is Dictionary or not part.get("bonus_sources") is Array: continue
				for source_id in part.bonus_sources:
					var source = c.attribute_sources.get(source_id)
					if not source is Dictionary or source.get("origin_kind")!="part_bonus" or source.get("scope")!="body": p.append("bodies: invalid part bonus "+str(source_id))
	for id in c.units:
		var u = c.units[id]
		if not fields(u, {"character":"string", "weapon":"string", "reserve_ammo":"count", "items":"dict", "skills":"dict", "sources":"list"}, "units." + id, p): continue
		if not c.characters.has(u.character) or not c.weapons.has(u.weapon): p.append("units." + id + ": unknown character/weapon")
		validate_skill_xp(u.skills, "units."+id+".skills", c.skills, p)
		for source_id in u.sources:
			if not c.attribute_sources.has(source_id): p.append("units."+id+": unknown source")
		for item in u.items:
			if not c.items.has(item): p.append("units." + id + ": unknown item " + item)
			fields({"quantity":u.items[item]}, {"quantity":"count"}, "units." + id + ".items." + item, p)
	return p


static func validate_skill_xp(xp: Dictionary, path: String, skills: Dictionary, p: PackedStringArray):
	if not skills.has("definitions") or not skills.has("level"): return
	for key in skills.definitions:
		if fields(xp,{key:"nonnegative"},path,p) and xp[key]>skills.level.xp_max: p.append(path+": XP exceeds maximum")
	for key in xp:
		if not skills.definitions.has(key): p.append(path+": unknown skill "+key)


static func validate_ability_rules(c: Dictionary, p: PackedStringArray):
	var rule: Dictionary = c.ability_rules
	if fields(rule,{"base":"dict","aim":"dict","state":"dict","skill_factor":"dict","sia_factor":"dict","recoil_control":"dict"},"ability_rules",p):
		fields(rule.recoil_control,{"response_delay_seconds":"positive","build_seconds":"positive","max_acceleration_degrees_per_second2":"positive","return_frequency":"positive","memory_decay_seconds":"positive","burst_gap_seconds":"positive"},"ability_rules.recoil_control",p)
		var base_schema := {}
		for key in ["force_n","carry_capacity_kg","move_speed_mps","acceleration_mps2","turn_speed_radps","view_distance_m","response_delay_seconds","aim_gain_per_second"]: base_schema[key] = "positive"
		if fields(rule.base,base_schema,"ability_rules.base",p):
			var first := validate_pair(rule.base.get("aim_unsettled_degrees"),"ability_rules.aim_unsettled_degrees",p,45)
			var second := validate_pair(rule.base.get("aim_settled_degrees"),"ability_rules.aim_settled_degrees",p,45)
			if first and second:
				for axis in range(2):
					if rule.base.aim_settled_degrees[axis]>rule.base.aim_unsettled_degrees[axis]: p.append("ability_rules: settled error exceeds unsettled error")
		fields(rule.aim,{"curve_power":"positive","movement_loss_per_m":"nonnegative","turn_loss_per_degree":"nonnegative","switch_retention":"unit","idle_decay_per_second":"nonnegative","drift_interval_seconds":"positive","minimum_fire_progress":"unit"},"ability_rules.aim",p)
		fields(rule.state,{"fatigue_loss":"unit","heat_loss":"unit","energy_full_threshold":"positive","metabolic_loss":"unit","stress_loss":"unit","pain_loss":"unit"},"ability_rules.state",p)
		for key in ["skill_factor","sia_factor"]: fields(rule[key],{"base":"positive","per_level":"nonnegative"},"ability_rules."+key,p)
	var skills: Dictionary = c.skills
	if not fields(skills,{"definitions":"dict","level":"dict","channels":"dict","experience":"dict","psionic_xp_policy":"dict","sia_synchronization":"dict"},"skills",p): return
	for key in ["shooting","medicine","repair","hacking","sia_control","psionics"]:
		fields(skills.definitions.get(key),{"name":"string"},"skills.definitions."+key,p)
	if fields(skills.level,{"max":"positive","xp_scale":"positive","xp_max":"positive"},"skills.level",p):
		if not is_equal_approx(skills.level.xp_max,skills.level.xp_scale*pow(skills.level.max,2)): p.append("skills.level: XP range and curve disagree")
	for key in ["robot","android"]:
		if fields(skills.channels.get(key),{"controller":"unit","memory":"unit"},"skills.channels."+key,p):
			if not is_equal_approx(skills.channels[key].controller+skills.channels[key].memory,1): p.append("skills.channels: weights must sum to one")
	fields(skills.experience,{"shooting_per_shot":"nonnegative","work_per_second":"nonnegative","sia_extra":"nonnegative"},"skills.experience",p)
	if skills.psionic_xp_policy.get("enabled") != false: p.append("skills.psionic_xp_policy: feature is not implemented")


static func validate_character(a, path: String, c: Dictionary, p: PackedStringArray):
	if not fields(a,{"name":"string","species":"string","rule_id":"string","body":"string","presentation":"string","radius_m":"positive","height_m":"positive","eye_height_m":"positive","view_angle_degrees":"positive","muzzle_height_m":"positive","chest_height_fraction":"unit","attributes":"dict","recipes":"dict","state_defaults":"dict","movement_angle_curve":"array"},path,p): return
	if not SCAbilityRules.BODY_ATTRIBUTES.has(a.species): p.append(path+": unknown species"); return
	if a.rule_id != a.species+"_v1": p.append(path+": unknown rule")
	if not c.bodies.has(a.body) or not c.presentation.characters.has(a.presentation): p.append(path+": unknown body/presentation"); return
	for old in ["speed_mps","capacity_kg","aim","turn_speed_degrees_per_second","acceleration_mps2","view_distance_m"]:
		if a.has(old): p.append(path+": obsolete field "+old)
	if a.eye_height_m>a.height_m or a.muzzle_height_m>a.height_m or a.view_angle_degrees>360 or a.chest_height_fraction<=0: p.append(path+": invalid dimensions")
	var expected: Array = SCAbilityRules.BODY_ATTRIBUTES[a.species]+SCAbilityRules.MIND_ATTRIBUTES[a.species]
	for key in expected:
		if fields(a.attributes,{key:"nonnegative"},path+".attributes",p) and a.attributes[key]>1000: p.append(path+": attribute outside 0..1000")
	for key in a.attributes:
		if not key in expected: p.append(path+": foreign attribute "+key)
	for key in SCAbilityRules.STATES[a.species]: fields(a.state_defaults,{key:"unit"},path+".state_defaults",p)
	for key in a.state_defaults:
		if not key in SCAbilityRules.STATES[a.species]: p.append(path+": foreign state "+key)
	var parts := {}
	for region in c.bodies[a.body].regions:
		for part in region.parts: parts[part.id] = part
	for attr in SCAbilityRules.BODY_ATTRIBUTES[a.species]:
		var recipe = a.recipes.get(attr)
		if not recipe is Dictionary or recipe.is_empty(): p.append(path+": missing recipe "+attr); continue
		for slot in recipe:
			fields(recipe,{slot:"nonnegative"},path+".recipes."+attr,p)
			if slot=="innate": continue
			if not parts.has(slot): p.append(path+": unknown slot "+slot); continue
			if fields(parts[slot].attributes,{attr:"nonnegative"},path+".parts."+slot,p) and parts[slot].attributes[attr]>1000: p.append(path+": part attribute exceeds maximum")
	for key in a.recipes:
		if not key in SCAbilityRules.BODY_ATTRIBUTES[a.species]: p.append(path+": foreign recipe "+key)
	var previous := -1.0
	var valid: bool = a.movement_angle_curve.size()>=2
	for point in a.movement_angle_curve:
		if not point is Array or point.size()!=2: valid=false; break
		if not fields({"angle":point[0],"speed":point[1]},{"angle":"nonnegative","speed":"unit"},path+".movement_angle_curve",p): valid=false; break
		if point[0]<=previous or point[0]>180: valid=false
		previous=point[0]
	if valid: valid=a.movement_angle_curve[0][0]==0 and a.movement_angle_curve.back()[0]==180
	if not valid: p.append(path+": angle curve must ascend from 0 to 180")


static func validate_source(s, path: String, c: Dictionary, p: PackedStringArray):
	if not fields(s,{"name":"string","origin_kind":"string","scope":"string","contributions":"array"},path,p): return
	if not s.origin_kind in ["training","equipment","drug","part_bonus","trait"] or not s.scope in ["body","controller"]: p.append(path+": invalid source origin/scope")
	if not s.has("duration_seconds"): p.append(path+": missing duration")
	elif s.duration_seconds != null: fields(s,{"duration_seconds":"positive"},path,p)
	if s.has("requires_functional") and not s.requires_functional is bool: p.append(path+": requires_functional must be boolean")
	if s.origin_kind=="part_bonus" and not s.has("requires_functional"): p.append(path+": part bonus must declare requires_functional")
	if s.has("durability_curve"):
		var previous := -1.0
		if not s.durability_curve is Array or s.durability_curve.size()<2: p.append(path+": invalid durability curve")
		else:
			for point in s.durability_curve:
				if not validate_pair(point,path+".durability_curve",p,1): continue
				if point[0]<=previous: p.append(path+": durability curve must ascend")
				previous=point[0]
	var ids := {}
	for entry in s.contributions:
		if not fields(entry,{"contribution_id":"string","target_kind":"string","target_id":"string","role":"string","operation":"string","stack_group":"string","stack_policy":"string","priority":"count"},path+".contributions",p): continue
		if ids.has(entry.contribution_id): p.append(path+": duplicate contribution")
		ids[entry.contribution_id]=true
		if entry.role!="bonus" or not entry.operation in ["add","percent","factor"] or not entry.stack_policy in ["stack","exclusive"]: p.append(path+": invalid contribution rule")
		if not (entry.get("value") is int or entry.get("value") is float) or not is_finite(float(entry.value)): p.append(path+": invalid value"); continue
		if entry.operation=="factor" and entry.value<0 or entry.operation=="percent" and entry.value< -1: p.append(path+": invalid multiplier")
		var known := false
		match entry.target_kind:
			"capability": known=entry.target_id in SCAbilityRules.VALUE_KEYS
			"skill": known=c.skills.get("definitions",{}).has(entry.target_id)
			"attribute":
				for species in SCAbilityRules.BODY_ATTRIBUTES:
					if entry.target_id in SCAbilityRules.BODY_ATTRIBUTES[species]+SCAbilityRules.MIND_ATTRIBUTES[species]: known=true
		if not known: p.append(path+": unknown contribution target")


static func validate_pair(value, path: String, problems: PackedStringArray, maximum: float) -> bool:
	if not value is Array or value.size() != 2:
		problems.append(path + ": expected [horizontal, vertical]")
		return false
	var before := problems.size()
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > maximum:
			problems.append(path + ": pair values outside 0.." + str(maximum))
	return before == problems.size()


static func coordinates(value, size: int, path: String, problems: PackedStringArray) -> bool:
	if not value is Array or value.size() != size:
		problems.append(path + ": wrong coordinate count")
		return false
	for n in value:
		if not (n is int or n is float) or not is_finite(float(n)):
			problems.append(path + ": non-finite coordinate")
			return false
	return true


static func validate_range(value, problems: PackedStringArray):
	if not fields(value, {"bounds_m":"array", "lanes":"array", "targets":"array", "obstacles":"list", "impact_lifetime_seconds":"positive", "maximum_impacts":"integer"}, "tactical_study.range", problems): return
	if not coordinates(value.bounds_m, 4, "range.bounds_m", problems): return
	var b: Array = value.bounds_m
	var bounds := Rect2(b[0], b[1], b[2], b[3])
	if b[2] != 28.8 or b[3] != 10.0: problems.append("range.bounds_m: the 40 px/m stage is 28.8 x 10 meters")
	var ids := {}
	for spec in value.targets:
		if not fields(spec, {"id":"string", "label":"string", "position_m":"array"}, "range.targets", problems): continue
		if ids.has(spec.id): problems.append("range.targets: duplicate ID")
		ids[spec.id] = true
		if coordinates(spec.position_m, 2, "range.targets.position_m", problems):
			if not bounds.has_point(Vector2(spec.position_m[0], spec.position_m[1])): problems.append("range.targets: out of bounds")
	if value.lanes.size() != 8: problems.append("range.lanes: expected eight selector lanes")
	for spec in value.lanes:
		if not fields(spec, {"label":"string", "spawn_m":"array", "target":"string"}, "range.lanes", problems): continue
		if not ids.has(spec.target): problems.append("range.lanes: unknown target")
		if coordinates(spec.spawn_m, 2, "range.lanes.spawn_m", problems):
			if not bounds.has_point(Vector2(spec.spawn_m[0], spec.spawn_m[1])): problems.append("range.lanes: out of bounds")
	ids.clear()
	for spec in value.obstacles:
		if not fields(spec, {"id":"string", "label":"string", "kind":"string", "rect_m":"array", "height_m":"positive"}, "range.obstacles", problems): continue
		if ids.has(spec.id) or not spec.kind in ["cover", "wall"]: problems.append("range.obstacles: invalid ID or kind")
		ids[spec.id] = true
		if coordinates(spec.rect_m, 4, "range.obstacles.rect_m", problems):
			var v: Array = spec.rect_m
			if v[2] <= 0 or v[3] <= 0 or not bounds.encloses(Rect2(v[0], v[1], v[2], v[3])): problems.append("range.obstacles: invalid extent")


static func validate_body(b, path: String, p: PackedStringArray):
	if not fields(b, {"regions":"array", "fatal_parts":"list", "fatal_regions":"list", "capabilities":"dict", "hit_bands":"array"}, path, p): return
	var regions := {}
	var parts := {}
	for r in b.regions:
		if not fields(r, {"id":"string", "name":"string", "parts":"array"}, path + ".regions", p): continue
		if regions.has(r.id): p.append(path + ": duplicate region " + r.id)
		regions[r.id] = true
		for part in r.parts:
			if not fields(part, {"id":"string", "region":"string", "max_hp":"positive", "hit_weight":"positive", "tags":"list", "damage_multiplier":"nonnegative", "attributes":"dict", "bonus_sources":"list"}, path + ".parts", p): continue
			if parts.has(part.id) or part.region != r.id: p.append(path + ": duplicate part or mismatched region " + part.id)
			parts[part.id] = true
	for id in b.fatal_parts:
		if not parts.has(id): p.append(path + ": unknown fatal part " + str(id))
	for id in b.fatal_regions:
		if not regions.has(id): p.append(path + ": unknown fatal region " + str(id))
	for capability in ["movement", "manipulation", "vision"]:
		var v = b.capabilities.get(capability)
		if fields(v, {"regions":"dict"}, path + ".capabilities." + capability, p):
			validate_weights(v.regions, regions, path + ".capabilities." + capability, p)
	var previous := 2.0
	for band in b.hit_bands:
		if fields(band, {"min_height_fraction":"unit", "regions":"dict"}, path + ".hit_bands", p):
			if band.min_height_fraction >= previous: p.append(path + ": hit bands must descend to zero")
			previous = band.min_height_fraction
			validate_weights(band.regions, regions, path + ".hit_bands", p)
	if previous != 0: p.append(path + ": hit bands must end at zero")


static func validate_weights(weights: Dictionary, available: Dictionary, path: String, p: PackedStringArray):
	if weights.is_empty(): p.append(path + ": empty weights")
	for id in weights:
		if not available.has(id): p.append(path + ": unknown region " + str(id))
		fields({"weight":weights[id]}, {"weight":"positive"}, path, p)


static func angle_speed(points: Array, radians: float) -> float:
	var degrees := absf(rad_to_deg(wrapf(radians, -PI, PI)))
	for i in range(1, points.size()):
		if degrees <= float(points[i][0]):
			return lerpf(points[i - 1][1], points[i][1], smoothstep(points[i - 1][0], points[i][0], degrees))
	return float(points.back()[1])


static func cell(v) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1]))


static func center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func use_for(item: String) -> Dictionary:
	var use: Dictionary = catalog.items[item].uses[0].duplicate(true)
	if catalog.weapons.has(item): use.duration = catalog.weapons[item].reload_time
	return use


static func weapon(kind: String = "rifle", ammo: int = -1, reserve: int = 90) -> Dictionary:
	var spec = catalog.weapons[kind]
	var state := {
		"definition": spec.duplicate(true),
		"ammunition": catalog.ammunition[spec.ammunition].duplicate(true),
		"ammo": int(spec.magazine_size) if ammo < 0 else ammo,
		"reserve_ammo": reserve,
		"cooldown": 0.0,
		"recoil_offset_degrees": Vector2.ZERO,
		"shots_fired": 0
	}
	SCCombat.reset_recoil(state)
	return state


static func projectile_speed(weapon: Dictionary) -> float:
	return weapon.ammunition.speed_mps * weapon.definition.muzzle_velocity_multiplier


static func node(token: String, kind: String, options: Dictionary = {}) -> Dictionary:
	var n = {
		"token": token,
		"kind": kind,
		"cell": null,
		"angle": null,
		"target_id": null,
		"item": null,
		"sync": null,
		"task_id": null,
		"status": "queued",
		"reason": "",
		"elapsed": 0.0,
		"started": false,
		"object_id": null,
		"cargo_id": null
	}
	n.merge(options, true)
	return n


static func task(id: int, draft: Dictionary) -> Dictionary:
	return {
		"id": id,
		"token": "task:%d" % id,
		"draft": draft,
		"phase": "queued",
		"resume_phase": "stack",
		"reason": "",
		"ready": false,
		"released": false,
		"enter_index": 0,
		"entered": {},
		"released_at": -100.0,
		"searches": {},
		"observations": {},
		"finals": {},
		"action_started": false,
		"flash_released": false,
		"blast_at": 0.0,
		"jobs": {},
		"pickups": {},
		"guards": {},
		"seen_loot": {},
		"loot_idle": 0.0
	}
