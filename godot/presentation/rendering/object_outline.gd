extends RefCounted
## One identity/depth pass; registrations follow the resident presentation nodes.
const MASK_SHADER = preload("res://presentation/rendering/outline_mask.gdshader")
const CONTOUR_SHADER = preload("res://presentation/rendering/outline.gdshader")
var mask_view: SubViewport
var mask_camera: Camera3D
var mask_world: Node3D
var output: SubViewport
var material: ShaderMaterial
var pairs: Dictionary = {}
var group_ids: Dictionary = {}
var group_materials: Dictionary = {}
var group_counts: Dictionary = {}
var free_ids: Array[int] = []
var next_id := 1
var fog_texture: Texture2D
var fog_bounds := Vector4(0,0,1,1)
var fog_enabled := false

func configure(host: Node, source_view: SubViewport, source_world: Node3D, source_camera: Camera3D, actor: Node3D, assets: Array[Node3D], dimensions: Vector2i):
 mask_view=SubViewport.new();mask_view.name="ObjectIdentityView";mask_view.size=dimensions
 mask_view.own_world_3d=true
 # A linear floating-point target avoids sRGB/tonemap quantization of ID bytes.
 # Half-float precision still distinguishes all 256 values of each byte.
 mask_view.use_hdr_2d=true
 mask_view.msaa_3d=Viewport.MSAA_DISABLED;mask_view.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
 mask_view.use_debanding=false;mask_view.positional_shadow_atlas_size=0
 mask_view.render_target_update_mode=SubViewport.UPDATE_ONCE
 host.add_child(mask_view)
 mask_world=Node3D.new();mask_view.add_child(mask_world)
 mask_camera=Camera3D.new();mask_camera.cull_mask=1
 mask_camera.environment=Environment.new()
 mask_camera.environment.background_mode=Environment.BG_COLOR
 mask_camera.environment.background_color=Color.BLACK
 mask_camera.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 mask_camera.environment.tonemap_exposure=1.0
 mask_view.add_child(mask_camera);mask_camera.current=true;sync_camera(source_camera)
 register_subtree(source_world)
 # The supplied roots preserve the former tool's logical grouping.
 for asset in assets: set_subtree_group(asset,"asset_"+str(asset.get_instance_id()))
 if is_instance_valid(actor):
  for child in actor.get_children():set_subtree_group(child,"actor_"+str(child.get_instance_id()))
 output=SubViewport.new();output.name="OutlinedScene";output.size=dimensions;output.disable_3d=true
 output.render_target_update_mode=SubViewport.UPDATE_ONCE;host.add_child(output)
 var picture:=TextureRect.new();picture.size=dimensions;picture.texture=source_view.get_texture()
 picture.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
 material=ShaderMaterial.new();material.shader=CONTOUR_SHADER
 material.set_shader_parameter("object_mask",mask_view.get_texture())
 material.set_shader_parameter("resolution",Vector2(dimensions));picture.material=material;output.add_child(picture)

func allocate_group(key: String) -> int:
 if group_ids.has(key):return group_ids[key]
 var id: int
 if not free_ids.is_empty():id=free_ids.pop_back()
 else:id=next_id;next_id+=1
 assert(id<=65535,"Resident contour identity capacity exceeded")
 group_ids[key]=id;group_counts[key]=0
 var item:=ShaderMaterial.new();item.shader=MASK_SHADER;item.set_shader_parameter("object_id",id)
 if fog_texture:item.set_shader_parameter("knowledge_texture",fog_texture)
 item.set_shader_parameter("knowledge_bounds",fog_bounds);item.set_shader_parameter("knowledge_enabled",fog_enabled)
 group_materials[key]=item
 return id

