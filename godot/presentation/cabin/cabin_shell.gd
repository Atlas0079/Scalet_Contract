extends Node3D
## A decorative service enclosure: structural bays, fastened panels, cooling
## lines and supported cable harnesses. Static geometry is batched by material.
const HALF_WIDTH := 1.08
const SOURCE_HALF_WIDTH := 1.28
var decor_side := 0.0
var coarse_geometry := false
var detail_count := 0
var library: Dictionary = {}
var groups: Dictionary = {}
var materials: Dictionary = {}
var routes: Array[PackedVector3Array] = []
var mount_count := 0
var panel_count := 0

func _ready():
 var steel := StandardMaterial3D.new()
 steel.albedo_texture = preload("res://assets/environment/metal_plate_02/metal_plate_02_diff_1k.jpg")
 steel.roughness_texture = preload("res://assets/environment/metal_plate_02/metal_plate_02_rough_1k.jpg")
 steel.normal_enabled = true
 steel.normal_texture = preload("res://assets/environment/metal_plate_02/metal_plate_02_nor_gl_1k.jpg")
 steel.normal_scale = 0.28;steel.roughness = 0.9
 steel.metallic_texture = preload("res://assets/environment/metal_plate_02/metal_plate_02_metal_1k.jpg")
 steel.metallic = 0.25;steel.albedo_color = Color(0.75,0.75,0.75)
 steel.uv1_triplanar = true;steel.uv1_scale = Vector3.ONE*1.1
 var paint: StandardMaterial3D = steel.duplicate();paint.albedo_color = Color(0.65,0.68,0.67);paint.metallic=0.18
 materials={"steel":steel,"paint":paint}
 var atlas:=preload("res://assets/environment/cabin_shell/textures/service_materials.png")
 var detail_shader:=preload("res://presentation/cabin/shell_detail.gdshader")
 for band in range(4):
  var mat:=ShaderMaterial.new();mat.shader=detail_shader
  mat.set_shader_parameter("detail_atlas",atlas);mat.set_shader_parameter("material_band",band)
  materials[["rubber","tan","brass","black"][band]]=mat
 for key in materials:
  var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);groups[key]=surface
 box(Vector3(2.28,.08,2.62),Vector3(0,-.045,.51))
 box(Vector3(2.28,1.74,.06),Vector3(0,.87,-.77))
 box(Vector3(2.28,1.74,.06),Vector3(0,.87,1.79))
 box(Vector3(.06,1.74,2.62),Vector3(-1.11,.87,.51))
 box(Vector3(.06,1.74,2.62),Vector3(1.11,.87,.51))
 box(Vector3(2.28,.06,2.62),Vector3(0,1.74,.51))
 for side in [-1.0,1.0]:build_side(side)
 build_front()
 for z in [-.67,.42,1.57]:
  box(Vector3(2.10,.065,.07),Vector3(0,1.675,z),"paint")
  for x in [-.9,-.45,0.0,.45,.9]:bolt(Vector3(x,1.6425,z),Vector3.DOWN)
 # Two roof loom lanes are supported at each cross-member.
 for lane in [-.55,.58]:
  var points:=PackedVector3Array([Vector3(lane,1.605,-.68),Vector3(lane+.03,1.610,.35),Vector3(lane,1.605,1.52)])
  bundle(points,3,.005)
  for z in [-.62,.40,1.52]:
   box(Vector3(.10,.006,.038),Vector3(lane,1.585,z),"paint")
   for x in [-.045,.045]:box(Vector3(.008,.058,.038),Vector3(lane+x,1.616,z),"paint")
   mount_count+=1
 for key in groups:
  var surface: SurfaceTool=groups[key];surface.index()
  var mesh:=surface.commit()
  if mesh.get_surface_count()==0:continue
  var node:=MeshInstance3D.new();node.name="Structure_"+key;node.mesh=mesh;node.material_override=materials[key];add_child(node)

