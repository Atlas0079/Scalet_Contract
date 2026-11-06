class_name SCPlanner
extends RefCounted

const LABELS = {
	"move": "移动",
	"guard": "定点警戒",
	"face": "调整朝向",
	"attack": "指定攻击",
	"reload": "换弹",
	"bandage": "自行包扎",
	"throw": "投掷",
	"wait": "等待信号",
	"task": "房间行动",
	"move_face": "定向移动",
	"loot_search": "搜索物品",
	"loot_take": "到场拿取",
	"loot_drop": "放下物品",
	"loot_equip": "装备武器"
}
const STAGES = {
	"queued": "排队",
	"stack": "门外集结",
	"wait": "等待信号",
	"door": "操作门",
	"throw": "使用物品",
	"blast": "等待起爆",
	"enter": "依次进入",
	"search": "检查威胁",
	"blocked": "已挂起",
	"done": "完成",
	"loot": "搜索物资",
	"allocation": "等待物资分配"
}
var _world: WeakRef
var world:
	get:
		return _world.get_ref()
var tasks: Dictionary = {}
var next_id: int = 1
var release_requests: Dictionary = {}
var stalls: Dictionary = {}
var entrance_error: String = ""
var _requests: Dictionary = {}
var _next_request := 1
var _path_requests: Dictionary = {}
var _cost_requests: Dictionary = {}
var _movement_requests: Dictionary = {}
var _holds: Dictionary = {}
var _capacity: Dictionary = {}
var _last_pump_frame := -1
var _request_clock := 0
var _committing := false
var _room_requests: Dictionary = {}
var _probe_pending := false
var _retry_waiters: Dictionary = {}
var _finished_nodes: Dictionary = {}
var _query_parent := 0
const SEARCH_MEMORY_BUDGET := 64*1024*1024



func _init(w):
	_world = weakref(w)


func actor(id):
	return world.actor(id)


func position_cell(a):
	return (
		a.move_to
		if a.move_to != null
		else (a.occupied_cell if a.occupied_cell != null else SCData.cell_of(a.position))
	)


func _node_endpoint(a, node: Dictionary, previous):
	if node.kind=="task":
		if not tasks.has(node.task_id):return previous
		var draft: Dictionary=tasks[node.task_id].draft
		if draft.method in ["open","kick"]:return draft.outside
		if draft.method in ["stack","guarddoor"]:return draft.stacks.get(a.id)
		if draft.method=="loot" or draft.get("after_entry","hold")=="search":return null
		return draft.entries.get(a.id)
	if node.kind in ["move","move_face","guard","loot_search","loot_take"]:return node.cell
	return previous


func origin(a, append: bool = false):
	var cell=position_cell(a)
	if append:
		for node in a.queue:cell=_node_endpoint(a,node,cell)
	return cell


func _queue_anchor(a) -> Dictionary:
	return {"token":a.queue.back().token if not a.queue.is_empty() else null,"cell":origin(a,true)}


func _resolve_anchor(a, token, fallback) -> Dictionary:
	if token==null:return {"valid":true,"ready":fallback!=null,"cell":fallback}
	var cell=position_cell(a)
	for node in a.queue:
		cell=_node_endpoint(a,node,cell)
		if node.token==token:return {"valid":true,"ready":cell!=null,"cell":cell}
	var key: Array=[a.id,token]
	if _finished_nodes.has(key):return {"valid":true,"ready":true,"cell":_finished_nodes[key].cell}
	return {"valid":false,"ready":false,"cell":null}


func note_node_completed(a, token: String):
	_finished_nodes[[a.id,token]]={"cell":position_cell(a),"tick":world.tick_index}
	if _finished_nodes.size()>4096:
		var protected: Dictionary={}
		for request in _requests.values():
			if request.state=="planning":
				for id in request.anchors:protected[[id,request.anchors[id]]]=true
				for id in request.parent_requests:
					var parent: Dictionary=_requests.get(request.parent_requests[id],{})
					var parent_token=parent.get("tail_tokens",{}).get(id)
					if parent_token!=null:protected[[id,parent_token]]=true
		for key in _finished_nodes.keys():
			if not protected.has(key):_finished_nodes.erase(key)
			if _finished_nodes.size()<=3072:break


func _cancel_anchor(a, token: String):
	for request in _requests.values():
		if request.state=="planning" and request.anchors.get(a.id)==token:cancel_request(request.id)


func _capture_installed(request: Dictionary):
	request.tail_tokens={}
	for id in request.ids:
		var a=actor(id)
		if a!=null:request.tail_tokens[id]=_queue_anchor(a).token


func _bind_request(request: Dictionary, macro_append: bool = false):
	for id in request.ids:
		var a=actor(id)
		var append: bool=request.append if macro_append else micro_append(a,request.append)
		request.appends[id]=append
		var anchor: Dictionary=_queue_anchor(a) if append else {"token":null,"cell":position_cell(a)}
		request.origins[id]=anchor.cell;request.anchors[id]=anchor.token
		if append:
			var parent:=_pending_predecessor(id,request.id)
			if parent>0:request.parent_requests[id]=parent;request.anchors[id]=null


func _dependencies_ready(request: Dictionary) -> bool:
	for id in request.ids:
		var a=actor(id)
		if a==null or not a.alive:_fail_request(request,"执行者死亡");return false
		if request.parent_requests.has(id):
			var parent: Dictionary=_requests.get(request.parent_requests[id],{})
			if parent.get("state")=="planning":return false
			if parent.get("state")!="complete":_fail_request(request,"前序计划已取消或失败");return false
			request.anchors[id]=parent.get("tail_tokens",{}).get(id)
			if request.anchors[id]==null:request.origins[id]=position_cell(a)
		if request.appends.get(id,false):
			var endpoint:=_resolve_anchor(a,request.anchors.get(id),request.origins.get(id))
			if not endpoint.valid:_fail_request(request,"前序计划已变更，请重新下令");return false
			if not endpoint.ready:return false
			request.origins[id]=endpoint.cell
		else:
			var current=position_cell(a)
			if request.origins.get(id)!=current:request.snapshot={}
			request.origins[id]=current
	return true


func _player_query(a, options: Dictionary = {}) -> bool:
	return options.get("known",true) and world.is_controlled(a)


func _query_snapshot(player: bool) -> Dictionary:
	if _query_parent>0:
		var parent: Dictionary=_requests.get(_query_parent,{})
		if not parent.is_empty() and parent.get("player",player)==player and not parent.snapshot.is_empty():return parent.snapshot
	return world.grid.capture_navigation(world.perception if player else null)


func _remember_query_path(route: Array, player: bool):
	if _query_parent>0 and not route.is_empty():_requests[_query_parent].used_paths.append({"route":route,"player":player})


