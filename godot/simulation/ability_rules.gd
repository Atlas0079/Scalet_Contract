class_name SCAbilityRules
extends RefCounted

const BODY_ATTRIBUTES := {
	"human": ["muscle", "endurance", "coordination", "senses"],
	"robot": ["actuator_output", "drive_efficiency", "servo_precision", "sensor_quality", "cooling", "em_shielding", "control_security"],
	"android": ["muscle_fiber_output", "neural_speed", "fine_control", "senses", "circulation_efficiency", "tissue_stability"]}
const MIND_ATTRIBUTES := {"human":["resolve","psi_potential"], "robot":[], "android":["resolve"]}
const STATES := {"human":["fatigue"], "robot":["heat","energy","electronic_fault"], "android":["artificial_blood","metabolic_load","circulation_fault"]}
const VALUE_KEYS := ["force_n","carry_capacity_kg","move_speed_mps","acceleration_mps2","turn_speed_radps","manipulation_rate","reload_rate","treatment_rate","repair_rate","hacking_rate","aim_gain_per_second","aim_unsettled_degrees","aim_settled_degrees","recoil_kick_scale","recoil_response_delay_seconds","recoil_compensation_build_seconds","recoil_control_acceleration","recoil_support_scale","recoil_control_frequency","recoil_prediction_scale","recoil_overshoot_degrees","view_distance_m","view_angle_rad","identification_rate","response_delay_seconds","em_protection","control_protection","circulation_recovery_scale","tissue_stability_scale","sync_current","psi_capacity","psi_execution_rate"]


static func freeze(value):
	if value is Dictionary:
		for v in value.values(): freeze(v)
		value.make_read_only()
	elif value is Array:
		for v in value: freeze(v)
		value.make_read_only()


static func source(identity: String, owner_kind: String, owner_id: String, origin: String, scope: String, contributions: Array) -> Dictionary:
	return {"source_id":identity,"owner_kind":owner_kind,"owner_id":owner_id,"origin_kind":origin,"definition_id":identity,
		"scope":scope,"active":true,"starts_at":0.0,"ends_at":null,"contributions":contributions}


static func contribution(id: String, kind: String, target: String, value: float, role := "bonus", operation := "add") -> Dictionary:
	return {"contribution_id":id,"target_kind":kind,"target_id":target,"role":role,"operation":operation,"value":value,
		"stack_group":"", "stack_policy":"stack", "priority":0}


static func instantiate_source(definition_id: String, identity: String, owner_kind: String, owner_id: String, at: float) -> Dictionary:
	var spec: Dictionary = SCData.catalog.attribute_sources[definition_id]
	var result := source(identity,owner_kind,owner_id,spec.origin_kind,spec.scope,spec.contributions.duplicate(true))
	result.definition_id = definition_id
	result.starts_at = at
	if spec.duration_seconds != null: result.ends_at = at + spec.duration_seconds
	for key in ["requires_functional","durability_curve"]:
		if spec.has(key): result[key] = spec[key]
	return result


static func curve(points: Array, x: float) -> float:
	if x <= points[0][0]: return points[0][1]
	for i in range(1, points.size()):
		if x <= points[i][0]: return lerpf(points[i-1][1], points[i][1], (x-points[i-1][0])/(points[i][0]-points[i-1][0]))
	return points.back()[1]


static func select_sources(sources: Array, time: float, parts: Dictionary, details: Array) -> Array:
	var unique := {}
	for entry in sources:
		if unique.has(entry.source_id):
			assert(unique[entry.source_id] == entry, "Conflicting source ID: " + entry.source_id)
		else: unique[entry.source_id] = entry
	var keys: Array = unique.keys()
	keys.sort()
	var candidates: Array = []
	var winners := {}
	for key in keys:
		var s: Dictionary = unique[key]
		var reason := ""
		if not s.active: reason = "inactive"
		elif time < s.starts_at: reason = "not_started"
		elif s.ends_at != null and time >= s.ends_at: reason = "expired"
		var ratio := 1.0
		if s.owner_kind == "part":
			var part: Dictionary = parts.get(s.owner_id, {})
			if part.is_empty(): reason = "unequipped"
			else:
				if s.get("requires_functional", false) and part.hp <= 0: reason = "destroyed_part"
				if s.has("durability_curve"): ratio = curve(s.durability_curve, part.hp / part.definition.max_hp)
		var contributions: Array = s.contributions.duplicate(true)
		contributions.sort_custom(func(a,b): return a.contribution_id < b.contribution_id)
		for c in contributions:
			c["source_id"] = key
			c["owner_id"] = s.owner_id
			c["origin_kind"] = s.origin_kind
			c["reason"] = reason
			c["raw_value"] = c.value
			if c.role == "bonus": c.value = 1.0 + (c.value-1.0)*ratio if c.operation == "factor" else c.value*ratio
			details.append(c)
			if not reason.is_empty(): continue
			candidates.append(c)
			if c.stack_policy == "exclusive":
				var group: String = c.stack_group
				if not winners.has(group) or c.priority > winners[group].priority: winners[group] = c
	var result: Array = []
	for c in candidates:
		if c.stack_policy == "exclusive" and not is_same(winners[c.stack_group], c):
			c.reason = "suppressed_by:" + winners[c.stack_group].source_id
		else: result.append(c)
	return result


