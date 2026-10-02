extends Node3D
## An isolated, seated-view experiment. Both feeds are real existing scenes.
const SIZE := Vector2i(2560,1440) # Outer application/cabin canvas.
const GAME_SIZE := Vector2i(1920,1440) # 4:3 picture filling the CRT glass.
const RANGE = preload("res://presentation/cabin/embedded_range.gd")
const MAINTENANCE = preload("res://presentation/cabin/embedded_maintenance.gd")
const TV = preload("res://assets/environment/television_02/television_live.gltf")
const TABLE = preload("res://assets/environment/painted_wooden_table/parts.gltf")
const SEAT := Vector3(0.30,1.25,1.28)
const LOOK := Vector3(-0.002,1.009,0.115)
var camera: Camera3D
var feed: SubViewport
var feeds: Array[SubViewport] = []
var sources: Array[Node] = []
var source: Node
var channel := 0
var focused := false
var transitioning := false
var powered := true
var crt_enabled := true
var crt_view: SubViewport
var crt: ShaderMaterial
var empty_text: ImageTexture
var glass: ShaderMaterial
var glass_faces := PackedVector3Array()
var last_pointer := Vector2.ZERO
var hud: Label
var glow: OmniLight3D
var tween: Tween
var root_ui: Control
var tv_mesh: MeshInstance3D

func _ready():
 ThemeDB.fallback_font = preload("res://assets/NotoSansSC-Regular.ttf")
 build_room()
 build_crt()
 build_display()
 build_ui()
 switch_channel(0)
 configure_window()
 get_window().focus_exited.connect(release_controls)
 refresh_hud()

func configure_window():
 var win := get_window()
 win.title = "Scarlet Contract · CRT 舱室实验"
 win.content_scale_size = SIZE
 win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
 win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
 win.size = Vector2i(1440,810)
 win.min_size = Vector2i(960,540)

func build_room():
 var env := WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color("05080b")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("82969e")
 env.environment.ambient_light_energy = 0.06
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 add_child(env)
 var table = TABLE.instantiate()
 table.scale = Vector3.ONE*0.78
 table.position.z = -0.12
 add_child(table)
 box(Vector3(2.5,0.08,2.8),Vector3(0,-0.05,0),Color("101518"))
 box(Vector3(2.5,2.6,0.08),Vector3(0,1.25,-0.86),Color("18262a"))
 box(Vector3(0.08,2.6,2.8),Vector3(-1.2,1.25,0.5),Color("131b21"))
 box(Vector3(0.08,2.6,2.8),Vector3(1.2,1.25,0.5),Color("131b21"))
 for x in [-0.9,-0.3,0.3,0.9]:
  box(Vector3(0.016,2.4,0.025),Vector3(x,1.25,-0.803),Color("0b1115"))
 var key := OmniLight3D.new()
 key.position = Vector3(-0.65,1.7,0.35)
 key.light_color = Color("9ab6b8")
 key.light_energy = 0.22
 key.omni_range = 2.2
 key.shadow_enabled = true
 add_child(key)
 var rim := OmniLight3D.new()
 rim.position = Vector3(0.7,1.4,-0.5)
 rim.light_color = Color("e3a268")
 rim.light_energy = 0.15
 rim.omni_range = 1.45
 rim.shadow_enabled = true
 add_child(rim)
 camera = Camera3D.new()
 camera.position = SEAT
 camera.fov = 52
 camera.near = 0.015
 camera.far = 12
 add_child(camera)
 camera.look_at(LOOK)
 camera.current = true

func box(dimensions: Vector3, at: Vector3, color: Color):
 var node := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = dimensions
 node.mesh = mesh
 var mat := StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = 0.9
 node.material_override = mat
 node.position = at
 add_child(node)

func build_crt():
 # Reuse the tested shader and its defaults, rather than a second CRT approximation.
 crt_view = SubViewport.new()
 crt_view.size = GAME_SIZE
 crt_view.disable_3d = true
 crt_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(crt_view)
 var picture := TextureRect.new()
 picture.size = GAME_SIZE
 picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
 crt = ShaderMaterial.new()
 crt.shader = preload("res://presentation/maintenance/crt.gdshader")
 # Material getters only return explicit overrides; initialize from the shared shader defaults.
 for parameter in crt.shader.get_shader_uniform_list():
  var value: Variant = RenderingServer.shader_get_parameter_default(crt.shader.get_rid(),parameter.name)
  if value != null: crt.set_shader_parameter(parameter.name,value)
 crt.set_shader_parameter("resolution",Vector2(GAME_SIZE))
 crt.set_shader_parameter("signal_resolution",Vector2(720,540))
 crt.set_shader_parameter("warp_amount",0.0)
 picture.material = crt
 crt_view.add_child(picture)
 var transparent := Image.create(1,1,false,Image.FORMAT_RGBA8)
 transparent.fill(Color.TRANSPARENT)
 empty_text = ImageTexture.create_from_image(transparent)
 picture.texture = empty_text

