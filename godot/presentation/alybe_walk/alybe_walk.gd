extends Node3D

const MAP = preload("res://presentation/alybe_walk/walk_map.gd")
const GROUND_SHADER = preload("res://presentation/alybe_walk/ground.gdshader")
const VIEW_RADIUS := 3
const EYE := 1.65
const BODY_RADIUS := .24
const FONT = preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf")
const ASSETS := {
 "table":"painted_wooden_table", "desk":"painted_wooden_table", "counter":"painted_wooden_table",
 "workbench":"cabin_workbench", "chair":"metal_stool_02", "locker":"drawer_cabinet",
 "wardrobe":"drawer_cabinet", "shelf":"drawer_cabinet", "medicine":"metal_tool_chest",
 "tools":"metal_tool_chest", "cart":"tool_cart", "crates":"wooden_crate_01",
 "electric":"power_box_01", "tank":"Barrel_02", "bin":"plastic_crate_02", "tv":"television_02"
}
var map = MAP.new()
var player: CharacterBody3D
var camera: Camera3D
var lamp: SpotLight3D
var status: Label
var help: Label
var target_label: Label
var minimap: TextureRect
var marker: ColorRect
var map_overlay: PanelContainer
var loaded: Dictionary = {}
var queue: Array = []
var live_doors: Dictionary = {}
var live_lights: Dictionary = {}
var asset_cache: Dictionary = {}
var ground_materials: Dictionary = {}
var materials: Dictionary = {}
var last_chunk = Vector2i(-999,-999)
var ready_done = false
var pitch = 0.0
var time = 0.0
var ui_timer = 0.0
var grid_enabled = true
var map_path = "res://data/generated/alybe_walk.json"
var floor_colors = {1:Color("666758"),2:Color("697274"),4:Color("8f9487"),6:Color("8f9487"),7:Color("7f7764"),8:Color("8d8c78")}
var current_poi = 0
var error_text = ""

func _ready():
 Engine.max_fps = 60
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 get_window().title = "阿利贝 · 第一人称尺度漫游"
 get_window().content_scale_size = Vector2i(1280,800)
 get_window().size = Vector2i(1280,800)
 get_window().min_size = Vector2i(960,600)
 var args = OS.get_cmdline_user_args()
 for i in range(args.size()-1):
  if args[i] == "--map": map_path = args[i+1]
 make_ui()
 var result = map.load_map(map_path)
 if result != OK:
  error_text = "无法载入地图。请运行 Open Alybe Walk.command 生成地图。"
  status.text = error_text
  push_error(error_text+" "+map_path)
  return
 make_environment()
 make_player()
 make_minimap()
 make_rails()
 place_poi(0)
 ready_done = true
 get_window().focus_entered.connect(func(): update_help())
 get_window().focus_exited.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; update_help())
 update_help()

func material(key: String, color: Color, metallic := 0.0, unshaded := false) -> StandardMaterial3D:
 if materials.has(key): return materials[key]
 var mat = StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = .82
 mat.metallic = metallic
 if unshaded: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 materials[key] = mat
 return mat

func floor_material(tile: int) -> ShaderMaterial:
 if not ground_materials.has(tile):
  var mat = ShaderMaterial.new()
  mat.shader = GROUND_SHADER
  mat.set_shader_parameter("surface_color",floor_colors.get(tile,Color("696b62")))
  mat.set_shader_parameter("show_grid",grid_enabled)
  ground_materials[tile] = mat
 return ground_materials[tile]

func make_environment():
 var world = WorldEnvironment.new()
 var env = Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("172124")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("adbbb4")
 env.ambient_light_energy = float(map.data.lighting.ambient)
 env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
 env.fog_enabled = true
 env.fog_light_color = Color("223333")
 env.fog_density = .009
 env.fog_sky_affect = 0.0
 world.environment = env
 add_child(world)

func make_player():
 player = CharacterBody3D.new()
 player.name = "Surveyor"
 player.collision_layer = 8
 player.collision_mask = 7
 player.floor_snap_length = .2
 player.safe_margin = .001
 add_child(player)
 var collision = CollisionShape3D.new()
 var shape = CapsuleShape3D.new()
 shape.radius = BODY_RADIUS
 shape.height = 1.78
 collision.shape = shape
 collision.position.y = .89
 player.add_child(collision)
 camera = Camera3D.new()
 camera.position.y = EYE
 camera.fov = 75
 camera.near = .05
 camera.far = 68
 player.add_child(camera)
 camera.current = true
 lamp = SpotLight3D.new()
 lamp.light_color = Color("f3e4ba")
 lamp.light_energy = 2.0
 lamp.spot_range = 22
 lamp.spot_angle = 38
 lamp.shadow_enabled = true
 lamp.position = Vector3(.12,-.12,-.1)
 camera.add_child(lamp)

