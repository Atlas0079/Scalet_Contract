extends Node3D
## An aged plastic desk toy with a weighted base and a deforming steel spring.
const DUCK = preload("res://assets/environment/desk_toys/aged_duck.gltf")
const SURFACE = preload("res://presentation/cabin/toy_surface.gdshader")
const ATLAS = preload("res://assets/environment/desk_toys/textures/aged_toy_atlas.png")
const SOURCE = preload("res://assets/environment/desk_toys/rubber_duck_duck.webp")
const TOP := 0.0323
var model: Node3D
var moving: Array[Node3D] = []
var spring_rig: Skeleton3D
var spring_mesh: MeshInstance3D
var angle := 0.0
var speed := 0.0

func _ready():
 var toward := Vector3(0,1.08965,1.42)-global_position
 rotation.y = atan2(toward.x,toward.z)
 build_duck()

func finish(kind: int,pose:=Transform3D.IDENTITY,source: Texture2D=SOURCE) -> ShaderMaterial:
 var mat:=ShaderMaterial.new();mat.shader=SURFACE
 mat.set_shader_parameter("aged_atlas",ATLAS);mat.set_shader_parameter("body_source",source)
 mat.set_shader_parameter("surface_kind",kind)
 mat.set_shader_parameter("surface_to_toy",pose)
 mat.set_shader_parameter("normal_to_toy",Transform3D(pose.basis.inverse().transposed(),Vector3.ZERO))
 return mat
func shape(name_: String,mesh: Mesh,at: Vector3,kind: int,parent: Node3D=null) -> MeshInstance3D:
 if parent==null:parent=self
 var node:=MeshInstance3D.new();node.name=name_;node.mesh=mesh;node.position=at;parent.add_child(node)
 var pose: Transform3D=global_transform.affine_inverse()*node.global_transform
 node.material_override=finish(kind,pose);return node
func lathe(name_: String,profile: Array,kind: int,parent: Node3D=null,at:=Vector3.ZERO) -> MeshInstance3D:
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rows: Array=[];var normals: Array=[];var uv: Array=[]
 for p in profile:
  var row:=PackedVector3Array();var nr:=PackedVector3Array();var coords:=PackedVector2Array()
  for i in range(97):
   var a:=TAU*i/96.0;row.append(Vector3(cos(a)*p.x,p.y,sin(a)*p.x));nr.append(Vector3(cos(a)*p.z,p.w,sin(a)*p.z).normalized())
   coords.append(Vector2(cos(a)*p.x,sin(a)*p.x) if absf(p.w)>.7 else Vector2(a*.0287,p.y))
  rows.append(row);normals.append(nr);uv.append(coords)
 for r in range(rows.size()-1):
  for i in range(96):
   for tri in [[Vector2i(r,i),Vector2i(r+1,i+1),Vector2i(r+1,i)],[Vector2i(r,i),Vector2i(r,i+1),Vector2i(r+1,i+1)]]:
    var a: Vector3=rows[tri[0].x][tri[0].y];var b: Vector3=rows[tri[1].x][tri[1].y];var c: Vector3=rows[tri[2].x][tri[2].y]
    if (b-a).cross(c-a).length_squared()<1e-15:continue
    for q in tri:
     st.set_normal(normals[q.x][q.y]);st.set_uv(uv[q.x][q.y]);st.add_vertex(rows[q.x][q.y])
 st.index();return shape(name_,st.commit(),at,kind,parent)
func cylinder(name_: String,radius: float,height: float,at: Vector3,kind: int,parent: Node3D=null):
 var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=48
 var node:=shape(name_,mesh,at,kind,parent)
 node.material_override.set_shader_parameter("uv_to_metres",Vector2(TAU*radius,height*2.0))
 return node

