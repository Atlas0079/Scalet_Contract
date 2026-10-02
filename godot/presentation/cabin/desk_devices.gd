extends Node3D
## Physical controls. World time is supplied externally; this study owns no clock.
signal sleep_requested
const FONT = preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf")
const CLOCK_MODEL = preload("res://assets/environment/alarm_clock_1980s/alarm_clock.glb")
var clock_text: Label
var alarm_text: Label
var alarm_minutes := 7 * 60
var alarm_enabled := false
var clock_seconds := -1.0
var previous_seconds := -1.0
var contacts: Array[Dictionary] = []
var alarm_audio: AudioStreamPlayer
var sleep_button: Node3D
var models: Dictionary = {}
var display_view: SubViewport

func _ready():
 build_clock()
 alarm_audio = AudioStreamPlayer.new()
 alarm_audio.stream = preload("res://assets/ready.wav")
 add_child(alarm_audio)
 refresh()

func place_model(scene: PackedScene, at: Vector3, width: float, kind: String) -> Node3D:
 var model := scene.instantiate() as Node3D
 add_child(model)
 var bounds := AABB()
 var first := true
 for node in model.find_children("*","MeshInstance3D",true,false):
  var box: AABB = model.global_transform.affine_inverse()*node.global_transform*node.get_aabb()
  if first: bounds = box; first = false
  else: bounds = bounds.merge(box)
 var factor := width/bounds.size.x
 model.scale = Vector3.ONE*factor
 model.position = at-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
 models[kind] = {"node":model,"bounds":bounds}
 return model

func build_clock():
 var clock := place_model(CLOCK_MODEL,Vector3(0,1.29541,0.08),0.34,"clock")
 # Bind authored buttons: SLEEP, ALARM, FAST, SLOW. TIME cannot edit the world clock.
 var bindings := {"Buttons Circle":"sleep","Buttons Circle_002":"alarm","Buttons Circle_004":"hour","Buttons Circle_005":"minute"}
 for node in clock.find_children("*","MeshInstance3D",true,false):
  var original := String(node.name)
  if bindings.has(original):
   node.set_meta("rest_y",node.position.y)
   contacts.append({"node":node,"action":bindings[original]})
   if bindings[original] == "sleep": sleep_button = node
  if node.name == "DisplayPerspex":
   var glass := StandardMaterial3D.new()
   glass.albedo_color = Color(0.10,0.14,0.11,0.08)
   glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
   glass.roughness = 0.15
   node.material_override = glass
  if node.name == "Plane":
   display_view = SubViewport.new()
   display_view.size = Vector2i(480,192)
   display_view.disable_3d = true
   display_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
   add_child(display_view)
   var background := ColorRect.new()
   background.size = display_view.size
   background.color = Color("020503")
   display_view.add_child(background)
   clock_text = display_label(Vector2(28,28),72,Color("4a9859"))
   alarm_text = display_label(Vector2(28,126),24,Color("3d7748"))
   var screen := StandardMaterial3D.new()
   screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
   screen.albedo_texture = display_view.get_texture()
   screen.cull_mode = BaseMaterial3D.CULL_DISABLED
   node.material_override = screen
 assert(sleep_button != null and contacts.size()==4,"Missing authored alarm buttons")

func display_label(at: Vector2, font_size: int, color: Color) -> Label:
 var text := Label.new()
 text.position = at
 text.add_theme_font_override("font",FONT)
 text.add_theme_font_size_override("font_size",font_size)
 text.add_theme_color_override("font_color",color)
 display_view.add_child(text)
 return text

func mesh_hit(camera: Camera3D, point: Vector2, node: MeshInstance3D) -> Variant:
 var inverse := node.global_transform.affine_inverse()
 var origin := inverse*camera.project_ray_origin(point)
 var direction := (inverse.basis*camera.project_ray_normal(point)).normalized()
 if not node.get_aabb().intersects_segment(origin,origin+direction*100): return null
 var nearest: Variant = null
 var distance := INF
 for surface in range(node.mesh.get_surface_count()):
  var arrays := node.mesh.surface_get_arrays(surface)
  var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
  for i in range(0,indices.size(),3):
   var at: Variant = Geometry3D.ray_intersects_triangle(origin,direction,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]])
   if at != null and origin.distance_squared_to(at) < distance:
    distance = origin.distance_squared_to(at)
    nearest = node.to_global(at)
 return nearest

func hit(camera: Camera3D, point: Vector2) -> Dictionary:
 var result := {}
 var distance := INF
 for contact in contacts:
  var at: Variant = mesh_hit(camera,point,contact.node)
  if at != null:
   var d: float = camera.global_position.distance_squared_to(at)
   if d < distance: distance = d; result = contact
 return result

func body_hit(camera: Camera3D, point: Vector2) -> String:
 var result := ""
 var distance := INF
 for kind in models:
  var model: Node3D = models[kind].node
  for node in model.find_children("*","MeshInstance3D",true,false):
   var at: Variant = mesh_hit(camera,point,node)
   if at != null:
    var d: float = camera.global_position.distance_squared_to(at)
    if d < distance: distance = d; result = kind
 return result

func focus_point(kind: String) -> Vector3:
 return models[kind].node.to_global(models[kind].bounds.get_center())

func activate(contact: Dictionary):
 match contact.action:
  "hour": alarm_minutes = (alarm_minutes+60)%1440
  "minute": alarm_minutes = (alarm_minutes+1)%1440
  "alarm": alarm_enabled = not alarm_enabled
  "sleep": sleep_requested.emit()
 var node: Node3D = contact.node
 var rest: float = node.get_meta("rest_y")
 if node.has_meta("press_tween"):
  var old: Tween = node.get_meta("press_tween")
  if old and old.is_valid(): old.kill()
 var tween := create_tween()
 node.set_meta("press_tween",tween)
 tween.tween_property(node,"position:y",rest-0.004,0.07)
 tween.tween_property(node,"position:y",rest,0.12)
 refresh()

func read_world_time(seconds: float):
 # The world owner calls this with authoritative time; never written by a button.
 previous_seconds = clock_seconds
 clock_seconds = seconds
 if alarm_enabled and previous_seconds >= 0 and seconds > previous_seconds:
  var next_alarm := floorf(previous_seconds/86400)*86400 + alarm_minutes*60
  if next_alarm <= previous_seconds: next_alarm += 86400
  if seconds >= next_alarm: alarm_audio.play(); alarm_enabled = false
 refresh()

func refresh():
 if clock_text:
  clock_text.text = "--:--" if clock_seconds < 0 else "%02d:%02d" % [int(clock_seconds/3600)%24,int(clock_seconds/60)%60]
  alarm_text.text = "%s %02d:%02d" % ["AL" if alarm_enabled else "OFF",alarm_minutes/60,alarm_minutes%60]