func make_ui():
 var layer = CanvasLayer.new()
 add_child(layer)
 var font = FONT
 var root = Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter = Control.MOUSE_FILTER_IGNORE
 var ui_theme = Theme.new()
 ui_theme.default_font = font
 root.theme = ui_theme
 layer.add_child(root)
 var header = ColorRect.new()
 header.color = Color(.035,.065,.068,.9)
 header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
 header.offset_bottom = 90
 header.mouse_filter = Control.MOUSE_FILTER_IGNORE
 root.add_child(header)
 status = Label.new()
 status.position = Vector2(22,12)
 status.add_theme_font_size_override("font_size",18)
 root.add_child(status)
 help = Label.new()
 help.position = Vector2(22,42)
 help.add_theme_font_size_override("font_size",14)
 root.add_child(help)
 target_label = Label.new()
 target_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 target_label.offset_left = -400
 target_label.offset_right = 400
 target_label.offset_top = -90
 target_label.offset_bottom = -30
 target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 target_label.add_theme_font_size_override("font_size",19)
 root.add_child(target_label)
 var cross = Label.new()
 cross.text = "+"
 cross.add_theme_color_override("font_color",Color("eedba3"))
 cross.add_theme_font_size_override("font_size",25)
 cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 cross.offset_left = -7
 cross.offset_top = -17
 root.add_child(cross)
 map_overlay = PanelContainer.new()
 map_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 map_overlay.offset_left = -300
 map_overlay.offset_top = -270
 map_overlay.offset_right = 300
 map_overlay.offset_bottom = 270
 map_overlay.visible = false
 root.add_child(map_overlay)
 var panel = VBoxContainer.new()
 map_overlay.add_child(panel)
 var title = Label.new()
 title.text = "地图 / 漫游定位     Tab 关闭"
 panel.add_child(title)
 minimap = TextureRect.new()
 minimap.custom_minimum_size = Vector2(600,440)
 minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
 panel.add_child(minimap)
 marker = ColorRect.new()
 marker.color = Color("ffd66b")
 marker.size = Vector2(7,7)
 minimap.add_child(marker)
 var buttons = HBoxContainer.new()
 panel.add_child(buttons)
 for i in range(4):
  var button = Button.new()
  button.text = ["1 中央车站","2 工厂入口","3 住宅入口","4 医院入口"][i]
  button.pressed.connect(func(): place_poi(i); map_overlay.hide(); Input.mouse_mode=Input.MOUSE_MODE_CAPTURED)
  buttons.add_child(button)

func make_minimap():
 var image = Image.create(map.width,map.height,false,Image.FORMAT_RGB8)
 var colors = [Color("172126"),Color("626a60"),Color("a49f82"),Color("bdb18d"),Color("a7b6aa"),Color("414d48"),Color("a7b6aa"),Color("8b805c"),Color("b3a478")]
 for y in range(map.height):
  for x in range(map.width): image.set_pixel(x,y,colors[map.tile(x,y)])
 minimap.texture = ImageTexture.create_from_image(image)

func update_help():
 if not ready_done: return
 help.text = "WASD 行走 · Shift 快行 · 鼠标 / 方向键观察 · E 开关门 · F 手电 · G 米格 · Tab 地图 · 1–4 定位 · Esc 释放鼠标"
 if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: help.text = "点击画面进入漫游；Esc 释放鼠标。  地图种子 %s / %d×%d 米" % [map.data.seed,map.width,map.height]

