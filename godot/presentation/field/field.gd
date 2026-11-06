extends Control
## A new command scene. SCWorld/SCPlanner own actors, time, movement and queues.
signal picture_changed
const ACTOR = preload("res://presentation/tactical/tactical_actor.gd")
const SURFACE = preload("res://presentation/rendering/surface.gdshader")
const OUTLINE = preload("res://presentation/rendering/object_outline.gd")
const OVERLAY = preload("res://presentation/field/field_overlay.gd")
const FONT = preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf")
const COLORS = [Color("a6cbb7"),Color("d7c08b"),Color("8fb9ce"),Color("c3a8bc")]
const RENDER_SCALE := 0.75
var input_active := false
var ui_pointer_inside := false
var started := false
var loading := false
var models_ready := false
var loading_started_usec := 0
var render_live := false
var simulation: SCWorld
var clock_time: float:
 get: return simulation.time if started else idle_time
var idle_time := 0.0
var view: SubViewport
var world: Node3D
var camera: Camera3D
var compose: SubViewport
var ui_layer: Control
var object_outline: RefCounted
var menu: Control
var start_button: Button
var field_ui: Control
var overlay: Control
var friendly_overlay: Control
var units_root: Node3D
var units: Dictionary = {}
var assets: Array[Node3D] = []
var font: FontFile
var selected: Array = []
var groups := {KEY_F1:[],KEY_F2:[]}
var pointer := Vector2(-10000,-10000)
var pointer_world := Vector2.ZERO
var map_rect := Rect2()
var pan_center := Vector2(20,33)
var view_height := 34.0
var speed := 1.0
var tool_mode := ""
var guard_anchor := Vector2.ZERO
var left_drag := false
var right_drag := false
var pan_drag := false
var drag_start := Vector2.ZERO
var right_world := Vector2.ZERO
var drag_ids: Array = []
var drag_append := false
var preview_paths := {}
var preview_signature := ""
var last_selection_key := 0
var last_selection_time := 0
var hud_tick := 0.0
var cards: Dictionary = {}
var selected_label: Label
var queue_label: Label
var detail_label: Label
var feedback: Label
var time_label: Label
var pause_button: Button
var speed_button: Button
var command_buttons: Array[Button] = []

const CHUNK_METRES := 32.0
const OVERVIEW_HEIGHT := 112.0
var map_bounds := Rect2(0,0,500,500)
var fog_image: Image
var fog_texture: ImageTexture
var fog_revision := 0
var last_visibility_version := -1
var last_knowledge_version := -1
var previous_visible: Dictionary = {}
var explored_chunks: Dictionary = {}
var camera_revision := 0
var scene_dirty := true
var mask_dirty := true
var overlay_dirty := true
var ui_dirty := true
var resident_dirty := true
var chunk_specs: Dictionary = {}
var chunks: Dictionary = {}
var pending_assets: Array = []
var pending_asset_keys: Dictionary = {}
var entity_nodes: Dictionary = {}
var known_entity_signatures: Dictionary = {}
var asset_scenes: Dictionary = {}
var asset_bounds: Dictionary = {}
var asset_loads: Dictionary = {}
var pending_upgrades: Dictionary = {}
var scene_materials: Array[ShaderMaterial] = []
var actor_signatures: Dictionary = {}
var rendered_actors: Array = []
var preview_request := -1
var preview_state := ""
var preview_since := 0
var queue_paths: Dictionary = {}
var queue_signature := ""
var selected_style: StyleBoxFlat
var unselected_style: StyleBoxFlat
var hud_signature := ""
var performance_label: Label
var performance_visible := false
var performance_elapsed := 0.0
var performance_samples := 0
var performance_usec := 0
var performance_previous_tick := 0
var last_render_time := -1.0
var picture_revision := 0
var overview := false
var overview_items: Array = []
var rendered_actor_signature := 0
var recent_sound := ""
var recent_sound_time := -10.0
var sound_seen: Dictionary = {}
var heard_sounds: Array = []
var actor_shots: Dictionary = {}
var heard_signature := 0
# Local runtime CSV instrumentation is opt-in and does not enable the profiler.
var runtime_timing_enabled := false
var frame_cpu_usec := 0
var simulation_cpu_usec := 0
var presentation_cpu_usec := 0
var ui_cpu_usec := 0
var timing_frame_index := -1

var details_open := false
var header_panel: Panel
var details_panel: Panel
var queue_scroll: ScrollContainer
var zoom_label: Label
var details_button: Button
var footer_label: Label
var zoom_target_height := 34.0
var zoom_start_height := 34.0
var zoom_elapsed := 0.0
var zoom_active := false
var zoom_anchor_screen := Vector2.ZERO
var zoom_anchor_world := Vector2.ZERO
var zoom_center_target = null
var zoom_start_center := Vector2.ZERO
const ZOOM_DURATION := .14
const UI_MARGIN_X := 56.0
const UI_HEADER_Y := 40.0
const UI_HEADER_HEIGHT := 86.0
const UI_MAP_TOP := UI_HEADER_Y+UI_HEADER_HEIGHT+8.0
const UI_CARD_HEIGHT := 92.0
const UI_CARD_BOTTOM := 60.0
const UI_FOOTER_BOTTOM := 52.0
const UI_FOOTER_X := 96.0
var marker_layout: Dictionary = {}
var squad_markers: Array = []
var marker_signature := 0
var preview_error := ""
var preview_target = null
var drag_takeover := ""
var transient_feedback := ""
var transient_feedback_until := 0
var transient_feedback_error := false

func _ready():
 for argument in OS.get_cmdline_args()+OS.get_cmdline_user_args():
  if argument.begins_with("--runtime-log="):runtime_timing_enabled=true;break
 if not SCData.ensure_valid(get_tree()): return
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 font = FONT.duplicate()
 font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
 font.hinting = TextServer.HINTING_NONE
 font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
 view = SubViewport.new()
 view.own_world_3d = true
 view.msaa_3d = Viewport.MSAA_2X
 view.positional_shadow_atlas_size = 2048
 add_child(view)
 world = Node3D.new();view.add_child(world)
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color.BLACK
 environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color = Color("a0b7ba")
 environment.environment.ambient_light_energy = 0.48
 environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 world.add_child(environment)
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.near = 0.05;camera.far = 150
 view.add_child(camera);camera.current = true
 units_root = Node3D.new();world.add_child(units_root)
 object_outline = OUTLINE.new()
 object_outline.configure(self,view,world,camera,units_root,assets,Vector2i(1728,1080))
 compose = SubViewport.new()
 compose.disable_3d = true
 compose.transparent_bg = true
 add_child(compose)
 ui_layer = Control.new()
 ui_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
 ui_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 compose.add_child(ui_layer)
 menu = Control.new();menu.mouse_filter = Control.MOUSE_FILTER_IGNORE;ui_layer.add_child(menu)
 start_button = button(menu,"启动测试场景",Vector2.ZERO,Vector2(600,108),start_scene)
 start_button.add_theme_font_size_override("font_size",36)
 set_display_size(get_viewport().size)
 set_render_live(false)

func set_display_size(value: Vector2i):
 cancel_interaction()
 size = Vector2(value)
 var render_size := Vector2i(Vector2(value)*RENDER_SCALE)
 for viewport in [view,object_outline.mask_view,object_outline.output]: viewport.size = render_size
 object_outline.output.get_child(0).size = render_size
 object_outline.material.set_shader_parameter("resolution",Vector2(render_size))
 compose.size = value;ui_layer.size = size
 update_layout_metrics()
 start_button.position = (size-start_button.size)*0.5
 if started: build_command_ui()
 apply_camera()
 mark_scene_dirty(true);ui_dirty=true

func set_render_live(value: bool):
 render_live=value
 # Sources are retained between invalidations; input delivery never waits for a redraw.
 if value:mark_scene_dirty(true);ui_dirty=true
 else:
  for viewport in [view,object_outline.mask_view,object_outline.output,compose]:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func controlled_actors() -> Array:
 var result: Array=[]
 if not started:return result
 for id in simulation.controlled_ids:
  var character: SCActor=simulation.actor(id)
  if character:result.append(character)
 return result

