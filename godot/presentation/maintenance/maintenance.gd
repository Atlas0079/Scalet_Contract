extends Control
## World state and interactions belong to SCWorld; this script renders the room.
const ACTOR = preload("res://presentation/tactical/tactical_actor.gd")
const SURFACE = preload("res://presentation/maintenance/surface.gdshader")
const OBJECT_OUTLINE = preload("res://presentation/maintenance/object_outline.gd")
const CRT = preload("res://presentation/maintenance/crt.gdshader")
const FONT_SOURCE = preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf")
var font: FontFile
const SIZE = Vector2i(2560,1440)
const ARENA = Rect2(-6,-4,12,8)
var view: SubViewport
var world: Node3D
var camera: Camera3D
var screen: TextureRect
var post: ShaderMaterial
var compose: SubViewport
var final_view: SubViewport
var ui_layer: Control
var text_items: Array[Dictionary] = []
var simulation: SCWorld
var doors: Array[Dictionary] = []
var bypass := false
var saved_crt_enabled := true
var capture_time := 1.25
var surfaces: Array[ShaderMaterial] = []

var unit: Node3D
var character: SCActor
var at: Vector2:
 get: return character.position
 set(value): character.position = value
var facing: float:
 get: return character.facing
 set(value): character.facing = value
var clock_time: float:
 get: return simulation.time
var frozen: bool:
 get: return simulation.paused
 set(value): simulation.set_paused(value)
var zoom := 1.0
var strength := 0.4
const CRT_WARP := 0.30
const CRT_SIGNAL_SIZE := Vector2(960,540)
const OUTLINE_PIXELS := 3.0
var object_outline: RefCounted
var outline_enabled := true
var imported_assets: Array[Node3D] = []
var selected_note := -1
var status: Label
var note: Label
var note_back: ColorRect
var help: Label

var lights: Array[OmniLight3D] = []
var capture_pending := ""

func _ready():
 if not SCData.ensure_valid(get_tree()): return
 simulation = SCWorld.new("maintenance",true)
 character = simulation.actors[0]
 var win := get_window()
 win.title = "Scarlet Contract · 地下维护站 / 美术小样"
 win.content_scale_size = SIZE
 win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
 win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
 win.size = Vector2i(1280,720)
 win.min_size = Vector2i(1280,720)
 view = SubViewport.new()
 view.size = SIZE
 view.own_world_3d = true
 view.msaa_3d = Viewport.MSAA_8X
 view.positional_shadow_atlas_size = 4096
 view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(view)
 world = Node3D.new()
 view.add_child(world)
 var env := WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color("080f13")
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color("829ca4")
 env.environment.ambient_light_energy = 0.23
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 world.add_child(env)
 var fill := DirectionalLight3D.new()
 fill.rotation_degrees = Vector3(-68,-28,0)
 fill.light_color = Color("b7c7d0")
 fill.light_energy = 0.27
 fill.shadow_enabled = true
 world.add_child(fill)
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 10.8
 camera.position = Vector3(0,24,-0.25)
 world.add_child(camera)
 camera.look_at(Vector3(0,0,-0.25),Vector3.FORWARD)
 camera.far = 50
 camera.current = true
 font = FONT_SOURCE.duplicate()
 font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
 font.hinting = TextServer.HINTING_NONE
 font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
 build_architecture()
 build_workshop()
 build_power_room()
 build_corridor()
 for light in lights: light.light_energy *= 0.52
 build_character()
 object_outline = OBJECT_OUTLINE.new()
 object_outline.configure(self,view,world,camera,unit,imported_assets,SIZE)
 compose = SubViewport.new()
 compose.size = SIZE
 compose.disable_3d = true
 compose.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(compose)
 compose.transparent_bg = true
 ui_layer = Control.new()
 ui_layer.size = SIZE
 ui_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 compose.add_child(ui_layer)
 for item in text_items:
  var label := ui_label(item.text,Vector2.ZERO,item.font_size,item.color)
  label.add_theme_constant_override("outline_size",0)
  item["label"] = label
 build_ui()
 final_view = SubViewport.new()
 final_view.size = SIZE
 final_view.disable_3d = true
 final_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(final_view)
 var glass := TextureRect.new()
 glass.size = SIZE
 glass.texture = object_outline.output.get_texture()
 glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 post = ShaderMaterial.new()
 post.shader = CRT
 post.set_shader_parameter("scene_texture",object_outline.output.get_texture())
 post.set_shader_parameter("text_texture",compose.get_texture())
 post.set_shader_parameter("enabled",true)
 post.set_shader_parameter("strength",strength)
 post.set_shader_parameter("warp_amount",CRT_WARP)
 post.set_shader_parameter("signal_resolution",CRT_SIGNAL_SIZE)
 post.set_shader_parameter("noise_amount",0.012)
 post.set_shader_parameter("interference_amount",0.02)
 post.set_shader_parameter("roll_line_amount",0.035)
 post.set_shader_parameter("aberration_pixels",1.5)
 glass.material = post
 final_view.add_child(glass)
 screen = TextureRect.new()
 screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 screen.texture = final_view.get_texture()
 screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(screen)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture="): capture_pending = arg.trim_prefix("--capture=")
  if arg == "--clean": set_bypass(true)
  if arg == "--no-crt": post.set_shader_parameter("enabled",false)
  if arg.begins_with("--time="): capture_time = arg.trim_prefix("--time=").to_float()
  if arg == "--no-outline": toggle_outline()
  if arg == "--closed": set_door(0,true)
  if arg == "--zoom": zoom = 1.5; camera.size = 10.8/zoom
 update_outline_width()
 refresh_status()
 update_text_positions()
 if not capture_pending.is_empty():
  await get_tree().create_timer(2.0).timeout
  frozen = true
  post.set_shader_parameter("elapsed_time",capture_time)
  await RenderingServer.frame_post_draw
  final_view.get_texture().get_image().save_png(capture_pending)
  print("CAPTURE ",capture_pending," ",final_view.size)
  get_tree().quit()