func register_subtree(root: Node, group_key := ""):
 var meshes: Array = root.find_children("*","MeshInstance3D",true,false)
 if root is MeshInstance3D:meshes.push_front(root)
 for mesh: MeshInstance3D in meshes:
  var source_id:=mesh.get_instance_id()
  if pairs.has(source_id):continue
  var key:=group_key
  if key.is_empty():key=str(mesh.get_meta("outline_group",""))
  var outlined:=not key.is_empty()
  if key.is_empty():
   var surface: Material=mesh.get_active_material(0)
   outlined=surface!=null and bool(surface.get_meta("outlined",false))
   key="mesh_"+str(source_id) if outlined else "background"
  var id:=allocate_group(key) if outlined else 0
  if not group_materials.has(key):
   var background:=ShaderMaterial.new();background.shader=MASK_SHADER;background.set_shader_parameter("object_id",0)
   group_materials[key]=background;group_counts[key]=0
   apply_fog(background)
  group_materials[key].set_shader_parameter("current_only",bool(root.get_meta("knowledge_current_only",false)))
  var proxy:=MeshInstance3D.new();proxy.name="ContourMask";proxy.mesh=mesh.mesh;proxy.skin=mesh.skin
  proxy.layers=1;proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  proxy.material_override=group_materials[key];mask_world.add_child(proxy)
  proxy.global_transform=mesh.global_transform;proxy.visible=mesh.is_visible_in_tree()
  if mesh.skin:
   var skeleton:=mesh.get_node_or_null(mesh.skeleton)
   assert(skeleton is Skeleton3D,"Skinned contour requires its original skeleton")
   proxy.skeleton=proxy.get_path_to(skeleton)
  pairs[source_id]={"source":mesh,"proxy":proxy,"id":id,"group":key,"transform":mesh.global_transform,"visible":proxy.visible}
  group_counts[key]=int(group_counts.get(key,0))+1

func set_subtree_group(root: Node, key: String):
 unregister_subtree(root);register_subtree(root,key)

func unregister_subtree(root: Node):
 var ids: Array=[]
 for id in pairs:
  var entry: Dictionary=pairs[id]
  if not is_instance_valid(entry.source) or entry.source==root or root.is_ancestor_of(entry.source):ids.append(id)
 for id in ids:
  var entry: Dictionary=pairs[id];var key: String=entry.group
  if is_instance_valid(entry.proxy):entry.proxy.visible=false;entry.proxy.queue_free()
  pairs.erase(id);group_counts[key]=int(group_counts[key])-1
  if group_counts[key]==0:
   if group_ids.has(key):free_ids.append(group_ids[key]);group_ids.erase(key)
   group_materials.erase(key);group_counts.erase(key)

func sync_subtree(root: Node) -> bool:
 var changed:=false
 for id in pairs:
  var entry: Dictionary=pairs[id]
  if not is_instance_valid(entry.source):continue
  if entry.source!=root and not root.is_ancestor_of(entry.source):continue
  changed=sync_pair(entry) or changed
 return changed

func sync_pair(entry: Dictionary) -> bool:
 var source: MeshInstance3D=entry.source;var changed:=false
 var transform:=source.global_transform;var visible:=source.is_visible_in_tree()
 if transform!=entry.transform:entry.proxy.global_transform=transform;entry.transform=transform;changed=true
 if visible!=entry.visible:entry.proxy.visible=visible;entry.visible=visible;changed=true
 return changed

func sync_instances() -> bool:
 var changed:=false
 for entry in pairs.values():
  if is_instance_valid(entry.source):changed=sync_pair(entry) or changed
 return changed

func sync_camera(source: Camera3D):
 mask_camera.projection=source.projection;mask_camera.size=source.size
 mask_camera.near=source.near;mask_camera.far=source.far;mask_camera.global_transform=source.global_transform

func apply_fog(item: ShaderMaterial):
 if fog_texture:item.set_shader_parameter("knowledge_texture",fog_texture)
 item.set_shader_parameter("knowledge_bounds",fog_bounds);item.set_shader_parameter("knowledge_enabled",fog_enabled)

func set_knowledge(texture: Texture2D, bounds: Rect2, enabled := true):
 fog_texture=texture;fog_bounds=Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y);fog_enabled=enabled
 for item in group_materials.values():apply_fog(item)

func request_update():
 mask_view.render_target_update_mode=SubViewport.UPDATE_ONCE
 output.render_target_update_mode=SubViewport.UPDATE_ONCE

func set_enabled(value: bool):material.set_shader_parameter("enabled",value);request_update()
func set_width(value: float):material.set_shader_parameter("outline_pixels",value);request_update()
