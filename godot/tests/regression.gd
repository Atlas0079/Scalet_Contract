extends SceneTree

var failures:Array=[]
var checks=0

func check(ok:bool,message:String):
	checks+=1
	if not ok: failures.append(message); print("FAIL: ",message)

func quiet(config:String="A") -> SCWorld:
	var w=SCWorld.new(config)
	for a in w.actors: a.ai_enabled=false; a.fire_mode="hold_fire"
	return w

func place(a,cell:Vector2i):
	a.clear_movement(); a.move_from=null; a.move_to=null; a.move_progress=0.0; a.mode="standing"; a.occupied_cell=cell; a.position=SCData.center(cell)

func advance(w,seconds:float):
	for i in range(roundi(seconds*60)): w.set_paused(false); w.update(1.0/60)

func until(w,condition:Callable,seconds:float) -> bool:
	for i in range(roundi(seconds*60)):
		w.set_paused(false); w.update(1.0/60)
		if condition.call(): return true
	return false

func custom(w,after:String="hold") -> Dictionary:
	var r=w.planner.preview_task([1,2],"door_S_R","R","direct",{"after_entry":after,"stack_overrides":{1:Vector2i(34,31),2:Vector2i(36,31)},"entry_overrides":{1:Vector2i(37,28),2:Vector2i(33,28)},"stack_angles":{1:PI,2:0.0},"entry_angles":{1:0.0,2:PI}})
	check(r[1].is_empty(),"custom preview: "+r[1]); return r[0]

func test_map():
	for cfg in ["A","B","C"]:
		var w=SCWorld.new(cfg)
		check(w.actors.size()==14 and w.loot.objects.size()==10,"configuration "+cfg+" actor and loot counts")
		check(w.grid.zones.size()==10,"configuration "+cfg+" rooms")
		check(w.actor(1).position==Vector2(33.5,32.5),"spawn")
		check(not w.perception.player_visible.has(101),"initial enemy hidden")
		check(w.loot.objects["case:S"].discovered,"initial supply discovered")
	var g=SCGrid.new(); g.width=10; g.height=10
	check(g.can_move(Vector2i(1,1),Vector2i(2,2)),"diagonal open")
	g.set_cell(Vector2i(2,1),SCGrid.feature("wall",3,true,true,true))
	check(g.can_move(Vector2i(1,1),Vector2i(2,2)),"one clear side diagonal")
	g.set_cell(Vector2i(1,2),SCGrid.feature("wall",3,true,true,true))
	check(not g.can_move(Vector2i(1,1),Vector2i(2,2)),"both sides block diagonal")
	g=SCGrid.new(); g.width=10; g.height=10
	var route=g.find_path(Vector2i(1,1),Vector2i(4,4))
	check(route.size()==4 and absf(g.path_cost(route)-3*sqrt(2))<0.00001,"diagonal weighted distance")
	g.terrain_speed[Vector2i(2,1)]=0.1
	check(Vector2i(2,1) not in g.find_path(Vector2i(1,1),Vector2i(4,1)),"weighted path avoids slow cell")

func test_movement():
	var w=quiet(); var p=w.planner
	check(p.submit([1],"move",{"cell":Vector2i(30,32)}).is_empty(),"move accepted")
	check(until(w,func(): return w.actor(1).queue.is_empty(),10),"move completes")
	check(w.actor(1).occupied_cell==Vector2i(30,32),"move arrives exactly")
	var choice=p.movement_targets([1,2,3,4],Vector2i(28,32))
	check(choice[1].is_empty(),"squad destination preview")
	check(p.submit([1,2,3,4],"move",{"cell":Vector2i(28,32)}).is_empty(),"squad accepted")
	check(until(w,func(): return w.actors.slice(0,4).all(func(a): return a.queue.is_empty()),20),"squad completes")
	for id in choice[0]: check(w.actor(id).occupied_cell==choice[0][id],"preview and execution same destination %d" % id)
	var a=SCActor.new(1,"a","red",Vector2(1.5,1.5)); var b=SCActor.new(2,"b","red",Vector2(1.6,1.5)); var g=SCGrid.new()
	a.route=[Vector2i(1,1),Vector2i(2,1)]; b.route=a.route.duplicate()
	var allowance=SCMovement.allowances([a,b],g,0.1)
	check(is_equal_approx(allowance[1],0.2) and is_equal_approx(allowance[2],0.09),"equal speed slows only higher id")
	b.position=Vector2(4.5,1.5); b.occupied_cell=Vector2i(4,1); b.route=[Vector2i(4,1),Vector2i(5,1)]
	allowance=SCMovement.allowances([a,b],g,0.25)
	check(is_equal_approx(allowance[2],0.225),"crowding linger after separation")
	SCMovement.allowances([a,b],g,0.25); allowance=SCMovement.allowances([a,b],g,0.1)
	check(is_equal_approx(allowance[2],0.2),"crowding expires")

