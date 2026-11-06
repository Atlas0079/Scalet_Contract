class_name SCEntity
extends RefCounted

var definition: Dictionary
var actor: SCActor
var space: WeakRef
var position: Vector2:
	get: return actor.position if actor != null else _position
	set(value):
		if actor != null: actor.position = value
		elif _position != value:
			_position = value
			_geometry_changed()
var _position := Vector2.ZERO
var facing := 0.0:
	set(value):
		if facing == value: return
		facing = value
		_geometry_changed()
var exists := true:
	set(value):
		if exists==value: return
		exists=value
		_geometry_changed()
var durability := 0.0
var contents: Dictionary = {}
var door: Dictionary = {}
var hits := 0
var ruined := false
var _ray_revision := -1
var _ray_position := Vector2.ZERO
var _ray_facing := 0.0
var _ray_door_progress := -1.0
var _ray_parts: Array[Dictionary] = []
var _ray_body := AABB()
var _ray_bottom := 0.0
var _ray_top := 0.0
var _ray_height := -1.0

func _geometry_changed():
	_ray_revision=-1
	var grid: SCGrid = space.get_ref() if space else null
	if grid and actor==null:
		grid.invalidate_entity(self,true)

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
	var ground: float = grid.ground_at(SCData.cell_of(position)) if grid else 0.0
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
	_ray_revision = -1
	var grid: SCGrid=space.get_ref() if space else null
	if grid: grid.invalidate_entity(self,true)


# The broad footprint remains conservative for movement; rays use the actual solid parts.
func solid_parts() -> Array:
	if not door.is_empty() or actor!=null: return []
	return definition.get("structure",{}).get("parts",[])

func _prepare_ray_geometry():
	var at := position
	var progress: float = door.get("progress",0.0)
	var lower := bottom()
	var body_height := height()
	# Only this object's geometry invalidates its exact parts. Unrelated doors
	# must not reconstruct every cached object along every ray.
	if _ray_revision>=0 and _ray_position==at and _ray_facing==facing and _ray_door_progress==progress and _ray_bottom==lower and _ray_height==body_height:
		return
	_ray_revision=0
	_ray_position=at
	_ray_facing=facing
	_ray_door_progress=progress
	_ray_bottom=lower
	_ray_height=body_height
	_ray_top=_ray_bottom+body_height
	_ray_body=collision_box()
	_ray_body.position.x-=at.x
	_ray_body.position.z-=at.y
	_ray_parts.clear()
	var size := footprint().size
	for part in solid_parts():
		var offset: Array=part.offset_m
		var dimensions: Array=part.size_m
		_ray_parts.append({
			"box":AABB(Vector3(float(offset[0])-size.x*.5,_ray_bottom+float(offset[1]),float(offset[2])-size.y*.5),Vector3(dimensions[0],dimensions[1],dimensions[2])),
			"part_id":part.id,"contact_key":definition.id+":"+part.id,
			"blocks_sight":part.get("blocks_sight",false),"blocks_projectile":part.get("blocks_projectile",false),
			"protection":float(part.protection)
		})

func ray_hit(start: Vector3, end: Vector3, kind := "projectile", ignored: Dictionary = {}) -> Dictionary:
	if not blocks(kind): return {}
	_prepare_ray_geometry()
	if not _ray_parts.is_empty():
		var a = Vector2(start.x-_ray_position.x,start.z-_ray_position.y).rotated(-facing)
		var b = Vector2(end.x-_ray_position.x,end.z-_ray_position.y).rotated(-facing)
		var origin := Vector3(a.x,start.y,a.y)
		var finish := Vector3(b.x,end.y,b.y)
		var best := INF
		var hit_part: Dictionary = {}
		for part in _ray_parts:
			if ignored.has(part.contact_key) or not part["blocks_"+kind]: continue
			var fraction := SCCombat.box_hit_fraction(origin,finish,part.box)
			if fraction>=0 and fraction<best: best=fraction;hit_part=part
		return {} if hit_part.is_empty() else {"fraction":best,"part_id":hit_part.part_id,"protection":hit_part.protection,"contact_key":hit_part.contact_key}
	var key: String = definition.id+":body"
	if ignored.has(key): return {}
	var hit: float
	if definition.get("shape","")=="cylinder":
		hit=SCCombat.cylinder_hit_fraction(Vector2(start.x,start.z),Vector2(end.x,end.z),start.y,end.y,_ray_position,_ray_position,definition.radius_m,_ray_bottom,_ray_top)
	else:
		var a = Vector2(start.x-_ray_position.x,start.z-_ray_position.y).rotated(-facing)
		var b = Vector2(end.x-_ray_position.x,end.z-_ray_position.y).rotated(-facing)
		hit=SCCombat.box_hit_fraction(Vector3(a.x,start.y,a.y),Vector3(b.x,end.y,b.y),_ray_body)
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
