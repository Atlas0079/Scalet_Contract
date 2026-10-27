class_name SCEntity
extends RefCounted

var definition: Dictionary
var actor: SCActor
var space: WeakRef
var position: Vector2:
	get: return actor.position if actor != null else _position
	set(value):
		if actor != null: actor.position = value
		else: _position = value
var _position := Vector2.ZERO
var facing := 0.0
var exists := true
var durability := 0.0
var contents: Dictionary = {}
var door: Dictionary = {}
var hits := 0
var ruined := false

func _init(spec: Dictionary, character: SCActor = null):
	definition = spec.duplicate(true)
	actor = character
	_position = SCCombat.pair(spec.position_m)
	facing = float(spec.get("facing_radians",0.0))
	durability = float(spec.get("durability",spec.get("max_durability",0.0)))
	contents = spec.get("contents",{}).duplicate(true)
	if spec.has("door"):
		door = spec.door.duplicate(true)
		door["progress"] = 1.0 if door.state == "open" else 0.0
		door["target_open"] = door.state == "open"

func footprint() -> Rect2:
	if actor==null and not door.is_empty() and door.placement=="edge": return SCGrid.edge_rect(SCData.cell(definition.edge_cell),definition.edge_direction)
	var size: Vector2 = Vector2.ONE*actor.radius*2 if actor != null else SCCombat.pair(definition.footprint_m)
	return Rect2(position-size*.5,size)

func bottom() -> float:
	var grid: SCGrid = space.get_ref() if space else null
	var ground: float = grid.cells.get(SCData.cell_of(position),{}).get("ground_height_m",0.0) if grid else 0.0
	return ground+float(definition.get("bottom_m",0.0))

func height() -> float:
	return (float(definition.get("height_m",.35)) if not actor.alive else actor.height) if actor != null else float(definition.height_m)

func collision_box() -> AABB:
	var rect := footprint()
	var lower := bottom()
	# Rolling shutters retract vertically; partial opening has real clearance.
	if not door.is_empty(): lower += door.opening_height_m*door.progress
	return AABB(Vector3(rect.position.x,lower,rect.position.y),Vector3(rect.size.x,height()+bottom()-lower,rect.size.y))

func blocks(kind: String) -> bool:
	if not exists: return false
	if not door.is_empty() and door.progress >= 1.0 and door.opening_height_m>=height(): return false
	return bool(definition.get("blocks_"+kind,false))

func request_door(opened: bool) -> String:
	if door.is_empty(): return "不是门"
	if door.faulted: return "门发生故障"
	if not door.powered: return "门动力不可用"
	if opened and door.locked: return "门已锁定"
	door.target_open = opened
	door.state = "opening" if opened else "closing"
	return ""

func advance(dt: float):
	if door.is_empty() or door.state not in ["opening","closing"]: return
	var target := 1.0 if door.target_open else 0.0
	var duration: float = door.opening_seconds if door.target_open else door.closing_seconds
	door.progress = move_toward(door.progress,target,dt/maxf(duration,.000001))
	if is_equal_approx(door.progress,target): door.state = "open" if door.target_open else "closed"

func damage(amount: float):
	if ruined or not definition.get("damageable",false): return
	durability = maxf(0,durability-amount)
	if durability>0: return
	ruined = true
	var result: Dictionary = definition.get("destroyed",{})
	for key in ["blocks_movement","blocks_sight","blocks_projectile","height_m","protection","structure","condition"]:
		if result.has(key): definition[key] = result[key]
	exists = result.get("exists",true)
	if not door.is_empty(): door.faulted = true


# The broad footprint remains conservative for movement; rays use the actual solid parts.
func solid_parts() -> Array:
	if not door.is_empty() or actor!=null: return []
	return definition.get("structure",{}).get("parts",[])

func ray_hit(start: Vector3, end: Vector3, kind := "projectile", ignored: Dictionary = {}) -> Dictionary:
	if not blocks(kind): return {}
	var parts = solid_parts()
	if not parts.is_empty():
		var a = Vector2(start.x-position.x,start.z-position.y).rotated(-facing)
		var b = Vector2(end.x-position.x,end.z-position.y).rotated(-facing)
		var size = footprint().size
		var best: Dictionary = {}
		for part in parts:
			var key: String = definition.id+":"+part.id
			if ignored.has(key) or not part.get("blocks_"+kind,false): continue
			var offset: Array = part.offset_m
			var dimensions: Array = part.size_m
			var box = AABB(Vector3(float(offset[0])-size.x*.5,bottom()+float(offset[1]),float(offset[2])-size.y*.5),Vector3(dimensions[0],dimensions[1],dimensions[2]))
			var fraction = SCCombat.box_hit_fraction(Vector3(a.x,start.y,a.y),Vector3(b.x,end.y,b.y),box)
			if fraction>=0 and (best.is_empty() or fraction<best.fraction): best={"fraction":fraction,"part_id":part.id,"protection":float(part.protection),"contact_key":key}
		return best
	var key: String = definition.id+":body"
	if ignored.has(key): return {}
	var hit: float
	if definition.get("shape","")=="cylinder":
		hit=SCCombat.cylinder_hit_fraction(Vector2(start.x,start.z),Vector2(end.x,end.z),start.y,end.y,position,position,definition.radius_m,bottom(),bottom()+height())
	else:
		var a = Vector2(start.x-position.x,start.z-position.y).rotated(-facing)
		var b = Vector2(end.x-position.x,end.z-position.y).rotated(-facing)
		var box = collision_box()
		box.position.x-=position.x
		box.position.z-=position.y
		hit=SCCombat.box_hit_fraction(Vector3(a.x,start.y,a.y),Vector3(b.x,end.y,b.y),box)
	return {} if hit<0 else {"fraction":hit,"part_id":"body","protection":float(definition.get("protection",1.0 if actor!=null and not actor.alive else INF)),"contact_key":key}

func ray_fraction(start: Vector3, end: Vector3) -> float:
	var result = ray_hit(start,end)
	return -1.0 if result.is_empty() else result.fraction

func move_fraction(start: Vector2, end: Vector2, radius: float, body_height: float, ground: float) -> float:
	if actor!=null or definition.get("shape","")=="cylinder":
		var object_radius: float = actor.radius if actor!=null else definition.radius_m
		if bottom()>=ground+body_height or bottom()+height()<=ground: return -1.0
		return SCCombat.cylinder_hit_fraction(start,end,ground+body_height*.5,ground+body_height*.5,position,position,object_radius+radius,bottom()-body_height*.5,bottom()+height()+body_height*.5)
	var box := collision_box()
	if box.position.y>=ground+body_height or box.end.y<=ground: return -1.0
	var local_start := (start-position).rotated(-facing)
	var local_end := (end-position).rotated(-facing)
	var local_rect := Rect2(-footprint().size*.5,footprint().size).grow(radius)
	var h := clampf(ground+body_height*.5,box.position.y,box.end.y)
	return SCCombat.box_hit_fraction(Vector3(local_start.x,h,local_start.y),Vector3(local_end.x,h,local_end.y),AABB(Vector3(local_rect.position.x,box.position.y,local_rect.position.y),Vector3(local_rect.size.x,box.size.y,local_rect.size.y)))