func mat(hex: String, outlined := true) -> ShaderMaterial:
 var m := ShaderMaterial.new()
 m.shader = SURFACE
 m.set_shader_parameter("base_color",Color(hex))
 surfaces.append(m)
 m.set_meta("outlined",outlined)
 return m

func box(pos: Vector3, dims: Vector3, hex: String, outlined := true) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = dims
 n.mesh = mesh
 n.material_override = mat(hex,outlined and minf(dims.x,dims.z) >= 0.07)
 n.position = pos
 world.add_child(n)
 return n


func wall(pos: Vector2, dims: Vector2):
 var base := box(Vector3(pos.x,0.6,pos.y),Vector3(dims.x,1.2,dims.y),"394548")
 var cap := box(Vector3(pos.x,1.22,pos.y),Vector3(dims.x+0.025,0.045,dims.y+0.025),"768281")
 var key := "wall_"+str(base.get_instance_id())
 base.set_meta("outline_group",key)
 cap.set_meta("outline_group",key)


func cable_run(points: Array):
 for i in range(points.size()-1):
  var a: Vector3 = points[i]
  var b: Vector3 = points[i+1]
  var delta := b-a
  asset("modular_electric_cables",(a+b)*0.5,atan2(delta.x,delta.z),1.0,"cable_straight_long",PI/2,delta.length()/0.607252)

func label3(text: String, pos: Vector3, scale_value: float, color: String):
 # World-anchored pixel-font text is composed directly with the clean 2K scene.
 text_items.append({"text":text,"pos":pos,"font_size":36 if scale_value>=0.29 else 24,"color":color})

func update_text_positions():
 for item in text_items:
  if not item.has("label"): continue
  var l: Label = item.label
  l.reset_size()
  l.position = (camera.unproject_position(item.pos)-l.size*0.5).round()

func occupy(cells: Rect2i):
 var rect := Rect2(Vector2(cells.position),Vector2(cells.size))

 # A shallow mounting platform makes the entire blocked footprint visible.
 box(Vector3(rect.get_center().x,0.045,rect.get_center().y),Vector3(rect.size.x-0.035,0.055,rect.size.y-0.035),"384746",false)
 for x in range(cells.position.x,cells.end.x):
  for z in range(cells.position.y,cells.end.y):
   for corner in [Vector2(0.08,0.08),Vector2(0.92,0.08),Vector2(0.08,0.92),Vector2(0.92,0.92)]:
    box(Vector3(x+corner.x,0.078,z+corner.y),Vector3(0.10,0.012,0.025),"859082",false)