static func modified(base: float, contributions: Array, kind: String, target: String) -> float:
	var add := 0.0
	var percent := 0.0
	var factor := 1.0
	for c in contributions:
		if c.role != "bonus" or c.target_kind != kind or c.target_id != target: continue
		match c.operation:
			"add": add += c.value
			"percent": percent += c.value
			"factor": factor *= c.value
	return maxf(0.0, base + add) * maxf(0.0, 1.0 + percent) * factor


static func attributes(keys: Array, contributions: Array) -> Dictionary:
	var result := {}
	for key in keys:
		var base := 0.0
		for c in contributions:
			if c.role == "base" and c.target_kind == "attribute" and c.target_id == key: base += c.value
		result[key] = clampf(modified(base, contributions, "attribute", key), 0, 1000)
	return result


static func _shooting_capabilities(g: Dictionary, training: float, base: Dictionary, rules: Dictionary) -> Dictionary:
	# Only unified inputs enter this function. Source corrections on these
	# inputs have already settled; corrections on its outputs settle afterwards.
	var result := {"aim_gain_per_second":0.0, "aim_unsettled_degrees":Vector2(45,45),
		"aim_settled_degrees":Vector2(45,45), "recoil_kick_scale":4.0,
		"recoil_response_delay_seconds":rules.recognition_seconds,
		"recoil_compensation_build_seconds":rules.build_seconds,
		"recoil_control_acceleration":0.0, "recoil_support_scale":sqrt(g.force_ratio),
		"recoil_control_frequency":0.0, "recoil_prediction_scale":0.0, "recoil_overshoot_degrees":0.0}
	if g.force_ratio <= 0 or g.execution <= 0 or g.perception <= 0 or g.control <= 0: return result
	var t := clampf(training, 0.0, 1.0)
	var strength := sqrt(g.force_ratio)
	var execution := sqrt(g.execution)
	var perception := sqrt(g.perception)
	var brace := lerpf(rules.brace_efficiency[0],rules.brace_efficiency[1],t)
	var recognition := lerpf(rules.recognition_factor[0],rules.recognition_factor[1],t)
	var establishment := lerpf(rules.establishment_factor[0],rules.establishment_factor[1],t)
	var correction := lerpf(rules.correction_factor[0],rules.correction_factor[1],t)
	var settled := lerpf(rules.settled_precision_factor[0],rules.settled_precision_factor[1],t)
	var unsettled := lerpf(rules.unsettled_precision_factor[0],rules.unsettled_precision_factor[1],t)
	return {
		"recoil_kick_scale":rules.reference_brace/(strength*brace),
		"recoil_response_delay_seconds":g.response_delay_seconds+rules.recognition_seconds/(perception*recognition),
		"recoil_compensation_build_seconds":rules.build_seconds/(execution*establishment),
		"recoil_control_acceleration":rules.max_acceleration_degrees_per_second2*g.force_ratio*g.control,
		"recoil_support_scale":strength,
		"recoil_control_frequency":rules.return_frequency*execution*correction,
		"recoil_prediction_scale":lerpf(rules.prediction_factor[0],rules.prediction_factor[1],t),
		"recoil_overshoot_degrees":minf(rules.overshoot_max_degrees,rules.overshoot_degrees_per_force_surplus*maxf(0,g.force_ratio-1)*pow(1-t,2)),
		"aim_gain_per_second":base.aim_gain_per_second*execution*perception*establishment,
		"aim_unsettled_degrees":Vector2(base.aim_unsettled_degrees[0],base.aim_unsettled_degrees[1])/(execution*unsettled),
		"aim_settled_degrees":Vector2(base.aim_settled_degrees[0],base.aim_settled_degrees[1])/(execution*settled)}