func append_mesh(mesh: Mesh, pose: Transform3D, kind: String):
 var surface: SurfaceTool=groups[kind]
 if decor_side!=0.0:pose=side_frame(decor_side)*pose
 var normal_pose:=pose.basis.inverse().transposed()
 for s in range(mesh.get_surface_count()):
  var a:=mesh.surface_get_arrays(s)
  var vertices: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
  var coords: PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
  var ids:=PackedInt32Array()
  if a[Mesh.ARRAY_INDEX]!=null:ids=a[Mesh.ARRAY_INDEX]
  if ids.is_empty():
   for i in range(vertices.size()):ids.append(i)
  for i in ids:
   surface.set_color(Color(0,0,0,1))
   surface.set_normal((normal_pose*normals[i]).normalized())
   surface.set_uv(coords[i] if coords.size()>i else Vector2.ZERO)
   surface.add_vertex(pose*vertices[i])

func side_frame(side: float) -> Transform3D:
 return Transform3D(Basis.IDENTITY,Vector3(side*(HALF_WIDTH-SOURCE_HALF_WIDTH),0,0))

func box(size: Vector3, at: Vector3, kind:="steel", basis:=Basis.IDENTITY):
 var bevel:=minf(.002,minf(size.x,minf(size.y,size.z))*.22)
 if coarse_geometry or maxf(size.x,maxf(size.y,size.z))>1.8 or kind=="black":
  var mesh:=BoxMesh.new();mesh.size=size;append_mesh(mesh,Transform3D(basis,at),kind);return
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var half:=size*.5;var core:=half-Vector3.ONE*bevel
 for axis in range(3):
  var u: int=(axis+1)%3;var v: int=(axis+2)%3
  for sign_ in [-1.0,1.0]:
   var us: Array=[-half[u],-half[u]+bevel,half[u]-bevel,half[u]]
   var vs: Array=[-half[v],-half[v]+bevel,half[v]-bevel,half[v]]
   for j in range(3):
    for i in range(3):
     var corners: Array=[Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j+1)]
     for index in ([0,2,1,1,2,3] if sign_>0 else [0,1,2,1,3,2]):
      var pair: Vector2i=corners[index]
      var p:=Vector3.ZERO;p[axis]=sign_*half[axis];p[u]=us[pair.x];p[v]=vs[pair.y]
      var clamped:=p.clamp(-core,core);var normal: Vector3=(p-clamped).normalized()
      st.set_normal(normal);st.set_uv(Vector2(p[u],p[v]));st.add_vertex(clamped+normal*bevel)
 st.index();append_mesh(st.commit(),Transform3D(basis,at),kind)
func cylinder(at: Vector3, direction: Vector3, radius: float, height: float, kind:="steel",sides:=24):
 if coarse_geometry and sides>12:sides=12
 var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=sides;mesh.rings=1
 append_mesh(mesh,Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized())),at),kind)
func bolt(at: Vector3, direction: Vector3,radius:=.006):
 var n:=direction.normalized();var h:=radius*.65
 if coarse_geometry:
  cylinder(at+n*(h*.5),n,radius,h,"steel",6);mount_count+=1;detail_count+=1;return
 cylinder(at+n*.00065,n,radius*1.45,.0013,"steel",20)
 cylinder(at+n*(.0013+h*.5),n,radius,h,"steel",6)
 cylinder(at+n*(.0014+h),n,radius*.29,.0003,"black",6)
 mount_count+=1;detail_count+=1
func annulus(at: Vector3,direction: Vector3,inner: float,outer: float,width: float,kind: String):
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var profile: Array=[Vector4(inner,-width*.5,-1,0),Vector4(inner,-width*.5,0,-1),Vector4(outer,-width*.5,0,-1),Vector4(outer,-width*.5,1,0),Vector4(outer,width*.5,1,0),Vector4(outer,width*.5,0,1),Vector4(inner,width*.5,0,1),Vector4(inner,width*.5,-1,0),Vector4(inner,-width*.5,-1,0)]
 for row in range(profile.size()-1):
  for i in range(24):
   for q in [Vector2i(row,i),Vector2i(row+1,i+1),Vector2i(row+1,i),Vector2i(row,i),Vector2i(row,i+1),Vector2i(row+1,i+1)]:
    var p: Vector4=profile[q.x];var a: float=TAU*q.y/24.0
    st.set_normal(Vector3(cos(a)*p.z,p.w,sin(a)*p.z));st.set_uv(Vector2(a*outer,p.y));st.add_vertex(Vector3(cos(a)*p.x,p.y,sin(a)*p.x))
 st.index();append_mesh(st.commit(),Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized())),at),kind)
