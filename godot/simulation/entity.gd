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

func _init(spec: Dictionary, character: SCActor = null):
	definition = spec.duplicate(true)
	actor = character
	_position = SCCombat.pair(spec.position_m)
	facing = float(spec.get("facing_radians",0.0))
	durability = float(spec.get("max_durability",0.0))
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
	return (.35 if not actor.alive else actor.height) if actor != null else float(definition.height_m)

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
	if not definition.get("damageable",false): return
	durability = maxf(0,durability-amount)
	if durability>0: return
	var result: Dictionary = definition.get("destroyed",{})
	for key in ["blocks_movement","blocks_sight","blocks_projectile","height_m"]:
		if result.has(key): definition[key] = result[key]
	exists = result.get("exists",true)
	if not door.is_empty(): door.faulted = true


func ray_fraction(start: Vector3, end: Vector3) -> float:
	if definition.get("shape","")=="cylinder":
		return SCCombat.cylinder_hit_fraction(Vector2(start.x,start.z),Vector2(end.x,end.z),start.y,end.y,position,position,definition.radius_m,bottom(),bottom()+height())
	var a := Vector2(start.x-position.x,start.z-position.y).rotated(-facing)
	var b := Vector2(end.x-position.x,end.z-position.y).rotated(-facing)
	var box := collision_box()
	box.position.x-=position.x
	box.position.z-=position.y
	return SCCombat.box_hit_fraction(Vector3(a.x,start.y,a.y),Vector3(b.x,end.y,b.y),box)

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