func _unhandled_input(event):
 if not ready_done: return
 if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not map_overlay.visible:
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
  update_help()
 if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
  player.rotation.y -= event.relative.x*.0023
  pitch = clampf(pitch-event.relative.y*.0023,-1.25,1.25)
  camera.rotation.x = pitch
 if not event is InputEventKey or not event.pressed or event.echo: return
 match event.physical_keycode:
  KEY_ESCAPE:
   map_overlay.hide()
   Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
   update_help()
  KEY_TAB:
   map_overlay.visible = not map_overlay.visible
   Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if map_overlay.visible else Input.MOUSE_MODE_CAPTURED
   update_help()
  KEY_F: lamp.visible = not lamp.visible
  KEY_G:
   grid_enabled = not grid_enabled
   for mat in ground_materials.values(): mat.set_shader_parameter("show_grid",grid_enabled)
  KEY_E:
   var target = door_target()
   if target >= 0: operate_door(target)
  KEY_1,KEY_2,KEY_3,KEY_4: place_poi(int(event.physical_keycode-KEY_1))

func _physics_process(delta: float):
 if not ready_done: return
 var direction = Vector3.ZERO
 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not map_overlay.visible:
  direction.x = float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
  direction.z = float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))
  player.rotation.y += (float(Input.is_physical_key_pressed(KEY_LEFT))-float(Input.is_physical_key_pressed(KEY_RIGHT)))*delta*1.6
  pitch = clampf(pitch+(float(Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_DOWN)))*delta,-1.25,1.25)
  camera.rotation.x = pitch
 var speed = 5.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 2.8
 direction = player.basis*direction.normalized()*speed
 player.velocity.x = direction.x
 player.velocity.z = direction.z
 player.velocity.y = minf(player.velocity.y-15*delta,0) if not player.is_on_floor() else 0.0
 player.move_and_slide()
 if player.position.y < -3: place_poi(current_poi)
 var key = map.chunk_at(Vector2(player.position.x,player.position.z))
 if key != last_chunk: request_chunks(key)

func _process(delta: float):
 if not ready_done: return
 time += delta
 for i in range(mini(2,queue.size())):
  var key: Vector2i = queue.pop_front()
  if not loaded.has(key): build_chunk(key)
 for id in live_doors:
  var group: Dictionary = map.door_groups[id]
  for entity in group.entities: entity.advance(delta)
  var item: Dictionary = live_doors[id]
  var progress: float = group.entities[0].door.progress
  item.panel.position.y = group.height*.5+2.5*progress
  item.panel.visible = progress < .999
  item.collision.disabled = progress >= .999
 ui_timer -= delta
 if ui_timer <= 0:
  ui_timer = .1
  status.text = "%s   ·   (%.1f, %.1f) m   ·   %d 个已加载区块" % [map.location(Vector2(player.position.x,player.position.z)),player.position.x,player.position.z,loaded.size()]
  var target = door_target()
  target_label.text = ""
  if target >= 0:
   var group: Dictionary = map.door_groups[target]
   target_label.text = "%s\nE  %s" % [group.name,"关闭" if group.entities[0].door.target_open else "开启"]
  else:
   var hit = inspect_ray()
   if not hit.is_empty() and hit.collider.has_meta("object_name"): target_label.text = str(hit.collider.get_meta("object_name"))
  if map_overlay.visible:
   var s = minf(minimap.size.x/map.width,minimap.size.y/map.height)
   var offset = (minimap.size-Vector2(map.width,map.height)*s)*.5
   marker.position = offset+Vector2(player.position.x,player.position.z)*s-marker.size*.5

func place_poi(index: int):
 if index >= map.pois.size(): return
 current_poi = index
 var poi: Dictionary = map.pois[index]
 var at: Vector2 = poi.at
 player.position = Vector3(at.x,.04,at.y)
 player.velocity = Vector3.ZERO
 var look: Vector2 = poi.look-at
 player.rotation.y = atan2(-look.x,-look.y)
 pitch = 0
 camera.rotation.x = 0
 queue.clear()
 var key = map.chunk_at(at)
 request_chunks(key)
 for y in range(key.y-1,key.y+2):
  for x in range(key.x-1,key.x+2):
   var near = Vector2i(x,y)
   if not loaded.has(near): build_chunk(near)
 update_help()

