extends Node3D
## An isolated, seated-view experiment. Both feeds are real existing scenes.
const SIZE := Vector2i(2560,1440) # Outer application/cabin canvas.
const GAME_SIZE := Vector2i(1920,1440) # 4:3 picture filling the CRT glass.
const RANGE = preload("res://presentation/cabin/embedded_range.gd")
const MAINTENANCE = preload("res://presentation/cabin/embedded_maintenance.gd")
const SCREEN_DEVICE = preload("res://presentation/cabin/screen_device.gd")
const DESK_DEVICES = preload("res://presentation/cabin/desk_devices.gd")
const SECURITY_CAMERA = preload("res://assets/environment/security_camera_01/security_camera_01.gltf")
const TABLE = preload("res://assets/environment/painted_wooden_table/parts.gltf")
const SEAT := Vector3(0,1.08965,1.42)
const LOOK := Vector3(0,1.08965,0.10)
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
var screen_light_texture: ImageTexture
var screen_light_elapsed := 0.0
var screen_light_view: SubViewport
var crt_view: SubViewport
var crt: ShaderMaterial
var empty_text: ImageTexture
var glass: ShaderMaterial
var last_pointer := Vector2.ZERO
var hud: Label
var tween: Tween
var root_ui: Control
var screens: Array[Node3D] = []
var active_screen := 1
var focused_device := ""
var security_camera: Node3D
var camera_led: MeshInstance3D
var devices: Node3D
var notice := ""

func _ready():
 ThemeDB.fallback_font = preload("res://assets/NotoSansSC-Regular.ttf")
 build_room()
 build_crt()
 build_display()
 devices = DESK_DEVICES.new()
 add_child(devices)
 devices.sleep_requested.connect(func():
  notice = "睡觉按键已触发；世界时间与睡觉流程尚未接入"
  refresh_hud())
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
 env.environment.background_color = Color("010203")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("82969e")
 env.environment.ambient_light_energy = 0.0
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 add_child(env)
 var table = TABLE.instantiate()
 table.scale = Vector3(1.02,0.78,1.16)
 table.position.z = -0.12
 add_child(table)
 # Dark matte paint keeps the desk from overpowering the screen-lit hardware.
 for node in table.find_children("*","MeshInstance3D",true,false):
  for surface in range(node.mesh.get_surface_count()):
   var original := node.get_active_material(surface) as StandardMaterial3D
   if original:
    var matte := original.duplicate() as StandardMaterial3D
    matte.albedo_color *= Color(0.07,0.07,0.07,1.0)
    matte.roughness = 0.95
    node.set_surface_override_material(surface,matte)
 box(Vector3(2.5,0.08,2.8),Vector3(0,-0.05,0),Color("101518"))
 box(Vector3(2.5,2.6,0.08),Vector3(0,1.25,-0.86),Color("18262a"))
 box(Vector3(0.08,2.6,2.8),Vector3(-1.2,1.25,0.5),Color("131b21"))
 box(Vector3(0.08,2.6,2.8),Vector3(1.2,1.25,0.5),Color("131b21"))
 for x in [-0.9,-0.3,0.3,0.9]:
  box(Vector3(0.016,2.4,0.025),Vector3(x,1.25,-0.803),Color("0b1115"))
 camera = Camera3D.new()
 camera.position = SEAT
 camera.fov = 65
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
 # Shared low-resolution live picture for the three screen emitters.
 var light_black := Image.create(128,128,false,Image.FORMAT_RGBA8)
 light_black.fill(Color.BLACK)
 screen_light_texture = ImageTexture.create_from_image(light_black)
 screen_light_view = SubViewport.new()
 screen_light_view.size = Vector2i(128,128)
 screen_light_view.disable_3d = true
 screen_light_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(screen_light_view)
 var light_picture := TextureRect.new()
 light_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 light_picture.size = screen_light_view.size
 light_picture.texture = crt_view.get_texture()
 screen_light_view.add_child(light_picture)


func _process(_delta: float):
 screen_light_elapsed += _delta
 if screen_light_elapsed >= 0.1 and screen_light_view:
  screen_light_elapsed = 0.0
  var image := screen_light_view.get_texture().get_image()
  if image and not image.is_empty():
   image.convert(Image.FORMAT_RGBA8)
   # Rebinding refreshes the area-light atlas; retain the previous texture until all emitters switch.
   var next_texture := ImageTexture.create_from_image(image)
   for monitor in screens: monitor.glow.area_texture = next_texture
   screen_light_texture = next_texture
 if not is_instance_valid(source) or not crt: return
 # Use simulation time, so the existing pause also freezes CRT interference.
 crt.set_shader_parameter("elapsed_time", source.clock_time if channel == 0 else source.simulation_time)

func build_display():
 for index in range(3):
  var monitor := SCREEN_DEVICE.new()
  add_child(monitor)
  var at := Vector3(0,0.74,0.02)
  monitor.configure(at,0.0,1.35)
  if index != 1:
   # Join the measured front housing edges, then aim each side glass towards the seated eye.
   var left := index == 0
   var hinge_x := -0.201708734 if left else 0.198039740
   var edge_x := 0.198039740 if left else -0.201708734
   var hinge := Vector3(hinge_x*1.35,0.74,0.02+0.121902674*1.35)
   var edge := Vector3(edge_x,0,0.121902674)*1.35
   for attempt in range(12):
    monitor.position = hinge-monitor.basis.orthonormalized()*edge
    var direction := SEAT-monitor.center()
    monitor.rotation.y = atan2(direction.x,direction.z)
   monitor.position = hinge-monitor.basis.orthonormalized()*edge
  monitor.glass.set_shader_parameter("live_picture",crt_view.get_texture())
  monitor.glow.area_texture = screen_light_texture
  screens.append(monitor)
 select_screen(1)
 security_camera = SECURITY_CAMERA.instantiate()
 security_camera.position = Vector3(0.85,1.57,-0.32)
 security_camera.scale = Vector3.ONE*0.55
 add_child(security_camera)
 # Source glass is the front +Z face, centred at these measured model coordinates.
 for attempt in range(3):
  var lens := security_camera.to_global(Vector3(0.00083,0.18785,0.19876))
  security_camera.quaternion = Basis.looking_at(SEAT-lens,Vector3.UP,true).get_rotation_quaternion()
 camera_led = MeshInstance3D.new()
 var dot := SphereMesh.new()
 dot.radius = 0.0045
 dot.height = 0.009
 camera_led.mesh = dot
 var material := StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color = Color("c01812")
 camera_led.material_override = material
 # Attached next to the lens on the source front panel, in model coordinates.
 camera_led.position = Vector3(0.063,0.208,0.2035)
 security_camera.add_child(camera_led)

