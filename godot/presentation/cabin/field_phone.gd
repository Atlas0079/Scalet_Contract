extends "res://presentation/cabin/retro_phone.gd"
## Supplied Field Terminal V5 handset, with authored controls and PBR materials.
const MODEL = preload("res://assets/environment/field_phone_v5/field_phone.glb")
const VALUES = ["1","2","3","4","5","6","7","8","9","*","0","#","ok","soft_left","clear","call","end"]
var lcd_mesh: MeshInstance3D

func _ready():
 model=MODEL.instantiate();add_child(model)
 # glTF already converts the Blender front-up handset to Godot +Y.
 var bounds:=AABB();var first:=true
 for mesh in model.find_children("*","MeshInstance3D",true,false):
  var box: AABB=model.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
  bounds=box if first else bounds.merge(box);first=false
 model.position.y=-bounds.position.y
 for mesh in model.find_children("*","MeshInstance3D",true,false):
  var title:=String(mesh.name)
  if title.begins_with("Key ") and "low profile fitted cap" in title:
   var index:=int(title.substr(4,2))-1
   bind_key(mesh,VALUES[index])
  elif title.begins_with("Navigation"):bind_key(mesh,"nav")
  elif title.begins_with("07 "):
   lcd_mesh=mesh;build_lcd(mesh)
   var material: ShaderMaterial=mesh.material_override
   material.shader=preload("res://presentation/cabin/field_phone_lcd.gdshader")
   var box: AABB=mesh.get_aabb()
   material.set_shader_parameter("screen_rect",Vector4(box.position.x,box.position.z,box.size.x,box.size.z))
  elif title.begins_with("08 "):
   mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 ring_audio=audio_player(-20);tone_audio=audio_player(-24);voice_audio=audio_player(-12)
 call.changed.connect(refresh);call.outgoing_requested.connect(preview_outgoing);call.answer_requested.connect(preview_answer)
 refresh()

func bind_key(mesh: MeshInstance3D, value: String):
 var parent: Node3D=mesh.get_parent()
 var old:=mesh.transform
 var centre:=old*mesh.get_aabb().get_center()
 var pivot:=Node3D.new();pivot.name="Control_"+value
 parent.add_child(pivot);pivot.position=centre
 pivot.set_meta("rest_position",centre);pivot.set_meta("press_travel",Vector3(0,-.7,0))
 mesh.reparent(pivot,false);mesh.transform=Transform3D(Basis.IDENTITY,-centre)*old
 keys[value]=pivot
 # The locator nib is a physical part of the 5 key and moves with its cap.
 if value=="5":
  var nib: Node3D=model.find_child("5 *",true,false)
  if nib:nib.reparent(pivot,true)

func build_lcd(mesh: MeshInstance3D):
 super.build_lcd(mesh)
 display.size=Vector2i(128,96)
 var background: ColorRect=display.get_child(0)
 background.size=display.size;background.color=Color("304b50")
 text.size=Vector2(120,64);softkeys.position.y=80
 for node in display.get_children():
  if node is Label:node.add_theme_color_override("font_color",Color("bdd8d0"))

func contact(ray_owner: Node3D, camera: Camera3D, point: Vector2) -> String:
 var value: String="";var distance:=INF
 for candidate in keys:
  var mesh: MeshInstance3D=keys[candidate].get_child(0)
  var at: Variant=ray_owner.mesh_hit(camera,point,mesh)
  if at!=null and camera.global_position.distance_to(at)<distance:
   distance=camera.global_position.distance_to(at);value=candidate
 if value.is_empty():return ""
 for mesh in model.find_children("*","MeshInstance3D",true,false):
  if mesh.get_parent() in keys.values() or String(mesh.name).begins_with("08 "):continue
  var at: Variant=ray_owner.mesh_hit(camera,point,mesh)
  if at!=null and camera.global_position.distance_to(at)<distance-.00001:return ""
 return value