func gland(at: Vector3,direction: Vector3,radius: float,cable: bool):
 var n:=direction.normalized()
 if coarse_geometry:
  cylinder(at+n*.003,n,radius*1.4,.012,"rubber" if cable else "steel",12);detail_count+=1;return
 cylinder(at,n,radius*1.65,.007,"steel",6)
 cylinder(at+n*.006,n,radius*1.30,.013,"rubber" if cable else "steel",20)
 annulus(at+n*.010,n,radius*1.25,radius*1.44,.002,"rubber" if cable else "steel")
 detail_count+=1
func pipe_clamp(at: Vector3,direction: Vector3,radius: float,side: float):
 annulus(at,direction,radius,radius+.0015,.013,"rubber")
 annulus(at,direction,radius+.0015,radius+.0033,.014,"steel")
 box(Vector3(.10,.014,.028),Vector3(side*1.225,at.y,at.z),"paint")
 box(Vector3(.014,.075,.04),Vector3(side*1.273,at.y,at.z),"paint")
 for dy in [-.024,.024]:bolt(Vector3(side*1.266,at.y+dy,at.z),Vector3(-side,0,0),.003)
 mount_count+=1;detail_count+=1

func tube(points: PackedVector3Array, radius: float, kind:="rubber",prepared:=false):
 var previous_side:=decor_side
 if decor_side!=0.0:
  var mapped:=PackedVector3Array()
  for point in points:mapped.append(side_frame(decor_side)*point)
  points=mapped;decor_side=0.0
 routes.append(points)
 var curve:=Curve3D.new();curve.bake_interval=.040 if coarse_geometry else .018
 if prepared:pass
 elif kind=="steel":
  curve.add_point(points[0])
  for i in range(1,points.size()-1):
   var incoming: Vector3=(points[i]-points[i-1]).normalized()
   var outgoing: Vector3=(points[i+1]-points[i]).normalized()
   if incoming.dot(outgoing)>.995:curve.add_point(points[i]);continue
   var trim:=minf(.060,minf(points[i].distance_to(points[i-1]),points[i+1].distance_to(points[i]))*.30)
   curve.add_point(points[i]-incoming*trim,Vector3.ZERO,incoming*trim*.667)
   curve.add_point(points[i]+outgoing*trim,-outgoing*trim*.667,Vector3.ZERO)
  curve.add_point(points[-1])
 else:
  for i in range(points.size()):
   var tangent: Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)])/6.0
   curve.add_point(points[i],-tangent,tangent)
 var raw: PackedVector3Array=points if prepared else curve.get_baked_points()
 var baked:=PackedVector3Array()
 for i in range(raw.size()):
  if baked.is_empty() or raw[i].distance_to(baked[-1])>radius*.012:baked.append(raw[i])
  elif i==raw.size()-1:baked[-1]=raw[i]
 var surface: SurfaceTool=groups[kind]
 var sides:=12 if coarse_geometry else (24 if radius>=.011 else 16)
 var rings: Array[PackedVector3Array]=[];var normals: Array[PackedVector3Array]=[]
 var previous:=Vector3.ZERO;var previous_direction:=Vector3.ZERO;var distance:=0.0;var lengths:=[]
 for i in range(baked.size()):
  var direction: Vector3=(baked[mini(i+1,baked.size()-1)]-baked[maxi(i-1,0)]).normalized()
  var normal: Vector3=orthogonal(direction) if i==0 else Quaternion(previous_direction,direction)*previous
  normal-=direction*normal.dot(direction)
  if normal.length_squared()<.0001:normal=orthogonal(direction)
  normal=normal.normalized();previous=normal;previous_direction=direction
  var across:=direction.cross(normal).normalized();var ring:=PackedVector3Array();var ns:=PackedVector3Array()
  if i>0:distance+=baked[i].distance_to(baked[i-1])
  lengths.append(distance)
  for j in range(sides+1):
   var n:=normal*cos(TAU*j/sides)+across*sin(TAU*j/sides)
   ring.append(baked[i]+radius*n);ns.append(n)
  rings.append(ring);normals.append(ns)
 for i in range(rings.size()-1):
  for j in range(sides):
   var k: int=j+1
   for index in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,k),Vector2i(i,j),Vector2i(i+1,k),Vector2i(i,k)]:
    surface.set_color(Color(1,0,0,1));surface.set_normal(normals[index.x][index.y]);surface.set_uv(Vector2(float(index.y)/sides,lengths[index.x]));surface.add_vertex(rings[index.x][index.y])
 for i in [0,points.size()-1]:
  var direction: Vector3=(points[1]-points[0]).normalized() if i==0 else (points[-2]-points[-1]).normalized()
  gland(points[i],direction,radius,kind!="steel")
 decor_side=previous_side