func start_scene():
 if started or loading:return
 loading=true;loading_started_usec=Time.get_ticks_usec()
 start_button.text="正在载入场景…";start_button.disabled=true
 ui_dirty=true;compose.render_target_update_mode=SubViewport.UPDATE_ONCE;picture_revision+=1
 # Give the UI texture and outer CRT composition two normal display frames.
 # Duplicate clicks remain gated while the authoritative world is constructed.
 await get_tree().process_frame
 await get_tree().process_frame
 var world_started:=Time.get_ticks_usec()
 simulation=SCWorld.new("field")
 simulation.perception.refresh(simulation,0.0,true);simulation.set_paused(true)
 print("FIELD_STAGE world_ms=",snappedf(float(Time.get_ticks_usec()-world_started)/1000.0,.1))
 var scene_started:=Time.get_ticks_usec()
 started=true
 map_bounds=simulation.grid.bounds
 selected=simulation.controlled_ids.duplicate()
 groups[KEY_F1]=selected.slice(0,2);groups[KEY_F2]=selected.slice(2,4)
 var entry: Array=simulation.scene_definition.get("entry_camera_m",[map_bounds.get_center().x,map_bounds.end.y-30])
 pan_center=Vector2(entry[0],entry[1]);view_height=float(simulation.scene_definition.get("entry_view_height_m",40.0));zoom_target_height=view_height
 fog_image=Image.create(int(map_bounds.size.x),int(map_bounds.size.y),false,Image.FORMAT_RG8)
 fog_image.fill(Color(0,0,0,1));fog_texture=ImageTexture.create_from_image(fog_image)
 object_outline.set_knowledge(fog_texture,map_bounds)
 menu.visible=false
 build_environment();build_command_ui();apply_camera()
 pointer=Vector2(-10000,-10000)
 refresh_knowledge(true)
 set_render_live(input_active);refresh_hud();picture_changed.emit()
 print("FIELD_STAGE scene_ms=",snappedf(float(Time.get_ticks_usec()-scene_started)/1000.0,.1))
 log_first_picture_ready()

func log_first_picture_ready():
 await RenderingServer.frame_post_draw
 # Markers already represent every legal visible actor. Detailed rigs start
 # after this first real frame and are added one per display frame below.
 models_ready=true;loading=false
 print("FIELD_STAGE first_picture_ready_ms=",snappedf(float(Time.get_ticks_usec()-loading_started_usec)/1000.0,.1))

func mark_scene_dirty(with_mask := false):
 scene_dirty=true
 if with_mask:mask_dirty=true

func apply_material_knowledge(item: ShaderMaterial):
 if not fog_texture:return
 item.set_shader_parameter("knowledge_texture",fog_texture)
 item.set_shader_parameter("knowledge_bounds",Vector4(map_bounds.position.x,map_bounds.position.y,map_bounds.size.x,map_bounds.size.y))
 item.set_shader_parameter("knowledge_enabled",true)

func knowledge_state(point: Vector2) -> int:
 var cell:=SCData.cell_of(point)
 if simulation.perception.visible_cells.has(cell):return 2
 return 1 if simulation.perception.explored.has(cell) else 0

func refresh_knowledge(force := false):
 var perception: SCPerception=simulation.perception
 var visibility: int=perception.visibility_version
 var knowledge: int=perception.knowledge_version
 var visibility_changed:=force or visibility!=last_visibility_version
 if not visibility_changed and knowledge==last_knowledge_version:return
 last_visibility_version=visibility;last_knowledge_version=knowledge
 if visibility_changed:
  for cell: Vector2i in previous_visible:
   var pixel:=cell-Vector2i(map_bounds.position)
   if pixel.x>=0 and pixel.y>=0 and pixel.x<fog_image.get_width() and pixel.y<fog_image.get_height():fog_image.set_pixelv(pixel,Color(0,1,0,1))
  if force:
   for cell: Vector2i in perception.explored:
    var pixel:=cell-Vector2i(map_bounds.position)
    if pixel.x>=0 and pixel.y>=0 and pixel.x<fog_image.get_width() and pixel.y<fog_image.get_height():fog_image.set_pixelv(pixel,Color(0,1,0,1))
    explored_chunks[chunk_at(Vector2(cell))]=true
  for cell: Vector2i in perception.visible_cells:
   var pixel:=cell-Vector2i(map_bounds.position)
   if pixel.x>=0 and pixel.y>=0 and pixel.x<fog_image.get_width() and pixel.y<fog_image.get_height():fog_image.set_pixelv(pixel,Color(1,1,0,1))
   explored_chunks[chunk_at(Vector2(cell))]=true
  previous_visible=perception.visible_cells.duplicate()
  fog_texture.update(fog_image);fog_revision+=1
 resident_dirty=true;overlay_dirty=true;mark_scene_dirty(true)
 update_overview_items()

func crt_fog_parameters() -> Dictionary:
 if not started:return {"enabled":false}
 var origin:=screen_to_world(Vector2.ZERO)
 return {"enabled":true,"texture":fog_texture,"bounds":Vector4(map_bounds.position.x,map_bounds.position.y,map_bounds.size.x,map_bounds.size.y),
  "view_origin":origin,"view_axis_x":screen_to_world(Vector2(size.x,0))-origin,"view_axis_y":screen_to_world(Vector2(0,size.y))-origin,
  "map_rect":Vector4(map_rect.position.x,map_rect.position.y,map_rect.size.x,map_rect.size.y),"display_size":size}

func chunk_at(point: Vector2) -> Vector2i:return Vector2i(floori((point.x-map_bounds.position.x)/CHUNK_METRES),floori((point.y-map_bounds.position.y)/CHUNK_METRES))

func map_view_bounds() -> Rect2:
 return Rect2(screen_to_world(map_rect.position),screen_to_world(map_rect.end)-screen_to_world(map_rect.position)).abs()

func add_chunk_spec(position_: Vector2, spec: Dictionary):
 var key:=chunk_at(position_)
 if not chunk_specs.has(key):chunk_specs[key]=[]
 chunk_specs[key].append(spec)

func make_floor(rect: Rect2, elevation: float, color: Color):
 var node:=box(Vector3(rect.get_center().x,elevation,rect.get_center().y),Vector3(rect.size.x,.04,rect.size.y),color,false)
 var item:=ShaderMaterial.new();item.shader=preload("res://presentation/field/field_floor.gdshader")
 item.set_shader_parameter("base_color",color);item.set_shader_parameter("metre_grid",true)
 apply_material_knowledge(item);node.material_override=item
 object_outline.register_subtree(node)

func build_environment():
 make_floor(map_bounds,-.03,Color("4a5757"))
 for road: Array in simulation.scene_definition.get("roads",[]):make_floor(Rect2(road[0],road[1],road[2],road[3]),-.005,Color("39494b"))
 for patch: Dictionary in simulation.scene_definition.get("floor_patches",[]):
  var rect: Array=patch.rect_m
  make_floor(Rect2(rect[0],rect[1],rect[2],rect[3]),.005,Color(patch.color))
 for run: Dictionary in simulation.scene_definition.wall_runs:
  var horizontal: bool=run.direction=="N"
  var length_: float=run.length_m
  var start:=Vector2(run.position_m[0],run.position_m[1])
  var offset:=0.0
  while offset<length_:
   var segment:=minf(8.0,length_-offset)
   var center:=start+(Vector2(offset+segment*.5,0) if horizontal else Vector2(0,offset+segment*.5))
   add_chunk_spec(center,{"kind":"wall","position":center,"length":segment,"horizontal":horizontal})
   offset+=segment
 for spec: Dictionary in simulation.scene_definition.entities:
  add_chunk_spec(Vector2(spec.position_m[0],spec.position_m[1]),{"kind":"entity","id":str(spec.id)})
 var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-68,-30,0)
 key.light_color=Color("c8d5cf");key.light_energy=.7;key.shadow_enabled=true
 key.directional_shadow_max_distance=95;key.shadow_bias=.025;key.shadow_normal_bias=.4;world.add_child(key)

func resident_chunks():
 resident_dirty=false
 var desired: Dictionary={}
 if not overview:
  var region:=map_view_bounds().grow(CHUNK_METRES)
  var first:=chunk_at(region.position);var last:=chunk_at(region.end)
  for y in range(first.y,last.y+1):
   for x in range(first.x,last.x+1):
    var key:=Vector2i(x,y)
    if explored_chunks.has(key) and chunk_specs.has(key):desired[key]=true
 for key in chunks.keys():
  if desired.has(key):continue
  var root: Node3D=chunks[key]
  object_outline.unregister_subtree(root)
  for id in entity_nodes.keys():
   if root.is_ancestor_of(entity_nodes[id]):entity_nodes.erase(id);known_entity_signatures.erase(id);pending_upgrades.erase(id)
  root.visible=false;root.queue_free();chunks.erase(key);mark_scene_dirty(true)
 for key in desired:
  if chunks.has(key):
   for spec: Dictionary in chunk_specs[key]:
    if spec.kind=="entity" and not entity_nodes.has(spec.id) and not pending_asset_keys.has(spec.id) and simulation.perception.known_entities.has(spec.id):
     pending_assets.append({"id":spec.id,"chunk":key});pending_asset_keys[spec.id]=true
   continue
  var root:=Node3D.new();root.name="Resident_%d_%d" % [key.x,key.y];world.add_child(root);chunks[key]=root
  for spec: Dictionary in chunk_specs[key]:
   if spec.kind=="wall":
    var dimensions:=Vector3(spec.length,1.25,.14) if spec.horizontal else Vector3(.14,1.25,spec.length)
    var item:=box(Vector3(spec.position.x,.625,spec.position.y),dimensions,Color("41565b"))
    item.reparent(root,true)
    item.set_meta("outline_group","wall_"+str(item.get_instance_id()))
    object_outline.register_subtree(item)
   elif not entity_nodes.has(spec.id) and not pending_asset_keys.has(spec.id):
    pending_assets.append({"id":spec.id,"chunk":key});pending_asset_keys[spec.id]=true
  mark_scene_dirty(true)
 # Update observed state on the same display node, including remembered doors.
 for id in entity_nodes.keys():
  var snapshot: Dictionary=simulation.perception.known_entities.get(id,{})
  if snapshot.is_empty():continue
  var signature:=hash([snapshot.position,snapshot.facing,snapshot.door_progress,snapshot.exists,snapshot.ruined,snapshot.definition])
  if known_entity_signatures.get(id)==signature:continue
  known_entity_signatures[id]=signature
  apply_entity_memory(entity_nodes[id],snapshot);object_outline.sync_subtree(entity_nodes[id]);mark_scene_dirty(true)

