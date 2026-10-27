extends RefCounted

const CHUNK := 24
var data: Dictionary
var width = 0
var height = 0
var tiles = PackedByteArray()
var ceilings = PackedFloat32Array()
var room_at = PackedInt32Array()
var rooms: Array = []
var buildings: Array = []
var chunks: Dictionary = {}
var door_groups: Array = []
var objects: Array = []
var entities: Dictionary = {}
var actors: Array = []
var loot: SCLoot
var time := 0.0
var power_overrides: Dictionary = {}
var object_cells: Dictionary = {}
var vertical = PackedByteArray()
var horizontal = PackedByteArray()
var pois: Array = []

func index(x: int, y: int) -> int:
 return y * width + x

func in_bounds(x: int, y: int) -> bool:
 return x >= 0 and y >= 0 and x < width and y < height

func tile(x: int, y: int) -> int:
 return int(tiles[index(x,y)]) if in_bounds(x,y) else 0

func walkable(x: int, y: int) -> bool:
 return tile(x,y) not in [0,5] and not object_cells.has(Vector2i(x,y))

func ceiling(x: int, y: int) -> float:
 return ceilings[index(x,y)] if in_bounds(x,y) else 5.8

func chunk_at(p: Vector2) -> Vector2i:
 return Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))

func entry_chunk(key: Vector2i) -> Dictionary:
 if not chunks.has(key): chunks[key] = {"edges":[],"doors":[],"objects":[],"labels":[]}
 return chunks[key]

func location(p: Vector2) -> String:
 var x = floori(p.x)
 var y = floori(p.y)
 if not in_bounds(x,y): return "地图边界"
 var r = int(room_at[index(x,y)])
 if r >= 0: return rooms[r].building_name + " / " + rooms[r].name
 var kind = tile(x,y)
 return "街道" if kind == 2 else "作业区 / 共用院" if kind in [7,8] else "天然洞穴"

func safe_point(p: Vector2) -> Vector2:
 for radius in range(0,16):
  for dy in range(-radius,radius+1):
   for dx in range(-radius,radius+1):
    var x = floori(p.x) + dx
    var y = floori(p.y) + dy
    if not walkable(x,y): continue
    if tile(x,y) == 2: return Vector2(x+.5,y+.5)
 return p