func orthogonal(direction: Vector3) -> Vector3:
 var axis:=Vector3.UP if absf(direction.y)<.85 else Vector3.RIGHT
 if absf(axis.dot(direction))>.95:axis=Vector3.FORWARD
 return (axis-direction*axis.dot(direction)).normalized()

func bundle(points: PackedVector3Array, strands: int, radius: float):
 # Offsets are perpendicular to a transported centreline frame, including
 # vertical branches. Fan out only near sockets so neighbouring nuts clear.
 var curve:=Curve3D.new();curve.bake_interval=.040 if coarse_geometry else clampf(radius*1.5,.006,.018)
 for i in range(points.size()):
  var tangent: Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)])/6.0
  curve.add_point(points[i],-tangent,tangent)
 var centreline:=curve.get_baked_points();var normal:=Vector3.ZERO;var previous:=Vector3.ZERO
 var lengths:=[];var distance:=0.0;var frames:=[]
 for i in range(centreline.size()):
  if i>0:distance+=centreline[i].distance_to(centreline[i-1])
  lengths.append(distance)
  var direction: Vector3=(centreline[mini(i+1,centreline.size()-1)]-centreline[maxi(i-1,0)]).normalized()
  normal=orthogonal(direction) if i==0 else Quaternion(previous,direction)*normal
  normal-=direction*normal.dot(direction)
  if normal.length_squared()<.0001:normal=orthogonal(direction)
  normal=normal.normalized();frames.append(normal);previous=direction
 for strand in range(strands):
  var shifted:=PackedVector3Array()
  for i in range(centreline.size()):
   var end_distance: float=minf(lengths[i],distance-lengths[i])
   var spacing: float=lerpf(3.8,2.3,smoothstep(0.0,.045,end_distance))*radius
   shifted.append(centreline[i]+frames[i]*(strand-(strands-1)/2.0)*spacing)
  tube(shifted,radius,"tan" if strand==1 else "rubber",true)

func library_part(asset: String, part: String) -> Dictionary:
 if not library.has(asset):
  var original: Node3D=load("res://assets/environment/"+asset+"/parts.gltf").instantiate()
  var parts: Dictionary={}
  for mesh in original.find_children("*","MeshInstance3D",true,false):parts[String(mesh.name)]={"mesh":mesh.mesh,"pose":mesh.transform}
  library[asset]=parts;original.free()
 return library[asset][part]
func fitting(at: Vector3, radius_scale:=.16):
 var part:=library_part("modular_industrial_pipes_01","modular_industrial_pipes_01_pipe06")
 var mesh: Mesh=part.mesh;var pose:=Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3.ONE*radius_scale),at-Basis(Vector3.RIGHT,PI/2)*mesh.get_aabb().get_center()*radius_scale)
 append_mesh(mesh,pose,"steel")
func power_case(at: Vector3, side: float, height: float):
 var factor:=height/.50314
 var pose:=Transform3D(Basis(Vector3.UP,-side*PI/2).scaled(Vector3.ONE*factor),at)
 for name in ["power_box_01_box","power_box_01_door"]:
  var part:=library_part("power_box_01",name)
  var local:=Transform3D.IDENTITY
  if name.ends_with("door"):local.origin=Vector3(-.16383,0,.04318)
  append_mesh(part.mesh,pose*local,"paint")
 for y in [-height*.43,height*.43]:
  for z in [-height*.29,height*.29]:
   box(Vector3(.018,.036,.035),at+Vector3(side*.029,y,z),"steel")
   bolt(at+Vector3(-side*.060*factor,y,z),Vector3(-side,0,0),.0035)