func load_resident_assets():
 var deadline:=Time.get_ticks_usec()+1800
 var created:=0
 while not pending_assets.is_empty() and Time.get_ticks_usec()<deadline and created<3:
  var entry: Dictionary=pending_assets.pop_front();pending_asset_keys.erase(entry.id)
  if not chunks.has(entry.chunk) or entity_nodes.has(entry.id):continue
  var snapshot: Dictionary=simulation.perception.known_entities.get(entry.id,{})
  if snapshot.is_empty() or not snapshot.exists:continue
  var node:=place_asset(snapshot.definition)
  node.reparent(chunks[entry.chunk],true);entity_nodes[entry.id]=node
  apply_entity_memory(node,snapshot);object_outline.register_subtree(node,"asset_"+entry.id)
  if node.has_meta("pending_asset"):pending_upgrades[entry.id]=node.get_meta("pending_asset")
  known_entity_signatures.erase(entry.id);created+=1;mark_scene_dirty(true)
 for asset in asset_loads.keys():
  var path: String=asset_loads[asset]
  if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_LOADED:
   asset_scenes[asset]=ResourceLoader.load_threaded_get(path);asset_loads.erase(asset)
   print("FIELD_ASSET_READY ",asset)
 for id in pending_upgrades.keys():
  if Time.get_ticks_usec()>=deadline or created>=3:break
  if not entity_nodes.has(id):pending_upgrades.erase(id);continue
  var asset: String=pending_upgrades[id]
  if not asset_scenes.has(asset):continue
  var snapshot: Dictionary=simulation.perception.known_entities.get(id,{})
  if snapshot.is_empty():continue
  var previous: Node3D=entity_nodes[id];var parent:=previous.get_parent()
  var node:=place_asset(snapshot.definition);node.reparent(parent,true);apply_entity_memory(node,snapshot)
  object_outline.unregister_subtree(previous);previous.visible=false;previous.queue_free()
  entity_nodes[id]=node;object_outline.register_subtree(node,"asset_"+id)
  pending_upgrades.erase(id);known_entity_signatures.erase(id);created+=1;mark_scene_dirty(true)
  print("FIELD_ASSET_UPGRADED ",id," ",asset)

func place_asset(spec: Dictionary) -> Node3D:
 var node: Node3D
 var asset: String=spec.get("asset","")
 if not asset.is_empty() and not asset_scenes.has(asset) and not asset_loads.has(asset):
  var path: String="res://assets/environment/"+asset+"/parts.gltf"
  if ResourceLoader.load_threaded_request(path,"PackedScene")==OK:asset_loads[asset]=path
 if not asset.is_empty() and asset_scenes.has(asset):
  node=asset_scenes[asset].instantiate();world.add_child(node)
  var bounds:=AABB();var first:=true
  for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
   if not asset_bounds.has(asset):
    var b: AABB=node.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
    bounds=b if first else bounds.merge(b);first=false
   for surface in range(mesh.mesh.get_surface_count()):
    var previous: Material=mesh.get_active_material(surface);var color:=Color("7f9186")
    if previous is BaseMaterial3D:color=previous.albedo_color
    mesh.set_surface_override_material(surface,material(color))
  if not asset_bounds.has(asset):asset_bounds[asset]=bounds
  bounds=asset_bounds[asset]
  var footprint:=Vector2(spec.get("footprint_m",[1,1])[0],spec.get("footprint_m",[1,1])[1])
  var fit:=minf(minf(footprint.x/maxf(.01,bounds.size.x),footprint.y/maxf(.01,bounds.size.z))*.92,float(spec.get("height_m",1.25))/maxf(.01,bounds.size.y))
  node.scale=Vector3.ONE*fit
  node.set_meta("local_offset",-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*fit)
 else:
  node=Node3D.new();world.add_child(node)
  var footprint:=Vector2(spec.get("footprint_m",[1,.16])[0],spec.get("footprint_m",[1,.16])[1])
  var dimensions:=Vector3(footprint.x,minf(1.25,float(spec.get("height_m",1.25))),footprint.y)
  var body:=box(Vector3(0,dimensions.y*.5,0),dimensions,Color("71817b"));body.name="DoorLeaf" if spec.has("door") else "Body";body.reparent(node,false)
  if spec.has("door"):
   for side in [-1.0,1.0]:
    var frame:=box(Vector3(side*(footprint.x*.5+.035),.65,0),Vector3(.07,1.3,.18),Color("a3ada1"));frame.reparent(node,false)
   var frame:=box(Vector3(0,1.32,0),Vector3(footprint.x+.14,.07,.18),Color("a3ada1"));frame.reparent(node,false)
  node.set_meta("local_offset",Vector3.ZERO)
 if not asset.is_empty() and not asset_scenes.has(asset):node.set_meta("pending_asset",asset)
 node.set_meta("source_asset",asset);node.set_meta("display_height",minf(1.25,float(spec.get("height_m",1.25))))
 return node

func apply_entity_memory(node: Node3D, snapshot: Dictionary):
 node.visible=bool(snapshot.exists)
 var at: Vector2=snapshot.position
 node.position=Vector3(at.x,0,at.y)+Vector3(node.get_meta("local_offset",Vector3.ZERO))
 node.rotation.y=-float(snapshot.facing)+deg_to_rad(float(snapshot.definition.get("asset_yaw",0)))
 if snapshot.definition.has("door"):
  var leaf: Node3D=node.get_node("DoorLeaf")
  var progress:=clampf(float(snapshot.door_progress),0,1)
  leaf.visible=progress<.999;leaf.scale.y=maxf(.001,1.0-progress);leaf.position.y=.625+progress*.625

func update_overview_items():
 overview_items.clear()
 if not overview:return
 for id in simulation.perception.known_entities:
  var snapshot: Dictionary=simulation.perception.known_entities[id]
  if not snapshot.exists:continue
  var footprint: Array=snapshot.definition.get("footprint_m",[1,1])
  overview_items.append({"position":snapshot.position,"size":Vector2(footprint[0],footprint[1]),"kind":"entity"})
 for key in chunk_specs:
  if not explored_chunks.has(key):continue
  for spec: Dictionary in chunk_specs[key]:
   if spec.kind=="wall":overview_items.append(spec)

func material(color: Color, outlined := true) -> ShaderMaterial:
 var m := ShaderMaterial.new();m.shader = SURFACE
 m.set_shader_parameter("base_color",color);m.set_meta("outlined",outlined)
 apply_material_knowledge(m)
 return m

func box(at: Vector3, dimensions: Vector3, color: Color, outlined := true) -> MeshInstance3D:
 var item := MeshInstance3D.new()
 var mesh := BoxMesh.new();mesh.size = dimensions
 item.mesh = mesh;item.material_override = material(color,outlined);item.position = at
 world.add_child(item)
 return item

func style(background: Color, border: Color) -> StyleBoxFlat:
 var value := StyleBoxFlat.new();value.bg_color=background;value.border_color=border;value.set_border_width_all(2)
 value.content_margin_left=8;value.content_margin_right=8;value.content_margin_top=6;value.content_margin_bottom=6
 return value

func panel(parent: Control, rect: Rect2) -> Panel:
 var result := Panel.new();result.position=rect.position;result.size=rect.size
 result.add_theme_stylebox_override("panel",style(Color("101d21"),Color("3e5559")))
 parent.add_child(result);return result

func label(parent: Control, text: String, at: Vector2, pixels := 24, color := Color("b7c8c3")) -> Label:
 var result := Label.new();result.text=text;result.position=at
 result.add_theme_font_override("font",font);result.add_theme_font_size_override("font_size",pixels)
 result.add_theme_color_override("font_color",color);result.mouse_filter=Control.MOUSE_FILTER_IGNORE
 parent.add_child(result);return result

