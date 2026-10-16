class_name SCWeaponRules
extends RefCounted

static func begin_trigger(actor: SCActor, value: bool):
	var weapon: Dictionary = actor.weapon
	weapon.trigger_held=value
	if not value: weapon.startup_elapsed=0.0

static func advance(actor: SCActor, dt: float):
	var weapon: Dictionary = actor.weapon
	var spec: Dictionary = weapon.definition
	weapon.cooldown=maxf(0,weapon.cooldown-dt)
	if spec.attack_category=="thermal":
		weapon.heat=maxf(0,weapon.heat-spec.cooling_per_second*dt)
		if weapon.trigger_held and not weapon.radiator_failed and weapon.action.is_empty():
			var work := minf(dt,maxf(0,spec.startup_seconds-weapon.startup_elapsed))
			var cost: float = work*spec.startup_energy_per_second
			if weapon.energy<cost: begin_trigger(actor,false)
			else: weapon.energy-=cost; weapon.startup_elapsed+=work
	if not weapon.action.is_empty():
		if weapon.action.kind=="melee":
			weapon.action.elapsed+=dt
			if not weapon.action.hit and weapon.action.elapsed>=spec.preparation_seconds:
				weapon.action.hit=true
				if actor.alive and actor.capabilities.permissions.can_operate: actor.world.resolve_attack(actor,weapon.action.target)
		else:
			weapon.action.remaining-=dt
			if weapon.action.remaining<=0:
				var resource: Dictionary = weapon.action.resource
				resource["reserved"]=false
				if weapon.action.kind=="battery":
					var old: float = weapon.energy
					weapon.energy=resource.energy
					resource.energy=old
				else:
					weapon.heat=0.0
					weapon.radiator_failed=false
					resource.used=true
				weapon.action={}
		if not weapon.action.is_empty() and weapon.action.kind=="melee" and weapon.action.elapsed>=spec.fire_interval: weapon.action={}

static func can_attack(actor: SCActor, unlimited_ammo := false) -> bool:
	var w: Dictionary = actor.weapon
	if not actor.alive or not actor.capabilities.permissions.can_operate or not actor.equipment_action.is_empty() or not w.action.is_empty() or w.cooldown>.000001: return false
	if w.definition.attack_category!="melee" and not actor.capabilities.permissions.can_aim: return false
	match w.definition.attack_category:
		"kinetic": return not SCEquipment.kinetic_locked(actor) and (unlimited_ammo or w.ammo>0)
		"thermal": return not w.radiator_failed and w.startup_elapsed>=w.definition.startup_seconds and w.energy>=w.definition.attack_energy
		"melee": return actor.capabilities.permissions.can_operate
	return false

static func consume(actor: SCActor, unlimited_ammo := false):
	var w: Dictionary = actor.weapon
	w.cooldown=w.definition.fire_interval
	if w.definition.attack_category=="kinetic":
		if not unlimited_ammo: w.ammo-=1
	elif w.definition.attack_category=="thermal":
		w.energy-=w.definition.attack_energy
		w.heat+=w.definition.attack_heat
		if w.heat>=w.definition.overheat_threshold: w.radiator_failed=true; w.trigger_held=false

static func begin_service(actor: SCActor, kind: String, resource: Dictionary) -> String:
	var w: Dictionary = actor.weapon
	if w.definition.attack_category!="thermal": return "仅热能武器支持能源维护"
	if not w.action.is_empty(): return "武器正在维护"
	if kind=="battery":
		if resource.get("kind")!="battery" or resource.get("energy",-1)<0 or resource.energy>w.definition.energy_capacity or resource.get("reserved",false): return "电池不适配"
	elif kind=="radiator":
		if resource.get("kind")!="radiator" or resource.get("used",true) or resource.get("reserved",false): return "散热器不可用"
	else: return "未知维护操作"
	resource["reserved"]=true
	begin_trigger(actor,false)
	w.action={"kind":kind,"remaining":w.definition.battery_replace_seconds if kind=="battery" else w.definition.radiator_replace_seconds,"resource":resource}
	return ""

static func charge(state: Dictionary, available_energy: float, dt: float) -> float:
	if not state.action.is_empty() or state.definition.get("attack_category","")!="thermal" and state.definition.get("kind","")!="shield": return 0.0
	var accepted := minf(maxf(available_energy,0),minf(state.definition.charge_per_second*maxf(dt,0),state.definition.energy_capacity-state.energy))
	state.energy+=accepted
	return accepted

static func attack_profile(weapon: Dictionary) -> Dictionary:
	if weapon.definition.attack_category=="kinetic":
		return {"category":"kinetic","damage":weapon.ammunition.damage,"penetration":weapon.ammunition.penetration}
	return {"category":weapon.definition.attack_category,"damage":weapon.definition.damage,"penetration":weapon.definition.penetration}