func _process(_delta: float):
 if not is_instance_valid(source) or not crt: return
 # Use simulation time, so the existing pause also freezes CRT interference.
 crt.set_shader_parameter("elapsed_time", source.clock_time if channel == 0 else source.simulation_time)

func build_display():
 var monitor = TV.instantiate()
 monitor.position.y = 0.75
 add_child(monitor)
 for node in monitor.find_children("*","MeshInstance3D",true,false):
  tv_mesh = node
 glass = ShaderMaterial.new()
 glass.shader = preload("res://presentation/cabin/monitor.gdshader")
 tv_mesh.set_surface_override_material(1,glass)
 var arrays := tv_mesh.mesh.surface_get_arrays(1)
 var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 for index in arrays[Mesh.ARRAY_INDEX]: glass_faces.append(vertices[index])
 glow = OmniLight3D.new()
 glow.position = Vector3(0,1.04,0.29)
 glow.light_color = Color("78b8bd")
 glow.light_energy = 0.08
 glow.omni_range = 0.75
 glow.shadow_enabled = true
 add_child(glow)

func build_ui():
 var layer := CanvasLayer.new()
 add_child(layer)
 root_ui = Control.new()
 root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
 layer.add_child(root_ui)
 hud = Label.new()
 hud.position = Vector2(48,1340)
 hud.add_theme_font_override("font",preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf"))
 hud.add_theme_font_size_override("font_size",24)
 hud.add_theme_color_override("font_color",Color("a6b8b8"))
 hud.add_theme_color_override("font_shadow_color",Color.BLACK)
 hud.add_theme_constant_override("shadow_offset_x",2)
 hud.add_theme_constant_override("shadow_offset_y",2)
 root_ui.add_child(hud)

func switch_channel(index: int):
 release_controls()
 if is_instance_valid(source):
  source.input_active = false
  source.process_mode = Node.PROCESS_MODE_DISABLED
  feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
 channel = index
 while feeds.size() <= index:
  feeds.append(null)
  sources.append(null)
 if feeds[index] == null:
  var viewport := SubViewport.new()
  viewport.size = GAME_SIZE
  viewport.own_world_3d = true
  viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
  viewport.handle_input_locally = true
  viewport.gui_disable_input = false
  add_child(viewport)
  var scene: Node = MAINTENANCE.new() if index == 0 else RANGE.new()
  if scene is Control: scene.size = GAME_SIZE
  var previous_window_size := get_window().size
  viewport.add_child(scene)
  feeds[index] = viewport
  sources[index] = scene
  configure_window()
  get_window().size = previous_window_size
 feed = feeds[index]
 source = sources[index]
 source.process_mode = Node.PROCESS_MODE_INHERIT
 source.input_active = focused and powered
 feed.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 if channel == 0:
  # Preserve the original separate 2K text layer and 960x540 scene sampling.
  crt.set_shader_parameter("scene_texture",source.object_outline.output.get_texture())
  crt.set_shader_parameter("text_texture",source.compose.get_texture())
 else:
  crt.set_shader_parameter("scene_texture",feed.get_texture())
  crt.set_shader_parameter("text_texture",empty_text)
 crt.set_shader_parameter("enabled",crt_enabled)
 glass.set_shader_parameter("live_picture",crt_view.get_texture())
 refresh_hud()

func refresh_hud():
 if not hud: return
 var name_text := "维护站 · 实时场景" if channel == 0 else "射击测试场 · 实时运行"
 if focused:
  hud.text = "Esc 返回桌前    1 切换画面    2 CRT 开关"
  hud.position = Vector2(980,8)
  hud.modulate.a = 0.7
 else:
  hud.text = "CRT 舱室实验 / " + name_text + "\n点击屏幕 / Enter 靠近    1 切换画面    2 CRT 开关    F8 显示器电源"
  hud.position = Vector2(48,1332)
  hud.modulate.a = 1.0

func release_controls():
 if not is_instance_valid(source): return
 if source.has_method("set_trigger"): source.set_trigger(false,false)
 if is_instance_valid(feed):
  var up := InputEventMouseButton.new()
  up.button_index = MOUSE_BUTTON_LEFT
  up.pressed = false
  feed.push_input(up,true)

func set_focus(value: bool):
 if transitioning or value == focused or (value and not powered): return
 release_controls()
 transitioning = true
 source.input_active = false
 focused = value
 tween = create_tween()
 tween.set_parallel(true)
 tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
 var destination := Vector3(-0.002,1.009,0.375) if value else SEAT
 var target_transform := Transform3D(Basis.IDENTITY,destination).looking_at(LOOK,Vector3.UP)
 tween.tween_property(camera,"position",destination,0.65)
 tween.tween_property(camera,"quaternion",target_transform.basis.get_rotation_quaternion(),0.65)
 tween.chain().tween_callback(func():
  transitioning = false
  source.input_active = focused and powered
  refresh_hud())

func set_power(value: bool):
 if transitioning: return
 if focused: set_focus(false)
 powered = value
 release_controls()
 source.input_active = false
 glass.set_shader_parameter("powered",powered)
 glow.visible = powered
 refresh_hud()

func glass_intersection(point: Vector2) -> Variant:
 # Intersect the original curved triangles, not a flat overlay or proxy plane.
 var inverse := tv_mesh.global_transform.affine_inverse()
 var origin := inverse * camera.project_ray_origin(point)
 var direction := (inverse.basis * camera.project_ray_normal(point)).normalized()
 var nearest: Variant = null
 var distance := INF
 for i in range(0,glass_faces.size(),3):
  var hit: Variant = Geometry3D.ray_intersects_triangle(origin,direction,glass_faces[i],glass_faces[i+1],glass_faces[i+2])
  if hit != null:
   var d: float = origin.distance_squared_to(hit)
   if d < distance:
    distance = d
    nearest = hit
 return nearest

func screen_hit(point: Vector2) -> bool:
 return glass_intersection(point) != null

func game_point(point: Vector2) -> Vector2:
 var hit: Variant = glass_intersection(point)
 if hit == null: return Vector2(-1,-1)
 # This is the same position-derived UV and letterbox mapping as monitor.gdshader.
 var uv := Vector2((hit.x+0.16010)/0.31654,(0.37741-hit.y)/0.23720)
 if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1: return Vector2(-1,-1)
 if crt_enabled: uv = crt_source_uv(uv)
 if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1: return Vector2(-1,-1)
 return uv*Vector2(GAME_SIZE)

func crt_source_uv(uv: Vector2) -> Vector2:
 # Match the shared shader's geometric warp and dynamic horizontal deflection.
 var warp_amount: float = crt.get_shader_parameter("warp_amount")
 var strength: float = crt.get_shader_parameter("strength")
 var signal_size: Vector2 = crt.get_shader_parameter("signal_resolution")
 var elapsed: float = crt.get_shader_parameter("elapsed_time")
 var delta := uv-Vector2(0.5,0.5)
 var delta2 := delta.length_squared()
 var pos := (uv+delta*delta2*delta2*warp_amount-Vector2(0.5,0.5))/lerpf(1.0,1.2,warp_amount/5.0)+Vector2(0.5,0.5)
 var x := pos.y*3.0-elapsed*float(crt.get_shader_parameter("roll_speed"))
 var f := cos(x)*cos(x*2.35+1.1)*cos(x*4.45+2.3)
 var line := smoothstep(0.5,0.9,f)*float(crt.get_shader_parameter("roll_line_amount"))*(0.6+strength)
 var row := floorf(pos.y*signal_size.y)/signal_size.y
 var frame := floorf(elapsed*30.0)
 var random_value := fposmod(cos(row*83.4827+frame*92.2842)*43758.5453123,1.0)
 var interference := (random_value-0.5)*float(crt.get_shader_parameter("interference_amount"))*(0.6+strength)
 pos.x += (interference+line*2.0)/signal_size.x
 return pos

func forward_to_screen(event: InputEvent):
 var forwarded := event.duplicate() as InputEvent
 if event is InputEventMouse:
  var mapped := game_point(event.position)
  if mapped.x < 0:
   # Clear hover and release the trigger even if release happens on the bezel.
   if event is InputEventMouseButton and not event.pressed:
    forwarded.position = last_pointer
    forwarded.global_position = last_pointer
    feed.push_input(forwarded,true)
   elif event is InputEventMouseMotion:
    var leave := InputEventMouseMotion.new()
    leave.position = Vector2(-10000,-10000)
    leave.global_position = leave.position
    feed.push_input(leave,true)
   return
  forwarded.position = mapped
  forwarded.global_position = mapped
  if event is InputEventMouseMotion:
   forwarded.relative = mapped-last_pointer
   forwarded.screen_relative = forwarded.relative
  last_pointer = mapped
 feed.push_input(forwarded,true)

func _input(event: InputEvent):
 # Numeric editors retain ordinary typing; monitor shortcuts apply outside them.
 if focused and event is InputEventKey and event.keycode in [KEY_1,KEY_2] and feed.gui_get_focus_owner() is LineEdit:
  forward_to_screen(event)
  get_viewport().set_input_as_handled()
  return
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_ESCAPE:
    if focused: set_focus(false)
    get_viewport().set_input_as_handled()
    return
   KEY_ENTER:
    if not focused:
     set_focus(true)
     get_viewport().set_input_as_handled()
     return
   KEY_1:
    if not transitioning: switch_channel(1-channel)
    get_viewport().set_input_as_handled()
    return
   KEY_2:
    crt_enabled = not crt_enabled
    crt.set_shader_parameter("enabled",crt_enabled)
    get_viewport().set_input_as_handled()
    return
   KEY_F8:
    set_power(not powered)
    get_viewport().set_input_as_handled()
    return
 if transitioning: return
 if focused and powered:
  forward_to_screen(event)
  get_viewport().set_input_as_handled()
 elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  if screen_hit(event.position): set_focus(true)
