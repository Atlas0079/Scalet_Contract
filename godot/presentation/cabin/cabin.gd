extends Node3D
## Seated cabin with live maintenance and optional shooting-range feeds.
const SIZE := Vector2i(2560,1440) # Outer application/cabin canvas.
const GAME_SIZE := Vector2i(1920,1440) # 4:3 picture filling the CRT glass.
const RANGE = preload("res://presentation/cabin/embedded_range.gd")
const MAINTENANCE = preload("res://presentation/cabin/embedded_maintenance.gd")
const RIGHT_TERMINAL = preload("res://presentation/cabin/aeon_terminal.gd")
const SCREEN_DEVICE = preload("res://presentation/cabin/screen_device.gd")
const DESK_DEVICES = preload("res://presentation/cabin/desk_devices.gd")
const SECURITY_CAMERA = preload("res://assets/environment/security_camera_01/articulated.gltf")
const TABLE = preload("res://assets/environment/cabin_workbench/workbench.gltf")
const SHELL = preload("res://presentation/cabin/cabin_shell.gd")
const SEAT := Vector3(0,1.08965,1.42)
const LOOK := Vector3(0,1.08965,0.10)
const SCREEN_DESK_INSET := 0.18
const LOOK_SOFT := Vector2(0.488692,0.279253) # 28 / 16 degrees.
const LOOK_HARD := Vector2(0.802851,0.523599) # 46 / 30 degrees.
const LOOK_SENSITIVITY := 0.002
var table_materials: Array[Material] = []
var camera: Camera3D
var shell: Node3D
var reflection_probe: ReflectionProbe
var look_angles := Vector2.ZERO # Rightward yaw / upward pitch.
var look_pending := Vector2.ZERO
var ignore_next_motion := false
var security_head: Node3D
var security_base: Node3D
var surveillance_rng := RandomNumberGenerator.new()
var glance_timer := 2.0
var glance_target := Vector2.ZERO
var glance_angles := Vector2.ZERO
var security_home := Quaternion.IDENTITY
var sight: Label
var centre_target := {}
var target_elapsed := 0.0
var desktop_fov := 65.0
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
var last_pointer := Vector2.ZERO
var fps_display: Label
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
 surveillance_rng.randomize()
 build_room()
 build_crt()
 build_display()
 devices = DESK_DEVICES.new()
 devices.position.z = -SCREEN_DESK_INSET
 add_child(devices)
 devices.sleep_requested.connect(func():
  notice = "睡觉按键已触发；世界时间与睡觉流程尚未接入"
  refresh_hud())
 build_ui()
 switch_channel(0)
 configure_window()
 get_window().focus_exited.connect(on_window_focus_exited)
 get_window().focus_entered.connect(restore_mouse_mode)
 refresh_hud()
 restore_mouse_mode()

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
 # A very low diffuse floor keeps unlit surfaces readable in this unbaked room.
 env.environment.ambient_light_energy = 0.25
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 env.environment.ssao_enabled = true
 env.environment.ssao_radius = 0.18
 env.environment.ssao_intensity = 0.6
 env.environment.ssao_detail = 0.25
 add_child(env)
 var table = TABLE.instantiate()
 table.name = "CabinWorkbench"
 table.position.z = -0.12
 add_child(table)
 # The folded tabletop keeps its continuous worn-material controls,
 # with corrosion and wiped areas placed consistently in physical space.
 var steel := ShaderMaterial.new()
 steel.resource_name = "CabinRustSteel"
 steel.shader = preload("res://presentation/cabin/table_steel.gdshader")
 steel.set_shader_parameter("paint_color",preload("res://assets/environment/cabin_workbench/textures/worn_paint_albedo.png"))
 steel.set_shader_parameter("steel_color",preload("res://assets/environment/rusty_metal_05/rusty_metal_05_diff_4k.jpg"))
 steel.set_shader_parameter("steel_arm",preload("res://assets/environment/rusty_metal_05/rusty_metal_05_arm_4k.jpg"))
 steel.set_shader_parameter("steel_normal",preload("res://assets/environment/rusty_metal_05/rusty_metal_05_nor_gl_4k.jpg"))
 for node in table.find_children("*","MeshInstance3D",true,false):
  for surface in range(node.mesh.get_surface_count()):
   var material: ShaderMaterial = steel.duplicate()
   node.set_surface_override_material(surface,material)
   table_materials.append(material)
 shell = SHELL.new()
 shell.name = "CabinShell"
 add_child(shell)
 build_cabin_lighting()
 camera = Camera3D.new()
 camera.position = SEAT
 camera.fov = 65
 camera.near = 0.015
 camera.far = 12
 add_child(camera)
 camera.look_at(LOOK)
 camera.current = true