func request_chunks(center: Vector2i):
 last_chunk = center
 for key in loaded.keys():
  if maxi(absi(key.x-center.x),absi(key.y-center.y)) > VIEW_RADIUS+1:
   var node = loaded[key]
   if is_instance_valid(node):
    for id in node.get_meta("door_ids",[]): live_doors.erase(id)
    node.queue_free()
   loaded.erase(key)
 queue.clear()
 for y in range(center.y-VIEW_RADIUS,center.y+VIEW_RADIUS+1):
  for x in range(center.x-VIEW_RADIUS,center.x+VIEW_RADIUS+1):
   if x < 0 or y < 0 or x*MAP.CHUNK>=map.width or y*MAP.CHUNK>=map.height: continue
   var key = Vector2i(x,y)
   if not loaded.has(key): queue.append(key)
 queue.sort_custom(func(a,b): return a.distance_squared_to(center)<b.distance_squared_to(center))

func inspect_ray() -> Dictionary:
 var from = camera.global_position
 var query = PhysicsRayQueryParameters3D.create(from,from-camera.global_basis.z*3.0,7)
 return get_world_3d().direct_space_state.intersect_ray(query)

func door_target() -> int:
 var best = -1
 var distance = 2.4
 var p = Vector2(player.position.x,player.position.z)
 for id in live_doors:
  var group: Dictionary = map.door_groups[id]
  var to: Vector2 = group.center-p
  if to.length() > distance: continue
  var forward = Vector2(-camera.global_basis.z.x,-camera.global_basis.z.z).normalized()
  if to.normalized().dot(forward) < .68: continue
  var query = PhysicsRayQueryParameters3D.create(camera.global_position,Vector3(group.center.x,1.5,group.center.y),5)
  if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
  best = id
  distance = to.length()
 return best

func operate_door(id: int) -> String:
 var group: Dictionary = map.door_groups[id]
 var opened: bool = not group.entities[0].door.target_open
 if not opened:
  var size = Vector2(.16,group.width) if group.axis=="vertical" else Vector2(group.width,.16)
  if Rect2(group.center-size*.5,size).grow(BODY_RADIUS+.05).has_point(Vector2(player.position.x,player.position.z)):
   target_label.text = "请先离开门口"
   return "门口有人"
 for entity in group.entities:
  var message: String = entity.request_door(opened)
  if not message.is_empty(): return message
 return ""

func batch_box(batches: Dictionary, mat: Material, center: Vector3, size: Vector3):
 if not batches.has(mat):
  var surface = SurfaceTool.new()
  surface.begin(Mesh.PRIMITIVE_TRIANGLES)
  surface.set_material(mat)
  batches[mat] = surface
 var box = BoxMesh.new()
 box.size = size
 batches[mat].append_from(box,0,Transform3D(Basis.IDENTITY,center))

func commit_batch(parent: Node3D, batches: Dictionary, collision := true):
 if batches.is_empty(): return
 var mesh = ArrayMesh.new()
 for surface in batches.values(): surface.commit(mesh)
 var instance = MeshInstance3D.new()
 instance.mesh = mesh
 parent.add_child(instance)
 if collision:
  var body = StaticBody3D.new()
  body.collision_layer = 1
  var shape = ConcavePolygonShape3D.new()
  shape.set_faces(mesh.get_faces())
  shape.backface_collision = true
  var collider = CollisionShape3D.new()
  collider.shape = shape
  body.add_child(collider)
  parent.add_child(body)