func lamp(pos: Vector3, color: String, energy: float, radius: float):
 var l := OmniLight3D.new()
 l.position = pos
 l.light_color = Color(color)
 l.light_energy = energy
 l.omni_range = radius
 l.omni_attenuation = 1.55
 l.shadow_enabled = true
 l.shadow_bias = 0.025
 l.shadow_normal_bias = 0.6
 world.add_child(l)
 lights.append(l)
 return l

func strip(pos: Vector3, length: float, color: String, energy: float, radius: float):
 # Place complete authored fixtures; do not stretch their housings or build substitute bars.
 var count := 2 if length>1.2 else 1
 for i in range(count):
  var at_light := pos+Vector3((i-(count-1)*0.5)*0.92,0,0)
  var fixture := asset("mounted_fluorescent_lights",at_light,0.0,1.0,"mounted_fluorescent_lights_a")
  for mesh in fixture.find_children("*","MeshInstance3D",true,false):
   mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   for j in range(mesh.mesh.get_surface_count()):
    mesh.get_active_material(j).set_shader_parameter("emission_tint",Color(color)*0.45)
 lamp(pos+Vector3(0,0.3,0),color,energy,radius)

func build_architecture():
 box(Vector3(0,-0.16,0),Vector3(12.4,0.3,8.4),"1b262a")
 var floor_mesh := box(Vector3(0,0.002,0),Vector3(12,0.035,8),"596363",false)
 var floor_material := ShaderMaterial.new()
 floor_material.shader = preload("res://presentation/maintenance/floor.gdshader")
 floor_mesh.material_override = floor_material
 surfaces.append(floor_material)
 for entity in simulation.entities.values():
  if entity.definition.id.begins_with("wall_"): wall(entity.position,entity.footprint().size)
  elif entity.definition.id.begins_with("fixture_"):
   var rect: Rect2 = entity.footprint()
   occupy(Rect2i(Vector2i(rect.position),Vector2i(rect.size)))
  elif not entity.door.is_empty(): make_door(Vector2i(entity.footprint().position))
 for x in [-5.0,-3.05,-1.10]:
  asset("modular_industrial_pipes_01",Vector3(x,0.35,-3.83),PI/2,1.0,"modular_industrial_pipes_01_pipe02",PI/2)
 label3("维修 / SERVICE",Vector3(-4,0.1,0.45),0.24,"bdc0a9")
 label3("配电 / AUXILIARY",Vector3(4.5,0.1,0.45),0.24,"bdc0a9")

func make_door(cell: Vector2i):
 var footprint := Rect2(Vector2(cell),Vector2(3,1))
 var center := footprint.get_center()
 var threshold := box(Vector3(center.x,0.033,center.y),Vector3(2.97,0.04,0.97),"527267",false)
 # Authored three-metre rolling shutter. In the open state the leaf is retracted.
 var panel := asset("rollershutter_door",Vector3(center.x,0.06,center.y+0.43),0.0,0.96,"rollershutter_door")
 panel.visible = false
 var entity: SCEntity = simulation.entities["shutter_0" if cell.x==-4 else "shutter_1"]
 doors.append({"entity":entity,"center":center,"panel":panel,"threshold":threshold,"base_y":panel.position.y})
 label3("卷帘门 / OPEN",Vector3(center.x,0.1,center.y),0.20,"d0d7be")
 doors[-1]["label_item"] = text_items.size()-1

func set_door(index: int, closed: bool):
 var result := simulation.operate_door(doors[index].entity.definition.id,character,not closed)
 if not result.is_empty(): note.text=result
 sync_doors()

func sync_doors():
 for item in doors:
  var entity: SCEntity = item.entity
  item.panel.visible = entity.door.progress<1.0
  if item.panel.visible: item.panel.position.y=item.base_y+entity.height()*entity.door.progress
  item.threshold.material_override.set_shader_parameter("base_color",Color("785f50") if entity.door.progress<1.0 else Color("527267"))
  var text: Dictionary = text_items[item.label_item]
  text.text="卷帘门 / "+entity.door.state.to_upper()
  if text.has("label"): text.label.text=text.text