func test_plans():
	var w=quiet(); var d=custom(w)
	check(w.planner.submit_task(d).is_empty(),"custom submit")
	check(until(w,func(): return w.planner.tasks.is_empty(),45),"custom hold completes")
	for id in d.actors:
		check(w.actor(id).occupied_cell==d.entries[id],"custom position %d" % id)
		check(absf(angle_difference(w.actor(id).facing,d.entry_angles[id]))<0.1,"custom facing %d" % id)
	check(not w.room_checked.has("R"),"hold does not mark room searched")
	advance(w,2)
	check(w.actor(1).occupied_cell==d.entries[1],"hold stays at location")
	w=quiet(); d=custom(w,"search"); w.planner.submit_task(d)
	check(until(w,func(): return w.planner.tasks.is_empty(),90),"search plan completes")
	check(w.room_checked.has("R"),"search checks room")
	w=quiet(); d=custom(w); w.planner.submit_task(d); var t=w.planner.tasks.values()[0]; place(w.actor(3),d.entries[1])
	check(until(w,func(): return t.phase=="blocked",40),"occupied custom point suspends")
	check(t.draft.entries[1]==d.entries[1],"pinned point stays fixed")
	w=quiet(); w.planner.submit([1],"face",{"angle":1.0}); var old=w.actor(1).queue[0]; d=custom(w); d.entry_overrides[1]=Vector2i.ZERO
	check(not w.planner.submit_task(d).is_empty() and w.actor(1).queue[0]==old and w.planner.tasks.is_empty(),"invalid draft keeps existing command")
	for overrides in [{1:Vector2i(35,29)},{1:Vector2i(37,28),2:Vector2i(37,28)}]:
		check(not w.planner.preview_task([1,2],"door_S_R","R","direct",{"entry_overrides":overrides})[1].is_empty(),"doorway and overlapping slots rejected")
	check(not w.planner.preview_task([1,2],"door_S_R","R","flash",{"landing":Vector2i(35,28),"stack_overrides":{1:Vector2i(14,32)}})[1].is_empty(),"throw range from custom position")

func test_takeover_and_sync():
	var w=quiet(); var p=w.planner; var d=p.preview_task([1,2],"door_S_R","R","flash",{"landing":Vector2i(35,28)})[0]
	check(p.submit_task(d).is_empty(),"flash plan submit")
	check(w.actor(d.thrower).available("flashbang")==0 and w.actor(d.thrower).quantities.flashbang==1,"reservation without consuming")
	check(not p.submit([1],"move",{"cell":Vector2i.ZERO,"append":true}).is_empty(),"invalid takeover rejected")
	check(p.tasks.size()==1 and not w.actor(2).queue.is_empty(),"invalid takeover atomic")
	check(p.submit([1],"move",{"cell":Vector2i(30,32),"append":true}).is_empty(),"shift micro takeover")
	check(p.tasks.is_empty() and w.actor(2).queue.is_empty() and w.actor(d.thrower).available("flashbang")==1,"takeover cancels entire macro and releases")
	w=quiet(); p=w.planner; d=custom(w); d.sync="A"; p.submit_task(d); var t=p.tasks.values()[0]
	check(not p.release("A").is_empty(),"sync cannot release early")
	check(until(w,func(): return t.phase=="wait" and t.ready,20),"sync reaches ready")
	check(p.release("A").is_empty(),"sync release accepted")
	p.suspend_task(t,"test interruption")
	check(not p.release_requests.has("A") and not t.released,"suspension revokes release")
	check(p.retry_task(t.id).is_empty(),"retry sync")
	check(until(w,func(): return t.phase=="wait" and t.ready,20),"retry restages sync")
	check(p.release("A").is_empty(),"retry sync can release")
	check(until(w,func(): return p.tasks.is_empty(),30),"released sync completes")

