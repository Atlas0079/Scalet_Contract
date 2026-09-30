extends SceneTree

var g
var failures=[]
var checks=0
var captures=false
var out="C:/MyResearch/Scarlet Contract/.migration-local/"

func check(ok:bool,message:String):
	checks+=1
	if not ok: failures.append(message); print("FAIL: ",message)

func mouse(button:int,pressed:bool,point:Vector2,shift:bool=false):
	var e=InputEventMouseButton.new(); e.button_index=button; e.pressed=pressed; e.position=point; e.shift_pressed=shift
	g.map_view._gui_input(e)

func key(code:int,ctrl:bool=false):
	var e=InputEventKey.new(); e.keycode=code; e.pressed=true; e.ctrl_pressed=ctrl; g._input(e)

func frames(n:int=3):
	for i in range(n): await process_frame

func fresh():
	g.start_mission()
	for a in g.world.actors: a.ai_enabled=false; a.fire_mode="hold_fire"
	await frames()

func button_named(node:Node,text:String):
	if node is Button and node.text==text: return node
	for child in node.get_children():
		var found=button_named(child,text)
		if found!=null: return found
	return null

func shoot(name:String):
	await frames(5)
	if captures:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(out+name+".png")==OK,"capture "+name)

func test_draft():
	g.selected=[1,2]; g.set_focus("door","door_S_R"); g.choose_action("direct"); g.begin_edit()
	check(g.world.paused and g.editing and g.world.planner.tasks.is_empty(),"draft creation issues no orders")
	g.plan_phase="entry"; g.plan_actor=1
	for z in [12.0,32.0,64.0]:
		g.map_view.zoom=z; g.map_view.camera=Vector2(35,30)
		var start=g.map_view.to_screen(Vector2(37.5,28.5)); var end=g.map_view.to_screen(Vector2(38.5,28.5))
		mouse(MOUSE_BUTTON_RIGHT,true,start); mouse(MOUSE_BUTTON_RIGHT,false,end)
		check(g.draft.entries[1]==Vector2i(37,28) and is_zero_approx(g.draft.entry_angles[1]),"world-space drag at zoom "+str(z))
	var old=g.draft.duplicate(true); var count=g.undo_history.size(); g.edit_station(Vector2i.ZERO,null)
	check(g.draft==old and g.undo_history.size()==count,"invalid station doesn't alter draft or history")
	g.edit_station(Vector2i(36,28),PI)
	check(g.draft.entries[1]==Vector2i(36,28),"edit accepted")
	key(KEY_Z,true); check(g.draft==old,"undo restores exact draft")
	g.select_ids([3]); check(g.draft==old and g.plan_actor==1,"nonparticipant preserves draft")
	g.show_plan_settings(); button_named(g.modal,"door_S_R").pressed.emit()
	check(g.draft==old,"same entrance preserves custom points")
	g.map_view.zoom=32; g.map_view.camera=Vector2(35,28)
	await shoot("planning")
	var a=g.map_view.to_screen(Vector2(38.5,28.5)); mouse(MOUSE_BUTTON_RIGHT,true,a); key(KEY_ESCAPE)
	check(g.editing and g.map_view.right_start==null,"escape cancels gesture before leaving draft")
	key(KEY_ESCAPE); check(not g.editing and g.saved_draft!=null,"escape saves draft")
	g.restore_draft(); check(g.editing and g.draft==old,"restore validates saved draft")
	g.submit_draft(); check(not g.editing and g.world.paused and g.world.planner.tasks.size()==1,"commit once and remains paused")

func test_quick_and_time():
	await fresh(); g.selected=[1,2]; g.set_focus("door","door_S_R"); g.choose_action("flash")
	button_named(g.sidebar,"立即下令").pressed.emit()
	check(g.pick_mode=="quick_flash" and g.world.planner.tasks.is_empty(),"quick flash awaiting target")
	g.world.set_paused(false); var before=g.world.time
	g.show_events(); g._process(1.0)
	check(g.world.time==before and not g.world.paused,"overlay freezes time without changing pause preference")
	g.close_modal(); check(g.pick_mode=="quick_flash","overlay preserves targeting")
	g.cancel_pick(); check(g.draft==null and g.world.planner.tasks.is_empty(),"cancel quick flash cleanly")
	g.choose_action("flash"); button_named(g.sidebar,"立即下令").pressed.emit(); g.map_pick(Vector2(35.5,28.5))
	check(g.world.planner.tasks.size()==1 and g.world.actor(1).quantities.flashbang==1,"quick flash submits without early consumption")