func asset(id: String, pos: Vector3, yaw := 0.0, uniform_scale := 1.0, part := "", tilt := 0.0, stretch_y := 1.0) -> Node3D:
 var n: Node3D = load("res://assets/environment/"+id+"/parts.gltf").instantiate()
 world.add_child(n)
 # Modular packs contain independent authored variants; instantiate only the requested one.
 if not part.is_empty():
  for mesh in n.find_children("*","MeshInstance3D",true,false):
   if mesh.name != part:
    mesh.get_parent().remove_child(mesh)
    mesh.free()
 var bounds := AABB()
 var first := true
 for mesh in n.find_children("*","MeshInstance3D",true,false):
  var b: AABB = n.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
  if first: bounds=b;first=false
  else: bounds=bounds.merge(b)
  for i in range(mesh.mesh.get_surface_count()):
   var source = mesh.get_active_material(i)
   var color: Color = source.albedo_color if source is BaseMaterial3D else Color("929e96")
   mesh.set_surface_override_material(i,mat(color.to_html(false)))
 assert(not first,"Missing authored mesh variant: "+id+"/"+part)
 var pivot := Node3D.new()
 world.add_child(pivot)
 n.reparent(pivot)
 n.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
 pivot.rotation = Vector3(tilt,yaw,0)
 # Only modular cable segments permit length fitting; all props retain uniform proportions.
 assert(is_equal_approx(stretch_y,1.0) or id == "modular_electric_cables")
 pivot.scale = Vector3(uniform_scale,uniform_scale*stretch_y,uniform_scale)
 var placed := AABB()
 first=true
 for mesh in n.find_children("*","MeshInstance3D",true,false):
  var b: AABB = mesh.global_transform*mesh.get_aabb()
  if first: placed=b;first=false
  else: placed=placed.merge(b)
 pivot.position += pos-Vector3(placed.get_center().x,placed.position.y,placed.get_center().z)
 pivot.set_meta("bounds",placed.size)
 pivot.set_meta("source_asset",id)
 pivot.set_meta("source_part",part)
 imported_assets.append(pivot)
 return pivot

func build_workshop():
 asset("painted_wooden_table",Vector3(-4,0.08,-3.5),0.0,0.80)
 asset("painted_wooden_table",Vector3(-2,0.08,-3.5),0.0,0.80)
 asset("bench_vice_01",Vector3(-4.65,0.85,-3.32),0.6)
 asset("pipe_wrench",Vector3(-3.85,0.87,-3.35),-0.4,1.0,"",PI/2)
 asset("metal_tool_chest",Vector3(-2.75,0.85,-3.5))
 asset("retro_multimeter",Vector3(-1.65,0.85,-3.4),0.0,1.0,"",-PI/2)
 asset("plastic_crate_02",Vector3(-1.15,0.85,-3.55))
 asset("wooden_crate_01",Vector3(-5.5,0.08,-3.5))
 asset("metal_tool_chest",Vector3(-5.5,0.43,-3.5))
 asset("Barrel_02",Vector3(-0.5,0.08,-3.5))
 asset("portable_generator",Vector3(-4.5,0.08,-0.5),PI/2)
 asset("plastic_crate_02",Vector3(-3.5,0.08,-0.5))
 asset("pipe_wrench",Vector3(-3.6,0.34,-0.5),0.3,1.0,"",PI/2)
 cable_run([Vector3(-4.5,0.09,-0.45),Vector3(-4.5,0.09,-0.08),Vector3(-3.05,0.09,-0.08),Vector3(-3.05,0.09,-1.1),Vector3(0.03,0.09,-1.1)])
 asset("portable_welding_cart",Vector3(-5.5,0.08,-0.5),PI)
 asset("metal_stool_02",Vector3(-0.5,0.08,-0.5))
 strip(Vector3(-4,1.6,-3.85),1.7,"ffd29c",6.0,4.2)
 lamp(Vector3(-4.2,1.1,-1.7),"ffb878",1.25,2.5)

func build_power_room():
 asset("drawer_cabinet",Vector3(1,0.08,-3.5))
 var cart := asset("tool_cart",Vector3(3,0.08,-3.5))
 var top := 0.08+float(cart.get_meta("bounds").y)
 asset("power_box_01",Vector3(2.68,top,-3.5),0.0,1.0,"",-PI/2)
 asset("retro_multimeter",Vector3(3.38,top,-3.4),0.0,1.0,"",-PI/2)
 asset("portable_welding_cart",Vector3(5,0.08,-3.5),PI)
 asset("portable_generator",Vector3(4.5,0.08,-1.5),PI/2)
 cable_run([Vector3(4.5,0.1,-1.85),Vector3(4.88,0.1,-1.85),Vector3(4.88,0.1,-3.06),Vector3(3.5,0.1,-3.06)])
 var radio_cart := asset("tool_cart",Vector3(2,0.08,-0.5))
 var radio_top := 0.08+float(radio_cart.get_meta("bounds").y)
 asset("vintage_radio_transceiver",Vector3(1.84,radio_top,-0.5),0.0,1.0,"",-PI/2)
 asset("retro_multimeter",Vector3(2.5,radio_top,-0.5),0.0,1.0,"",-PI/2)
 label3("备用电源 / 02",Vector3(4.5,0.1,-0.5),0.22,"a8b6a9")
 strip(Vector3(2.5,2.05,-3.85),1.5,"b6ddc9",5.0,4.1)
 asset("industrial_wall_sconce",Vector3(5.83,0.9,-1.5),PI/2)
 lamp(Vector3(5.6,1.4,-1.5),"ff805b",1.7,3.0)