func test_loot():
	var w=quiet(); var a=w.actor(1); var obj=w.loot.objects["case:S"]
	check(w.planner.submit([1],"loot_search",{"object_id":obj.id}).is_empty(),"search command")
	check(until(w,func(): return w.loot.results.has(obj.id),15),"search completes to allocation")
	check(w.paused and obj.searched and obj.known.size()==3,"search automatically pauses and shows contents")
	var gun=obj.items.values().filter(func(i): return i.kind=="rifle")[0]; var id=gun.id
	check(w.loot.allocate(obj.id,{id:2},false).is_empty(),"assign physical pickup")
	check(obj.items.has(id) and not w.actor(2).cargo.has(id),"assignment does not teleport")
	var token=w.loot.pickup_reservation(obj.id,id)[0]
	check(w.loot.allocate(obj.id,{id:2},false).is_empty() and w.loot.pickup_reservation(obj.id,id)[0]==token,"same carrier keeps reservation")
	preload("res://tests/study_fixture.gd").zero_capacity(w.actor(3))
	check(not w.loot.allocate(obj.id,{id:3},false).is_empty() and w.loot.pickup_reservation(obj.id,id)[0]==token,"failed reassignment preserves original")
	check(w.loot.allocate(obj.id,{id:4},false).is_empty(),"reassignment accepted")
	check(w.loot.pickup_reservation(obj.id,id)[1].actor_id==4 and not w.loot.reservations.has(token),"old pickup cancelled")
	check(until(w,func(): return w.actor(4).cargo.has(id),15),"pickup physically completes")
	var carrier=w.actor(4)
	check(not obj.items.has(id) and carrier.cargo[id].weapon.ammo==17,"weapon state preserved")
	check(w.planner.submit([4],"loot_equip",{"cargo_id":id}).is_empty(),"equip accepted")
	check(until(w,func(): return carrier.equipped_id==id,3),"equip completes")
	check(carrier.weapon.ammo==17 and carrier.weapon.reserve_ammo==90 and carrier.cargo.has("weapon:4"),"swap preserves magazine reserve and old weapon")
	check(w.planner.submit([4],"loot_drop",{"cargo_id":"weapon:4"}).is_empty(),"drop accepted")
	check(until(w,func(): return not carrier.cargo.has("weapon:4"),3),"drop completes")
	check(w.loot.objects.values().any(func(o): return o.kind=="ground" and o.cell==carrier.occupied_cell and o.items.has("weapon:4")),"drop at actual position")
	carrier.parts.heart.hp=0; carrier.mark_dead_if_needed(); advance(w,0.1)
	var corpse=w.loot.objects.get("corpse:4")
	check(corpse!=null and corpse.items.has(id) and corpse.items[id].weapon.ammo==17,"corpse retains equipped identity and magazine")
	check(is_equal_approx(w.grid.terrain_speed[corpse.cell],0.6),"corpse terrain slowdown")

func test_loot_macro():
	var w=quiet()
	check(w.planner.submit_loot_task([1,2],"S",[2]).is_empty(),"room loot task accepted")
	var t=w.planner.tasks.values()[0]
	check(until(w,func(): return w.loot.results.has("case:S"),25),"macro discovers source")
	var obj=w.loot.objects["case:S"]; var id=obj.known.keys()[0]
	check(w.loot.allocate(obj.id,{id:2},false).is_empty(),"macro guard gets pickup")
	check(w.planner.tasks.has(t.id) and w.actor(2).queue[0].task_id==t.id,"internal assignment keeps macro")
	w.loot.results.erase(obj.id); w.loot.notifications.erase(obj.id)
	check(w.loot.allocate(obj.id,{id:1},false).is_empty() and w.planner.tasks.has(t.id),"reassign after result closed keeps macro")
	check(until(w,func(): return not obj.items.has(id),20),"macro pickup completes onsite")