func request_paths_valid() -> bool:
	if _query_parent==0:return true
	var request: Dictionary=_requests[_query_parent]
	for used in request.used_paths:
		if not _route_legal(used.route,used.player):
			request.snapshot=world.grid.capture_navigation(world.perception if request.player else null)
			_probe_pending=true;return false
	return true


func _region(options: Dictionary):
	if options.get("zone")!=null:return {"__zone":options.zone}
	if options.get("exclude")!=null:return {"__exclude":options.exclude}
	return null


func _query_key(a, goal, options: Dictionary = {}) -> Array:
	return [a.id,options.get("start",position_cell(a)),goal,options.get("zone"),options.get("exclude"),_player_query(a,options)]


func path(a, goal, options: Dictionary = {}) -> Array:
	if goal==null or a==null:return []
	var key:=_query_key(a,goal,options)
	if key[1]==null:_probe_pending=true;return []
	var grid: SCGrid=world.grid
	var snapshot:=_query_snapshot(key[5])
	var version: int=snapshot.version
	var cache_key:=key+[version]
	var cached=grid.cached_path(cache_key)
	if cached!=null:_remember_query_path(cached,key[5]);return cached
	var request: Dictionary={}
	if _path_requests.has(key):request=_requests.get(_path_requests[key],{})
	if not request.is_empty() and request.state=="planning":
		if _query_parent>0:request.sponsor=_query_parent
		_probe_pending=true;return []
	if not request.is_empty() and request.state=="complete" and request.snapshot.version==version:
		var route: Array=request.paths.get(a.id,[]).duplicate();_remember_query_path(route,key[5]);return route
	var id:=_new_request([a.id],"path",options)
	request=_requests[id];request.start=key[1];request.goal=goal;request.key=key;request.region=_region(options);request.player=key[5];request.snapshot=snapshot
	var tree=_matching_cost_tree(a,goal,options,snapshot)
	if tree!=null:request.snapshot=tree.snapshot;request.search=tree
	_path_requests[key]=id;_probe_pending=true
	return []


func cost_query(a, goals: Array, options: Dictionary = {}) -> Dictionary:
	if options.has("start") and options.start==null:_probe_pending=true;return {"state":"planning","costs":{}}
	var unique: Dictionary={}
	for goal in goals:unique[goal]=true
	var ordered: Array=unique.keys()
	ordered.sort_custom(SCData.cell_less)
	var player:=_player_query(a,options)
	var snapshot:=_query_snapshot(player)
	var version: int=snapshot.version
	var key: Array=[a.id,options.get("start",position_cell(a)),ordered,options.get("zone"),options.get("exclude"),player,version]
	if _cost_requests.has(key) and _requests.has(_cost_requests[key]):
		var existing: Dictionary=_requests[_cost_requests[key]]
		if existing.state=="planning":
			if _query_parent>0:existing.sponsor=_query_parent
			_probe_pending=true
		return existing
	if ordered.is_empty():return {"state":"complete","costs":{}}
	for previous in _requests.values():
		if previous.purpose!="multi" or previous.state!="complete" or previous.ids[0]!=a.id:continue
		if previous.start!=key[1] or previous.player!=player or previous.snapshot.version!=version or previous.region!=_region(options):continue
		var previous_goals: Dictionary=previous.get("goal_set",{})
		if ordered.all(func(goal):return previous_goals.has(goal)):return previous
	var id:=_new_request([a.id],"multi",options);var request: Dictionary=_requests[id]
	request.start=key[1];request.goals=ordered;request.goal_set=unique;request.key=key;request.region=_region(options);request.player=player;request.costs={};request.snapshot=snapshot
	_cost_requests[key]=id;_probe_pending=true
	return request


func _matching_cost_tree(a, goal, options: Dictionary, snapshot: Dictionary):
	var player:=_player_query(a,options)
	var version: int=snapshot.version
	for request in _requests.values():
		if request.purpose!="multi" or request.state!="complete" or request.get("tree")==null:continue
		if request.ids[0]==a.id and request.start==options.get("start",position_cell(a)) and request.player==player and request.snapshot.version==version and request.region==_region(options) and request.costs.has(goal):return request.tree
	return null


func _advance_backtrack(request: Dictionary, deadline: int) -> bool:
	var count:=0
	while request.trace_cell!=null:
		var cell: Vector2i=request.trace_cell;request.reverse_route.append(cell)
		request.trace_cell=request.search.parent_of(cell)
		var dependencies: Array=[cell]
		if request.trace_cell!=null:
			var parent: Vector2i=request.trace_cell;dependencies.append(parent)
			if parent.x!=cell.x and parent.y!=cell.y:dependencies.append(Vector2i(parent.x,cell.y));dependencies.append(Vector2i(cell.x,parent.y))
		for c: Vector2i in dependencies:
			var key: Vector2i=world.grid._chunk(c);var chunk: Dictionary=request.snapshot.chunks.get(key,{})
			request.trace_chunks[key]=int(chunk.get("version",0))
		count+=1
		if count>=64:
			count=0
			if Time.get_ticks_usec()>=deadline:return false
	request.reverse_route.reverse()
	return true


func path_state(a, goal, options: Dictionary = {}) -> String:
	var key:=_query_key(a,goal,options)
	if not _path_requests.has(key):return "planning"
	var request: Dictionary=_requests.get(_path_requests[key],{})
	return str(request.get("state","planning"))


func _new_request(ids: Array, purpose: String, options: Dictionary = {}) -> int:
	var id:=_next_request;_next_request+=1;_request_clock+=1
	_requests[id]={"id":id,"ids":ids.duplicate(),"purpose":purpose,"options":options.duplicate(),"state":"planning","assigned":{},"paths":{},"origins":{},"anchors":{},"appends":{},"search":null,"snapshot":{},"index":0,"error":"","created":_request_clock,"born_usec":Time.get_ticks_usec(),"candidates":[],"occupied":{},"parent_requests":{},"held":[],"reserved":[],"trees":{},"routes":{},"backtrack":null,"route_versions":{},"trace_chunks":{},"sponsor":_query_parent}
	return id


func request_result(id: int) -> Dictionary:
	var request: Dictionary=_requests.get(id,{"state":"cancelled","error":"请求已撤销","assigned":{},"paths":{}})
	request.last_used_usec=Time.get_ticks_usec()
	if request.get("purpose")=="preview" and request.state in ["complete","unreachable"]:
		var version: int=world.grid.knowledge_revision if request.player else world.grid.navigation_revision
		if request.state=="unreachable" and version!=request.get("last_version",version):
			request.state="planning";request.error="";_reset_request(request)
		elif request.state=="complete":
			for actor_id in request.ids:
				var a=actor(actor_id)
				if a==null or origin(a,request.appends[actor_id])!=request.origins[actor_id] or version!=request.get("last_version",version) and not _route_legal(request.paths[actor_id],request.player,{},request.route_versions.get(actor_id,{})):
					request.state="planning";_reset_request(request);break
			request.last_version=version
	return request