func build_chunk(key: Vector2i):
 var x0 = key.x*MAP.CHUNK
 var y0 = key.y*MAP.CHUNK
 var x1 = mini(x0+MAP.CHUNK,map.width)
 var y1 = mini(y0+MAP.CHUNK,map.height)
 if x0<0 or y0<0 or x0>=map.width or y0>=map.height: return
 var parent = Node3D.new()
 parent.name = "Chunk_%d_%d" % [key.x,key.y]
 parent.set_meta("door_ids",[])
 add_child(parent)
 loaded[key] = parent
 var batches: Dictionary = {}
 var used: Dictionary = {}
 var ceiling_mat = material("ceiling",Color("464e49"))
 var rock_mat = material("rock",Color("404e50"))
 var wall_mat = material("wall",Color("818b7d"))
 var base_mat = material("baseboard",Color("3c514c"),.2)
 for y in range(y0,y1):
  for x in range(x0,x1):
   var t: int = map.tile(x,y)
   if t==0 or used.has(Vector2i(x,y)): continue
   var ceiling: float = map.ceiling(x,y)
   var width = 1
   while x+width<x1 and map.tile(x+width,y)==t and is_equal_approx(map.ceiling(x+width,y),ceiling) and not used.has(Vector2i(x+width,y)): width+=1
   var depth = 1
   while y+depth<y1:
    var clear = true
    for xx in range(x,x+width):
     if map.tile(xx,y+depth)!=t or not is_equal_approx(map.ceiling(xx,y+depth),ceiling) or used.has(Vector2i(xx,y+depth)): clear=false;break
    if not clear: break
    depth+=1
   for yy in range(y,y+depth):
    for xx in range(x,x+width): used[Vector2i(xx,yy)] = true
   var center = Vector3(x+width*.5,-.08,y+depth*.5)
   if t==5: batch_box(batches,wall_mat,Vector3(center.x,ceiling*.5,center.z),Vector3(width,ceiling,depth))
   else:
    batch_box(batches,floor_material(t),center,Vector3(width,.16,depth))
    batch_box(batches,ceiling_mat,Vector3(center.x,ceiling+.06,center.z),Vector3(width,.12,depth))
 for y in range(y0,y1):
  for x in range(x0,x1):
   if not map.walkable(x,y): continue
   for d in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1)]:
    if map.tile(x+d.x,y+d.y)!=0: continue
    var p = Vector3(x+.5+d.x*.7,2.9,y+.5+d.y*.7)
    batch_box(batches,rock_mat,p,Vector3(.4 if d.x else 1.0,5.8,1.0 if d.x else .4))
 var info: Dictionary = map.entry_chunk(key)
 # Merge consecutive edge-wall segments to preserve grid boundaries with few mesh submissions.
 var edge_set: Dictionary = {}
 for e in info.edges: edge_set[str(e.axis)+":"+str(int(e.x))+":"+str(int(e.y))] = e
 for e in info.edges:
  var name = str(e.axis)+":"+str(int(e.x))+":"+str(int(e.y))
  if not edge_set.has(name): continue
  var x = int(e.x)
  var y = int(e.y)
  var vertical: bool = e.axis=="vertical"
  var h: float = maxf(map.ceiling(x,y),map.ceiling(x-1 if vertical else x,y if vertical else y-1))
  var length = 0
  while true:
   var xx = x if vertical else x+length
   var yy = y+length if vertical else y
   var k = str(e.axis)+":"+str(xx)+":"+str(yy)
   if not edge_set.has(k): break
   var next_h: float = maxf(map.ceiling(xx,yy),map.ceiling(xx-1 if vertical else xx,yy if vertical else yy-1))
   if not is_equal_approx(next_h,h): break
   edge_set.erase(k)
   length+=1
  var at = Vector3(x,h*.5,y)+ (Vector3(0,0,length*.5) if vertical else Vector3(length*.5,0,0))
  var size = Vector3(.14,h,length) if vertical else Vector3(length,h,.14)
  batch_box(batches,wall_mat,at,size)
  size.y = .15
  batch_box(batches,base_mat,Vector3(at.x,.075,at.z),size+Vector3(.025,0,.025))
 commit_batch(parent,batches)
 for id in info.doors: build_door(parent,int(id))
 for id in info.objects: build_object(parent,map.objects[id])
 for label in info.labels:
  var sign = Label3D.new()
  sign.font = FONT
  sign.text = label.text
  sign.font_size = 38
  sign.pixel_size = .006
  sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
  sign.position = Vector3(label.at.x,2.65,label.at.y)
  sign.modulate = Color("e5d7b0")
  sign.visibility_range_end = 18
  parent.add_child(sign)

func build_door(parent: Node3D, id: int):
 var group: Dictionary = map.door_groups[id]
 var root = Node3D.new()
 root.position = Vector3(group.center.x,0,group.center.y)
 if group.axis=="vertical": root.rotation.y = PI*.5
 parent.add_child(root)
 var panel = Node3D.new()
 root.add_child(panel)
 var mesh = MeshInstance3D.new()
 var box = BoxMesh.new()
 box.size = Vector3(group.width-.035,group.height,.13)
 mesh.mesh = box
 mesh.material_override = material("door",Color("65766e"),.35)
 panel.add_child(mesh)
 var body = StaticBody3D.new()
 body.collision_layer = 2
 body.set_meta("door_index",id)
 var collider = CollisionShape3D.new()
 var shape = BoxShape3D.new()
 shape.size = box.size
 collider.shape = shape
 body.add_child(collider)
 panel.add_child(body)
 var lintel: Dictionary = {}
 var h: float = maxf(0.1,group.wall_height-group.height)
 batch_box(lintel,material("door_frame",Color("40544c"),.4),Vector3(0,group.height+h*.5,0),Vector3(group.width,h,.16))
 commit_batch(root,lintel)
 live_doors[id] = {"root":root,"panel":panel,"collision":collider}
 parent.get_meta("door_ids").append(id)
 panel.position.y = group.height*.5+2.5*group.entities[0].door.progress

