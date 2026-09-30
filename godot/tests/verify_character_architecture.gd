extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize(): call_deferred("verify")

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func bonus(actor, target: String, value: float, operation := "add", kind := "capability", scope := "body", id := "sample") -> Dictionary:
	var c := SCAbilityRules.contribution("effect",kind,target,value,"bonus",operation)
	var s := SCAbilityRules.source(actor.identity+":"+id,"actor",actor.identity,"drug",scope,[c])
	actor.sources.append(s)
	actor.refresh_capabilities()
	return s

func robot(reg: Dictionary, pilot, id: int):
	var r := SCActor.new(id,"robot","red",Vector2.ZERO,0,"test_operator",reg)
	r.configure_character("robot")
	r.bind_controller(pilot,{"connected":true,"quality":1.0,"latency":0.0,"sync_base":1.0,"sync_ceiling":1.0})
	return r

func verify():
	check(SCData.ensure_valid(self),"Configuration invalid")
	var a := SCActor.new()
	check(a.speed==2 and a.capacity==18 and a.capabilities.values.aim_gain_per_second==1.25,"Healthy human baseline changed")
	check(a.capabilities.values.aim_settled_degrees.is_equal_approx(Vector2(.2,.2)),"Baseline aim error changed")
	check(a.capabilities.is_read_only() and a.capabilities.values.is_read_only(),"Ability snapshot is writable")
	var before: Dictionary = a.consciousness.duplicate(true)
	var one := SCAbilityRules.explain(a)
	var two := SCAbilityRules.explain(a)
	check(one==two and before==a.consciousness,"Ability query has side effects")
	var base_sources := a.innate_sources.duplicate(true)
	a.consciousness.xp.shooting=40000.0
	a.refresh_capabilities()
	check(a.capabilities.values.aim_gain_per_second>1.25 and a.innate_sources==base_sources,"Skill did not improve ability independently")
	var temp := bonus(a,"shooting",-10,"add","skill")
	check(a.capabilities.skills.shooting==10 and a.consciousness.xp.shooting==40000,"Skill modifier changed XP")
	temp.ends_at=1.0
	a.refresh_capabilities(1.0)
	check(a.capabilities.skills.shooting==20 and a.consciousness.xp.shooting==40000,"Expiry lost permanent experience")
	a=SCActor.new()
	bonus(a,"force_n",100)
	bonus(a,"force_n",.2,"percent","capability","body","percent")
	bonus(a,"force_n",2,"factor","capability","body","factor")
	check(is_equal_approx(a.capabilities.values.force_n,2640),"Source operation order")
	var ordered: Dictionary=a.capabilities.values
	a.sources.reverse()
	a.sources.append(a.sources[0])
	a.refresh_capabilities()
	check(a.capabilities.values==ordered,"Order or duplicate reference changes result")
	a=SCActor.new()
	var weak:=bonus(a,"force_n",100)
	weak.contributions[0].stack_group="strength_drug"
	weak.contributions[0].stack_policy="exclusive"
	var strong:=bonus(a,"force_n",200,"add","capability","body","strong")
	strong.contributions[0].stack_group="strength_drug"
	strong.contributions[0].stack_policy="exclusive"
	strong.contributions[0].priority=2
	a.refresh_capabilities()
	check(a.capabilities.values.force_n==1200,"Exclusive sources both applied")
	a.remove_source(strong.source_id)
	check(a.capabilities.values.force_n==1100,"Suppressed source did not return")
	var reg:=SCSkills.registry()
	var pilot:=SCActor.new(1,"pilot","red",Vector2.ZERO,0,"test_operator",reg)
	pilot.consciousness.xp.shooting=0.0
	pilot.consciousness.xp.sia_control=40000.0
	var r=robot(reg,pilot,2)
	r.chip.xp.shooting=40000.0
	r.refresh_capabilities()
	check(r.capabilities.skills.shooting==14,"Robot chip must supply 70 percent")
	check(not r.states.has("stress") and not r.definition.attributes.has("muscle"),"Robot has human attributes")
	check(r.capabilities.permissions.can_aim,"Valid human controller cannot operate robot")
	var r_before:float=r.speed
	pilot.parts.left_thigh.hp=0
	pilot.refresh_capabilities()
	r.refresh_capabilities()
	check(r.speed==r_before,"Pilot leg injury directly reduced mechanical drive")
	pilot.consciousness.states.pain=1
	r.refresh_capabilities()
	check(r.capabilities.values.reload_rate<1.2,"Pilot pain did not affect controls")
	pilot.consciousness.states.pain=0
	r.parts.motor_left.hp=0
	r.refresh_capabilities()
	check(is_equal_approx(r.speed,1),"Robot drive damage applied more than once")
	r.parts.motor_right.hp=0
	r.refresh_capabilities()
	check(r.speed==0 and not r.capabilities.permissions.can_move,"Destroyed drives still move")
	var android:=SCActor.new(3,"android","red",Vector2.ZERO,0,"test_operator",reg)
	android.configure_character("android")
	android.consciousness.xp.shooting=40000.0
	android.consciousness.active=false
	check(android.bind_controller(pilot,{"connected":true,"quality":1.0,"latency":0.0,"sync_base":1.0,"sync_ceiling":1.0}),"Android SIA binding failed")
	check(android.capabilities.skills.shooting==6,"Android memory must supply 30 percent")
	check(not r.bind_controller(android,{"connected":true,"quality":1.0,"latency":0.0,"sync_base":1.0,"sync_ceiling":1.0}),"Nonhuman pilot accepted")
	bonus(android,"psi_capacity",100)
	check(android.capabilities.values.psi_capacity==0 and not android.capabilities.permissions.can_use_psionics,"Bonus bypassed species gate")
	var fresh=robot(reg,pilot,4)
	fresh.chip.xp.shooting=0.0
	var original:float=pilot.consciousness.xp.shooting
	check(SCSkills.award(fresh,"shooting",10,"shot-a"),"Experience event refused")
	check(pilot.consciousness.xp.shooting==original+3 and fresh.chip.xp.shooting==7,"XP assigned to wrong owner")
	check(not SCSkills.award(fresh,"shooting",10,"shot-a") and fresh.chip.xp.shooting==7,"Replayed experience event counted twice")
	fresh.training_enabled=false
	check(not SCSkills.award(fresh,"shooting",10,"preview") and fresh.chip.xp.shooting==7,"Preview writes persistent experience")
	var saved:Dictionary=fresh.chip
	fresh.chip={}
	var replacement=robot(reg,pilot,5)
	replacement.chip=saved
	replacement.refresh_capabilities()
	check(replacement.chip.xp.shooting==7 and is_same(saved,replacement.chip),"Recovered chip copied or lost its skills")
	check(not SCSkills.settle(reg,"psi","psionics",100,[{"holder":pilot.consciousness,"weight":1.0}]),"Unimplemented psionic XP granted")
	var world:=SCWorld.new()
	var person=world.actors[0]
	person.weapon.ammo=0
	check(world.start_action(person,"reload",person.weapon.definition.reload_time,"auto:test").is_empty(),"Reload start failed")
	world.update_action(person,.5)
	check(is_equal_approx(person.current_action.timer,.5),"Reload did not consume baseline work")
	bonus(person,"reload_rate",.5,"factor")
	world.update_action(person,.5)
	check(is_equal_approx(person.current_action.timer,.75),"Mid-action ability change did not change remaining work")
	var part_actor=robot(reg,pilot,6)
	var original_part:Dictionary=part_actor.parts.gripper_left.definition.duplicate(true)
	var enhanced:Dictionary=original_part.duplicate(true)
	enhanced.attributes.actuator_output=300.0
	var contribution:=SCAbilityRules.contribution("test","capability","force_n",100.0)
	contribution.stack_group="test_part_strength"
	SCData.catalog.attribute_sources["test_part"]={"name":"测试部件","origin_kind":"part_bonus","scope":"body","duration_seconds":null,"requires_functional":true,"durability_curve":[[0,0],[1,1]],"contributions":[contribution]}
	enhanced.bonus_sources=["test_part"]
	check(SCData.validate(SCData.catalog).is_empty(),"Valid part bonus configuration rejected")
	check(part_actor.replace_part("gripper_left",enhanced),"Replacement part rejected")
	check(is_equal_approx(part_actor.capabilities.values.force_n,2500),"Part base and bonus not both applied")
	var replaced_id:String=part_actor.parts.gripper_left.instance_id
	var malformed:Dictionary=enhanced.duplicate(true)
	malformed.attributes.actuator_output=-1
	check(not part_actor.replace_part("gripper_left",malformed) and part_actor.parts.gripper_left.instance_id==replaced_id,"Invalid replacement partially changed actor")
	check(part_actor.replace_part("gripper_left",original_part) and is_equal_approx(part_actor.capabilities.values.force_n,1800),"Removed part base or bonus survived replacement")
	var trace:=SCAbilityRules.explain(part_actor)
	check(trace.explanation.sources.all(func(s): return s.owner_id!=replaced_id),"Old part remains in source trace")
	SCData.catalog.attribute_sources.erase("test_part")
	var invalid_catalog:=SCData.catalog.duplicate(true)
	invalid_catalog.attribute_sources.guard_reaction.durability_curve=[[1,1],[0,0]]
	check(not SCData.validate(invalid_catalog).is_empty(),"Descending durability curve accepted")
	check(SCInterface.ability_text(part_actor).contains("自学习芯片") and SCInterface.ability_text(part_actor).contains(pilot.consciousness.id),"Inspector lost skill provenance")
	var guard:=SCActor.new(7,"guard","blue",Vector2.ZERO,0,"guard")
	check(guard.sources.is_empty() and guard.consciousness.sources.size()==2,"Controller trait is attached to body rather than consciousness")
	var trait_id:String=guard.consciousness.sources[1].source_id
	guard.configure_character("android")
	check(not SCAbilityRules.explain(guard).explanation.sources.any(func(s): return s.source_id==trait_id),"Consciousness trait leaked into another mind")
	guard.configure_character("human")
	check(is_equal_approx(guard.reaction_seconds,.65),"Restored consciousness lost its trait")
	guard.remove_source(trait_id)
	check(is_equal_approx(guard.reaction_seconds,.25),"Controller source removal failed")
	var medic:=SCActor.new()
	var medicine_before:float=medic.consciousness.xp.medicine
	medic.current_action={"type":"bandage","experience_id":"partial-treatment","timer":.75,"learners":SCSkills.learners(medic),"sia_learning":false}
	medic.current_action=null
	medic.current_action=null
	check(is_equal_approx(medic.consciousness.xp.medicine,medicine_before+.75),"Cancelled treatment did not settle actual work exactly once")
	var scene=load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var formal:=SCActor.new(99,"formal","red",Vector2.ZERO,0,"test_operator")
	check(scene.character.capabilities.values==formal.capabilities.values,"Test range and formal actor use different ability rules")
	scene.show_abilities()
	await process_frame
	check(scene.paused,"Inspector did not pause test range")
	if "--capture-abilities" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../.art-preview-local/character-abilities.png")
	for child in scene.get_children():
		if child is AcceptDialog: child.hide()
	await process_frame
	check(not scene.paused,"Inspector failed to restore pause state")
	scene.queue_free()
	await process_frame
	var report:Dictionary={"checks":checks,"failures":failures}
	FileAccess.open("res://../.art-preview-local/character-architecture-verification.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CHARACTER_ARCHITECTURE: ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