func pending_request_count() -> int:
	var count:=0
	for request in _requests.values():
		if request.state=="planning":count+=1
	return count


func motion_held(a) -> bool:
	return _holds.has(a.id)


func _release_capacity(request: Dictionary):
	for id in request.reserved:
		_capacity[id]=maxi(0,int(_capacity.get(id,0))-1)
	request.reserved.clear()


func cancel_request(id: int):
	if not _requests.has(id):return
	var request: Dictionary=_requests[id]
	if request.state!="planning":return
	request.state="cancelled";request.error="规划已取消";request.search=null;request.trees.clear();request.snapshot={}
	_release_capacity(request)
	for other in _requests.values():
		if other.state=="planning" and other.parent_requests.values().has(id):cancel_request(other.id)
	for actor_id in request.held:
		if _holds.get(actor_id)==id:
			var a=actor(actor_id)
			if a!=null:a.blocked_reason="规划已取消，继续或重新下令"


func _cancel_retry_waiters(ids: Array):
	for key in _retry_waiters.keys():
		if _retry_waiters[key].ids.any(func(id):return id in ids):_retry_waiters.erase(key)


func cancel_actor_requests(ids: Array):
	_cancel_retry_waiters(ids)
	for request in _requests.values():
		if request.state=="planning" and request.purpose in ["command","room","node"] and request.ids.any(func(id):return id in ids):cancel_request(request.id)


func _fail_request(request: Dictionary, error: String):
	request.state="unreachable";request.error=error;request.search=null;request.trees.clear();request.snapshot={};_release_capacity(request)
	for child in _requests.values():
		if child.state=="planning" and child.parent_requests.values().has(request.id):cancel_request(child.id)
	if request.purpose in ["command","room","node"]:
		for id in request.held:
			var a=actor(id)
			if a!=null:a.blocked_reason=error+"，继续或重新下令"
		world.message(error,"")


func _pending_predecessor(id: int, before: int = 9223372036854775807) -> int:
	var previous: int=0
	for request in _requests.values():
		if request.id<before and request.purpose in ["command","room","node"] and request.state=="planning" and id in request.ids:previous=maxi(previous,int(request.id))
	return previous


func request_movement(ids: Array, cell, append: bool = false, purpose: String = "preview", options: Dictionary = {}) -> int:
	var sorted: Array=[]
	for id in ids:
		if id not in sorted:sorted.append(id)
	sorted.sort()
	var request_id:=_new_request(sorted,purpose,options)
	var request: Dictionary=_requests[request_id];request.goal=cell;request.append=append;request.player=true
	if sorted.is_empty():_fail_request(request,"先选择存活队员");return request_id
	for id in sorted:
		var a=actor(id)
		if a==null or not a.alive:_fail_request(request,"先选择存活队员");return request_id
		request.player=request.player and world.is_controlled(a)
	_bind_request(request)
	var snapshot: Dictionary=world.grid.capture_navigation(world.perception if request.player else null)
	request.last_version=snapshot.version
	if cell==null or not world.grid.in_bounds(cell):_fail_request(request,"目标不可通行");return request_id
	if request.player and world.grid.snapshot_flags(snapshot,cell)&1==0:_fail_request(request,"区域未探索");return request_id
	if not world.grid.snapshot_walkable(snapshot,cell):_fail_request(request,"目标不可通行");return request_id
	if purpose=="command":
		for id in sorted:
			var a=actor(id)
			if request.appends[id] and a.queue.size()+int(_capacity.get(id,0))>=8:_fail_request(request,"队列已满（最多 8 项）");return request_id
		_cancel_retry_waiters(sorted)
		for id in sorted:
			if request.appends[id]:_capacity[id]=int(_capacity.get(id,0))+1;request.reserved.append(id)
			else:
				for other in _requests.values():
					if other.id!=request_id and other.purpose in ["command","room","node"] and other.state=="planning" and id in other.ids:cancel_request(other.id)
				_holds[id]=request_id;request.held.append(id)
				var a=actor(id);a.blocked_reason="规划中"
		for task_id in related_tasks(sorted):
			for id in tasks[task_id].draft.actors:
				if not _holds.has(id):_holds[id]=request_id;request.held.append(id)
	return request_id


func _prepare_movement(request: Dictionary) -> bool:
	if not _dependencies_ready(request):return false
	request.snapshot=world.grid.capture_navigation(world.perception if request.player else null)
	request.last_version=request.snapshot.version
	var cell: Vector2i=request.goal;var zone=world.grid.zone_id(cell)
	for a in world.actors:
		if not a.alive or a.id in request.ids or a.occupied_cell==null:continue
		if request.player and not world.is_controlled(a) and not world.perception.player_visible.has(a.id):continue
		request.occupied[a.occupied_cell]=true
	if request.ids.size()==1:request.candidates=[cell]
	else:
		for y in range(cell.y-2,cell.y+3):
			for x in range(cell.x-2,cell.x+3):
				var c:=Vector2i(x,y)
				if Vector2(c-cell).length_squared()<=4 and world.grid.zone_id(c)==zone and world.grid.snapshot_walkable(request.snapshot,c):request.candidates.append(c)
	return true


func _route_legal(route: Array, player: bool, options: Dictionary = {}, dependencies: Dictionary = {}) -> bool:
	if route.is_empty():return false
	var snapshot: Dictionary=world.grid.capture_navigation(world.perception if player else null)
	var changed: Dictionary={}
	for key in dependencies:
		if int(snapshot.chunks.get(key,{}).get("version",0))!=int(dependencies[key]):changed[key]=true
	if not dependencies.is_empty() and changed.is_empty():return true
	var allowed=_region(options)
	for i in range(1,route.size()):
		var from: Vector2i=route[i-1];var to: Vector2i=route[i]
		if not dependencies.is_empty() and not changed.has(world.grid._chunk(from)) and not changed.has(world.grid._chunk(to)):
			if from.x==to.x or from.y==to.y:continue
			if not changed.has(world.grid._chunk(Vector2i(from.x,to.y))) and not changed.has(world.grid._chunk(Vector2i(to.x,from.y))):continue
		if not world.grid.snapshot_can_move(snapshot,from,to,allowed):return false
	return world.grid.snapshot_walkable(snapshot,route.back())


func _reset_request(request: Dictionary):
	request.search=null;request.snapshot={};request.index=0;request.assigned={};request.paths={};request.candidates=[];request.occupied={};request.trees={};request.backtrack=null;request.route_versions={};request.trace_chunks={}
	request.erase("trace_cell");request.erase("reverse_route")
	for id in request.ids:
		var a=actor(id)
		if a!=null and not request.parent_requests.has(id):request.origins[id]=origin(a,request.appends.get(id,false))