func collect_meshes(node: Node, transform: Transform3D, out: Array, part: String):
 var at = transform
 if node is Node3D: at=transform*node.transform
 if node is MeshInstance3D and (part.is_empty() or node.name==part): out.append({"mesh":node.mesh,"transform":at})
 for child in node.get_children(): collect_meshes(child,at,out,part)

func make_asset(id: String, footprint: Vector2, max_height: float, part := "") -> Node3D:
 var key = id+":"+part
 if not asset_cache.has(key):
  var path = "res://assets/environment/"+id+"/parts.gltf"
  if id=="cabin_workbench": path="res://assets/environment/cabin_workbench/workbench.gltf"
  if id=="television_02": path="res://assets/environment/television_02/television_02_2k.gltf"
  var scene = load(path)
  if not scene is PackedScene: asset_cache[key]=null;return null
  var source = scene.instantiate()
  var entries: Array = []
  collect_meshes(source,Transform3D.IDENTITY,entries,part)
  var combined = ArrayMesh.new()
  for item in entries:
   for surface in range(item.mesh.get_surface_count()):
    var tool = SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(item.mesh.surface_get_material(surface))
    tool.append_from(item.mesh,surface,item.transform)
    tool.commit(combined)
  source.free()
  asset_cache[key] = {"mesh":combined,"bounds":combined.get_aabb()}
 var template = asset_cache[key]
 if template==null: return null
 var bounds: AABB = template.bounds
 var factor = minf(minf(footprint.x/maxf(bounds.size.x,.01),footprint.y/maxf(bounds.size.z,.01)),max_height/maxf(bounds.size.y,.01))
 var mesh = MeshInstance3D.new()
 mesh.mesh = template.mesh
 mesh.scale = Vector3.ONE*factor
 mesh.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
 mesh.visibility_range_end = 48
 var pivot = Node3D.new()
 pivot.add_child(mesh)
 return pivot

func diagnostic_outline(size: Vector3) -> MeshInstance3D:
 var vertices = PackedVector3Array()
 var p: Array[Vector3] = []
 for z in [0.0,size.z]:
  for y in [0.0,size.y]:
   for x in [0.0,size.x]: p.append(Vector3(x,y,z)-Vector3(size.x*.5,0,size.z*.5))
 for edge in [[0,1],[0,2],[1,3],[2,3],[4,5],[4,6],[5,7],[6,7],[0,4],[1,5],[2,6],[3,7]]:
  vertices.append(p[edge[0]]);vertices.append(p[edge[1]])
 var arrays: Array = []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 var mesh = ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
 var instance = MeshInstance3D.new()
 instance.mesh = mesh
 instance.material_override = material("diagnostic",Color("c6b782"),0,true)
 instance.visibility_range_end = 20
 return instance

func build_object(parent: Node3D, object: Dictionary):
 if object.has("light"):
  build_lamp(parent,object)
  return
 var h: float = object.height_m
 var center = Vector3(float(object.x)+float(object.w)*.5,float(object.bottom_m),float(object.y)+float(object.h)*.5)
 var size = Vector3(float(object.w)-.10,h,float(object.h)-.10)
 var model: Node3D = null
 if ASSETS.has(object.type):
  var quarter_turn = int(object.rotation)%180!=0
  model=make_asset(ASSETS[object.type],Vector2(size.z,size.x) if quarter_turn else Vector2(size.x,size.z),h)
  if model: model.rotation.y=deg_to_rad(float(object.rotation))
 if model: model.position=center;parent.add_child(model)
 else:
  for part in object.structure.parts:
   var dimensions: Array = part.size_m
   var offset: Array = part.offset_m
   var part_size = Vector3(dimensions[0],dimensions[1],dimensions[2])
   var at = center-Vector3(float(object.w)*.5,0,float(object.h)*.5)+Vector3(float(offset[0])+part_size.x*.5,float(offset[1]),float(offset[2])+part_size.z*.5)
   var outline = diagnostic_outline(part_size)
   outline.position = at
   parent.add_child(outline)
  var label = Label3D.new()
  label.font = FONT
  label.text = object.name+" · 占地"
  label.position = center+Vector3(0,h+.1,0)
  label.font_size = 30
  label.pixel_size = .006
  label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
  label.modulate = Color("d6cda8")
  label.visibility_range_end = 9
  parent.add_child(label)
 if map.entities[object.id].blocks("movement"):
  var body = StaticBody3D.new()
  body.collision_layer = 4
  body.position = center+Vector3(0,h*.5,0)
  body.set_meta("object_name",object.name+" / %d×%d 米占地"%[object.w,object.h])
  var shape = BoxShape3D.new()
  shape.size = size
  var collider = CollisionShape3D.new()
  collider.shape = shape
  body.add_child(collider)
  parent.add_child(body)