func button(parent: Control, text: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
 var result := Button.new();result.position=at;result.size=dimensions;result.text=text;result.focus_mode=Control.FOCUS_NONE
 result.add_theme_font_override("font",font);result.add_theme_font_size_override("font_size",20)
 result.add_theme_color_override("font_color",Color("d6e0d5"))
 result.add_theme_color_override("font_disabled_color",Color("566966"))
 result.add_theme_stylebox_override("normal",style(Color("172b2d"),Color("456863")))
 result.add_theme_stylebox_override("hover",style(Color("28413f"),Color("acc7b2")))
 result.add_theme_stylebox_override("pressed",style(Color("3b4940"),Color("e3c58c")))
 result.add_theme_stylebox_override("disabled",style(Color("132125"),Color("283a3d")))
 result.pressed.connect(callback);parent.add_child(result);return result

func update_layout_metrics():
 var margin:=UI_MARGIN_X
 var drawer_width:=344.0
 var map_width:=size.x-margin*2.0-(drawer_width+12.0 if details_open else 0.0)
 map_rect=Rect2(margin,UI_MAP_TOP,maxf(320.0,map_width),maxf(240.0,size.y-UI_MAP_TOP-UI_CARD_HEIGHT-UI_CARD_BOTTOM-12.0))

func layout_command_ui():
 update_layout_metrics()
 if not is_instance_valid(field_ui):return
 field_ui.size=size
 header_panel.position=Vector2(UI_MARGIN_X,UI_HEADER_Y);header_panel.size=Vector2(size.x-UI_MARGIN_X*2,UI_HEADER_HEIGHT)
 overlay.position=map_rect.position;overlay.size=map_rect.size
 friendly_overlay.position=map_rect.position;friendly_overlay.size=map_rect.size
 details_panel.visible=details_open
 details_panel.position=Vector2(size.x-UI_MARGIN_X-344,UI_MAP_TOP);details_panel.size=Vector2(344,map_rect.size.y)
 selected_label.position=Vector2(16,16);detail_label.position=Vector2(16,60);detail_label.size=Vector2(312,152)
 queue_scroll.position=Vector2(16,264);queue_scroll.size=Vector2(312,maxf(120,details_panel.size.y-280))
 queue_label.custom_minimum_size=Vector2(288,0)
 feedback.size=Vector2(header_panel.size.x-32,26)
 time_label.position=Vector2(header_panel.size.x-202,14)
 var count:=maxi(1,simulation.controlled_ids.size())
 var width: float=(size.x-UI_MARGIN_X*2-12*(count-1))/count
 var slot:=0
 for character in controlled_actors():
  var card: Button=cards[character.id].button
  card.position=Vector2(UI_MARGIN_X+slot*(width+12),size.y-UI_CARD_BOTTOM-UI_CARD_HEIGHT);card.size=Vector2(width,UI_CARD_HEIGHT)
  cards[character.id].bar.size=Vector2(4,UI_CARD_HEIGHT)
  slot+=1
 performance_label.position=Vector2(UI_FOOTER_X,size.y-UI_FOOTER_BOTTOM)
 footer_label.visible=not performance_visible
 footer_label.position=Vector2(UI_FOOTER_X,size.y-UI_FOOTER_BOTTOM)
 details_button.text="收起详情" if details_open else "详情"
 ui_dirty=true;overlay_dirty=true;marker_signature=0
 apply_camera()

func toggle_details():
 if camera_locked():return
 details_open=not details_open
 stop_zoom()
 layout_command_ui()
 refresh_hud()

func build_command_ui():
 if is_instance_valid(field_ui):ui_layer.remove_child(field_ui);field_ui.queue_free()
 cards.clear();command_buttons.clear()
 field_ui=Control.new();field_ui.mouse_filter=Control.MOUSE_FILTER_IGNORE;field_ui.size=size;ui_layer.add_child(field_ui)
 overlay=OVERLAY.new();overlay.host=self;overlay.clip_contents=true;overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var overlay_material:=ShaderMaterial.new();overlay_material.shader=preload("res://presentation/field/knowledge_overlay.gdshader")
 overlay.material=overlay_material;field_ui.add_child(overlay)
 friendly_overlay=OVERLAY.new();friendly_overlay.host=self;friendly_overlay.friendly_markers_only=true
 friendly_overlay.clip_contents=true;friendly_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;field_ui.add_child(friendly_overlay)
 selected_style=style(Color("20352f"),Color("dfc38b"));unselected_style=style(Color("101d21"),Color("3e5559"))
 header_panel=panel(field_ui,Rect2(UI_MARGIN_X,UI_HEADER_Y,size.x-UI_MARGIN_X*2,UI_HEADER_HEIGHT))
 label(header_panel,"现场指挥",Vector2(16,9),26,Color("e5dcc6"))
 var x:=154.0
 pause_button=button(header_panel,"",Vector2(x,8),Vector2(148,40),toggle_pause);x+=156
 speed_button=button(header_panel,"",Vector2(x,8),Vector2(112,40),toggle_speed);x+=120
 for entry in [["移动","move"],["警戒","guard"],["换弹","reload"],["停止","stop"]]:
  var kind: String=entry[1]
  command_buttons.append(button(header_panel,entry[0],Vector2(x,8),Vector2(80,40),command_clicked.bind(kind)));x+=88
 button(header_panel,"−",Vector2(x,8),Vector2(44,40),func():zoom_at(1.0/.85));x+=48
 zoom_label=label(header_panel,"",Vector2(x,17),18,Color("c6d7cc"));zoom_label.size=Vector2(108,24);zoom_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;x+=112
 button(header_panel,"+",Vector2(x,8),Vector2(44,40),func():zoom_at(.85));x+=52
 button(header_panel,"全图",Vector2(x,8),Vector2(72,40),show_all);x+=80
 button(header_panel,"定位",Vector2(x,8),Vector2(72,40),center_selected);x+=80
 button(header_panel,"近看",Vector2(x,8),Vector2(72,40),zoom_near);x+=80
 details_button=button(header_panel,"详情",Vector2(x,8),Vector2(104,40),toggle_details)
 time_label=label(header_panel,"",Vector2.ZERO,18)
 feedback=label(header_panel,"",Vector2(16,58),18,Color("d4c6a3"));feedback.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 details_panel=panel(field_ui,Rect2())
 selected_label=label(details_panel,"",Vector2.ZERO,24,Color("e3c58c"))
 detail_label=label(details_panel,"",Vector2.ZERO,20);detail_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 label(details_panel,"行动队列 · 已安装",Vector2(16,224),20,Color("8ca79d"))
 queue_scroll=ScrollContainer.new();queue_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 details_panel.add_child(queue_scroll)
 queue_label=label(queue_scroll,"",Vector2.ZERO,20);queue_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 queue_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 for character in controlled_actors():
  var id: int=character.id
  var card:=button(field_ui,"",Vector2.ZERO,Vector2(100,92),select_actor.bind(id));card.clip_contents=true
  var bar:=ColorRect.new();bar.color=unit_color(id);bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(bar)
  var name_label:=label(card,"%02d  %s" % [simulation.controlled_ids.find(id)+1,character.actor_name],Vector2(16,8),24,unit_color(id))
  var state_label:=label(card,"",Vector2(16,38),18)
  var ammo_label:=label(card,"",Vector2(16,64),18)
  cards[id]={"button":card,"bar":bar,"state":state_label,"ammo":ammo_label,"name":name_label}
 performance_label=label(field_ui,"",Vector2.ZERO,16,Color("accabb"));performance_label.visible=performance_visible
 footer_label=label(field_ui,"滚轮／捏合／± 缩放 · 双指／WASD／中键移图 · 右键移动／拖朝向 · Shift 追加 · E 入口 · 空格暂停 · Esc 返回",Vector2.ZERO,16,Color("87a59c"))
 layout_command_ui();hud_signature="";refresh_hud();ui_dirty=true

func unit_color(id: int) -> Color:
 var index: int=simulation.controlled_ids.find(id) if started else -1
 if index>=0:return COLORS[index%COLORS.size()]
 var character: SCActor=simulation.actor(id)
 if simulation.hostile(controlled_actors()[0],character):return Color("d39980")
 return Color("a3b2ad")

func planning_waiting(ids: Array) -> int:
 var count:=0
 for id in ids:
  var character: SCActor=simulation.actor(id)
  if character and character.blocked_reason=="规划中":count+=1
 return count

func interaction_summary() -> String:
 var ids: Array=drag_ids if right_drag else selected
 var requested: bool=drag_append if right_drag else Input.is_key_pressed(KEY_SHIFT)
 var installed:=0;var append_count:=0
 for id in ids:
  var character: SCActor=simulation.actor(id)
  installed+=character.queue.size()
  if simulation.planner.micro_append(character,requested):append_count+=1
 var mode: String="追加" if requested else "替换"
 if requested and append_count<ids.size():mode="追加意图 · %d 人接管替换" % (ids.size()-append_count)
 return "%s%s · %d 人 · 已装 %d 项 · 规划等待 %d 人" % ["已锁定 " if right_drag else "",mode,ids.size(),installed,planning_waiting(ids)]

func show_feedback(text: String, seconds := 2.5, is_error := false):
 transient_feedback=text;transient_feedback_until=Time.get_ticks_msec()+int(seconds*1000);transient_feedback_error=is_error
 hud_signature="";refresh_hud()

func refresh_hud():
 if not started or not is_instance_valid(selected_label):return
 var state: Array=[selected,simulation.paused,speed,int(simulation.time),tool_mode,right_drag,drag_ids,drag_append,preview_state,preview_error,preview_state=="planning" and Time.get_ticks_msec()-preview_since>=100,recent_sound,simulation.time-recent_sound_time<4,simulation.events.back() if not simulation.events.is_empty() else [],transient_feedback,transient_feedback_error,Time.get_ticks_msec()<transient_feedback_until,Input.is_key_pressed(KEY_SHIFT),planning_waiting(selected)]
 for character in controlled_actors():state.append([character.id,character.mode,character.alive,character.ability_revision,character.blocked_reason,character.weapon.ammo,character.weapon.reserve_ammo,queue_display_state(character)])
 var signature:=str(hash(state))
 if signature==hud_signature:return
 hud_signature=signature;ui_dirty=true
 selected_label.text="选择 %d 人" % selected.size()
 pause_button.text="继续 / 空格" if simulation.paused else "暂停 / 空格"
 speed_button.text="%.1f× / Tab" % speed
 time_label.text="%02d:%02d · %s" % [int(simulation.time)/60,int(simulation.time)%60,"暂停" if simulation.paused else "行动中"]
 for command in command_buttons:command.disabled=selected.is_empty()
 for character in controlled_actors():
  var card: Dictionary=cards[character.id]
  card.button.add_theme_stylebox_override("normal",selected_style if character.id in selected else unselected_style)
  var action: String="停止中" if character.mode=="moving" and character.queue.is_empty() else "警戒"
  if character.blocked_reason=="规划中":action="规划等待"
  elif not character.blocked_reason.is_empty():action="挂起："+character.blocked_reason
  elif not character.queue.is_empty():
   action=SCPlanner.LABELS.get(character.queue[0].kind,character.queue[0].kind)
   if simulation.paused and not character.queue[0].started:action="已安排"+action
  var condition: String="阵亡" if not character.alive else "受伤" if character.parts.values().any(func(part):return part.hp<float(part.definition.max_hp)) else "完好"
  card.state.text=action+" · "+condition
  card.ammo.text="弹 %d/%d · 队列 %d%s" % [character.weapon.ammo,character.weapon.reserve_ammo,character.queue.size()," · 待算" if character.blocked_reason=="规划中" else ""]
 if selected.size()==1:
  var character: SCActor=simulation.actor(selected[0])
  var injuries: Array[String]=[]
  for id in character.parts:
   var part: Dictionary=character.parts[id]
   if part.hp<float(part.definition.max_hp):injuries.append(str(part.definition.get("label",part.definition.get("name",id))))
  detail_label.text="%s\n%s\n移动 %.1f m/s\n伤情：%s" % [character.actor_name,character.weapon.definition.item.name,character.speed,"完好" if injuries.is_empty() else "、".join(injuries)]
  queue_label.text="尚无已安装指令" if character.queue.is_empty() else ""
  for i in range(character.queue.size()):
   var node: Dictionary=character.queue[i]
   queue_label.text+="%d  %s\n" % [i+1,SCPlanner.LABELS.get(node.kind,node.kind)]
  if character.blocked_reason=="规划中":queue_label.text+="\n新指令正在计算\n完成后一次入队"
  elif simulation.planner.motion_held(character):queue_label.text+="\n旧计划挂起，请重新下令或停止"
 else:
  detail_label.text="共同下令\n各成员保留自身状态\nShift 可追加命令" if not selected.is_empty() else "点击队员编号或底部队员卡"
  queue_label.text="单选队员查看真实队列"
 var instructions: String={"move":"左键指定目的地","guard":"左键选择警戒格","guard_direction":"离警戒点至少 0.25 m，再点指定朝向"}.get(tool_mode,"")
 var status: String=""
 var failed:=preview_state in ["unknown","unreachable","invalid"]
 if Time.get_ticks_msec()<transient_feedback_until:status=transient_feedback
 elif preview_state=="planning" and Time.get_ticks_msec()-preview_since>=100:status="规划中 · 可继续移图或取消"
 elif failed:status=preview_error
 elif preview_state=="complete":status="路径可执行"
 elif not recent_sound.is_empty() and simulation.time-recent_sound_time<4:status=recent_sound
 elif not simulation.events.is_empty():status=str(simulation.events[-1][1])
 else:status="暂停时可先安排指令，再继续行动"
 var parts: Array[String]=[]
 if not instructions.is_empty():parts.append(instructions)
 if not status.is_empty():parts.append(status)
 if right_drag or pointer_on_map():parts.append(interaction_summary())
 if right_drag and not drag_takeover.is_empty():parts.append(drag_takeover)
 feedback.text=" · ".join(parts)
 feedback.modulate=Color("e6aa90") if failed or (Time.get_ticks_msec()<transient_feedback_until and transient_feedback_error) else Color.WHITE

func select_actor(id: int):
 if id not in simulation.controlled_ids:return
 cancel_interaction()
 var character: SCActor=simulation.actor(id)
 if not character.alive:
  pan_center=character.position;apply_camera()
  show_feedback("%s 已阵亡 · 已定位" % character.actor_name)
  return
 if Input.is_key_pressed(KEY_SHIFT):
  if id in selected:selected.erase(id)
  else:selected.append(id)
 else:selected=[id]
 preview_signature="";refresh_hud()

func select_all():
 cancel_interaction();selected=[]
 for character in controlled_actors():
  if character.alive:selected.append(character.id)
 refresh_hud()

func center_selected():
 if camera_locked():return
 stop_zoom()
 if not selected.is_empty():
  pan_center=Vector2.ZERO
  for id in selected:pan_center+=simulation.actor(id).position
  pan_center/=float(selected.size())
 apply_camera()

func zoom_near():
 if camera_locked():return
 var target:=pan_center
 if not selected.is_empty():
  target=Vector2.ZERO
  for id in selected:target+=simulation.actor(id).position
  target/=float(selected.size())
 stop_zoom();zoom_at(18.0/view_height,map_rect.get_center())
 zoom_start_center=pan_center;zoom_center_target=target;zoom_active=zoom_active or not pan_center.is_equal_approx(target)

func show_all():
 if camera_locked():return
 var aspect:=map_rect.size.x/maxf(1,map_rect.size.y)
 var height:=maxf(map_bounds.size.y,map_bounds.size.x/aspect)*1.06
 stop_zoom();zoom_at(height/view_height,map_rect.get_center())
 zoom_start_center=pan_center;zoom_center_target=map_bounds.get_center();zoom_active=zoom_active or not pan_center.is_equal_approx(map_bounds.get_center())

func toggle_pause():
 simulation.set_paused(not simulation.paused);refresh_hud()

func toggle_speed():speed=0.5 if speed==1.0 else 1.0;refresh_hud()

func command_clicked(kind: String):
 cancel_interaction()
 if selected.is_empty():return
 if kind=="stop":simulation.planner.stop(selected);simulation.message("已停止所选 %d 人" % selected.size(),"")
 elif kind=="reload":submit_command(selected,"reload",{})
 else:tool_mode=kind
 refresh_hud()

func submit_command(ids: Array, kind: String, options: Dictionary):
 ids=ids.filter(func(id):return simulation.actor(id)!=null and simulation.actor(id).alive and id in simulation.controlled_ids)
 if ids.is_empty():show_feedback("没有可下令的队员");return
 var error: String=simulation.planner.submit(ids,kind,options)
 var message: String=error if not error.is_empty() else "已接收%s · %d 人" % [SCPlanner.LABELS.get(kind,kind),ids.size()]
 simulation.message(message,"");preview_signature=""
 show_feedback(message,2.5,not error.is_empty())

func cancel_interaction() -> bool:
 var active := left_drag or right_drag or pan_drag or not tool_mode.is_empty()
 stop_zoom()
 left_drag=false;right_drag=false;pan_drag=false;tool_mode="";drag_takeover="";clear_preview();preview_signature="";overlay_dirty=true
 if started:refresh_hud()
 return active

func camera_locked() -> bool:return left_drag or right_drag

func pointer_on_map() -> bool:return map_rect.has_point(pointer)

func clamp_camera_center():
 var half:=Vector2(view_height*map_rect.size.x/maxf(1,map_rect.size.y),view_height)*.5
 for axis in range(2):
  if half[axis]*2.0>=map_bounds.size[axis]:pan_center[axis]=map_bounds.get_center()[axis]
  else:pan_center[axis]=clampf(pan_center[axis],map_bounds.position[axis]+half[axis],map_bounds.end[axis]-half[axis])

func apply_camera():
 if not camera or map_rect.size.y<=0:return
 clamp_camera_center()
 camera.size=view_height*size.y/map_rect.size.y
 var center:=pan_center+(size*.5-map_rect.get_center())*(view_height/map_rect.size.y)
 camera.position=Vector3(center.x,80,center.y);camera.look_at(Vector3(center.x,0,center.y),Vector3.FORWARD)
 if object_outline:object_outline.sync_camera(camera)
 var previous_overview:=overview
 overview=view_height>=OVERVIEW_HEIGHT
 if started and previous_overview!=overview:update_overview_items()
 pointer_world=screen_to_world(pointer)
 camera_revision+=1;fog_revision+=1;resident_dirty=true;overlay_dirty=true;mark_scene_dirty(true)
 marker_signature=0
 if started:
  update_overlay_projection();update_zoom_label()

func update_overlay_projection():
 if not is_instance_valid(overlay) or not fog_texture:return
 var parameters:=crt_fog_parameters()
 overlay.material.set_shader_parameter("knowledge_texture",fog_texture)
 overlay.material.set_shader_parameter("knowledge_bounds",parameters.bounds)
 overlay.material.set_shader_parameter("view_origin",parameters.view_origin)
 overlay.material.set_shader_parameter("view_axis_x",parameters.view_axis_x)
 overlay.material.set_shader_parameter("view_axis_y",parameters.view_axis_y)
 overlay.material.set_shader_parameter("display_size",size)

func world_to_screen(point: Vector2) -> Vector2:return camera.unproject_position(Vector3(point.x,.05,point.y))/RENDER_SCALE

func screen_to_world(point: Vector2) -> Vector2:
 var ray:=camera.project_ray_origin(point*RENDER_SCALE)
 return Vector2(ray.x,ray.z)

func update_zoom_label():
 if is_instance_valid(zoom_label):zoom_label.text="%.0f m" % view_height;ui_dirty=true

func stop_zoom():
 zoom_active=false;zoom_target_height=view_height;zoom_center_target=null

func zoom_at(factor: float, anchor := Vector2.INF):
 if camera_locked() or not started or factor<=0:return
 var point: Vector2=anchor
 if not point.is_finite() or not map_rect.has_point(point):point=pointer if pointer_on_map() else map_rect.get_center()
 zoom_center_target=null
 zoom_anchor_screen=point;zoom_anchor_world=screen_to_world(point)
 zoom_start_height=view_height
 zoom_target_height=clampf((zoom_target_height if zoom_active else view_height)*factor,10.0,maxf(map_bounds.size.x,map_bounds.size.y)*1.15)
 zoom_elapsed=0.0;zoom_active=not is_equal_approx(view_height,zoom_target_height)

func update_zoom(delta: float):
 if not zoom_active:return
 if camera_locked():stop_zoom();return
 zoom_elapsed=minf(ZOOM_DURATION,zoom_elapsed+delta)
 var progress:=smoothstep(0.0,1.0,zoom_elapsed/ZOOM_DURATION)
 view_height=exp(lerpf(log(zoom_start_height),log(zoom_target_height),progress))
 pan_center=zoom_start_center.lerp(zoom_center_target,progress) if zoom_center_target!=null else zoom_anchor_world-(zoom_anchor_screen-map_rect.get_center())*(view_height/map_rect.size.y)
 apply_camera()
 if zoom_elapsed>=ZOOM_DURATION:zoom_active=false;zoom_target_height=view_height;zoom_center_target=null

func pan_camera(offset: Vector2):
 if camera_locked():return
 var before:=pan_center
 pan_center+=offset;apply_camera()
 if zoom_active:
  if zoom_center_target!=null:
   zoom_center_target=null;zoom_anchor_world=screen_to_world(zoom_anchor_screen)
  else:zoom_anchor_world+=pan_center-before

func marker_point_known(point: Vector2) -> bool:
 if not map_rect.has_point(point):return false
 return knowledge_state(screen_to_world(point))>0

func refresh_marker_layout():
 var signature:=hash([rendered_actor_signature,camera_revision,overview,selected,(pointer/8.0).floor()])
 if signature==marker_signature:return
 marker_signature=signature;marker_layout.clear();squad_markers.clear()
 var occupied: Array[Rect2]=[]
 var controlled: Array=[]
 for id in rendered_actors:
  var character: SCActor=simulation.actor(id)
  var body:=world_to_screen(character.position)
  if not map_rect.grow(24).has_point(body):continue
  if simulation.is_controlled(character) and not marker_point_known(body):continue
  marker_layout[id]={"body":body,"badge":Rect2(),"label":Rect2(),"clustered":false,"radius":clampf(.42*map_rect.size.y/view_height,8,22)}
  if simulation.is_controlled(character) and character.alive:controlled.append(id)
 controlled.sort()
 if overview:
  var remaining: Array=controlled.duplicate()
  while not remaining.is_empty():
   var ids: Array=[remaining.pop_front()]
   var changed:=true
   while changed:
    changed=false
    for id in remaining.duplicate():
     if ids.any(func(other):return marker_layout[other].body.distance_to(marker_layout[id].body)<46.0):ids.append(id);remaining.erase(id);changed=true
   if ids.size()<2:continue
   var center:=Vector2.ZERO
   for id in ids:center+=marker_layout[id].body
   center/=float(ids.size())
   var rect:=Rect2()
   var anchors: Array[Vector2]=[center]
   for id in ids:anchors.append(marker_layout[id].body)
   for anchor in anchors:
    for offset in [Vector2(0,-20),Vector2(0,20),Vector2(30,0),Vector2(-30,0),Vector2.ZERO]:
     var candidate:=Rect2(anchor+offset-Vector2(34,16),Vector2(68,32))
     candidate.position=candidate.position.clamp(map_rect.position,map_rect.end-candidate.size)
     if not marker_point_known(anchor) or occupied.any(func(other):return other.intersects(candidate.grow(3))):continue
     rect=candidate;break
    if rect.has_area():break
   if not rect.has_area():continue
   squad_markers.append({"ids":ids,"rect":rect,"center":rect.get_center()});occupied.append(rect.grow(4))
   for id in ids:marker_layout[id].clustered=true
 var offsets: Array[Vector2]=[Vector2(0,-26),Vector2(30,0),Vector2(0,26),Vector2(-30,0),Vector2(28,-28),Vector2(-28,28),Vector2(46,20),Vector2(-46,-20)]
 for id in controlled:
  var entry: Dictionary=marker_layout[id]
  if entry.clustered:continue
  var chosen:=Rect2(entry.body-Vector2(14,14),Vector2(28,28))
  for offset in offsets:
   var candidate:=Rect2(entry.body+offset-Vector2(14,14),Vector2(28,28))
   if not map_rect.encloses(candidate):continue
   if occupied.any(func(rect):return rect.intersects(candidate.grow(3))):continue
   chosen=candidate;break
  entry.badge=chosen;occupied.append(chosen.grow(3))
 if not overview:
  for id in marker_layout:
   if id in controlled or not simulation.perception.player_visible.has(id):continue
   var entry: Dictionary=marker_layout[id]
   if view_height>36 and entry.body.distance_to(pointer)>32:continue
   var label_rect:=Rect2(entry.body+Vector2(12,-24),Vector2(154,22))
   if not map_rect.encloses(label_rect) or occupied.any(func(rect):return rect.intersects(label_rect)):continue
   if not marker_point_known(label_rect.get_center()):continue
   entry.label=label_rect;occupied.append(label_rect)
 overlay_dirty=true

func pick_squad(point: Vector2) -> Array:
 if not map_rect.has_point(point):return []
 for entry: Dictionary in squad_markers:
  if entry.rect.has_point(point):return entry.ids.duplicate()
 return []

func pick_actor(point: Vector2) -> int:
 if not map_rect.has_point(point):return -1
 var best:=-1;var distance:=INF
 for id in marker_layout:
  var character: SCActor=simulation.actor(id)
  if not simulation.is_controlled(character) or not character.alive:continue
  var entry: Dictionary=marker_layout[id]
  if entry.clustered:continue
  if entry.badge.has_point(point):return id
  var d: float=entry.body.distance_to(point)
  if d<=float(entry.radius) and d<distance:distance=d;best=id
 return best

func clear_preview():
 if preview_request>=0 and started:simulation.planner.cancel_request(preview_request)
 preview_request=-1;preview_state="";preview_error="";preview_target=null;preview_paths.clear();overlay_dirty=true

func update_preview():
 if selected.is_empty() or not pointer_on_map():
  if not preview_paths.is_empty() or preview_request>=0 or not preview_state.is_empty():clear_preview()
  preview_signature="";return
 if not simulation.paused and not right_drag and tool_mode.is_empty() and selected.any(func(id):return simulation.actor(id).mode=="moving"):
  clear_preview();preview_signature="";return
 var destination: Vector2=right_world if right_drag else guard_anchor if tool_mode=="guard_direction" else pointer_world
 var cell:=SCData.cell_of(destination)
 var ids: Array=drag_ids if right_drag else selected
 var append: bool=drag_append if right_drag else Input.is_key_pressed(KEY_SHIFT)
 var origins: Array=[]
 for id in ids:
  var character: SCActor=simulation.actor(id)
  var effective: bool=simulation.planner.micro_append(character,append)
  origins.append([simulation.planner.origin(character,effective),queue_display_state(character)])
 var signature:=str(hash([cell,ids,append,origins]))
 if preview_state=="unknown" and simulation.perception.explored.has(cell):preview_signature=""
 if signature!=preview_signature:
  clear_preview();preview_signature=signature;preview_target=cell
  if not simulation.perception.explored.has(cell):preview_state="unknown";preview_error="区域未探索";hud_signature="";return
  preview_since=Time.get_ticks_msec();preview_state="planning"
  preview_request=simulation.planner.request_movement(ids,cell,append,"preview")
 if preview_request<0:return
 var result: Dictionary=simulation.planner.request_result(preview_request)
 var state: String=result.get("state","planning")
 var error: String=result.get("error","")
 if state!=preview_state or error!=preview_error:
  preview_state=state;preview_error=error;hud_signature="";overlay_dirty=true
 if state=="complete":
  var paths: Dictionary=result.get("paths",{})
  if preview_paths!=paths:preview_paths=paths;overlay_dirty=true
 else:
  if not preview_paths.is_empty():preview_paths.clear();overlay_dirty=true
  if state=="unreachable" and preview_error.is_empty():preview_error="没有已知可达路线"

func queue_display_state(character: SCActor) -> Array:
 var result: Array=[]
 for node: Dictionary in character.queue:result.append([node.get("kind"),node.get("cell"),node.get("angle"),node.get("started"),node.get("stage"),node.get("planned_route",[]).size()])
 return result

func refresh_queue_paths():
 var state: Array=[selected,simulation.perception.knowledge_version]
 for id in selected:
  var character: SCActor=simulation.actor(id)
  state.append([id,hash(character.route),queue_display_state(character)])
 var signature:=str(hash(state))
 if queue_signature==signature:return
 queue_signature=signature;queue_paths.clear();overlay_dirty=true
 for id in selected:
  var character: SCActor=simulation.actor(id)
  if not character.route.is_empty():queue_paths[id]=character.route.duplicate()
  elif not character.queue.is_empty():
   var node: Dictionary=character.queue[0]
   var route: Array=node.get("planned_route",[])
   if not route.is_empty():queue_paths[id]=route.duplicate()

func operate_nearest_door():
 if selected.size()!=1:simulation.message("单选一名队员后操作附近入口","");return
 var character: SCActor=simulation.actor(selected[0]);var best: String="";var distance:=1.65
 for id in simulation.perception.known_entities:
  var snapshot: Dictionary=simulation.perception.known_entities[id]
  if not snapshot.exists or not snapshot.definition.has("door"):continue
  var d:=character.position.distance_to(snapshot.position)
  if d<=distance:best=id;distance=d
 if best.is_empty():simulation.message("附近没有已知可操作入口","");return
 var snapshot: Dictionary=simulation.perception.known_entities[best]
 var error: String=simulation.operate_door(best,character,float(snapshot.door_progress)<.5)
 simulation.message(error if not error.is_empty() else "已操作入口","");hud_signature="";refresh_hud()

func _input(event: InputEvent):
 if not input_active:return
 if event is InputEventMouse or event is InputEventGesture:
  ui_dirty=true;overlay_dirty=true;pointer=event.position
  if started:pointer_world=screen_to_world(pointer)
  var inside:=Rect2(Vector2.ZERO,size).has_point(pointer)
  if inside and not ui_pointer_inside:compose.notify_mouse_entered();ui_pointer_inside=true
  elif not inside and ui_pointer_inside:compose.notify_mouse_exited();ui_pointer_inside=false
  if started and event is InputEventMouseButton and not event.pressed and not pointer_on_map():
   if (event.button_index==MOUSE_BUTTON_LEFT and left_drag) or (event.button_index==MOUSE_BUTTON_RIGHT and right_drag) or (event.button_index==MOUSE_BUTTON_MIDDLE and pan_drag):cancel_interaction()
 var was_started:=started
 compose.push_input(event,true)
 if compose.is_input_handled() or started!=was_started:get_viewport().set_input_as_handled();return
 if not started:return
 if event is InputEventKey and event.pressed and not event.echo:
  var key: int=event.keycode
  if key in [KEY_F1,KEY_F2]:
   if event.ctrl_pressed:groups[key]=selected.duplicate()
   else:selected=groups[key].filter(func(id):return simulation.actor(id)!=null and simulation.actor(id).alive)
   cancel_interaction();refresh_hud();get_viewport().set_input_as_handled()
  elif key>=KEY_1 and key<=KEY_4:
   var slot:=key-KEY_1
   if slot>=simulation.controlled_ids.size():return
   var id: int=simulation.controlled_ids[slot];select_actor(id)
   var now:=Time.get_ticks_msec()
   if last_selection_key==key and now-last_selection_time<=300 and simulation.actor(id).alive:center_selected()
   last_selection_key=key;last_selection_time=now;get_viewport().set_input_as_handled()
  elif key==KEY_A and event.ctrl_pressed:select_all();get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent):
 if not input_active or not started:return
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_SPACE:toggle_pause()
   KEY_TAB:toggle_speed()
   KEY_Q:command_clicked("guard")
   KEY_R:command_clicked("reload")
   KEY_X:command_clicked("stop")
   KEY_HOME:show_all()
   KEY_E:operate_nearest_door()
   KEY_PLUS,KEY_EQUAL,KEY_KP_ADD:zoom_at(.85)
   KEY_MINUS,KEY_KP_SUBTRACT:zoom_at(1.0/.85)
   KEY_F10:
    performance_visible=not performance_visible;performance_label.visible=performance_visible;footer_label.visible=not performance_visible;ui_dirty=true
  return
 if event is InputEventMagnifyGesture:
  if pointer_on_map() and not camera_locked() and event.factor>0:zoom_at(1.0/event.factor,event.position);get_viewport().set_input_as_handled()
  return
 if event is InputEventPanGesture:
  if pointer_on_map() and not camera_locked():
   var pixels: Vector2=event.get_meta("map_pan_pixels",event.delta*32.0)
   pan_camera(pixels*(view_height/map_rect.size.y));get_viewport().set_input_as_handled()
  return
 if event is InputEventMouseMotion:
  if pan_drag and pointer_on_map() and not camera_locked():pan_camera(-event.relative*(view_height/map_rect.size.y))
  return
 if not event is InputEventMouseButton:return
 if event.button_index==MOUSE_BUTTON_MIDDLE:
  pan_drag=event.pressed and pointer_on_map() and not camera_locked();return
 if not pointer_on_map():return
 if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  var amount:=absf(event.factor)
  if amount>0:zoom_at(pow(.85,amount*(1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1.0)),event.position)
  get_viewport().set_input_as_handled();return
 if event.button_index==MOUSE_BUTTON_LEFT:
  if event.pressed:
   stop_zoom();refresh_marker_layout()
   if tool_mode=="move":
    submit_command(selected,"move",{"cell":SCData.cell_of(pointer_world),"append":event.shift_pressed});tool_mode="";return
   if tool_mode=="guard":
    var cell:=SCData.cell_of(pointer_world)
    if not simulation.perception.explored.has(cell):show_feedback("区域未探索",2.5,true);return
    guard_anchor=SCData.center(cell);tool_mode="guard_direction";preview_signature="";refresh_hud();return
   if tool_mode=="guard_direction":
    var direction:=pointer_world-guard_anchor
    if direction.length()<.25:show_feedback("请离警戒点至少 0.25 m 指定朝向",2.5,true);return
    submit_command(selected,"guard",{"cell":SCData.cell_of(guard_anchor),"angle":direction.angle(),"append":event.shift_pressed});tool_mode="";return
   var squad:=pick_squad(event.position)
   if not squad.is_empty():
    cancel_interaction()
    if event.shift_pressed:
     for id in squad:
      if id not in selected:selected.append(id)
    else:selected=squad
    if event.double_click:zoom_near()
    refresh_hud();return
   var id:=pick_actor(event.position)
   if id>=0:select_actor(id)
   else:left_drag=true;drag_start=event.position;drag_append=event.shift_pressed
  elif left_drag:
   var rect:=Rect2(drag_start,event.position-drag_start).abs()
   if not drag_append:selected=[]
   if drag_start.distance_to(event.position)>4:
    for character in controlled_actors():
     if character.alive and rect.has_point(world_to_screen(character.position)) and character.id not in selected:selected.append(character.id)
   left_drag=false;preview_signature="";marker_signature=0;refresh_hud()
 elif event.button_index==MOUSE_BUTTON_RIGHT:
  if event.pressed:
   if not tool_mode.is_empty():cancel_interaction();return
   if selected.is_empty():show_feedback("先选择队员或小队标记");return
   stop_zoom();right_drag=true;right_world=pointer_world;drag_ids=selected.duplicate();drag_append=event.shift_pressed
   drag_takeover=simulation.planner.takeover_text(drag_ids);hud_signature="";refresh_hud()
  elif right_drag:
   var direction:=pointer_world-right_world
   var options: Dictionary={"cell":SCData.cell_of(right_world),"append":drag_append}
   var kind: String="move"
   if direction.length()>=.5:kind="move_face";options.angle=direction.angle()
   right_drag=false;submit_command(drag_ids,kind,options);drag_takeover=""