func _finish_movement(request: Dictionary):
	for id in request.ids:
		var a=actor(id)
		if a==null or not a.alive:_fail_request(request,"执行者死亡");return
		var endpoint: Dictionary=_resolve_anchor(a,request.anchors.get(id),request.origins[id]) if request.appends[id] else {"valid":true,"ready":true,"cell":position_cell(a)}
		if not endpoint.valid:_fail_request(request,"前序计划已变更，请重新下令");return
		if not endpoint.ready:_reset_request(request);return
		var expected=endpoint.cell
		if expected!=request.origins[id] or not _route_legal(request.paths[id],request.player,{},request.route_versions.get(id,{})):_reset_request(request);return
		for other in world.actors:
			if other.id==id or not other.alive or other.occupied_cell!=request.assigned[id] or other.id in request.ids:continue
			if not request.player or world.is_controlled(other) or world.perception.player_visible.has(other.id):_reset_request(request);return
	request.state="complete";request.search=null;request.trees.clear()
	if request.purpose=="command":
		_release_capacity(request)
		var options: Dictionary=request.options.duplicate();options.append=request.append;options._resolved=request.assigned;options._routes=request.paths;options._origins=request.origins;options._nav_player=request.player;options._dependencies=request.route_versions;options._effective_appends=request.appends
		_committing=true
		var error:=_submit_now(request.ids,str(options.get("kind","move")),options)
		_committing=false
		if not error.is_empty():_fail_request(request,error);return
		_capture_installed(request)
		for id in request.held:
			if _holds.get(id)==request.id:_holds.erase(id)
			var a=actor(id)
			if a!=null and a.blocked_reason=="规划中":a.blocked_reason=""


func _queue_deferred(ids: Array, purpose: String, options: Dictionary) -> int:
	var unique: Array=[]
	for actor_id in ids:
		if actor_id not in unique:unique.append(actor_id)
	var id:=_new_request(unique,purpose,options);var request: Dictionary=_requests[id]
	request.append=bool(options.get("append",false));request.player=unique.all(func(actor_id):return actor(actor_id)!=null and world.is_controlled(actor(actor_id)))
	for actor_id in unique:
		var a=actor(actor_id)
		if a==null or not a.alive:_fail_request(request,"先选择存活队员");return id
	_bind_request(request,purpose=="room")
	for actor_id in unique:
		if request.appends[actor_id] and actor(actor_id).queue.size()+int(_capacity.get(actor_id,0))>=8:_fail_request(request,"队列已满（最多 8 项）");return id
	for actor_id in unique:
		var a=actor(actor_id)
		if request.appends[actor_id]:_capacity[actor_id]=int(_capacity.get(actor_id,0))+1;request.reserved.append(actor_id)
		else:
			for other in _requests.values():
				if other.id!=id and other.state=="planning" and other.purpose in ["command","room","node"] and actor_id in other.ids:cancel_request(other.id)
			_holds[actor_id]=id;request.held.append(actor_id);a.blocked_reason="规划中"
	_cancel_retry_waiters(unique)
	for task_id in related_tasks(unique):
		if unique.any(func(actor_id):return not request.appends[actor_id]):
			for actor_id in tasks[task_id].draft.actors:
				if not _holds.has(actor_id):_holds[actor_id]=id;request.held.append(actor_id)
	return id


func _advance_request(request: Dictionary, deadline: int):
	if request.purpose in ["room","node"]:
		if not _dependencies_ready(request):return
		if request.snapshot.is_empty():request.snapshot=world.grid.capture_navigation(world.perception if request.player else null)
		request.used_paths=[]
		_probe_pending=false;_committing=true;_query_parent=request.id
		request.options._effective_appends=request.appends;request.options._origins=request.origins
		var error: String
		if request.purpose=="room":error=SCRoomTasks.submit(self,request.options.draft,request.options.get("append",false))
		else:error=_submit_now(request.ids,request.options.kind,request.options)
		_committing=false;_query_parent=0
		if _probe_pending:return
		if not error.is_empty():_fail_request(request,error);return
		request.state="complete";_capture_installed(request);_release_capacity(request)
		for actor_id in request.held:
			if _holds.get(actor_id)==request.id:_holds.erase(actor_id)
		return
	if request.purpose in ["path","multi"]:
		if request.snapshot.is_empty():request.snapshot=world.grid.capture_navigation(world.perception if request.player else null)
		if request.search==null:
			request.search=world.grid.begin_search(request.start,request.goals if request.purpose=="multi" else [request.goal],request.snapshot,request.region)
		request.search.advance(deadline)
		if request.search.state!="complete":return
		if request.purpose=="multi":
			request.costs=request.search.settled.duplicate();request.tree=request.search;request.search=null;request.state="complete";return
		if not request.has("trace_cell"):
			request.trace_cell=request.goal if request.search.settled.has(request.goal) else null;request.reverse_route=[]
		if not _advance_backtrack(request,deadline):return
		var route: Array=request.reverse_route
		request.paths[request.ids[0]]=route;request.state="complete";request.search=null
		world.grid.cache_path(request.key+[request.snapshot.version],route)
		return
	if request.snapshot.is_empty() and not _prepare_movement(request):return
	if request.state!="planning":return
	if request.index>=request.ids.size():_finish_movement(request);return
	var id: int=request.ids[request.index]
	if request.search==null:
		var goals: Array=request.candidates.filter(func(c):return not request.occupied.has(c))
		if goals.is_empty():_fail_request(request,"路径被占位或已知通路阻断");return
		request.search=world.grid.begin_search(request.origins[id],goals,request.snapshot)
	request.search.advance(deadline)
	if request.search.state!="complete":return
	if not request.has("trace_cell"):
		var choices: Array=[]
		for c in request.search.settled:choices.append([Vector2(c).distance_squared_to(Vector2(request.goal)),request.search.settled[c],c.y,c.x,c])
		choices.sort_custom(SCGrid.heap_less)
		if choices.is_empty():_fail_request(request,"没有已知可达路线" if request.player else "路径暂不可达");return
		var destination: Vector2i=choices[0][4]
		request.assigned[id]=destination;request.occupied[destination]=true;request.trace_cell=destination;request.reverse_route=[]
	if not _advance_backtrack(request,deadline):return
	request.paths[id]=request.reverse_route;request.route_versions[id]=request.trace_chunks;request.trace_chunks={};request.erase("trace_cell");request.erase("reverse_route")
	request.search=null;request.index+=1
	if request.index>=request.ids.size():_finish_movement(request)


