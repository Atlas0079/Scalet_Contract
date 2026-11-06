extends Control
## Drawing consumes legal presentation/plan results. It never searches paths.
var host: Control
var friendly_markers_only := false

func at(point: Vector2) -> Vector2:return host.world_to_screen(point)-position

func arrow(origin: Vector2, direction: Vector2, color: Color):
 if direction.length()<.1:return
 var tip:=origin+direction*44
 draw_line(origin,tip,color,3,true)
 var side:=direction.orthogonal()*7
 draw_colored_polygon(PackedVector2Array([tip,tip-direction*13+side,tip-direction*13-side]),color)

func route_line(cells: Array, start: Vector2, color: Color, thickness: float):
 var previous:=start
 for cell: Vector2i in cells:
  var point:=SCData.center(cell)
  if not host.simulation.perception.explored.has(cell):break
  var first:=at(previous);var second:=at(point)
  if host.knowledge_state(point)==2 and host.knowledge_state(previous)==2:draw_line(first,second,color,thickness,true)
  else:draw_dashed_line(first,second,Color(color,.45),thickness,8.0,true,true)
  previous=point

func _draw():
 if not host.started:return
 if friendly_markers_only:draw_friendly_markers();return
 var amber:=Color("e3c58c")
 if host.overview:
  for item: Dictionary in host.overview_items:
   if item.kind=="wall":
    var half:=Vector2(item.length*.5,0) if item.horizontal else Vector2(0,item.length*.5)
    draw_line(at(item.position-half),at(item.position+half),Color("82948c"),2,true)
   else:
    var corner: Vector2=item.position-item.size*.5
    draw_rect(Rect2(at(corner),at(corner+item.size)-at(corner)).abs(),Color("81958b"),true)
 for id in host.simulation.scene_definition.zones:
  var zone: Dictionary=host.simulation.scene_definition.zones[id]
  var bounds: Array=zone.rect_m
  var center:=Vector2(float(bounds[0])+float(bounds[2])*.5,float(bounds[1])+minf(2.0,float(bounds[3])*.5))
  if host.knowledge_state(center)==0:continue
  var point:=at(center)
  draw_string(host.font,point-Vector2(110,0),zone.label,HORIZONTAL_ALIGNMENT_CENTER,220,24,Color(.73,.80,.76,.75))
 for id in host.marker_layout:
  var entry: Dictionary=host.marker_layout[id]
  var character: SCActor=host.simulation.actor(id)
  var controlled: bool=host.simulation.is_controlled(character)
  if controlled:
   if id in host.selected:
    route_line(host.queue_paths.get(id,[]),character.position,Color(host.unit_color(id),.60),2)
    if not character.queue.is_empty():
     var node: Dictionary=character.queue[0]
     if node.get("cell")!=null and node.get("angle")!=null:
      var destination:=SCData.center(node.cell)
      if host.knowledge_state(destination)>0:arrow(at(destination),(at(destination+Vector2.from_angle(node.angle))-at(destination)).normalized(),Color(host.unit_color(id),.8))
   continue
  var point: Vector2=entry.body-position
  var color: Color=host.unit_color(id)
  if not character.alive:
   draw_line(point-Vector2(5,5),point+Vector2(5,5),color,2,true)
   draw_line(point+Vector2(5,-5),point+Vector2(-5,5),color,2,true)
   continue
  if not host.units.has(id):draw_circle(point,4.0,color)
  if entry.label.has_area():
   var label_rect: Rect2=entry.label
   draw_string(host.font,label_rect.position-position+Vector2(0,17),character.actor_name,HORIZONTAL_ALIGNMENT_LEFT,154,18,color)
 for id in host.simulation.perception.last_seen:
  if host.simulation.perception.player_raw.has(id):continue
  var record: Array=host.simulation.perception.last_seen[id]
  var point: Vector2=record[0]
  if host.knowledge_state(point)==0:continue
  var p:=at(point)
  draw_arc(p,10,0,TAU,20,Color("907e71"),1,true)
  draw_string(host.font,p+Vector2(12,6),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("907e71"))
 for event: Dictionary in host.heard_sounds:
  var area: Vector2i=event.area
  var center:=Vector2(area)+Vector2(1.5,1.5)
  draw_arc(at(center),16,0,TAU,20,Color(.7,.65,.44,.45),1,true)
 for id in host.preview_paths:
  var path: Array=host.preview_paths[id]
  if path.is_empty():continue
  route_line(path,SCData.center(path[0]),Color(amber,.85),3)
  var end:=at(SCData.center(path[-1]));draw_arc(end,12,0,TAU,24,amber,2,true)
  if host.right_drag or host.tool_mode=="guard_direction":
   var anchor: Vector2=host.right_world if host.right_drag else host.guard_anchor
   if host.pointer_world.distance_to(anchor)>=(.25 if host.tool_mode=="guard_direction" else .5):arrow(end,(at(host.pointer_world)-at(anchor)).normalized(),amber)
 if host.preview_target!=null and host.preview_state in ["planning","unreachable","invalid"]:
  var target:=at(SCData.center(host.preview_target))
  var color:=Color("88bcc3") if host.preview_state=="planning" else Color("db967d")
  draw_arc(target,12,0,TAU,24,color,2,true)
  if host.preview_state!="planning":
   draw_line(target-Vector2(6,6),target+Vector2(6,6),color,2,true)
   draw_line(target+Vector2(6,-6),target+Vector2(-6,6),color,2,true)
 if host.left_drag and host.drag_start.distance_to(host.pointer)>4:
  var selection:=Rect2(host.drag_start-position,host.pointer-host.drag_start).abs()
  draw_rect(selection,Color(amber,.1),true);draw_rect(selection,amber,false,2)

func draw_friendly_markers():
 # Only the authoritative controlled roster contributes to this unmasked UI.
 # Its world anchor has already passed the knowledge check in marker_layout.
 var amber:=Color("e3c58c")
 for id in host.marker_layout:
  var character: SCActor=host.simulation.actor(id)
  if not host.simulation.is_controlled(character):continue
  var entry: Dictionary=host.marker_layout[id]
  var point: Vector2=entry.body-position
  var color: Color=host.unit_color(id)
  if not character.alive:
   draw_line(point-Vector2(5,5),point+Vector2(5,5),color,2,true)
   draw_line(point+Vector2(5,-5),point+Vector2(-5,5),color,2,true)
   continue
  if id in host.selected:draw_arc(point,18.0 if not host.overview else 8.0,0,TAU,32,amber,2,true)
  if not host.units.has(id):draw_circle(point,5.0,color)
  if entry.clustered:continue
  var badge: Rect2=entry.badge
  var center: Vector2=badge.get_center()-position
  if center.distance_to(point)>18:draw_line(point,center,Color(color,.6),1,true)
  draw_circle(center,14,color)
  var number: int=host.simulation.controlled_ids.find(id)+1
  draw_string(host.font,center+Vector2(-6,7),str(number),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("14201f"))
 for squad: Dictionary in host.squad_markers:
  var rect: Rect2=squad.rect
  rect.position-=position
  var chosen: bool=squad.ids.any(func(id):return id in host.selected)
  draw_rect(rect,Color("30463d"),true);draw_rect(rect,amber if chosen else Color("8fa99b"),false,2)
  draw_string(host.font,rect.position+Vector2(8,23),"小队 %d" % squad.ids.size(),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-8,16,Color("e3c58c"))