func test_scope_and_gestures():
	await fresh(); g.set_focus("door","door_S_R"); await frames()
	check(root.gui_get_focus_owner() is Button,"action menu has keyboard focus")
	var enter=InputEventKey.new(); enter.keycode=KEY_ENTER; enter.pressed=true; Input.parse_input_event(enter); await frames(); enter=enter.duplicate(); enter.pressed=false; Input.parse_input_event(enter); await frames()
	check(g.draft!=null,"enter activates native action button")
	g.selected=[1,2,3,4]; g.set_focus("personal",2)
	g.world.actor(1).weapon.ammo=8; g.world.actor(2).weapon.ammo=8; key(KEY_R)
	check(g.selected==[1,2,3,4] and g.world.actor(1).queue.is_empty() and g.world.actor(2).queue.size()==1,"personal shortcut does not alter squad selection")
	g.pick_mode="guard_cell"; g.select_ids([1]); check(g.pick_mode.is_empty(),"new selection cancels stale targeting")
	g.world.planner.submit([1],"move",{"cell":Vector2i(30,32)})
	var pos=g.map_view.to_screen(Vector2(28.5,32.5)); mouse(MOUSE_BUTTON_RIGHT,true,pos,true); mouse(MOUSE_BUTTON_RIGHT,false,pos,false)
	check(g.world.actor(1).queue.size()==2,"shift captured on press")
	pos=g.map_view.to_screen(Vector2(27.5,32.5)); mouse(MOUSE_BUTTON_RIGHT,true,pos,false); mouse(MOUSE_BUTTON_RIGHT,false,pos,true)
	check(g.world.actor(1).queue.size()==1,"release shift does not append")
	var n=g.world.actor(1).queue[0]; mouse(MOUSE_BUTTON_RIGHT,true,pos); key(KEY_ESCAPE)
	check(g.map_view.right_start==null and g.world.actor(1).queue[0]==n and g.selected==[1],"escape cancels drag only")
	mouse(MOUSE_BUTTON_RIGHT,true,pos); g.map_view.resized.emit(); check(g.map_view.right_start==null,"resize cancels drag")
	var card=g.cards.get_child(0); g.refresh_cards(); check(g.cards.get_child(0)==card,"card updates preserve input target")
	g.set_focus("personal",1); var wait_button=button_named(g.sidebar,"等待同步 A")
	check(wait_button!=null,"wait signal accessible")
	wait_button.pressed.emit(); check(g.world.actor(1).queue[0].kind=="wait","wait button submits")
	g.world.set_paused(true)
	g.target_menu([{"kind":"actor","id":1,"label":"1"},{"kind":"actor","id":2,"label":"2"}],Vector2(300,300))
	await frames()
	var e=InputEventMouseButton.new(); e.button_index=MOUSE_BUTTON_LEFT; e.pressed=true; e.position=g.pause_button.get_global_rect().get_center(); e.global_position=e.position
	Input.parse_input_event(e); await frames(); e=e.duplicate(); e.pressed=false; Input.parse_input_event(e); await frames()
	check(not g.world.paused and not g.popup.visible,"one click pauses or resumes while popup open")
	g.popup.hide(); g.world.set_paused(true)

func test_loot_and_windows():
	await fresh(); var obj=g.world.loot.objects["case:S"]; obj.searched=true; g.world.loot.remember(obj); g.world.loot.open_result(obj,g.world.actor(1)); g.world.pause_requested=false
	g.open_loot(obj.id); g._process(0.01); await frames()
	check(g.loot_window.visible and g.world.paused,"loot window opens paused")
	var id=obj.known.keys()[0]; g.allocate_item(id,2)
	check(g.world.loot.pickup_reservation(obj.id,id)[1].actor_id==2,"loot assignment through UI")
	g._process(0.01); await shoot("loot")
	var rect=g.loot_window.get_global_rect(); var viewport=root.get_visible_rect()
	print("WINDOWS: root ",viewport," game ",g.size," map ",g.map_view.size," loot ",rect," local ",g.loot_window.position)
	check(viewport.encloses(rect),"loot window within viewport")
	g.show_details(2); g._process(1); check(g.loot_window.visible,"details preserve loot window")
	await shoot("details"); g.close_modal(); check(g.world.loot.reservations.size()==1,"return preserves reservation")
	g.close_loot(true); check(not g.loot_window.visible and not g.world.loot.results.has(obj.id) and g.world.paused,"allocation done keeps paused")
	g.show_help(); await shoot("help"); g.close_modal()
	g.show_settings(); await shoot("settings"); g.close_modal()

func run():
	captures="--capture-ui" in OS.get_cmdline_user_args()
	g=load("res://main.tscn").instantiate(); root.add_child(g); await frames(); g.set_process(false)
	await shoot("title"); await fresh(); await shoot("start")
	await test_draft(); await test_quick_and_time(); await test_scope_and_gestures(); await test_loot_and_windows()
	print("INTERFACE: ",checks," checks; ",failures.size()," failures")
	g.queue_free(); await frames(); quit(0 if failures.is_empty() else 1)

func _initialize(): call_deferred("run")