func pump_requests(budget_usec: int = 2000):
	var frame:=Engine.get_process_frames()
	if frame==_last_pump_frame:return
	_last_pump_frame=frame
	var deadline:=Time.get_ticks_usec()+maxi(100,budget_usec)
	for key in _retry_waiters.keys():
		if Time.get_ticks_usec()>=deadline:break
		var waiting: Dictionary=_retry_waiters[key];_probe_pending=false
		var error: String=""
		if waiting.has("task"):
			error=_retry_task_now(waiting.task)
		else:
			var a=actor(waiting.ids[0]);var node=null
			if a!=null:
				for queued in a.queue:
					if queued.token==waiting.token:node=queued;break
			if node==null:_retry_waiters.erase(key);continue
			error=_retry_node_now(a,node)
		if not _probe_pending:
			_retry_waiters.erase(key)
			if not error.is_empty():world.message(error,"")
	var pending: Array=_requests.values().filter(func(request):return request.state=="planning")
	pending.sort_custom(func(a,b):return _priority(a)<_priority(b) or _priority(a)==_priority(b) and a.id<b.id)
	var active:=0
	var retained_bytes:=0
	for request in _requests.values():
		if request.get("tree")!=null:retained_bytes+=request.tree.bytes_used()
		if request.search!=null:active+=1;retained_bytes+=request.search.bytes_used()
	if retained_bytes>SEARCH_MEMORY_BUDGET/2:
		for old in _requests.values():
			if old.get("tree")!=null and old.state=="complete":
				retained_bytes-=old.tree.bytes_used();old.tree=null
				if retained_bytes<=SEARCH_MEMORY_BUDGET/2:break
	for request in pending:
		if Time.get_ticks_usec()>=deadline:break
		var had_search: bool=request.search!=null
		if not had_search and request.purpose not in ["room","node"] and (active>=4 or retained_bytes>SEARCH_MEMORY_BUDGET*3/4):continue
		_advance_request(request,deadline)
		if not had_search and request.search!=null:active+=1
		elif had_search and request.search==null:active=maxi(0,active-1)
	# Completed results are bounded separately from the packed active search state.
	if _requests.size()>512:
		var protected: Dictionary={}
		for request in _requests.values():
			if request.state=="planning":
				for parent in request.parent_requests.values():protected[parent]=true
		var oldest: Array=_requests.values()
		oldest.sort_custom(func(a,b):return int(a.get("last_used_usec",a.born_usec))<int(b.get("last_used_usec",b.born_usec)))
		for request in oldest:
			var id: int=request.id
			if request.state!="planning" and not protected.has(id) and not _holds.values().has(id):_requests.erase(id)
			if _requests.size()<=384:break
		for index in [_path_requests,_cost_requests,_movement_requests]:
			for key in index.keys():
				if not _requests.has(index[key]):index.erase(key)


func _priority(request: Dictionary) -> int:
	var rank:=0 if request.purpose in ["command","room","node"] else 2 if request.purpose=="preview" else 3
	var sponsor: Dictionary=_requests.get(request.get("sponsor",0),{})
	if sponsor.get("state")=="planning":rank=0
	var age:=int((Time.get_ticks_usec()-int(request.born_usec))/1000000)
	return maxi(0,rank-age/2)


func releasing(a) -> Array:
	var tokens = []
	for n in a.queue:
		tokens.append(n.token)
		if tasks.has(n.task_id):
			tokens.append(tasks[n.task_id].token)
	return tokens


func micro_append(a, append: bool) -> bool:
	if not append or a.queue.any(func(n):return tasks.has(n.task_id)):return false
	for request in _requests.values():
		if request.purpose=="room" and request.state=="planning" and a.id in request.ids:return false
	return true


func available(a, item: String, append: bool) -> int:
	return a.available(item, [] if append else releasing(a))


func item_error(a, item: String, kind: String, append: bool = false, cell = null, resolved_append: bool = false) -> String:
	if not resolved_append:append=micro_append(a,append)
	if not a.alive:
		return "执行者死亡"
	if not SCData.catalog.items.has(item):
		return "未知物品"
	if kind == "reload":
		if a.weapon.ammo >= a.weapon.definition.magazine_size:
			return "弹匣已满"
		return "储备弹药耗尽" if a.weapon.reserve_ammo <= 0 else ""
	if available(a, item, append) < 1:
		return "物品不足（可能已预约）"
	if kind == "bandage" and a.treatment_part() == null:
		return "没有可治疗伤口"
	if kind == "throw" and cell != null:
		return throw_error(a, item, cell, origin(a, append))
	return ""


func throw_error(a, item: String, cell, from = null, room = null, opening_door = null) -> String:
	var g = world.grid
	if not g.walkable(cell):
		return "落点被家具或墙占用"
	if room == null and a.team == "red" and not world.perception.explored.has(cell):
		return "区域未探索"
	if room != null and g.zone_id(cell) != room:
		return "落点必须在目标房间"
	var use = SCData.use_for(item)
	var start = SCData.center(from) if from != null else a.position
	var end = SCData.center(cell)
	if start.distance_to(end) > use.range + 0.000001:
		return "超出 %s 格" % str(use.range)
	for pair in g.ray_features(start, end):
		var f = pair[1]
		if opening_door != null and f.interactive_id == opening_door:
			continue
		if f.blocks_projectile and f.height >= 2.0:
			return "被墙阻挡"
	return ""


func movement_targets(ids: Array, cell, append: bool = false) -> Array:
	var key: Array=[ids,cell,append]
	var request_id: int=int(_movement_requests.get(key,0))
	if request_id==0 or not _requests.has(request_id):
		request_id=request_movement(ids,cell,append,"preview");_movement_requests[key]=request_id
	var result:=request_result(request_id)
	if result.state=="complete":return [result.assigned,""]
	return [{},"规划中" if result.state=="planning" else result.error]


func submit(ids: Array, kind: String, options: Dictionary = {}) -> String:
	if kind in ["move","guard","move_face"]:
		var id:=request_movement(ids,options.get("cell"),options.get("append",false),"command",options.merged({"kind":kind}))
		var request: Dictionary=_requests[id]
		return str(request.error) if request.state!="planning" else ""
	for actor_id in ids:
		var a=actor(actor_id)
		if a==null or not a.alive:return "先选择存活队员"
		if micro_append(a,options.get("append",false)) and (_pending_predecessor(actor_id)>0 or origin(a,true)==null):
			var pending_id:=_queue_deferred(ids,"node",options.merged({"kind":kind}))
			return str(_requests[pending_id].error) if _requests[pending_id].state!="planning" else ""
	_probe_pending=false
	var error:=_submit_now(ids,kind,options)
	if _probe_pending:
		var pending_id:=_queue_deferred(ids,"node",options.merged({"kind":kind}))
		return str(_requests[pending_id].error) if _requests[pending_id].state!="planning" else ""
	if error.is_empty():
		cancel_actor_requests(ids)
		for actor_id in ids:_holds.erase(actor_id)
	return error