func prune_dead_selection():
 var alive: Array=selected.filter(func(id):return simulation.actor(id)!=null and simulation.actor(id).alive)
 var live_drag: Array=drag_ids.filter(func(id):return simulation.actor(id)!=null and simulation.actor(id).alive)
 if alive==selected and live_drag==drag_ids:return
 selected=alive;drag_ids=live_drag
 for key in groups:groups[key]=groups[key].filter(func(id):return simulation.actor(id)!=null and simulation.actor(id).alive)
 if selected.is_empty():left_drag=false;right_drag=false;tool_mode=""
 clear_preview();preview_signature="";marker_signature=0;hud_signature="";refresh_hud()

func should_show_actor(character: SCActor) -> bool:
 return simulation.is_controlled(character) or simulation.perception.player_raw.has(character.id)

func update_units(delta: float):
 var region:=map_view_bounds().grow(3.0)
 var desired: Dictionary={};rendered_actors.clear()
 for character: SCActor in simulation.actors:
  if not should_show_actor(character):continue
  rendered_actors.append(character.id)
  if not character.alive or overview or not region.has_point(character.position):continue
  # Every legally visible person remains represented. Detailed bodies are useful
  # only at the close camera scale; overview markers carry the rest.
  if view_height>72.0 and not simulation.is_controlled(character):continue
  desired[character.id]=true
 for id in units.keys():
  if desired.has(id):continue
  var unit: Node3D=units[id];object_outline.unregister_subtree(unit);unit.visible=false;unit.queue_free();units.erase(id);actor_signatures.erase(id);mark_scene_dirty(true)
 var render_state: Array=[]
 for id in rendered_actors:
  var actor: SCActor=simulation.actor(id)
  render_state.append([id,actor.position,actor.alive])
 var state_signature:=hash([render_state,simulation.perception.last_seen.keys()])
 if state_signature!=rendered_actor_signature:rendered_actor_signature=state_signature;overlay_dirty=true
 var creations:=0
 for id in desired:
  var character: SCActor=simulation.actor(id)
  if not units.has(id):
   if not models_ready or creations>=1:continue
   var unit:=ACTOR.new();unit.embedded=true;unit.show_reticle=false;unit.stylized=true;unit.armed=character.armed
   unit.character_definition=character.definition;unit.shooter=character;unit.weapon_state=character.weapon
   unit.set_meta("knowledge_current_only",not simulation.is_controlled(character))
   units_root.add_child(unit);unit.set_knowledge(fog_texture,map_bounds,not simulation.is_controlled(character))
   units[id]=unit;object_outline.register_subtree(unit,"actor_"+str(id));creations+=1;mark_scene_dirty(true)
  var unit: Node3D=units[id]
  var fired: int=int(character.weapon.get("shots_fired",0))
  if actor_shots.has(id) and fired>int(actor_shots[id]):
   unit.gait.kick(0.0,0.0);unit.shot_age=0.0
  actor_shots[id]=fired
  var holding:=SCCombat.holding_error(character)
  var action: String=character.current_action.kind if character.current_action!=null else "aim"
  var signature:=hash([character.position,character.facing,character.velocity,action,holding,character.weapon.recoil_offset_degrees,character.weapon.reaim_offset_degrees])
  var animated: bool=not simulation.paused and (character.velocity.length_squared()>.0001 or unit.current_action!="aim" or unit.gait.recoil.length_squared()>.000001 or unit.gait.weight>.001)
  if actor_signatures.get(id)==signature and not animated:continue
  actor_signatures[id]=signature
  unit.position=Vector3(character.position.x,0,character.position.y)
  var yaw: float=PI/2-character.facing
  var motion:=Vector3(character.velocity.x,0,character.velocity.y).rotated(Vector3.UP,-yaw)
  unit.effect_origin=Vector2.ZERO;unit.aim_target=character.position+Vector2.from_angle(character.facing)*4.0
  if action=="reload" and unit.current_action!="reload":unit.trigger("reload")
  unit.advance_unit(delta,yaw,Vector2(motion.x,motion.z),0.0);unit.skeleton.advance(delta)
  object_outline.sync_subtree(unit);mark_scene_dirty(true);overlay_dirty=true