func build_cabin_lighting():
 reflection_probe = ReflectionProbe.new()
 reflection_probe.name = "CabinReflection"
 reflection_probe.position = Vector3(0,0.87,0.51)
 reflection_probe.size = Vector3(2.28,1.74,2.62)
 reflection_probe.origin_offset = Vector3(0,0.25,0.15)
 reflection_probe.interior = true
 reflection_probe.box_projection = true
 reflection_probe.intensity = 0.55
 reflection_probe.max_distance = 4.0
 reflection_probe.cull_mask = 1
 reflection_probe.enable_shadows = true
 reflection_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
 add_child(reflection_probe)

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
 update_observation(minf(_delta,0.05))
 if not is_instance_valid(source) or not crt: return
 # Use simulation time, so the existing pause also freezes CRT interference.
 crt.set_shader_parameter("elapsed_time", source.clock_time if channel == 0 else source.simulation_time)

func build_display():
 for index in range(3):
  var monitor = RIGHT_TERMINAL.new() if index==2 else SCREEN_DEVICE.new()
  add_child(monitor)
  var at := Vector3(0,0.74,0.02-SCREEN_DESK_INSET)
  if index==2:
   monitor.configure_terminal(Vector3(0,.7451026,-.16),screens[1].housing_bounds.size.y*screens[1].scale.y*.8)
  else:monitor.configure(at,0.0,1.35)
  if index != 1:
   # Join the measured front housing edges, then aim each side glass towards the seated eye.
   var left := index == 0
   var hinge_x := -0.201708734 if left else 0.198039740
   var edge_x := 0.198039740 if left else -0.201708734
   var hinge := Vector3(hinge_x*1.35,0.74,0.02-SCREEN_DESK_INSET+0.121902674*1.35)
   var edge: Vector3 = Vector3(edge_x,0,0.121902674)*1.35 if left else Vector3(monitor.housing_bounds.position.x,0,monitor.housing_bounds.end.z)*monitor.scale.x
   for attempt in range(12):
    monitor.position = hinge-monitor.basis.orthonormalized()*edge
    var direction: Vector3 = SEAT-monitor.center()
    monitor.rotation.y = atan2(direction.x,direction.z)
   monitor.position = hinge-monitor.basis.orthonormalized()*edge
   if not left:monitor.position.y=.7473526-monitor.housing_bounds.position.y*monitor.scale.y
  if monitor.uses_crt:monitor.glass.set_shader_parameter("live_picture",crt_view.get_texture())
  screens.append(monitor)
 select_screen(1)
 fit_desktop_view()
 security_camera = SECURITY_CAMERA.instantiate()
 # Mount on the player's right wall: source -Z plate faces outward along world +X.
 security_camera.position = Vector3(0.9130877,1.50,-0.34)
 security_camera.rotation.y = -PI/2.0
 security_camera.scale = Vector3.ONE*0.55
 add_child(security_camera)
 for mesh in security_camera.find_children("*","MeshInstance3D",true,false):
  for surface in range(mesh.mesh.get_surface_count()):
   var original := mesh.get_active_material(surface) as StandardMaterial3D
   if original:
    var dark := original.duplicate() as StandardMaterial3D
    dark.albedo_color *= Color(0.45,0.45,0.45,1.0)
    if dark.metallic_texture:
     dark.ao_enabled = true
     dark.ao_texture = dark.metallic_texture
     dark.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    mesh.set_surface_override_material(surface,dark)
 security_head = security_camera.find_child("Head",true,false)
 security_base = security_camera.find_child("FixedBase",true,false)
 var head_geometry: Node3D = security_camera.find_child("HeadGeometry",true,false)
 # Source glass is the front +Z face, centred at these measured model coordinates.
 for attempt in range(3):
  var lens := head_geometry.to_global(Vector3(0.00083,0.18785,0.19876))
  var world_pose := Basis.looking_at(SEAT-lens,Vector3.UP,true)
  var parent_pose: Basis = security_head.get_parent().global_basis.orthonormalized()
  security_head.quaternion = (parent_pose.inverse()*world_pose).get_rotation_quaternion()
 security_home = security_head.quaternion
 camera_led = MeshInstance3D.new()
 var dot := SphereMesh.new()
 dot.radius = 0.0035
 dot.height = 0.007
 camera_led.mesh = dot
 var material := StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color = Color("c01812")
 material.emission_enabled = true
 material.emission = Color("c01812")
 material.emission_energy_multiplier = 1.2
 camera_led.material_override = material
 # Attached next to the lens on the source front panel, in model coordinates.
 camera_led.position = Vector3(0.063,0.208,0.2035)
 head_geometry.add_child(camera_led)
 # Optical halo belongs to the visible LED, independently of light on its housing.
 var glare := MeshInstance3D.new()
 glare.name = "IndicatorGlare"
 var glare_quad := QuadMesh.new()
 glare_quad.size = Vector2(0.05,0.05)
 glare.mesh = glare_quad
 glare.layers = 2 # Optical scatter is visible to the player, not a reflection source.
 glare.position.z = 0.007
 glare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var glare_material := ShaderMaterial.new()
 glare_material.shader = preload("res://presentation/cabin/indicator_glare.gdshader")
 glare.material_override = glare_material
 camera_led.add_child(glare)
 glare.look_at(SEAT,Vector3.UP,true)
 # A tiny physical emitter lets the indicator tint the nearby front panel.
 var indicator_light := OmniLight3D.new()
 indicator_light.name = "IndicatorLight"
 indicator_light.position.z = 0.008
 indicator_light.light_color = Color("ff2114")
 indicator_light.light_energy = 0.00006
 indicator_light.omni_range = 0.012
 indicator_light.omni_attenuation = 1.5
 indicator_light.shadow_enabled = true
 camera_led.add_child(indicator_light)