func service_panel(side: float, z: float, y: float, width: float, height: float):
 panel_count+=1
 var x:=side*1.25
 box(Vector3(.04,height,width),Vector3(x,y,z),"paint")
 box(Vector3(.012,height-.055,width-.055),Vector3(x-side*.025,y,z),"black")
 for row in range(9):
  box(Vector3(.016,.013,width-.08),Vector3(x-side*.035,y-height*.37+row*height*.085,z),"steel")
 for dy in [-height*.43,height*.43]:
  for dz in [-width*.43,width*.43]:bolt(Vector3(x-side*.020,y+dy,z+dz),Vector3(-side,0,0))

func service_bay(side: float, z: float, y: float, width: float, height: float):
 panel_count+=1
 box(Vector3(.035,height,width),Vector3(side*1.26,y,z),"paint")
 box(Vector3(.012,height-.05,width-.05),Vector3(side*1.235,y,z),"black")
 for dy in [-height/2,height/2]:box(Vector3(.07,.024,width+.03),Vector3(side*1.215,y+dy,z),"steel")
 for dz in [-width/2,width/2]:box(Vector3(.07,height,.024),Vector3(side*1.215,y,z+dz),"steel")
 for dy in [-height/2,height/2]:
  for dz in [-width*.42,width*.42]:bolt(Vector3(side*1.18,y+dy,z+dz),Vector3(-side,0,0),.0035)
 for i in range(5):
  var at:=z-width*.32+i*width*.16
  for row in [-1.0,1.0]:
   var centre:=Vector3(side*1.205,y+row*height*.34,at)
   box(Vector3(.055,.045,.059),centre,"paint")
   box(Vector3(.003,.033,.047),centre+Vector3(-side*.029,0,0),"black")
   for dz in [-.014,.014]:
    cylinder(centre+Vector3(-side*.033,0,dz),Vector3(-side,0,0),.0045,.006,"brass",16)
   bolt(centre+Vector3(-side*.030,.013,0),Vector3(-side,0,0),.0023)
  tube(PackedVector3Array([Vector3(side*1.19,y+height*.31,at),Vector3(side*1.17,y+height*.10,at+.030-i*.003),Vector3(side*1.18,y-height*.10,at-.015+i*.002),Vector3(side*1.19,y-height*.31,at)]),.0045,"tan" if i==1 else "rubber")