func update_sound_feedback():
 heard_sounds.clear()
 for event: Dictionary in simulation.sounds:
  if not event.get("audible",false):continue
  var point: Vector2=event.position
  if knowledge_state(point)>0:heard_sounds.append(event)
  var key:=hash([point,event.team,event.kind,roundi((simulation.time+float(event.timer))*60.0)])
  if sound_seen.has(key):continue
  sound_seen[key]=simulation.time
  var direction:=point-pan_center
  var bearing: String="东" if absf(direction.x)>absf(direction.y) and direction.x>=0 else "西" if absf(direction.x)>absf(direction.y) else "南" if direction.y>=0 else "北"
  var kind: String=str(event.kind)
  var sound_name: String="枪声" if kind in ["rifle","pistol","shotgun","smg","lmg"] else "爆炸" if kind in ["flash","explosion","grenade"] else "动静"
  recent_sound="%s侧传来%s" % [bearing,sound_name];recent_sound_time=simulation.time;hud_signature="";overlay_dirty=true
 var sound_state: Array=[]
 for event: Dictionary in heard_sounds:sound_state.append([event.position,event.kind])
 var signature:=hash(sound_state)
 if signature!=heard_signature:heard_signature=signature;overlay_dirty=true
 for key in sound_seen.keys():
  if simulation.time-float(sound_seen[key])>3.0:sound_seen.erase(key)