func test_items_and_damage():
	var w=quiet(); var a=w.actor(1)
	a.weapon.ammo=7
	check(w.planner.submit([1],"reload").is_empty(),"reload accepted")
	check(until(w,func(): return a.queue.is_empty(),5),"reload completes")
	check(a.weapon.ammo==30 and a.weapon.reserve_ammo==67,"reload ammo conservation")
	for part in a.parts.values():
		if part.definition.region=="left_leg" and "bleeds" in part.definition.tags: part.hp=maxf(1,part.hp-20); break
	var before=a.body_function("movement"); var part_id=a.treatment_part()
	check(before<1 and part_id!=null,"wound affects mobility")
	var hp=a.parts[part_id].hp
	check(w.planner.submit([1],"bandage").is_empty(),"bandage accepted")
	check(a.available("bandage")==0 and a.quantities.bandage==1,"bandage reserved")
	check(until(w,func(): return a.queue.is_empty(),8),"bandage completes")
	check(a.parts[part_id].hp>hp and a.quantities.bandage==0,"bandage actual treatment and consumption")
	w=quiet(); var d=w.planner.preview_task([1,2],"door_S_R","R","flash",{"landing":Vector2i(35,28)})[0]
	check(w.planner.submit_task(d).is_empty(),"flash accepted")
	check(until(w,func(): return w.stats.items.get("flashbang",0)==1,20),"flash releases")
	advance(w,2)
	check(w.stats.items.flashbang==1 and w.actor(d.thrower).quantities.flashbang==0,"flash consumed once")

func test_combat_and_priority():
	var w=quiet(); var a=w.actor(1); var enemy=w.actor(101)
	place(enemy,Vector2i(30,30)); enemy.facing=PI/2; a.facing=-PI/2
	place(a,Vector2i(30,33)); a.fire_mode="aimed_shot"; a.weapon.ammo=0
	check(w.planner.submit([1],"move",{"cell":Vector2i(27,33)}).is_empty(),"micro under threat accepted")
	check(until(w,func(): return a.queue.is_empty(),10),"micro moves despite visible enemy and empty magazine")
	check(a.occupied_cell==Vector2i(27,33),"micro destination maintained")
	w.planner.submit([1],"face",{"angle":(enemy.position-a.position).angle()})
	check(until(w,func(): return not enemy.alive,25),"automatic reload and actual combat kills")
	check(w.stats.rounds>0 and w.loot.objects.has("corpse:101"),"combat stats and corpse")
	w=quiet(); a=w.actor(1); enemy=w.actor(101)
	w.planner.submit([1],"move",{"cell":Vector2i(30,32)})
	w.receive_attack(a,{"start":Vector2(25,25),"end":a.position},enemy)
	check(a.queue[0].status!="blocked" and a.under_fire_timer>w.time,"unknown fire does not interrupt micro")
	check(not w.perception.player_visible.has(enemy.id),"unknown fire does not reveal attacker")
	w=quiet(); var d=custom(w); w.planner.submit_task(d)
	w.receive_attack(w.actor(1),{"start":Vector2(25,25),"end":w.actor(1).position},w.actor(101))
	check(w.planner.tasks.values()[0].phase=="blocked","unknown fire suspends macro")

func test_clock_and_victory():
	var w=quiet(); w.update(1.0); check(w.time==0,"paused clock")
	w.set_paused(false); w.update(1.0)
	check(is_equal_approx(w.time,5.0/60) and w.discarded_time>0.8,"bounded fixed-step catchup")
	w=quiet()
	for a in w.actors:
		if a.team=="blue": a.parts.heart.hp=0; a.mark_dead_if_needed()
	advance(w,0.1); check(w.winner=="red","victory")
	w.continue_looting(); check(w.winner==null and w.combat_cleared and w.paused,"continue looting")
	advance(w,0.1); check(w.winner==null,"victory does not repeat")

func _initialize():
	var started=Time.get_ticks_msec()
	for test in [test_map,test_movement,test_plans,test_takeover_and_sync,test_loot,test_loot_macro,test_items_and_damage,test_combat_and_priority,test_clock_and_victory]:
		print("RUN ",test.get_method()); test.call()
	print("REGRESSION: ",checks," checks; ",failures.size()," failures; ",(Time.get_ticks_msec()-started)/1000.0," seconds")
	quit(0 if failures.is_empty() else 1)