func fit_desktop_view():
 # Fit the actual housing geometry, retaining 1.5% of picture width at either edge.
 var horizontal_slope := 0.0
 var camera_inverse := camera.global_transform.affine_inverse()
 for monitor in screens:
  for mesh in monitor.find_children("*","MeshInstance3D",true,false):
   for surface in range(mesh.mesh.get_surface_count()):
    var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
    for vertex in vertices:
     var local: Vector3 = camera_inverse*mesh.to_global(vertex)
     if local.z < -camera.near:
      horizontal_slope = maxf(horizontal_slope,absf(local.x)/-local.z)
 var aspect := float(SIZE.x)/float(SIZE.y)
 desktop_fov = rad_to_deg(2.0*atan(horizontal_slope/(aspect*0.97)))
 camera.fov = desktop_fov

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
 fps_display = preload("res://presentation/cabin/fps_display.gd").new()
 fps_display.name = "FrameRate"
 root_ui.add_child(fps_display)
 sight = Label.new()
 sight.add_theme_font_override("font",preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf"))
 sight.add_theme_font_size_override("font_size",24)
 sight.add_theme_color_override("font_color",Color("b8c6bc"))
 sight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 sight.size = Vector2(600,80)
 sight.position = Vector2(SIZE)/2.0-Vector2(300,8)
 sight.mouse_filter = Control.MOUSE_FILTER_IGNORE
 root_ui.add_child(sight)

func switch_channel(index: int):
 release_controls()
 if is_instance_valid(source):
  source.input_active = false
  source.process_mode = Node.PROCESS_MODE_DISABLED
  feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
  for child in feed.find_children("*","SubViewport",true,false):child.render_target_update_mode = SubViewport.UPDATE_DISABLED
 channel = index
 while feeds.size() <= index:
  feeds.append(null)
  sources.append(null)
 if feeds[index] == null:
  var viewport := SubViewport.new()
  viewport.size = GAME_SIZE
  viewport.own_world_3d = true
  viewport.disable_3d = index==0
  viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if index==0 else SubViewport.UPDATE_ALWAYS
  viewport.handle_input_locally = true
  viewport.gui_disable_input = false
  add_child(viewport)
  var scene: Node = MAINTENANCE.new() if index == 0 else RANGE.new()
  if scene is Control: scene.size = Vector2(viewport.size)
  var previous_window_size := get_window().size
  viewport.add_child(scene)
  feeds[index] = viewport
  sources[index] = scene
  configure_window()
  get_window().size = previous_window_size
 feed = feeds[index]
 source = sources[index]
 source.process_mode = Node.PROCESS_MODE_INHERIT
 source.input_active = focused and powered and focused_device.is_empty() and screens[active_screen].uses_crt
 feed.render_target_update_mode = SubViewport.UPDATE_DISABLED if index==0 else SubViewport.UPDATE_ALWAYS
 if index==0:
  source.set_render_live(source.input_active)
 if channel==0:
  crt.set_shader_parameter("scene_texture",source.object_outline.output.get_texture())
  crt.set_shader_parameter("text_texture",source.compose.get_texture())
 else:
  crt.set_shader_parameter("scene_texture",feed.get_texture())
  crt.set_shader_parameter("text_texture",empty_text)
 crt.set_shader_parameter("enabled",crt_enabled)
 for monitor in screens:
  if monitor.uses_crt:monitor.glass.set_shader_parameter("live_picture",crt_view.get_texture())
 refresh_hud()

func refresh_hud():
 if not hud: return
 hud.text = "鼠标转头 · 左键聚焦视野中心设备 · 转头过度会回弹\nEsc 返回观察 / 释放鼠标 · F1 左 F2 中 F3 终端 · 1 房间／射击预览 · 2 左／中 CRT · F8 当前屏电源 · F9 隐藏提示"
 if devices: hud.text += "\n世界时钟未接入（--:--）"
 if focused_device=="phone":hud.text += "\n数字键输入 · Enter 呼叫／接听 · Backspace 清除／拒接 · End 挂断 · I 测试来电"
 if focused and focused_device.is_empty() and not screens[active_screen].uses_crt:hud.text += "\n左键拖动下方四个旋钮 · 滚轮微调"
 if not notice.is_empty(): hud.text += " · "+notice
 hud.position = Vector2(48,1320)
 hud.modulate.a = 0.65

func release_controls():
 for monitor in screens:monitor.release_controls()
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
 var direction := Vector3(sin(look_angles.x)*cos(look_angles.y),sin(look_angles.y),-cos(look_angles.x)*cos(look_angles.y))
 var target := SEAT+direction
 var fov := desktop_fov
 var eye := SEAT
 var up := Vector3.UP
 if value:
  if focused_device.is_empty():
   target = screens[active_screen].focus_center()
   var distance: float = SEAT.distance_to(target)
   # Frame the real glass with a small bezel, consistently for all three CRTs.
   var frame_height: float = screens[active_screen].focus_height()
   fov = rad_to_deg(2.0*atan(frame_height/(2.0*distance)))
  else:
   target = devices.focus_point(focused_device)
   # Lean above the top-mounted clock so its authored buttons can be reached.
   eye = Vector3(0,1.65,0.66)
   fov = 34.0
   if focused_device=="phone":
    eye = target+Vector3(0,0.34,0)
    up = Vector3.FORWARD
    fov = 23.0
 else: focused_device = ""
 release_controls()
 transitioning = true
 look_pending = Vector2.ZERO
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 if is_instance_valid(source): source.input_active = false
 focused = value
 tween = create_tween()
 tween.set_parallel(true)
 tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
 var pose := Transform3D(Basis.IDENTITY,eye).looking_at(target,up)
 tween.tween_property(camera,"position",eye,0.65)
 tween.tween_property(camera,"quaternion",pose.basis.get_rotation_quaternion(),0.65)
 tween.tween_property(camera,"fov",fov,0.65)
 tween.chain().tween_callback(func():
  transitioning = false
  source.input_active = focused and powered and focused_device.is_empty() and screens[active_screen].uses_crt
  restore_mouse_mode()
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
 source.input_active = focused and powered and focused_device.is_empty() and screens[active_screen].uses_crt
 refresh_hud()

func glass_intersection(point: Vector2) -> Variant:
 return screens[active_screen].intersect(camera,point)

func game_point(point: Vector2) -> Vector2:
 var hit: Variant = glass_intersection(point)
 if hit == null: return Vector2(-1,-1)
 # This is the same position-derived UV and letterbox mapping as monitor.gdshader.
 var uv: Vector2 = screens[active_screen].picture_uv(hit)
 if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1: return Vector2(-1,-1)
 if crt_enabled and screens[active_screen].uses_crt: uv = crt_source_uv(uv)
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

func restore_mouse_mode():
 if not get_window().has_focus(): return
 if is_instance_valid(source): source.input_active = focused and powered and focused_device.is_empty() and screens[active_screen].uses_crt and not transitioning
 var mode := Input.MOUSE_MODE_VISIBLE if focused or transitioning else Input.MOUSE_MODE_CAPTURED
 if mode == Input.MOUSE_MODE_CAPTURED and Input.mouse_mode != mode:
  look_pending = Vector2.ZERO
  ignore_next_motion = true
 Input.mouse_mode = mode

func on_window_focus_exited():
 look_pending = Vector2.ZERO
 release_controls()
 if is_instance_valid(source): source.input_active = false
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func apply_look_pose():
 var direction := Vector3(sin(look_angles.x)*cos(look_angles.y),sin(look_angles.y),-cos(look_angles.x)*cos(look_angles.y))
 camera.position = SEAT
 camera.look_at(SEAT+direction,Vector3.UP)
 camera.fov = desktop_fov

func update_observation(delta: float):
 if not focused and not transitioning:
  for axis in range(2):
   var angle: float = look_angles[axis]
   var movement: float = look_pending[axis]*LOOK_SENSITIVITY
   var pressure := clampf((absf(angle)-LOOK_SOFT[axis])/(LOOK_HARD[axis]-LOOK_SOFT[axis]),0.0,1.0)
   if signf(movement) == signf(angle): movement /= 1.0+pressure*pressure*8.0
   angle = clampf(angle+movement,-LOOK_HARD[axis],LOOK_HARD[axis])
   var excess := maxf(absf(angle)-LOOK_SOFT[axis],0.0)
   var outer := excess/(LOOK_HARD[axis]-LOOK_SOFT[axis])
   angle = signf(angle)*(absf(angle)-minf(excess,excess*(3.0+4.0*outer*outer)*delta))
   look_angles[axis] = angle
  apply_look_pose()
 look_pending = Vector2.ZERO
 if is_instance_valid(security_head):
  glance_timer -= delta
  if glance_timer <= 0.0:
   glance_timer = surveillance_rng.randf_range(2.0,5.0)
   glance_target = Vector2(surveillance_rng.randf_range(-0.10,0.10),surveillance_rng.randf_range(-0.06,0.06))
  glance_angles = glance_angles.lerp(glance_target,1.0-exp(-delta*3.0))
  security_head.quaternion = security_home*Quaternion(Vector3.UP,glance_angles.x)*Quaternion(Vector3.RIGHT,glance_angles.y)
  camera_led.get_node("IndicatorGlare").look_at(camera.global_position,Vector3.UP,true)
 if not sight: return
 sight.visible = not focused and not transitioning and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
 target_elapsed += delta
 if sight.visible and target_elapsed >= 0.1:
  target_elapsed = 0.0
  centre_target = centre_device()
  var label: String = centre_target.get("label","")
  var strained := absf(look_angles.x)>LOOK_SOFT.x+0.005 or absf(look_angles.y)>LOOK_SOFT.y+0.005
  sight.text = "·\n"+(label+(" · 左键拨弄" if not centre_target.get("focusable",true) else " · 左键聚焦") if not label.is_empty() else "")
  if strained: sight.text += "\n转头受限"

func centre_device() -> Dictionary:
 var point := camera.get_viewport().get_visible_rect().get_center()
 var result := {}
 var distance := INF
 for index in range(screens.size()):
  var hit: Variant = screens[index].housing_hit(camera,point)
  if hit != null:
   var d: float = camera.global_position.distance_squared_to(hit)
   if d < distance:
    distance = d
    result = {"kind":"screen","index":index,"label":["左显示器","中央显示器","AEON 终端"][index]}
 if devices:
  for kind in devices.models:
   for mesh in devices.models[kind].node.find_children("*","MeshInstance3D",true,false):
    var hit: Variant = devices.mesh_hit(camera,point,mesh)
    if hit != null:
     var d: float = camera.global_position.distance_squared_to(hit)
     if d < distance:
      distance = d
      result = {"kind":kind,"label":devices.label_for(kind),"focusable":devices.focusable(kind)}
 return result

func focus_centre_device():
 var target := centre_device()
 if target.is_empty(): return
 if target.kind == "screen": focus_screen(target.index)
 elif not target.get("focusable",true):devices.poke(target.kind)
 else: focus_desk_device(target.kind)

func _input(event: InputEvent):
 if focused and focused_device=="phone" and not transitioning and event is InputEventKey:
  if devices.phone.keyboard(event):
   get_viewport().set_input_as_handled()
   return
 # Numeric editors retain ordinary typing; monitor shortcuts apply outside them.
 if focused and focused_device.is_empty() and screens[active_screen].uses_crt and event is InputEventKey and event.keycode in [KEY_1,KEY_2] and feed.gui_get_focus_owner() is LineEdit:
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
    elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
     look_pending = Vector2.ZERO
     Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else: restore_mouse_mode()
    get_viewport().set_input_as_handled()
    return
   KEY_ENTER:
    if not focused:
     focus_centre_device()
     get_viewport().set_input_as_handled()
     return
   KEY_1:
    if not transitioning: switch_channel(1-channel)
    get_viewport().set_input_as_handled()
    return
   KEY_2:
    if screens[active_screen].uses_crt:
     crt_enabled = not crt_enabled
     crt.set_shader_parameter("enabled",crt_enabled)
    get_viewport().set_input_as_handled()
    return
   KEY_F8:
    set_power(not powered)
    get_viewport().set_input_as_handled()
    return
 if transitioning: return
 if not focused:
  if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
   if ignore_next_motion: ignore_next_motion = false
   else: look_pending += Vector2(event.screen_relative.x,-event.screen_relative.y)
   get_viewport().set_input_as_handled()
  elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
   if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: restore_mouse_mode()
   else: focus_centre_device()
   get_viewport().set_input_as_handled()
  return
 if focused and focused_device.is_empty() and not screens[active_screen].uses_crt:
  if screens[active_screen].handle_control_input(event,camera,devices):
   get_viewport().set_input_as_handled()
   return
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
 if focused and powered and focused_device.is_empty() and screens[active_screen].uses_crt:
  forward_to_screen(event)
  get_viewport().set_input_as_handled()
