extends SceneTree
const FX = preload("res://presentation/tactical/tactical_fire_fx.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("verify")
func fixture():
	var fx = FX.new(SCData.weapon("test_carbine"))
	fx.targets.clear()
	fx.obstacles.clear()
	return fx
func emit(fx, point := Vector3(0,1,6), age := 0.0):
	fx.emit_shot(Vector3(0,1,0),Vector3.ZERO,(point-Vector3(0,1,0)).normalized(),Vector2.RIGHT,age,Vector3(0,1,6))
func wall(fx, z: float):
	fx.obstacles.append({"id":"wall","label":"墙壁","rect":Rect2(-2,z,4,.2),"height":3.0})
func verify():
	check(SCData.ensure_valid(self),"configuration")
	for fps in [20.0,37.0,60.0,144.0]:
		var fx=fixture()
		emit(fx,Vector3(-.3,1.6,6))
		check(fx.paper_shots[0].status=="flying","arrive only after travel")
		for i in range(ceili(fps*.1)): fx.advance(1/fps)
		check(fx.paper_shots[0].status=="passed","miss crosses plane")
		check(fx.paper_shots[0].point.distance_to(Vector2(.3,.6))<.00001,"true yaw and height, shooter right")
	var fx=fixture()
	fx.targets.append({"id":"target","label":"靶","position":Vector2(0,6),"radius":.23,"height":1.8,"hits":0})
	fx.selected_target_id="target"
	emit(fx,Vector3(0,1.1,6),.04)
	check(fx.paper_shots[0].status=="hit" and fx.total_hits==1,"cylinder front hit projects onto plane")
	check(absf(fx.paper_shots[0].point.y-.1)<.00001,"hit height projection")
	fx=fixture()
	wall(fx,3)
	emit(fx,Vector3(0,1,6),.04)
	check(fx.paper_shots[0].status=="墙壁截停","cover has no fake hole")
	fx=fixture()
	wall(fx,7)
	emit(fx,Vector3(0,1,6),.04)
	check(fx.paper_shots[0].status=="passed","wall beyond plane preserves crossing")
	fx=fixture()
	emit(fx,Vector3(0,-1,6),.04)
	check(fx.paper_shots[0].status=="地面截停","ground has no fake hole")
	fx=fixture()
	fx.bullet_range=3
	emit(fx,Vector3(0,1,6),.04)
	check(fx.paper_shots[0].status=="射程不足","range cannot reach plane")
	fx=fixture()
	emit(fx)
	var old=fx.paper_shots[0]
	fx.clear_paper()
	emit(fx,Vector3(-.2,1.4,6))
	fx.advance(.04)
	check(fx.paper_shots.size()==1 and fx.paper_shots[0].id==1,"clear isolates in-flight shots")
	check(old.status=="passed" and fx.paper_shots[0].point.distance_to(Vector2(.2,.4))<.00001,"new record isolated")
	fx.emit_shot(Vector3(0,1,0),Vector3.ZERO,Vector3(0,1,6).normalized(),Vector2.RIGHT,.04,Vector3(4,1,9))
	check(fx.paper_plane.center==Vector3(0,1,6),"first aim remains anchored")
	for i in range(130): emit(fx,Vector3(0,1,6),.04)
	check(fx.paper_shots.size()==120 and fx.paper_shots.back().id==132,"bounded records preserve sequence")
	var scene=load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.demo=false
	scene.choose_lane(1)
	for i in range(90):
		if i==15: scene.set_trigger(true,false)
		if i==70: scene.set_trigger(false,false)
		scene.step(1.0/60,Vector2.ZERO)
		await process_frame
	var a=scene.units[0].effects
	var b=scene.units[1].effects
	check(a.paper_shots.size()>3,"actor integration records burst")
	check(a.paper_shots.size()==b.paper_shots.size(),"A/B shot count")
	for i in range(a.paper_shots.size()):
		check(a.paper_shots[i].point.distance_to(b.paper_shots[i].point)<.00001,"A/B same ballistic record")
	var panel=scene.target_paper
	var center=panel.plot_position(Vector2.ZERO)
	var x=panel.plot_position(Vector2(1,0))-center
	var y=panel.plot_position(Vector2(0,1))-center
	check(x.x>0 and y.y<0 and is_equal_approx(x.length(),y.length()),"equal aspect and positive up")
	var count=a.total_shots
	var recoil=scene.character.weapon.recoil_offset_degrees
	scene.clear_target_paper()
	check(a.paper_shots.is_empty() and b.paper_shots.is_empty(),"UI clear both styles")
	check(a.total_shots==count and scene.character.weapon.recoil_offset_degrees==recoil,"clear preserves shot stats and recoil")
	emit(a)
	scene.cycle_height()
	check(a.paper_shots.is_empty(),"height change clears group")
	emit(a)
	scene.select_lane(2)
	check(a.paper_shots.is_empty(),"lane change clears group")
	print("TARGET_PAPER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