static func evaluate(actor, explain := false) -> Dictionary:
	var details: Array = []
	var body := select_sources(actor.body_sources(), actor.ability_time, actor.parts_by_instance(), details)
	var control := select_sources(actor.control_sources(), actor.ability_time, {}, details)
	var memory := select_sources(actor.chip.get("sources", []), actor.ability_time, {}, details)
	var species: String = actor.definition.species
	var a := attributes(BODY_ATTRIBUTES[species], body)
	var controller: Dictionary = actor.controller()
	var mind := attributes(MIND_ATTRIBUTES.get(controller.get("species", "robot"), []), control)
	var skills := SCSkills.compose(actor, body, control, memory)
	var parameters: Dictionary = SCData.catalog.ability_rules
	var base: Dictionary = parameters.base
	var state: Dictionary = parameters.state
	var f_move: float = actor.body_function("movement")
	var f_hand: float = actor.body_function("manipulation")
	var f_sense: float = actor.body_function("vision")
	var p := 0.0
	var v := 0.0
	var d := 0.0
	var s := 0.0
	var u := 0.0
	match species:
		"human":
			p = a.muscle / 100.0
			v = sqrt(p * a.endurance / 100.0)
			d = a.coordination / 100.0
			s = a.senses / 100.0
			u = 1.0 - state.fatigue_loss * actor.states.fatigue
		"robot":
			p = a.actuator_output / 100.0
			v = a.drive_efficiency / 100.0
			d = a.servo_precision / 100.0
			s = a.sensor_quality / 100.0
			u = clampf(actor.states.energy/state.energy_full_threshold,0,1) * (1-state.heat_loss*clampf(actor.states.heat/maxf(0.1,a.cooling/100.0),0,1)) * (1-actor.states.electronic_fault)
		"android":
			p = a.muscle_fiber_output / 100.0
			v = a.neural_speed / 100.0
			d = a.fine_control / 100.0
			s = a.senses / 100.0
			u = actor.states.artificial_blood * (1-state.metabolic_loss*actor.states.metabolic_load) * (1-actor.states.circulation_fault)
	var c := 0.0
	if not controller.is_empty(): c = clampf(1-state.stress_loss*controller.states.stress/maxf(0.1,mind.resolve/100.0)-state.pain_loss*controller.states.pain,0,1)
	var ceiling := float(actor.control.get("sync_ceiling", 0.0))
	var sync := clampf(modified(actor.control.get("sync_base", 0.0), control, "capability", "sync_current"),0,ceiling) if actor.control_mode == "sia" else 0.0
	var q: float = 1.0 if actor.control_mode == "self" else (parameters.sia_factor.base+parameters.sia_factor.per_level*skills.sia_control)*actor.control.get("quality",0.0)*sync
	var h: float = d*u*f_hand*c*q
	var k: float = parameters.skill_factor.base + parameters.skill_factor.per_level*skills.shooting
	var precision: float = h*k
	var values := {
		"force_n":base.force_n*p*u*f_hand, "carry_capacity_kg":base.carry_capacity_kg*p*u*f_move,
		"move_speed_mps":base.move_speed_mps*v*u*f_move, "acceleration_mps2":base.acceleration_mps2*v*u*f_move,
		"turn_speed_radps":base.turn_speed_radps*d*u, "manipulation_rate":h, "reload_rate":precision,
		"view_distance_m":base.view_distance_m*s*f_sense,"view_angle_rad":deg_to_rad(actor.definition.view_angle_degrees),
		"identification_rate":s*f_sense*c*q,"response_delay_seconds":base.response_delay_seconds/maxf(0.1,d*c*q)+(actor.control.get("latency",0.0) if actor.control_mode=="sia" else 0.0),
		"em_protection":a.get("em_shielding",0.0)/100.0,"control_protection":a.get("control_security",0.0)/100.0 if species=="robot" else (1.0 if actor.control_mode=="sia" else 0.0),
		"circulation_recovery_scale":a.get("circulation_efficiency",100.0)/100.0,"tissue_stability_scale":a.get("tissue_stability",100.0)/100.0,
		"sync_current":sync,"sync_ceiling":ceiling,"sia_pain_scale":sync,"psi_capacity":0.0,"psi_execution_rate":0.0}
	for pair in [["treatment_rate","medicine"],["repair_rate","repair"],["hacking_rate","hacking"]]: values[pair[0]] = h*(parameters.skill_factor.base+parameters.skill_factor.per_level*skills[pair[1]])
	if species=="human" and actor.control_mode=="self":
		values.psi_capacity = mind.psi_potential/100.0*(1-controller.states.psi_load)
		values.psi_execution_rate = c*(parameters.skill_factor.base+parameters.skill_factor.per_level*skills.psionics)*(1-controller.states.psi_load)
	var all_bonus: Array = body + control
	for key in values:
		if key in ["sync_current","sync_ceiling","sia_pain_scale"]: continue
		values[key] = modified(values[key],all_bonus,"capability",key)
	var shooting_inputs := {"force_ratio":values.force_n/base.force_n, "execution":values.manipulation_rate,
		"perception":values.identification_rate, "control":c*q, "response_delay_seconds":values.response_delay_seconds}
	var shooting := _shooting_capabilities(shooting_inputs,skills.shooting/SCData.catalog.skills.level.max,base,parameters.recoil_control)
	for key in shooting:
		values[key] = shooting[key]
		if values[key] is Vector2:
			values[key] = Vector2(clampf(modified(values[key].x,all_bonus,"capability",key),0,45),clampf(modified(values[key].y,all_bonus,"capability",key),0,45))
		else: values[key] = modified(values[key],all_bonus,"capability",key)
	values.aim_settled_degrees = values.aim_settled_degrees.min(values.aim_unsettled_degrees)
	values.recoil_kick_scale = clampf(values.recoil_kick_scale,0.25,4)
	values.recoil_response_delay_seconds = maxf(.01,values.recoil_response_delay_seconds)
	values.recoil_compensation_build_seconds = maxf(.01,values.recoil_compensation_build_seconds)
	values.recoil_prediction_scale = clampf(values.recoil_prediction_scale,0,1)
	values.recoil_overshoot_degrees = clampf(values.recoil_overshoot_degrees,0,parameters.recoil_control.overshoot_max_degrees)
	values.view_angle_rad = clampf(values.view_angle_rad,0,TAU)
	values["move_angle_curve"] = actor.definition.movement_angle_curve.duplicate(true)
	values.merge(parameters.aim.duplicate(true))
	var enabled: bool = actor.alive and actor.stunned <= 0 and not controller.is_empty() and controller.active
	if actor.control_mode == "sia": enabled = enabled and actor.control.get("connected",false) and sync>0 and actor.control.get("quality",0.0)>0
	var permissions := {"can_move":enabled and f_move>0 and values.move_speed_mps>0,
		"can_operate":enabled and h>0 and values.manipulation_rate>0,
		"can_aim":enabled and precision>0 and f_sense>0 and p>0 and values.aim_gain_per_second>0,
		"can_use_psionics":false}
	var reasons: Array = []
	if not enabled: reasons.append("unavailable_controller" if actor.alive else "body_dead")
	if not permissions.can_operate:
		for key in ["manipulation_rate","reload_rate","treatment_rate","repair_rate","hacking_rate"]: values[key] = 0.0
	if not permissions.can_aim: values.aim_gain_per_second = 0.0; values.recoil_control_acceleration = 0.0
	if not permissions.can_move: values.move_speed_mps = 0.0; values.acceleration_mps2 = 0.0
	if not enabled: values.turn_speed_radps = 0.0
	if species!="human" or not enabled: values.psi_capacity = 0.0; values.psi_execution_rate = 0.0
	if not actor.alive: values.force_n = 0.0; values.carry_capacity_kg = 0.0
	for key in values:
		if values[key] is float: assert(is_finite(values[key]), "Non-finite ability: "+key)
	var result := {"actor_id":actor.identity,"revision":actor.ability_revision+1,"evaluated_at":actor.ability_time,"values":values,"permissions":permissions,"reason_codes":reasons,"skills":skills}
	if explain: result["explanation"] = {"sources":details,"attributes":a,"controller_attributes":mind,"body_functions":{"movement":f_move,"manipulation":f_hand,"vision":f_sense},"control_factor":c*q,"shooting_inputs":shooting_inputs}
	freeze(result)
	return result


static func explain(actor) -> Dictionary:
	return evaluate(actor,true)