func update_performance(delta: float):
 var now:=Time.get_ticks_usec()
 if performance_previous_tick!=0:performance_usec+=now-performance_previous_tick;performance_samples+=1
 performance_previous_tick=now;performance_elapsed+=delta
 if performance_elapsed<.5:return
 performance_elapsed=0.0
 if performance_visible:
  var fine:=0
  for character in simulation.actors:
   if character.simulation_detail:fine+=1
  performance_label.text="%d FPS · %.1f ms · 世界 %.1fs · 精细 %d/%d · 规划 %d · 资源 %d/%d" % [Engine.get_frames_per_second(),float(performance_usec)/maxi(1,performance_samples)/1000.0,simulation.time,fine,simulation.actors.size(),simulation.planner.pending_request_count(),asset_loads.size(),pending_upgrades.size()]
  ui_dirty=true
 performance_usec=0;performance_samples=0

func flush_picture():
 if mask_dirty:
  object_outline.mask_view.render_target_update_mode=SubViewport.UPDATE_ONCE
 if scene_dirty:
  view.render_target_update_mode=SubViewport.UPDATE_ONCE
 if scene_dirty or mask_dirty:
  object_outline.output.render_target_update_mode=SubViewport.UPDATE_ONCE;picture_revision+=1
 if overlay_dirty and is_instance_valid(overlay):overlay.queue_redraw();friendly_overlay.queue_redraw();ui_dirty=true
 if ui_dirty:compose.render_target_update_mode=SubViewport.UPDATE_ONCE;picture_revision+=1
 scene_dirty=false;mask_dirty=false;overlay_dirty=false;ui_dirty=false