func build_corridor():
 for x in [-5.5,-4.5,-3.5]:
  asset("wooden_crate_01",Vector3(x,0.08,3.3))
  asset("wooden_crate_01",Vector3(x,0.08,3.75))
 asset("wooden_crate_01",Vector3(-5.5,0.43,3.3))
 for x in [-5.74,-5.25]: asset("Barrel_02",Vector3(x,0.08,1.5),0.0,0.90)
 for z in [1.26,1.75]: asset("Barrel_02",Vector3(5.5,0.08,z),0.0,0.9)
 asset("wooden_crate_01",Vector3(5.5,0.08,3.3))
 asset("plastic_crate_02",Vector3(5.5,0.08,3.8))
 asset("hand_truck",Vector3(2.5,0.08,3.5),PI)
 label3("出口  ->",Vector3(3.8,0.1,2.5),0.29,"bfc2a9")
 label3("B-02",Vector3(-3.5,0.1,2.5),0.4,"9fae9f")
 strip(Vector3(-2.5,1.6,3.85),1.5,"a3c3d7",5.0,4.2)
 asset("industrial_wall_sconce",Vector3(4,0.9,4.0))
 lamp(Vector3(4,1.4,3.8),"ff9570",1.8,3.6)

func build_character():
 character.training_enabled = false
 unit = ACTOR.new()
 unit.stylized = true
 unit.character_definition = character.definition
 unit.shooter = character
 unit.weapon_state = character.weapon
 world.add_child(unit)
 # This study shares room lights; remove the rig's isolated studio lighting.
 for child in unit.get_children():
  if child is WorldEnvironment or child is Light3D:
   unit.remove_child(child)
   child.queue_free()
 for mesh in unit.rig.find_children("*","MeshInstance3D",true,false):
  if mesh.material_override:
   mesh.material_override = character_material(mesh.material_override)
  else:
   # The skinned body stores its toon palette on mesh surfaces, unlike the rifle.
   for surface in range(mesh.mesh.get_surface_count()):
    mesh.set_surface_override_material(surface,character_material(mesh.get_active_material(surface)))
 unit.position = Vector3(at.x,0,at.y)

func character_material(source: Material) -> ShaderMaterial:
 var m := mat("9da99f")
 if source is ShaderMaterial:
  var color = source.get_shader_parameter("base_color")
  var palette = source.get_shader_parameter("use_vertex_palette")
  m.set_shader_parameter("base_color",color if color != null else Color.WHITE)
  m.set_shader_parameter("vertex_palette",palette == true)
 elif source is BaseMaterial3D:
  m.set_shader_parameter("base_color",source.albedo_color)
 return m

func toggle_outline():
 outline_enabled = not outline_enabled
 if object_outline: object_outline.set_enabled(outline_enabled)

func update_outline_width():
 if object_outline:
  object_outline.sync_camera(camera)
  object_outline.set_width(OUTLINE_PIXELS*zoom)

func ui_label(text: String, pos: Vector2, font_size: int, color: String) -> Label:
 var l := Label.new()
 l.text = text
 l.position = pos
 l.add_theme_font_override("font",font)
 l.add_theme_font_size_override("font_size",font_size)
 l.add_theme_color_override("font_color",Color(color))
 l.mouse_filter = Control.MOUSE_FILTER_IGNORE
 ui_layer.add_child(l)
 return l

func plate(rect: Rect2) -> ColorRect:
 var panel := ColorRect.new()
 panel.position = rect.position
 panel.size = rect.size
 panel.color = Color(0.025,0.045,0.052,0.90)
 panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
 ui_layer.add_child(panel)
 return panel

