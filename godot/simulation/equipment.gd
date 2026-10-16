class_name SCEquipment
extends RefCounted

static func create(kind: String) -> Dictionary:
	var spec: Dictionary = SCData.catalog.equipment[kind].duplicate(true)
	return {"kind":kind,"definition":spec,"durability":float(spec.max_durability),"enabled":false,"energy":float(spec.get("energy_capacity",0)),"heat":0.0,"radiator_failed":false,"action":{},"filter_remaining":float(spec.get("filter_capacity",0))}

static func fraction(item: Dictionary) -> float:
	return clampf(item.durability/item.definition.max_durability,0,1)

static func shield_active(item: Dictionary) -> bool:
	return item.definition.kind=="shield" and item.enabled and item.energy>0 and not item.radiator_failed and fraction(item)>0 and item.action.is_empty()

static func kinetic_locked(actor: SCActor) -> bool:
	return actor.equipment.any(func(e): return shield_active(e))

static func equip_error(actor: SCActor, kind: String) -> String:
	if not SCData.catalog.equipment.has(kind): return "未知装备"
	var spec: Dictionary = SCData.catalog.equipment[kind]
	for item in actor.equipment:
		if item.kind==kind or item.definition.kind==spec.kind: return "同类装备已穿戴"
		if item.kind in spec.incompatible or kind in item.definition.incompatible: return "装备不兼容"
	return ""

static func equip(actor: SCActor, kind: String) -> String:
	var error := equip_error(actor,kind)
	if not error.is_empty(): return error
	actor.equipment.append(create(kind))
	actor.refresh_capabilities()
	return ""

static func begin_wear(actor: SCActor, item: Dictionary) -> String:
	var kind: String = item.kind
	if not actor.equipment_action.is_empty() or not actor.capabilities.permissions.can_operate: return "无法开始穿戴"
	var error := equip_error(actor,kind)
	if not error.is_empty(): return error
	actor.equipment_action={"kind":"wear","equipment":item,"remaining":item.definition.wear_seconds}
	return ""

static func begin_remove(actor: SCActor, item: Dictionary) -> String:
	if not actor.equipment_action.is_empty() or not actor.capabilities.permissions.can_operate or item not in actor.equipment: return "无法开始卸下"
	actor.equipment_action={"kind":"remove","equipment":item,"remaining":item.definition.remove_seconds}
	return ""

static func enable(item: Dictionary, value: bool) -> String:
	if item.definition.kind!="shield": return "不是主动护盾"
	if value and (item.energy<=0 or item.radiator_failed or fraction(item)<=0 or not item.action.is_empty()): return "护盾无法启动"
	item.enabled=value
	return ""

static func begin_service(item: Dictionary, kind: String, resource: Dictionary) -> String:
	if not item.action.is_empty(): return "装备正在维护"
	if item.definition.kind!="shield": return "该装备不支持能源维护"
	if kind=="battery":
		if resource.get("kind")!="battery" or resource.get("energy",-1)<0 or resource.energy>item.definition.energy_capacity or resource.get("reserved",false): return "电池不适配"
	elif kind=="radiator":
		if resource.get("kind")!="radiator" or resource.get("used",true) or resource.get("reserved",false): return "散热器不可用"
	else: return "未知维护操作"
	resource["reserved"]=true
	item.enabled=false
	item.action={"kind":kind,"remaining":item.definition.battery_replace_seconds if kind=="battery" else item.definition.radiator_replace_seconds,"resource":resource}
	return ""