func build_side(side: float):
 decor_side=side
 for z in [-.68,.03,.80,1.62]:
  box(Vector3(.065,1.63,.052),Vector3(side*1.255,.85,z),"paint")
  box(Vector3(.10,.10,.075),Vector3(side*1.25,.12,z),"steel")
  for y in [.18,.72,1.34,1.61]:bolt(Vector3(side*1.2225,y,z),Vector3(-side,0,0))
 service_bay(side,1.13,.97,.58,.46)
 service_bay(side,.40,1.475,.40,.28)
 service_panel(side,-.35,.96,.40,.27)
 power_case(Vector3(side*1.241,1.09,.75),side,.28)
 power_case(Vector3(side*1.247,.46,1.16),side,.28)
 # A supported loom, with rubber-lined folded straps and visible wall fixings.
 box(Vector3(.025,.18,1.62),Vector3(side*1.275,1.48,.83),"black")
 for y in [1.385,1.58]:box(Vector3(.065,.025,1.65),Vector3(side*1.24,y,.83),"paint")
 var loom:=PackedVector3Array()
 for i in range(5):
  var t:=i/4.0;loom.append(Vector3(side*(1.21-.012*sin(PI*t)),1.48-.025*sin(PI*t),.06+t*1.54))
 bundle(loom,4,.006)
 for z in [.12,.36,.60,.84,1.08,1.32,1.56]:
  var t: float=(z-.06)/1.54;var x: float=side*(1.21-.012*sin(PI*t));var y: float=1.48-.025*sin(PI*t)
  box(Vector3(.0025,.056,.021),Vector3(x-side*.007,y,z),"rubber")
  box(Vector3(.002,.063,.018),Vector3(x-side*.009,y,z),"paint")
  for dy in [-.031,.031]:
   var distance: float=1.28-absf(x)+.009
   box(Vector3(distance,.0025,.018),Vector3(side*(1.28-distance*.5),y+dy,z),"paint")
   bolt(Vector3(side*1.266,y+dy,z),Vector3(-side,0,0),.0028)
  mount_count+=1;detail_count+=1
 for z in [.07,1.60]:box(Vector3(.075,.14,.10),Vector3(side*1.22,1.48,z),"paint")
 # The roof/feed harness terminates in the authored front boxes. Keep this
 # passage clear of the side rib rather than cutting a loose loop through it.
 box(Vector3(.080,.085,.075),Vector3(side*1.226,1.463,.74),"paint")
 detail_count+=1
 bundle(PackedVector3Array([Vector3(side*1.21,1.43,.74),Vector3(side*1.21,1.31,.74),Vector3(side*1.240,1.23,.75)]),2,.005)
 # Vertical returns sit behind the tabletop; the forward run clears CRT tops.
 for at in [Vector3(side*1.20,.48,.66),Vector3(side*1.20,.98,1.67),Vector3(side*1.20,1.34,.01)]:
  box(Vector3(.14,.13,.18),at,"paint")
  for dz in [-.056,.056]:bolt(at+Vector3(-side*.070,.045,dz),Vector3(-side,0,0),.0035)
  box(Vector3(.014,.10,.07),at+Vector3(side*.073,0,0),"steel")
 tube(PackedVector3Array([Vector3(side*1.16,.545,.66),Vector3(side*1.16,1.34,.66)]),.015,"steel")
 tube(PackedVector3Array([Vector3(side*1.16,1.34,.10),Vector3(side*1.16,1.34,1.47),Vector3(side*1.16,.98,1.47),Vector3(side*1.16,.98,1.58)]),.015,"steel")
 fitting(Vector3(side*1.16,.98,1.54))
 for z in [.25,.48,.76]:pipe_clamp(Vector3(side*1.16,1.34,z),Vector3.FORWARD,.015,side)
 pipe_clamp(Vector3(side*1.16,.98,1.53),Vector3.FORWARD,.015,side)
 tube(PackedVector3Array([Vector3(side*1.20,1.38,1.45),Vector3(side*1.16,1.04,1.48),Vector3(side*1.18,.74,1.44),Vector3(side*1.20,.60,1.17)]),.009)
 if side>0:
  box(Vector3(.06,.06,.14),Vector3(1.25,1.47,.12),"paint")
  tube(PackedVector3Array([Vector3(1.255,1.49,-.33),Vector3(1.23,1.59,-.28),Vector3(1.23,1.56,.08),Vector3(1.23,1.47,.12)]),.006)
 decor_side=0.0

func build_front():
 # Dark distant decoration retains its silhouette at a lower static detail tier.
 coarse_geometry=true
 for x in [-1.015,-.42,.42,1.015]:box(Vector3(.06,1.58,.07),Vector3(x,.87,-.702),"paint")
 for x in [-.75,.73]:
  box(Vector3(.53,.30,.055),Vector3(x,1.46,-.70),"paint")
  box(Vector3(.44,.15,.012),Vector3(x,1.47,-.662),"black")
  for row in range(5):box(Vector3(.42,.012,.014),Vector3(x,1.42+row*.026,-.65),"steel")
  for dx in [-.23,.23]:
   for y in [1.34,1.58]:bolt(Vector3(x+dx,y,-.654),Vector3.BACK)
 bundle(PackedVector3Array([Vector3(-1.035,1.60,-.66),Vector3(-.55,1.59,-.65),Vector3(.06,1.57,-.65),Vector3(.70,1.61,-.65),Vector3(1.035,1.62,-.65)]),3,.005)
 for x in [-.98,-.48,.05,.56,.98]:
  box(Vector3(.022,.09,.055),Vector3(x,1.59,-.677),"paint");mount_count+=1
 for x in [-.98,.98]:
  box(Vector3(.14,.13,.065),Vector3(x,1.605,-.69),"paint")
  for dx in [-.047,.047]:bolt(Vector3(x+dx,1.60,-.6575),Vector3.BACK,.0028)
 # Central service cassette clears the clock on the centre monitor.
 box(Vector3(.45,.11,.075),Vector3(0,1.58,-.69),"paint")
 for x in [-.16,-.08,0.0,.08,.16]:cylinder(Vector3(x,1.58,-.64),Vector3.BACK,.015,.012,"brass")
 coarse_geometry=false