func _submit_now(ids: Array, kind: String, options: Dictionary = {}) -> String:
	var units = []
	var appends = {}
	var append = options.get("append", false)
	var cell = options.get("cell")
	var sync = options.get("sync")
	for id in ids:
		var a = actor(id)
		if a == null or not a.alive:
			return "先选择存活队员"
		if a not in units:
			units.append(a)
			appends[id]=options.get("_effective_appends",{}).get(id,micro_append(a,append))
	if units.is_empty():
		return "先选择存活队员"
	if kind in ["loot_search", "loot_drop", "loot_equip"]:
		if units.size() != 1:
			return "请选择一名执行者"
		var a = units[0]
		var error = ""
		if kind == "loot_search":
			error = world.loot.search_error(a,options.get("object_id"),options.get("_origins",{}).get(a.id,origin(a,appends[a.id])))
		else:
			error = world.loot.action_error(
				a,
				"drop_item" if kind == "loot_drop" else "equip_item",
				"",
				null,
				options.get("cargo_id")
			)
		if not error.is_empty():
			return error
	for a in units:
		if appends[a.id] and a.queue.size() >= 8:
			return "队列已满（最多 8 项）"
		if sync != null and has_sync(a, appends[a.id]):
			return "该队员已有同步等待"
	if kind == "wait" and sync not in ["A", "B"]:
		return "请选择同步 A 或 B"
	var loot_cells: Dictionary={};var loot_paths: Dictionary={}
	if kind in ["loot_search","loot_take"]:
		for a in units:
			var obj=world.loot.objects.get(options.get("object_id"))
			if obj==null or not obj.discovered:return "尚未发现此对象"
			var endpoint=world.loot.approach(a,obj,options.get("_origins",{}).get(a.id,origin(a,appends[a.id])))
			if endpoint==null:return "规划中" if _probe_pending else "没有可达的交互位置"
			var route: Array=path(a,endpoint,{"start":options.get("_origins",{}).get(a.id,origin(a,appends[a.id]))})
			if route.is_empty():return "规划中" if _probe_pending else "没有可达的交互位置"
			loot_cells[a.id]=endpoint;loot_paths[a.id]=route
	var assigned: Dictionary=options.get("_resolved",{})
	if kind in ["move","guard","move_face"] and assigned.is_empty():return "规划尚未完成"
	var chosen = options.get(
		"item", {"reload": "rifle", "bandage": "bandage", "throw": "flashbang"}.get(kind)
	)
	for a in units:
		if kind in ["reload", "bandage", "throw"]:
			var error=item_error(a,chosen,kind,appends[a.id],cell,true)
			if not error.is_empty():
				return error
		if kind == "attack" and not world.perception.player_visible.has(options.get("target_id")):
			return "目标已失去视野"
	if not request_paths_valid():return "规划中"
	cancel_related(ids)
	for a in units:
		if not appends[a.id]:
			cancel_actor(a)
		elif not a.queue.is_empty() and a.queue.back().kind == "guard":
			a.queue.back().kind = "move_face"
		var token = "node:%d" % next_id
		next_id += 1
		var values = options.duplicate()
		values.erase("append")
		for internal in ["_resolved","_routes","_origins","_nav_player","_dependencies","_effective_appends","kind"]:values.erase(internal)
		if options.get("_routes",{}).has(a.id):
			values.planned_route=options._routes[a.id]
			values.planned_player=options._nav_player
			values.planned_dependencies=options.get("_dependencies",{}).get(a.id,{})
		values.cell=assigned.get(a.id,cell)
		if loot_cells.has(a.id):
			values.cell=loot_cells[a.id];values.planned_route=loot_paths[a.id];values.planned_player=world.is_controlled(a)
		values.item = chosen
		var n = SCData.node(token, kind, values)
		if chosen != null and kind != "reload":
			a.reserve(token, chosen)
		a.queue.append(n)
		a.blocked_reason = ""
	world.message("%s：%s" % [str(ids), LABELS.get(kind, kind)])
	return ""


func has_sync(a, append: bool) -> bool:
	if not append:
		return false
	for n in a.queue:
		if n.sync != null or tasks.has(n.task_id) and tasks[n.task_id].draft.sync != null:
			return true
	return false


func related_tasks(ids: Array) -> Array:
	var found = {}
	for id in ids:
		if actor(id) == null:
			continue
		for n in actor(id).queue:
			if tasks.has(n.task_id):
				found[n.task_id] = true
	var result = found.keys()
	result.sort()
	return result


func micro_controls_motion(a) -> bool:
	if not a.alive or a.team != "red" or a.queue.is_empty() or not a.blocked_reason.is_empty():
		return false
	var n = a.queue[0]
	if n.task_id != null or n.status == "blocked":
		return false
	return (
		n.kind in ["move", "move_face", "face"]
		or n.kind == "guard" and not n.started
		or n.kind in ["loot_search", "loot_take"] and not n.started and n.status != "allocation"
	)


func takeover_text(ids: Array) -> String:
	var names = []
	var members = {}
	for id in related_tasks(ids):
		names.append(task_label(tasks[id]))
		for i in tasks[id].draft.actors:
			members[i] = true
	return "" if names.is_empty() else "将取消 %s · 影响 %s 号" % [" / ".join(names), str(members.keys())]


func cancel_related(ids: Array):
	for id in related_tasks(ids):
		cancel_task(id)


func suspend_task(task: Dictionary, reason: String):
	if task.phase != "blocked":
		task.resume_phase = task.phase
	task.phase = "blocked"
	task.reason = reason
	task.ready = false
	task.action_started = false
	if task.draft.sync != null:
		task.released = false
		release_requests.erase(task.draft.sync)
	var tokens = [task.token]
	for job in task.jobs.values():
		tokens.append(job.token)
	for id in task.draft.actors:
		var a = actor(id)
		if not a.queue.is_empty() and a.queue[0].task_id == task.id:
			a.clear_movement()
		if a.current_action != null and a.current_action.owner_token in tokens:
			a.current_action = null
			if a.alive:
				a.mode = "standing"
		if task.jobs.has(id):
			task.jobs[id].started = false


func suspend_actor(a, reason: String):
	a.clear_movement()
	if not a.queue.is_empty():
		var n = a.queue[0]
		if tasks.has(n.task_id):
			suspend_task(tasks[n.task_id], reason)
		else:
			n.status = "blocked"
			n.reason = reason
			n.started = false
			a.blocked_reason = reason
	if a.current_action != null:
		a.current_action = null
		if a.alive:
			a.mode = "standing"