static func advance(actor: SCActor, dt: float):
	if not actor.equipment_action.is_empty():
		actor.equipment_action.remaining-=dt*actor.operation_rate("equip")
		if actor.equipment_action.remaining<=0:
			if actor.equipment_action.kind=="wear": actor.equipment.append(actor.equipment_action.equipment)
			else:
				var removed: Dictionary = actor.equipment_action.equipment
				removed.enabled=false
				actor.equipment.erase(removed)
			actor.equipment_action={}
			actor.refresh_capabilities()
	for item in actor.equipment:
		var spec: Dictionary = item.definition
		if spec.kind!="shield": continue
		item.heat=maxf(0,item.heat-spec.cooling_per_second*dt)
		if not item.action.is_empty():
			item.action.remaining-=dt
			if item.action.remaining<=0:
				var resource: Dictionary = item.action.resource
				resource["reserved"]=false
				if item.action.kind=="battery":
					var old: float = item.energy
					item.energy=resource.energy
					resource.energy=old
				else:
					item.radiator_failed=false
					item.heat=0.0
					resource.used=true
				item.action={}
		if shield_active(item):
			item.energy=maxf(0,item.energy-spec.standby_energy_per_second*dt)
			if item.energy<=0: item.enabled=false

static func protect(actor: SCActor, region: String, attack: Dictionary) -> Dictionary:
	var damage: float = attack.damage
	var category: String = attack.category
	if category=="kinetic":
		for item in actor.equipment:
			if not shield_active(item): continue
			var cost: float = item.definition.block_energy
			if item.energy<cost:
				item.enabled=false
				break
			item.energy-=cost
			item.heat+=item.definition.block_heat
			if item.heat>=item.definition.overheat_threshold:
				item.radiator_failed=true
				item.enabled=false
			if item.energy<=0: item.enabled=false
			return {"damage":0.0,"blocked":true,"layer":"shield"}
	var layers: Array = actor.equipment.filter(func(e): return e.definition.kind!="shield")
	layers.sort_custom(func(a,b): return a.definition.layer>b.definition.layer)
	for item in layers:
		var spec: Dictionary = item.definition
		if region not in spec.coverage or fraction(item)<=0: continue
		var resistance: float = spec.protection[category]*fraction(item)
		if resistance>0 and attack.penetration<=resistance: return {"damage":0.0,"blocked":true,"layer":item.kind}
		# Penetrated layers transmit damage; no unconfirmed hidden percentage reduction.
	return {"damage":damage,"blocked":false,"layer":"body"}

static func filtered_exposure(actor: SCActor, amount: float) -> float:
	var result := amount
	for item in actor.equipment:
		if item.definition.kind!="suit" or item.filter_remaining<=0: continue
		var captured := minf(item.filter_remaining,result*item.definition.filter_efficiency*fraction(item))
		item.filter_remaining-=captured
		result-=captured
	return result

static func mass(actor: SCActor) -> float:
	var result := 0.0
	for item in actor.equipment: result+=item.definition.mass
	return result

static func movement_factor(actor: SCActor) -> float:
	var result := 1.0
	for item in actor.equipment: result*=item.definition.movement_multiplier
	return result

static func operation_factor(actor: SCActor) -> float:
	var result := 1.0
	for item in actor.equipment: result*=item.definition.operation_multiplier
	return result

static func validate(doc: Dictionary) -> PackedStringArray:
	var p: PackedStringArray = []
	for id in doc:
		var spec = doc[id]
		if not SCData.fields(spec,{"kind":"string","name":"string","mass":"nonnegative","movement_multiplier":"unit","operation_multiplier":"unit","max_durability":"positive","wear_seconds":"positive","remove_seconds":"positive","coverage":"list","protection":"dict","incompatible":"list"},"equipment."+id,p): continue
		if spec.kind not in ["suit","armor","shield"]: p.append("equipment."+id+": unknown kind")
		SCData.fields(spec.protection,{"kinetic":"nonnegative","thermal":"nonnegative","melee":"nonnegative"},"equipment."+id+".protection",p)
		for other in spec.incompatible:
			if not doc.has(other): p.append("equipment."+id+": unknown incompatibility")
		if spec.kind=="suit": SCData.fields(spec,{"filter_efficiency":"unit","filter_capacity":"positive"},"equipment."+id,p)
		if spec.kind=="shield": SCData.fields(spec,{"energy_capacity":"positive","standby_energy_per_second":"positive","block_energy":"positive","block_heat":"positive","cooling_per_second":"nonnegative","overheat_threshold":"positive","battery_replace_seconds":"positive","radiator_replace_seconds":"positive","charge_per_second":"positive"},"equipment."+id,p)
	return p