func build_ui():
 plate(Rect2(64,28,600,164))
 plate(Rect2(1760,32,700,96))
 plate(Rect2(64,1272,1350,120))
 note_back = plate(Rect2(1480,1274,960,124))
 note_back.visible = false
 ui_label("SCARLET CONTRACT",Vector2(80,42),36,"c4cec8")
 ui_label("B-02 / 地下维护站",Vector2(80,90),48,"e1ded0")
 ui_label("夜间检修中断 / 1 格 = 1 米",Vector2(80,154),24,"91a8aa")
 status = ui_label("",Vector2(1780,54),24,"c5b688")
 help = ui_label("WASD 移动  鼠标朝向  滚轮缩放  E 查看现场  O 开关附近门\nV 显像管  F 完全无滤镜  N 描边对照  [ ] CRT 强度  空格暂停",Vector2(80,1284),24,"b5c8c5")
 note = ui_label("",Vector2(1500,1288),24,"d0d1be")
 note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 note.size.x = 900

func refresh_status():
 if not post: return
 note_back.visible = not note.text.is_empty()
 status.text = "输出 2560 x 1440 / CRT 960 x 540\n%s" % ("无滤镜原图" if bypass else ("CRT 开启" if post.get_shader_parameter("enabled") else "CRT 关闭"))

func set_bypass(value: bool):
 if value == bypass: return
 if value:
  saved_crt_enabled = bool(post.get_shader_parameter("enabled"))
  post.set_shader_parameter("enabled",false)
 else:
  post.set_shader_parameter("enabled",saved_crt_enabled)
 bypass = value

func screen_uv_to_scene(uv: Vector2) -> Vector2:
 if not post.get_shader_parameter("enabled"): return uv
 var delta := uv-Vector2(0.5,0.5)
 var delta2 := delta.length_squared()
 var warped := uv+delta*(delta2*delta2*CRT_WARP)
 return (warped-Vector2(0.5,0.5))/lerpf(1.0,1.2,CRT_WARP/5.0)+Vector2(0.5,0.5)

func _unhandled_input(event: InputEvent):
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_V:
    if bypass: set_bypass(false)
    post.set_shader_parameter("enabled",not post.get_shader_parameter("enabled"))
   KEY_F: set_bypass(not bypass)
   KEY_N: toggle_outline()
   KEY_SPACE: frozen = not frozen
   KEY_BRACKETLEFT: strength = maxf(0.0,strength-0.1)
   KEY_BRACKETRIGHT: strength = minf(1.0,strength+0.1)
   KEY_O:
    for i in range(doors.size()):
     if at.distance_to(doors[i].center)<1.65:
      set_door(i,doors[i].entity.door.target_open)
      break
   KEY_E:
    note.text = simulation.inspect(character)
  post.set_shader_parameter("strength",strength)
  refresh_status()
 if event is InputEventMouseButton and event.pressed:
  if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = minf(2.0,zoom+0.25)
  elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = maxf(0.75,zoom-0.25)
  camera.size = 10.8/zoom
  update_outline_width()
  update_text_positions()

func _process(delta: float):
 if not is_instance_valid(unit) or not post: return
 if object_outline: object_outline.sync_instances()
 if frozen: return
 simulation.update(delta)
 sync_doors()
 post.set_shader_parameter("elapsed_time",clock_time)
 var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).normalized()
 var mouse := screen_uv_to_scene(get_local_mouse_position()/Vector2(SIZE))*Vector2(view.size)
 var ray := camera.project_ray_origin(mouse)
 var target := Vector2(ray.x,ray.z)
 if not capture_pending.is_empty(): target=at+Vector2(1,-1)
 var desired := (target-at).angle() if target.distance_to(at)>.2 else facing
 simulation.controlled_movement(character,movement,desired,delta)
 var velocity := character.velocity
 unit.position=Vector3(at.x,0,at.y)
 var yaw := PI/2-facing
 var local_velocity := Vector3(velocity.x,0,velocity.y).rotated(Vector3.UP,-yaw)
 # Actor pose solver uses origin-relative target coordinates.
 unit.effect_origin = Vector2.ZERO
 unit.aim_target = target-at
 unit.advance_unit(delta,yaw,Vector2(local_velocity.x,local_velocity.z),0.0)
 unit.skeleton.advance(delta)
 if object_outline: object_outline.sync_instances()