func build_duck():
 lathe("WeightedBase",[Vector4(0,.0014,0,-1),Vector4(.0268,.0014,0,-1),Vector4(.0278,.0017,.4,-.9),Vector4(.0285,.0026,.9,-.4),Vector4(.0287,.0042,1,0),Vector4(.0287,.0073,1,0),Vector4(.0285,.0086,.9,.4),Vector4(.0279,.0098,.5,.85),Vector4(.0271,.0102,.1,1),Vector4(.022,.0102,0,1),Vector4(.014,.0091,.08,1),Vector4(.009,.0086,0,1),Vector4(0,.0086,0,1)],1)
 cylinder("RubberFoot",.0265,.0014,Vector3(0,.0007,0),4)
 lathe("LowerSpringSeat",[Vector4(.0061,.009,0,-1),Vector4(.010,.009,0,-1),Vector4(.010,.0104,1,0),Vector4(.0088,.0122,.6,.8),Vector4(.0061,.0122,0,1),Vector4(.0061,.009,-1,0)],2)
 for x in [-.019,.019]:
  cylinder("RecessedFastener",.0018,.0007,Vector3(x,.0102,.003),2)
  var slot:=BoxMesh.new();slot.size=Vector3(.0025,.00015,.00045);shape("ScrewSlot",slot,Vector3(x,.01059,.003),4)
 var pivot:=Node3D.new();pivot.name="DuckPivot";pivot.position.y=TOP;add_child(pivot);moving.append(pivot)
 cylinder("UpperSpringSeat",.0086,.0026,Vector3(0,-.0013,0),2,pivot)
 var duck: Node3D=DUCK.instantiate();model=duck;pivot.add_child(duck)
 var bounds:=AABB();var first:=true
 for mesh in duck.find_children("*","MeshInstance3D",true,false):
  var box: AABB=duck.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
  if first:bounds=box;first=false
  else:bounds=bounds.merge(box)
 var factor:=.083/bounds.size.length();duck.scale*=factor
 duck.position=-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
 for mesh in duck.find_children("*","MeshInstance3D",true,false):
  for surface in range(mesh.mesh.get_surface_count()):
   var source: StandardMaterial3D=mesh.get_active_material(surface)
   var image: Texture2D=source.albedo_texture if source and source.albedo_texture else SOURCE
   var pose: Transform3D=global_transform.affine_inverse()*mesh.global_transform
   mesh.set_surface_override_material(surface,finish(3 if mesh.name=="MouldSeam" else 0,pose,image))
 build_spring()

func build_spring():
 spring_rig=Skeleton3D.new();spring_rig.name="SpringRig";add_child(spring_rig)
 spring_rig.add_bone("FixedSeat");spring_rig.add_bone("MovingSeat");spring_rig.set_bone_parent(1,0)
 spring_rig.set_bone_rest(0,Transform3D.IDENTITY)
 spring_rig.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0,TOP,0)))
 # Runtime-created bones need their pose translation initialized to the rest.
 # Otherwise inverse binds collapse the upper coils into the lower socket.
 spring_rig.set_bone_pose_position(1,Vector3(0,TOP,0))
 var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uv:=PackedVector2Array();var ids:=PackedInt32Array();var bones:=PackedInt32Array();var weights:=PackedFloat32Array()
 var rings:=320;var sides:=12;var distance:=0.0;var previous:=Vector3.ZERO
 for i in range(rings+1):
  var t:=float(i)/rings;var a:=t*TAU*4.5
  var y: float
  if t<.18:y=.0124+.0015*t/.18
  elif t<.82:y=.0139+.016*(t-.18)/.64
  else:y=.0299+.0015*(t-.82)/.18
  var centre:=Vector3(cos(a)*.0072,y,sin(a)*.0072)
  if i>0:distance+=centre.distance_to(previous)
  previous=centre
  var pitch: float=.0015/.18 if t<.18 or t>.82 else .016/.64
  var tangent:=Vector3(-sin(a)*.0072*TAU*4.5,pitch,cos(a)*.0072*TAU*4.5).normalized()
  var radial:=Vector3(cos(a),0,sin(a));var across:=tangent.cross(radial).normalized()
  var w:=smoothstep(.18,.82,t)
  for j in range(sides+1):
   var theta:=TAU*j/sides;var n:=radial*cos(theta)+across*sin(theta)
   vertices.append(centre+n*.00075);normals.append(n);uv.append(Vector2(theta*.00075,distance))
   bones.append_array(PackedInt32Array([0,1,0,0]));weights.append_array(PackedFloat32Array([1-w,w,0,0]))
 for i in range(rings):
  for j in range(sides):
   var a:=i*(sides+1)+j;var b:=a+1;var c:=a+sides+1;var d:=c+1;ids.append_array(PackedInt32Array([a,b,c,b,d,c]))
 var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=ids;arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 spring_mesh=shape("SteelSpring",mesh,Vector3.ZERO,2)
 var skin:=Skin.new();skin.add_bind(0,Transform3D.IDENTITY);skin.add_bind(1,Transform3D(Basis.IDENTITY,Vector3(0,-TOP,0)))
 spring_mesh.skin=skin;spring_mesh.skeleton=spring_mesh.get_path_to(spring_rig)
 spring_mesh.custom_aabb=AABB(Vector3(-.020,.005,-.020),Vector3(.04,.035,.04))

func poke():speed=clampf(speed+3.8,-5.0,5.0)
func activity() -> float:return absf(angle)+absf(speed)*.05
func _process(delta: float):
 var dt:=minf(delta,.05);speed+=(-90.0*angle-5.0*speed)*dt;angle=clampf(angle+speed*dt,-.45,.45)
 var rotation_:=Vector3(angle*.7,0,angle);moving[0].rotation=rotation_
 spring_rig.set_bone_pose_rotation(1,Basis.from_euler(rotation_).get_rotation_quaternion())
