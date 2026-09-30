extends SceneTree

var checks:=0
var failures:Array=[]
func _initialize(): call_deferred("verify")
func check(ok:bool,message:String):
	checks+=1
	if not ok and not message in failures:
		failures.append(message)
		push_error(message)

func run_burst(skill:int, fps:int, force_scale:=1.0) -> Dictionary:
	var actor:=SCActor.new(1,"recoil","red",Vector2.ZERO,0,"test_operator")
	actor.consciousness.xp.shooting=skill*skill*100.0
	actor.refresh_capabilities()
	actor.weapon.definition.recoil.impulse_degrees_per_second[1]*=force_scale
	var rng:=RandomNumberGenerator.new()
	rng.seed=891
	var shots:Array=[]
	var curve:Array=[]
	var time:=0.0
	var next_shot:=0.0
	var peak:=0.0
	for frame in range(fps*4):
		var end:float=(frame+1.0)/fps
		while next_shot<=end+1e-9:
			SCCombat.advance_recoil(actor,maxf(0,next_shot-time))
			time=next_shot
			shots.append(actor.weapon.recoil_offset_degrees.y)
			SCCombat.record_shot(actor,rng,false)
			next_shot+=actor.weapon.definition.fire_interval
		SCCombat.advance_recoil(actor,maxf(0,end-time))
		time=end
		peak=maxf(peak,actor.weapon.recoil_offset_degrees.y)
		curve.append([time,actor.weapon.recoil_offset_degrees.y,actor.weapon.recoil_compensation])
	var last_mean:=0.0
	for value in shots.slice(-10): last_mean+=value/10.0
	SCCombat.advance_recoil(actor,8.0)
	check(actor.weapon.recoil_offset_degrees.length()<.001 and actor.weapon.recoil_velocity_degrees_per_second.length()<.001,"Released weapon failed to settle")
	return {"shots":shots,"peak":peak,"late_mean":last_mean,"curve":curve}

func verify():
	check(SCData.ensure_valid(self),"Configuration invalid")
	var actor:=SCActor.new(1,"test","red",Vector2.ZERO,0,"test_operator")
	var rng:=RandomNumberGenerator.new()
	rng.seed=28
	var before:Vector2=actor.weapon.recoil_offset_degrees
	SCCombat.record_shot(actor,rng,false)
	check(actor.weapon.recoil_offset_degrees==before,"First recoil teleported angle before motion")
	check(actor.weapon.recoil_velocity_degrees_per_second.y>0,"Shot did not impart angular velocity")
	SCCombat.advance_recoil(actor,.1)
	check(actor.weapon.recoil_compensation==0,"Compensation began before reaction delay")
	check(actor.weapon.recoil_offset_degrees.y>.1,"Second shot did not inherit first-shot climb")
	var first_jump:float=actor.weapon.recoil_offset_degrees.y
	for i in range(30):
		SCCombat.record_shot(actor,rng,false)
		SCCombat.advance_recoil(actor,.1)
	var learned:float=actor.weapon.recoil_compensation
	SCCombat.advance_recoil(actor,.15)
	check(learned>.9 and actor.weapon.recoil_compensation>=learned,"Brief pause forgot acquired control")
	SCCombat.advance_recoil(actor,3)
	check(actor.weapon.recoil_compensation<.02,"Long pause retained full compensation")
	var results:Dictionary={}
	for skill in [0,10,20]:
		results[str(skill)]=run_burst(skill,60)
		print("RECOIL_SKILL ",skill," peak=",results[str(skill)].peak," late_mean=",results[str(skill)].late_mean," first_shots=",results[str(skill)].shots.slice(0,8))
	check(results["0"].shots[1]>results["10"].shots[1] and results["10"].shots[1]>results["20"].shots[1],"Skill did not reduce initial jump")
	check(absf(results["10"].late_mean)<results["10"].peak*.4,"Default shooter did not compensate sustained climb")
	check(absf(results["20"].late_mean)<results["10"].peak*.4,"Expert did not converge")
	var heavy:=run_burst(10,60,4)
	check(heavy.late_mean>results["10"].late_mean+1,"Control limit was bypassed by a heavy weapon")
	var maximum_difference:=0.0
	for fps in [20,37,144]:
		var other:=run_burst(10,fps)
		check(other.shots.size()==results["10"].shots.size(),"Frame rate changed shot count")
		for i in range(other.shots.size()): maximum_difference=maxf(maximum_difference,absf(other.shots[i]-results["10"].shots[i]))
	check(maximum_difference<.02,"Frame rate materially changed recoil: "+str(maximum_difference))
	SCCombat.reset_recoil(actor.weapon)
	SCCombat.advance_aim(actor,.8,true)
	check(actor.weapon.recoil_offset_degrees==Vector2.ZERO and actor.weapon.recoil_velocity_degrees_per_second==Vector2.ZERO,"Idle gun created recoil")
	var a:=SCCombat.holding_error(actor)
	actor.aim_clock+=1.7
	check(not SCCombat.holding_error(actor).is_equal_approx(a),"Old periodic sway survived")
	var state:Dictionary=actor.weapon.duplicate(true)
	SCCombat.holding_error(actor)
	check(actor.weapon==state,"Reading holding pose changed recoil state")
	var scene=load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.cycle_shooting_skill()
	check(scene.character.capabilities.skills.shooting==20,"K skill comparison did not select expert")
	scene.cycle_shooting_skill()
	check(scene.character.capabilities.skills.shooting==0,"K skill comparison did not select novice")
	scene.cycle_shooting_skill()
	check(scene.character.capabilities.skills.shooting==10 and not scene.character.training_enabled,"K failed to restore baseline without enabling persistent XP")
	scene.queue_free()
	await process_frame
	var report:Dictionary={"checks":checks,"failures":failures,"second_shot_climb":first_jump,"max_fps_difference_degrees":maximum_difference,"skills":results,"heavy":heavy}
	FileAccess.open("res://../.art-preview-local/active-recoil-verification.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ACTIVE_RECOIL: checks=",checks," failures=",failures," max_fps_difference=",maximum_difference)
	quit(0 if failures.is_empty() else 1)