func select_screen(index: int):
 active_screen = index
 var monitor = screens[index]
 glass = monitor.glass
 powered = monitor.powered

func focus_screen(index: int):
 if transitioning: return
 release_controls()
 if is_instance_valid(source): source.input_active = false
 select_screen(index)
 focused_device = ""
 animate_focus(true)

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
 source.input_active = focused and powered and focused_device.is_empty()
 feed.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 if channel == 0:
  # Preserve separate scene/text inputs; the cabin uses 720x540 sampling.
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
 hud.text = "点击屏幕 / F1 左 F2 中 F3 右 · Esc 桌前 · 1 切换画面 · 2 CRT · F8 当前屏电源 · F9 隐藏提示\n点击中央屏上方闹钟聚焦 · FAST/SLOW 调响铃 · ALARM 开关 · SLEEP 睡觉"
 if devices: hud.text += "\n世界时钟未接入（--:--）"
 if not notice.is_empty(): hud.text += " · "+notice
 hud.position = Vector2(48,1320)
 hud.modulate.a = 0.65

func release_controls():
 if not is_instance_valid(source): return
 if source.has_method("set_trigger"): source.set_trigger(false,false)
 if is_instance_valid(feed):
  var up := InputEventMouseButton.new()
  up.button_index = MOUSE_BUTTON_LEFT
  up.pressed = false
  feed.push_input(up,true)

func set_focus(value: bool):
 if transitioning or value == focused: return
 animate_focus(value)

func animate_focus(value: bool):
 var target := LOOK
 var fov := 65.0
 var eye := SEAT
 if value:
  if focused_device.is_empty():
   target = screens[active_screen].center()
   var distance: float = SEAT.distance_to(target)
   # Frame the real glass with a small bezel, consistently for all three CRTs.
   var frame_height: float = 0.23720 * screens[active_screen].scale.y * 1.35
   fov = rad_to_deg(2.0*atan(frame_height/(2.0*distance)))
  else:
   target = devices.focus_point(focused_device)
   # Lean above the top-mounted clock so its authored buttons can be reached.
   eye = Vector3(0,1.65,0.66)
   fov = 34.0
 else: focused_device = ""
 release_controls()
 transitioning = true
 if is_instance_valid(source): source.input_active = false
 focused = value
 tween = create_tween()
 tween.set_parallel(true)
 tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
 var pose := Transform3D(Basis.IDENTITY,eye).looking_at(target,Vector3.UP)
 tween.tween_property(camera,"position",eye,0.65)
 tween.tween_property(camera,"quaternion",pose.basis.get_rotation_quaternion(),0.65)
 tween.tween_property(camera,"fov",fov,0.65)
 tween.chain().tween_callback(func():
  transitioning = false
  source.input_active = focused and powered and focused_device.is_empty()
  refresh_hud())

func focus_desk_device(kind: String):
 if transitioning: return
 focused_device = kind
 animate_focus(true)

func set_power(value: bool):
 if transitioning: return
 release_controls()
 screens[active_screen].set_power(value)
 powered = value
 source.input_active = focused and powered and focused_device.is_empty()
 refresh_hud()

func glass_intersection(point: Vector2) -> Variant:
 return screens[active_screen].intersect(camera,point)

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
 if focused and focused_device.is_empty() and event is InputEventKey and event.keycode in [KEY_1,KEY_2] and feed.gui_get_focus_owner() is LineEdit:
  forward_to_screen(event)
  get_viewport().set_input_as_handled()
  return
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_F1, KEY_F2, KEY_F3:
    focus_screen(event.keycode-KEY_F1)
    get_viewport().set_input_as_handled()
    return
   KEY_F9:
    hud.visible = not hud.visible
    get_viewport().set_input_as_handled()
    return
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
 if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  var contact: Dictionary = devices.hit(camera,event.position)
  if not contact.is_empty():
   devices.activate(contact)
   refresh_hud()
   get_viewport().set_input_as_handled()
   return
 if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  var selected := -1
  var distance := INF
  for index in range(screens.size()):
   var hit: Variant = screens[index].intersect(camera,event.position)
   if hit != null:
    var world_hit: Vector3 = screens[index].mesh.to_global(hit)
    var d := camera.global_position.distance_squared_to(world_hit)
    if d < distance:
     distance = d
     selected = index
  if selected >= 0 and (not focused or not focused_device.is_empty() or selected != active_screen):
   focus_screen(selected)
   get_viewport().set_input_as_handled()
   return
 if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  var kind: String = devices.body_hit(camera,event.position)
  if not kind.is_empty() and (not focused or focused_device != kind):
   focus_desk_device(kind)
   get_viewport().set_input_as_handled()
   return
 if focused and powered and focused_device.is_empty():
  forward_to_screen(event)
  get_viewport().set_input_as_handled()
