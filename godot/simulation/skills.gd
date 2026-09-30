class_name SCSkills
extends RefCounted


static func registry() -> Dictionary:
	return {"consciousness": {}, "chips": {}, "settled": {}, "sequence": 0}


static func holder(kind: String, identity: String, species: String, attributes: Dictionary, xp: Dictionary) -> Dictionary:
	var base := attributes.duplicate(true)
	base.make_read_only()
	var entries: Array = []
	for key in base: entries.append(SCAbilityRules.contribution(key,"attribute",key,base[key],"base"))
	var innate := SCAbilityRules.source(identity+":innate",kind,identity,"innate","controller",entries)
	SCAbilityRules.freeze(innate)
	var states := {"stress":0.0,"pain":0.0}
	if species == "human": states["psi_load"] = 0.0
	if kind == "chip": states = {}
	return {"id":identity, "kind":kind, "species":species, "attributes":base,
		"xp":xp.duplicate(true), "sources":[innate], "states":states, "active":true}


static func level(xp: float) -> float:
	var rule: Dictionary = SCData.catalog.skills.level
	return minf(rule.max, sqrt(clampf(xp, 0, rule.xp_max) / rule.xp_scale))


static func effective(person: Dictionary, skill: String, contributions: Array, raw := false) -> float:
	if person.is_empty(): return 0.0
	var value := level(person.xp[skill])
	if not raw: value = SCAbilityRules.modified(value, contributions, "skill", skill)
	return clampf(value, 0, SCData.catalog.skills.level.max)


static func learners(actor) -> Array:
	var controller: Dictionary = actor.controller()
	if controller.is_empty(): return []
	if actor.control_mode == "self": return [{"holder":controller, "weight":1.0}]
	var weights: Dictionary = SCData.catalog.skills.channels[actor.definition.species]
	var result: Array = [{"holder":controller, "weight":float(weights.controller)}]
	var memory: Dictionary = actor.chip if actor.definition.species == "robot" else actor.consciousness
	if not memory.is_empty(): result.append({"holder":memory, "weight":float(weights.memory)})
	return result


static func compose(actor, body: Array, control: Array, memory: Array) -> Dictionary:
	var result := {}
	var controller: Dictionary = actor.controller()
	for skill in SCData.catalog.skills.definitions:
		var value := effective(controller, skill, control)
		if actor.control_mode == "sia" and skill not in ["sia_control", "psionics"]:
			var weights: Dictionary = SCData.catalog.skills.channels[actor.definition.species]
			var chip: bool = actor.definition.species == "robot"
			var other: Dictionary = actor.chip if chip else actor.consciousness
			value = value * weights.controller + effective(other, skill, memory, not chip) * weights.memory
		value = SCAbilityRules.modified(value, body, "skill", skill)
		if skill == "psionics" and (actor.definition.species != "human" or actor.control_mode != "self"): value = 0.0
		result[skill] = clampf(value, 0, SCData.catalog.skills.level.max)
	return result


static func settle(reg: Dictionary, event_id: String, skill: String, amount: float, recipients: Array, extra_sia := false) -> bool:
	if reg.settled.has(event_id): return false
	if event_id.is_empty() or not SCData.catalog.skills.definitions.has(skill) or not is_finite(amount) or amount < 0: return false
	if skill == "psionics" and not SCData.catalog.skills.psionic_xp_policy.enabled: return false
	if recipients.is_empty(): return false
	var ids := {}
	for recipient in recipients:
		var person: Dictionary = recipient.holder
		if person.is_empty() or ids.has(person.id) or not is_finite(recipient.weight) or recipient.weight < 0: return false
		if person.kind == "chip" and skill in ["psionics", "sia_control"]: return false
		var book: Dictionary = reg.chips if person.kind == "chip" else reg.consciousness
		if not book.has(person.id) or not is_same(book[person.id], person): return false
		ids[person.id] = true
	if extra_sia and recipients[0].holder.species != "human": return false
	reg.settled[event_id] = true
	for recipient in recipients:
		var person: Dictionary = recipient.holder
		person.xp[skill] = minf(SCData.catalog.skills.level.xp_max, person.xp[skill] + amount * recipient.weight)
	if extra_sia:
		var controller: Dictionary = recipients[0].holder
		controller.xp.sia_control = minf(SCData.catalog.skills.level.xp_max, controller.xp.sia_control + amount * SCData.catalog.skills.experience.sia_extra)
	return true


static func award(actor, skill: String, amount: float, event_id: String, recipients: Array = []) -> bool:
	if not actor.training_enabled: return false
	var result := settle(actor.skill_registry, event_id, skill, amount, learners(actor) if recipients.is_empty() else recipients, actor.control_mode == "sia")
	if result: actor.refresh_capabilities()
	return result