func build_lamp(parent: Node3D, object: Dictionary):
 var record: Dictionary = object.light
 var light = SpotLight3D.new()
 light.name = object.id
 var point = map.lamp_position(object)
 var at = Vector3(point.x,float(object.bottom_m),point.y)
 var direction = Vector3(float(record.direction[0]),float(record.direction[1]),float(record.direction[2]))
 parent.add_child(light)
 light.look_at_from_position(at,at+direction,Vector3.FORWARD if absf(direction.y)>.98 else Vector3.UP)
 light.spot_range = float(record.range_m)
 light.spot_angle = float(record.cone_degrees)*.5
 light.spot_attenuation = 1.3
 light.light_color = Color(record.color)
 light.light_energy = float(record.energy)*(.45 if record.health=="damaged" else 1.0) if map.lamp_active(object) else 0.0
 light.shadow_enabled = true
 light.distance_fade_enabled = true
 light.distance_fade_begin = 24
 light.distance_fade_length = 12
 light.distance_fade_shadow = 20
 live_lights[object.id]=light
 light.tree_exiting.connect(func(): live_lights.erase(object.id))
 var fixture = make_asset("mounted_fluorescent_lights",Vector2(.8,.35),.12,"mounted_fluorescent_lights_a")
 if fixture:
  fixture.position=at+Vector3(0,.13,0)
  parent.add_child(fixture)

func set_power(zone_id: String, powered: bool):
 map.power_overrides[zone_id]=powered
 for object in map.objects:
  if not object.has("light") or not live_lights.has(object.id): continue
  var record: Dictionary = object.light
  live_lights[object.id].light_energy=float(record.energy)*(.45 if record.health=="damaged" else 1.0) if map.lamp_active(object) else 0.0

func make_rails():
 var batches: Dictionary = {}
 var steel = material("rail",Color("84978e"),.72)
 var sleeper = material("sleeper",Color("4a514b"))
 for line in map.data.tram:
  var points: Array = line.points
  var travelled = 0.0
  for i in range(1,points.size()):
   var a = Vector2(float(points[i-1][0]),float(points[i-1][1]))
   var b = Vector2(float(points[i][0]),float(points[i][1]))
   var length = a.distance_to(b)
   if length<.0001: continue
   var normal = Vector2(-(b.y-a.y),(b.x-a.x))/length
   var middle = (a+b)*.5
   var yaw = atan2((b-a).x,(b-a).y)
   for offset in [-1.45,-.55,.55,1.45]:
    var box = BoxMesh.new()
    box.size = Vector3(.055,.025,length+.02)
    var tool: SurfaceTool
    if not batches.has(steel): tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);tool.set_material(steel);batches[steel]=tool
    tool=batches[steel]
    tool.append_from(box,0,Transform3D(Basis(Vector3.UP,yaw),Vector3(middle.x+normal.x*offset,.024,middle.y+normal.y*offset)))
   travelled+=length
   if travelled>1.3:
    travelled=0.0
    for offset in [-1.0,1.0]:
     var box = BoxMesh.new()
     box.size=Vector3(1.4,.012,.15)
     if not batches.has(sleeper):
      var tool =SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);tool.set_material(sleeper);batches[sleeper]=tool
     batches[sleeper].append_from(box,0,Transform3D(Basis(Vector3.UP,yaw),Vector3(middle.x+normal.x*offset,.01,middle.y+normal.y*offset)))
 commit_batch(self,batches,false)