func cancel_actor(a):
	if not _committing:cancel_actor_requests([a.id])
	_holds.erase(a.id)
	var affected = related_tasks([a.id])
	for n in a.queue:
		_cancel_anchor(a,n.token)
		a.reservations.erase(n.token)
		world.loot.release(n.token)
	a.queue.clear()
	a.current_action = null
	if a.mode == "acting":
		a.mode = "standing"
	a.clear_movement()
	a.blocked_reason = ""
	a.guard_angle = a.facing
	a.guard_explicit = false
	for id in affected:
		if not tasks.has(id):
			continue
		var t = tasks[id]
		var jobs = t.pickups.get(a.id, []).duplicate()
		if t.jobs.has(a.id):
			jobs.append(t.jobs[a.id])
		t.jobs.erase(a.id)
		t.pickups.erase(a.id)
		for job in jobs:
			world.loot.release(job.token)
			if job.kind == "loot_search":
				t.seen_loot.erase(job.object_id)
		var index = t.draft.actors.find(a.id)
		if index >= 0:
			if index < t.enter_index:
				t.enter_index -= 1
			t.draft.actors.erase(a.id)
		t.entered.erase(a.id)
		t.draft.stacks.erase(a.id)
		t.draft.entries.erase(a.id)
		a.reservations.erase(t.token)
		if t.draft.actors.is_empty():
			tasks.erase(id)
		else:
			if t.draft.method == "loot" and t.draft.actors.any(func(i): return not t.guards.has(i)):
				assign_search(t)
			suspend_task(t, "成员阵亡，请继续或取消")


func cancel_task(id):
	if not tasks.has(id):
		return
	var task = tasks[id]
	for actor_id in task.draft.actors:
		var participant=actor(actor_id)
		if participant!=null:_cancel_anchor(participant,task.token)
	tasks.erase(id)
	world.completed.erase(task.token)
	for job in task.jobs.values():
		world.loot.release(job.token)
	for nodes in task.pickups.values():
		for n in nodes:
			world.loot.release(n.token)
	for a in world.actors:
		var index = -1
		for j in range(a.queue.size()):
			if a.queue[j].task_id == id:
				index = j
				break
		a.reservations.erase(task.token)
		a.queue = a.queue.filter(func(n): return n.task_id != id)
		if index == 0:
			a.current_action = null
			if a.mode == "acting":
				a.mode = "standing"
			a.clear_movement()
			a.blocked_reason = ""
			a.guard_angle = a.facing
			a.guard_explicit = false
			if not a.queue.is_empty():
				suspend_actor(a, "前置宏观已取消，请继续或重下")
		elif index >= 0 and index < a.queue.size():
			var n = a.queue[index]
			if tasks.has(n.task_id):
				suspend_task(tasks[n.task_id], "前置宏观已取消，请继续或重下")
			else:
				n.status = "blocked"
				n.reason = "前置宏观已取消，请继续或重下"
	world.message("行动 %d 已取消" % id)


func stop(ids: Array):
	cancel_actor_requests(ids)
	for id in ids:_holds.erase(id)
	cancel_related(ids)
	for id in ids:
		if actor(id) != null:
			cancel_actor(actor(id))


func delete_node(a, index: int):
	if index < 0 or index >= a.queue.size():
		return
	var n = a.queue[index]
	_cancel_anchor(a,n.token)
	for request in _requests.values():
		if request.state=="planning" and request.anchors.get(a.id)==n.token:cancel_request(request.id)
	if tasks.has(n.task_id):
		cancel_task(n.task_id)
		return
	a.reservations.erase(n.token)
	world.loot.release(n.token)
	a.queue.remove_at(index)
	if index == 0:
		a.current_action = null
		if a.mode == "acting":
			a.mode = "standing"
		a.clear_movement()
		a.blocked_reason = ""


func retry_node(a, n: Dictionary) -> String:
	_probe_pending=false
	var error:=_retry_node_now(a,n)
	if _probe_pending:_retry_waiters[a.id]={"ids":[a.id],"token":n.token};return ""
	return error


func _retry_node_now(a, n: Dictionary) -> String:
	if not a.alive:
		return "执行者死亡"
	if a.stunned > 0 or a.under_fire_timer > world.time:
		return "等待震撼或受袭搜索结束"
	if n.cell != null and n.kind in ["move", "move_face", "guard"] and path(a, n.cell).is_empty():
		return "路径仍不可达"
	if n.kind in ["throw", "bandage"] and not world.completed.has(n.token):
		if not a.reservations.has(n.token):
			return "物品预约失效，请重新下达"
		if n.kind == "throw":
			var error = throw_error(a, n.item, n.cell)
			if not error.is_empty():
				return error
		elif a.treatment_part() == null:
			return "没有可治疗伤口"
	_holds.erase(a.id)
	n.status = "queued"
	n.reason = ""
	n.started = false
	a.blocked_reason = ""
	stalls.erase(a.id)
	return ""


func drive(a, cell, dt: float, angle = null, zone = null) -> bool:
	if a.stunned > 0 or a.current_action != null:
		return false
	if world.has_threat(a) and not micro_controls_motion(a):
		a.clear_movement()
		stalls.erase(a.id)
		return false
	if a.mode == "standing" and a.occupied_cell == cell:
		stalls.erase(a.id)
		a.clear_movement()
		if angle != null:
			a.guard_angle = angle
			a.guard_explicit = true
			return absf(angle_difference(a.facing, angle)) <= 0.087267
		return true
	var state = stalls.get(a.id, [a.position, 0.0, false])
	var elapsed = state[1] + dt if state[0].distance_to(a.position) < 0.000001 else 0.0
	if elapsed >= 5.0:
		a.blocked_reason = "5 秒无移动进展"
		a.clear_movement()
		return false
	if elapsed >= 2.0 and not state[2]:
		a.clear_movement()
		state[2] = true
	stalls[a.id] = [a.position, elapsed, state[2]]
	if a.target_cell != cell or a.route.is_empty() and a.mode == "standing":
		var route = path(a, cell, {"zone": zone} if zone != null else {})
		if not route.is_empty():
			a.route = route
			a.target_cell = cell
			a.reserved_cell = cell
		elif path_state(a,cell,{"zone":zone} if zone!=null else {})=="complete":
			a.blocked_reason = "路径暂不可达"
	return false


func sync_status(label: String) -> Array:
	var result = []
	for task in tasks.values():
		if task.draft.sync == label and not task.released:
			result.append([task_label(task), task.phase == "wait" and task.ready])
	for a in world.actors:
		for n in a.queue:
			if n.kind == "wait" and n.sync == label:
				result.append(
					[
						a.actor_name,
						n == a.queue[0] and n.status == "waiting" and not world.has_threat(a)
					]
				)
	return result


func release(label: String) -> String:
	var entries = sync_status(label)
	if entries.is_empty() or not entries.all(func(e): return e[1]):
		return "尚未全员就绪"
	release_requests[label] = true
	return ""