func load_map(path: String) -> Error:
 if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
 var value = JSON.parse_string(FileAccess.get_file_as_string(path))
 if not value is Dictionary or value.get("version",0) != 22: return ERR_INVALID_DATA
 data = value
 width = int(data.width)
 height = int(data.height)
 tiles = PackedByteArray(data.tiles)
 ceilings.resize(width*height)
 ceilings.fill(5.8)
 room_at.resize(width*height)
 room_at.fill(-1)
 vertical.resize((width+1)*height)
 horizontal.resize(width*(height+1))
 buildings = data.buildings
 var openings: Dictionary = {}
 for b in buildings:
  var floor_height = 5.6 if b.category == "industry" else 3.0
  for i in b.cells: ceilings[int(i)] = floor_height
  for r in b.rooms:
   var copy: Dictionary = r.duplicate(false)
   copy["building_name"] = b.name
   var id = rooms.size()
   rooms.append(copy)
   for y in range(int(r.y),int(r.y+r.h)):
    for x in range(int(r.x),int(r.x+r.w)):
     room_at[index(x,y)] = id
     ceilings[index(x,y)] = floor_height
   for o in r.objects: add_object(o)
  for d in b.doors:
   var key = str(b.id)+":"+str(d.get("opening",str(d.axis)+":"+str(d.x)+":"+str(d.y)))
   if not openings.has(key): openings[key] = {"key":key,"name":str(b.name)+" / "+str(d.get("role","入口门")),"segments":[],"axis":d.axis}
   openings[key].segments.append(d)
  var at = Vector2(float(b.entry.x),float(b.entry.y))
  entry_chunk(chunk_at(at)).labels.append({"text":b.name,"at":at})
 for o in data.streetObjects: add_object(o)
 for edge in data.edges:
  var e: Dictionary = edge
  var x = int(e.x)
  var y = int(e.y)
  if e.axis == "vertical": vertical[y*(width+1)+x] = 2 if e.kind == "door" else 1
  else: horizontal[y*width+x] = 2 if e.kind == "door" else 1
  if e.kind == "wall": entry_chunk(chunk_at(Vector2(x,y))).edges.append(e)
 for group in openings.values():
  group.segments.sort_custom(func(a,b): return a.y < b.y if group.axis == "vertical" else a.x < b.x)
  var first: Dictionary = group.segments[0]
  var count = group.segments.size()
  var center = Vector2(float(first.x),float(first.y)) + (Vector2(0,count*.5) if group.axis == "vertical" else Vector2(count*.5,0))
  group["center"] = center
  group["width"] = float(count)
  group["wall_height"] = maxf(ceiling(int(first.x),int(first.y)),ceiling(int(first.x)-1,int(first.y)-1))
  group["height"] = 2.35
  group["entities"] = []
  for d in group.segments:
   var direction = "W" if group.axis == "vertical" else "N"
   var entity = SCEntity.new({"id":str(group.key)+":"+str(d.x)+":"+str(d.y),"position_m":[float(d.x)+(0.0 if direction=="W" else .5),float(d.y)+(.5 if direction=="W" else 0.0)],"edge_cell":[int(d.x),int(d.y)],"edge_direction":direction,"height_m":2.35,"footprint_m":[1,.12],"blocks_movement":true,"blocks_sight":true,"blocks_projectile":true,"protection":45.0,"door":{"placement":"edge","state":"closed","opening_height_m":2.5,"powered":true,"faulted":false,"locked":false,"opening_seconds":.65,"closing_seconds":.65}})
   group.entities.append(entity)
  group["id"] = door_groups.size()
  door_groups.append(group)
  entry_chunk(chunk_at(center)).doors.append(group.id)
 loot = SCLoot.new(self)
 var station = Vector2(float(data.station.x),float(data.station.y))
 pois.append({"name":"中央车站","at":safe_point(station),"look":station+Vector2(12,0)})
 for type in ["production_complex","apartment","hospital"]:
  var candidates = buildings.filter(func(b): return b.type==type)
  if candidates.is_empty(): candidates = buildings.filter(func(b): return b.category==("housing" if type=="apartment" else "industry" if type=="production_complex" else "civic"))
  if candidates.is_empty(): candidates=buildings
  for b in candidates:
   var door = b.doors.filter(func(d): return d.a == "outside")[0]
   var outside = Vector2(float(door.sides[0][0])+.5,float(door.sides[0][1])+.5)
   var inside = Vector2(float(door.sides[1][0])+.5,float(door.sides[1][1])+.5)
   var at = safe_point(outside + (outside-inside).normalized()*2)
   pois.append({"name":b.name,"at":at,"look":inside})
   break
 return OK

func add_object(o: Dictionary):
 var id = objects.size()
 objects.append(o)
 var spec = {"id":o.id,"label":o.name,"classification":o.classification,"position_m":[float(o.x)+float(o.w)*.5,float(o.y)+float(o.h)*.5],"footprint_m":[o.w,o.h],"bottom_m":o.bottom_m,"height_m":o.height_m,"blocks_movement":o.blocks_movement,"blocks_sight":o.blocks_sight,"blocks_projectile":o.blocks_projectile}
 for key in ["loot","contents","damageable","max_durability","durability","destroyed","structure","protection","origin","installation","mobility","pickup_mode","mass_kg"]:
  if o.has(key): spec[key]=o[key]
 if o.has("light"):
  var at = lamp_position(o)
  spec.position_m=[at.x,at.y]
 entities[o.id]=SCEntity.new(spec)
 if o.blocks_movement:
  for y in range(int(o.y),int(o.y+o.h)):
   for x in range(int(o.x),int(o.x+o.w)): object_cells[Vector2i(x,y)]=o.id
 var p = Vector2(float(o.x)+float(o.w)*.5,float(o.y)+float(o.h)*.5)
 entry_chunk(chunk_at(p)).objects.append(id)

func lamp_active(o: Dictionary) -> bool:
 var l: Dictionary = o.light
 if not l.switchedOn or l.health=="broken": return false
 if l.source=="battery": return true
 for zone in data.powerZones:
  if zone.id==l.powerZoneId: return power_overrides.get(zone.id,zone.powered)
 return false

func lamp_position(o: Dictionary) -> Vector2:
 var l: Dictionary = o.light
 if l.mount=="wall":
  var e: Dictionary = l.edge
  return Vector2(float(e.x)+signf(float(l.direction[0]))*.12,float(e.y)+.5) if e.axis=="vertical" else Vector2(float(e.x)+.5,float(e.y)+signf(float(l.direction[2]))*.12)
 return Vector2(float(o.x)+.5,float(o.y)+.5)