func finish_frame_timing(started_usec: int):
 if not runtime_timing_enabled:return
 frame_cpu_usec=Time.get_ticks_usec()-started_usec
 timing_frame_index=Engine.get_process_frames()

func _process(delta: float):
 var frame_started: int=Time.get_ticks_usec() if runtime_timing_enabled else 0
 if runtime_timing_enabled:simulation_cpu_usec=0;presentation_cpu_usec=0;ui_cpu_usec=0
 if input_active!=render_live:set_render_live(input_active)
 if not started:
  idle_time+=delta
  if ui_dirty:compose.render_target_update_mode=SubViewport.UPDATE_ONCE;picture_revision+=1;ui_dirty=false
  finish_frame_timing(frame_started);return
 if not input_active:finish_frame_timing(frame_started);return
 var motion:=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
 update_zoom(delta)
 if motion.length()>0 and pointer_on_map() and not camera_locked() and not Input.is_physical_key_pressed(KEY_CTRL):
  pan_camera(motion.normalized()*delta*view_height*.65)
 var section_started: int=Time.get_ticks_usec() if runtime_timing_enabled else 0
 simulation.planner.pump_requests(2000)
 simulation.update(delta*speed)
 if runtime_timing_enabled:
  var now:=Time.get_ticks_usec();simulation_cpu_usec=now-section_started;section_started=now
 refresh_knowledge()
 if resident_dirty:resident_chunks()
 load_resident_assets()
 update_units(0.0 if simulation.paused else delta*speed)
 if runtime_timing_enabled:
  var now:=Time.get_ticks_usec();presentation_cpu_usec=now-section_started;section_started=now
 prune_dead_selection();refresh_marker_layout();update_preview();refresh_queue_paths();update_sound_feedback();update_performance(delta)
 hud_tick+=delta
 if hud_tick>.15:hud_tick=0;refresh_hud()
 flush_picture()
 if runtime_timing_enabled:ui_cpu_usec=Time.get_ticks_usec()-section_started
 finish_frame_timing(frame_started)