func task_label(t: Dictionary) -> String:
	var d = t.draft
	var label = (
		{
			"loot": "搜索物资",
			"direct": "直接突入",
			"breach": "破门突入",
			"flash": "闪光突入",
			"stack": "门外集结",
			"guarddoor": "守住门口",
			"open": "开门",
			"kick": "踹开"
		}
		. get(d.method, d.method)
	)
	if d.method in ["direct", "breach", "flash"]:
		label += "并就位" if d.after_entry == "hold" else "并检查威胁"
	return label + " · " + world.grid.zones[d.room].label


func tick(dt: float):
	for label in release_requests.keys():
		var entries = sync_status(label)
		if not entries.is_empty() and entries.all(func(e): return e[1]):
			for t in tasks.values():
				if t.draft.sync == label and not t.released:
					t.released = true
			for a in world.actors:
				if (
					not a.queue.is_empty()
					and a.queue[0].kind == "wait"
					and a.queue[0].sync == label
				):
					note_node_completed(a,a.queue[0].token);a.queue.pop_front()
			world.message("同步 %s · 已放行" % label)
		else:
			world.message("同步 %s · 就绪状态变化" % label)
		release_requests.erase(label)
	for t in tasks.values():
		if tasks.has(t.id) and not t.draft.actors.any(func(id):return _holds.has(id)):
			SCRoomTasks.tick(self, t, dt)
	for a in world.actors:
		if not a.alive or a.queue.is_empty() or motion_held(a):
			continue
		var n = a.queue[0]
		if n.get("planned_route")!=null and (a.route.is_empty() or a.target_cell!=n.cell):
			var planned: Array=n.planned_route
			if not planned.is_empty() and planned[0]==position_cell(a) and _route_legal(planned,n.get("planned_player",false),{},n.get("planned_dependencies",{})):
				a.route=planned.duplicate();a.target_cell=n.cell;a.reserved_cell=n.cell
			n.erase("planned_route")
		if n.kind == "task" or n.status == "blocked":
			continue
		if not a.blocked_reason.is_empty():
			n.status = "blocked"
			n.reason = a.blocked_reason
			continue
		if n.status != "allocation":
			n.status = "running"
		var done = false
		if n.kind.begins_with("loot_"):
			done = world.loot.tick_node(a, n, dt)
		elif n.kind in ["move", "guard", "move_face"]:
			a.guard_explicit = n.angle != null
			var arrived = drive(a, n.cell, dt, n.angle)
			if arrived and n.kind == "guard":
				n.started = true
			done = arrived and n.kind != "guard"
		elif n.kind == "face":
			if a.mode == "standing" and a.stunned <= 0 and a.current_action == null:
				a.guard_angle = n.angle
				a.guard_explicit = true
				done = absf(angle_difference(a.facing, n.angle)) <= 0.087267
		elif n.kind == "attack":
			a.target_id = n.target_id
			n.elapsed = 0.0 if a.visible.has(n.target_id) else n.elapsed + dt
			var target = actor(n.target_id)
			done = (
				n.elapsed >= 2.0
				or target != null and not target.alive and a.visible.has(n.target_id)
			)
		elif n.kind == "wait":
			a.clear_movement()
			if (
				a.mode == "standing"
				and a.current_action == null
				and a.stunned <= 0
				and not world.has_threat(a)
			):
				n.status = "waiting"
		elif n.kind in ["reload", "bandage", "throw"]:
			if world.completed.has(n.token):
				world.completed.erase(n.token)
				done = true
			elif (
				not n.started
				and a.mode == "standing"
				and a.stunned <= 0
				and a.current_action == null
			):
				if n.kind == "reload" and a.weapon.ammo >= a.weapon.definition.magazine_size:
					done = true
				else:
					var error = world.start_action(
						a,
						{"reload": "reload", "bandage": "bandage", "throw": "throw_grenade"}[
							n.kind
						],
						SCData.use_for(n.item).duration,
						n.token,
						{"item": n.item, "cell": n.cell}
					)
					if not error.is_empty():
						n.status = "blocked"
						n.reason = error
					else:
						n.started = true
		if done:
			a.reservations.erase(n.token)
			world.loot.release(n.token)
			if not a.queue.is_empty() and a.queue[0].token == n.token:
				note_node_completed(a,n.token);a.queue.pop_front()
			a.blocked_reason = ""


func preview_task(
	ids: Array, door: String, room: String, method: String, options: Dictionary = {}
) -> Array:
	_probe_pending=false
	var result: Array=SCRoomTasks.preview(self,ids,door,room,method,options)
	return [result[0],"规划中"] if _probe_pending else result


func choose_entrance(
	ids: Array, door = null, room = null, method: String = "direct", append: bool = false
):
	_probe_pending=false
	var result=SCRoomTasks.choose(self,ids,door,room,method,append)
	if _probe_pending:entrance_error="规划中";return null
	return result


func submit_task(d: Dictionary, append: bool = false) -> String:
	for actor_id in d.actors:
		var a=actor(actor_id)
		if a==null or not a.alive:return "先选择存活队员"
	if append and d.actors.any(func(actor_id):return _pending_predecessor(actor_id)>0 or origin(actor(actor_id),true)==null):
		var id:=_queue_deferred(d.actors,"room",{"draft":d.duplicate(true),"append":append})
		return str(_requests[id].error) if _requests[id].state!="planning" else ""
	_probe_pending=false
	var error: String=SCRoomTasks.submit(self,d,append)
	if _probe_pending:
		var id:=_queue_deferred(d.actors,"room",{"draft":d.duplicate(true),"append":append})
		return str(_requests[id].error) if _requests[id].state!="planning" else ""
	return error


func retry_task(id: int) -> String:
	_probe_pending=false
	var error:=_retry_task_now(id)
	if _probe_pending and tasks.has(id):_retry_waiters["task:"+str(id)]={"ids":tasks[id].draft.actors.duplicate(),"task":id};return ""
	return error


func _retry_task_now(id: int) -> String:
	var error: String=SCRoomTasks.retry(self,id)
	if error.is_empty() and tasks.has(id):
		for actor_id in tasks[id].draft.actors:_holds.erase(actor_id)
	return error


func assign_search(t: Dictionary):
	SCRoomTasks.assign_search(self, t)


func room_angle(room: String, c: Vector2i) -> float:
	return SCRoomTasks.room_angle(world.grid, room, c)


func finish_task(t: Dictionary):
	SCRoomTasks.finish(self, t)


func resolve_slot(t: Dictionary, a, c, assigned: Array, zone = null):
	return SCRoomTasks.resolve_slot(self, t, a, c, assigned, zone)


func submit_loot_task(ids: Array, room: String, guards: Array = []) -> String:
	return SCRoomTasks.submit_loot(self, ids, room, guards)
