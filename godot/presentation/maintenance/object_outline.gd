extends RefCounted
## A visibility-aware logical-object contour pass. The original mesh/skin is reused;
## mask instances share source skeletons and synchronize transforms/visibility.
const MASK_SHADER = preload("res://presentation/maintenance/outline_mask.gdshader")
const CONTOUR_SHADER = preload("res://presentation/maintenance/outline.gdshader")
var mask_view: SubViewport
var mask_camera: Camera3D
var mask_world: Node3D
var output: SubViewport
var material: ShaderMaterial
var pairs: Array[Dictionary] = []
var group_ids: Dictionary = {}
var group_materials: Dictionary = {}

func configure(host: Node, source_view: SubViewport, source_world: Node3D, source_camera: Camera3D, actor: Node3D, assets: Array[Node3D], size: Vector2i):
 mask_view=SubViewport.new()
 mask_view.name="ObjectIdentityView"
 mask_view.size=size
 mask_view.own_world_3d=true
 mask_view.disable_3d=false
 mask_view.msaa_3d=Viewport.MSAA_DISABLED
 mask_view.positional_shadow_atlas_size=0
 mask_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 host.add_child(mask_view)
 mask_world=Node3D.new()
 mask_view.add_child(mask_world)
 mask_camera=Camera3D.new()
 mask_camera.cull_mask=1
 mask_camera.environment=Environment.new()
 mask_camera.environment.background_mode=Environment.BG_COLOR
 mask_camera.environment.background_color=Color.BLACK
 mask_camera.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 mask_view.add_child(mask_camera)
 mask_camera.current=true
 sync_camera(source_camera)
 var sources=source_world.find_children("*","MeshInstance3D",true,false)
 for source in sources:
  var key=""
  if actor.is_ancestor_of(source): key="character"
  else:
   for asset in assets:
    if asset.is_ancestor_of(source):
     var id: String=asset.get_meta("source_asset","")
     key="asset_"+str(asset.get_instance_id())
     if id.begins_with("modular_"): key=id
     break
  if key.is_empty():
   if source.has_meta("outline_group"): key=str(source.get_meta("outline_group"))
   else:
    var surface=source.get_active_material(0)
    if surface and surface.get_meta("outlined",false): key="mesh_"+str(source.get_instance_id())
  var id:=0
  if not key.is_empty():
   if not group_ids.has(key):group_ids[key]=group_ids.size()+1
   id=group_ids[key]
  assert(id<255,"Object mask ID capacity exceeded")
  if not group_materials.has(id):
   var m:=ShaderMaterial.new()
   m.shader=MASK_SHADER
   m.set_shader_parameter("object_id",float(id))
   group_materials[id]=m
  var proxy:=MeshInstance3D.new()
  proxy.name="ContourMask"
  proxy.mesh=source.mesh
  proxy.skin=source.skin
  proxy.layers=1
  proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  proxy.material_override=group_materials[id]
  mask_world.add_child(proxy)
  proxy.global_transform=source.global_transform
  proxy.visible=source.is_visible_in_tree()
  if source.skin:
   var skeleton=source.get_node_or_null(source.skeleton)
   assert(skeleton is Skeleton3D,"Skinned contour requires its original skeleton")
   proxy.skeleton=proxy.get_path_to(skeleton)
  pairs.append({"source":source,"proxy":proxy,"id":id,"group":key})
 output=SubViewport.new()
 output.name="OutlinedScene"
 output.size=size
 output.disable_3d=true
 output.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 host.add_child(output)
 var image:=TextureRect.new()
 image.size=size
 image.texture=source_view.get_texture()
 image.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
 material=ShaderMaterial.new()
 material.shader=CONTOUR_SHADER
 material.set_shader_parameter("object_mask",mask_view.get_texture())
 material.set_shader_parameter("resolution",Vector2(size))
 image.material=material
 output.add_child(image)

func sync_instances():
 for pair in pairs:
  var source: MeshInstance3D=pair.source
  var proxy: MeshInstance3D=pair.proxy
  proxy.global_transform=source.global_transform
  proxy.visible=source.is_visible_in_tree()

func sync_camera(source: Camera3D):
 mask_camera.projection=source.projection
 mask_camera.size=source.size
 mask_camera.near=source.near
 mask_camera.far=source.far
 mask_camera.global_transform=source.global_transform

func set_enabled(value: bool): material.set_shader_parameter("enabled",value)
func set_width(value: float): material.set_shader_parameter("outline_pixels",value)
