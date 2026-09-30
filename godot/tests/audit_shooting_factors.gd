extends SceneTree
func _initialize(): call_deferred("audit")
func audit():
	var rows=[]
	for level in [0,10,20]:
		var actor=SCActor.new(0,"audit","red",Vector2.ZERO,0,"test_operator")
		actor.training_enabled=false
		actor.consciousness.xp.shooting=level*level*100
		actor.refresh_capabilities()
		actor.aim_progress=1
		var rng=RandomNumberGenerator.new()
		rng.seed=71093
		var shots=[]
		var peak=0.0
		for millisecond in range(3001):
			if millisecond%100==0:
				SCCombat.mechanical_error(actor.weapon,rng)
				shots.append({"shot":millisecond/100+1,"pitch":actor.weapon.recoil_offset_degrees.y,"yaw":actor.weapon.recoil_offset_degrees.x,"compensation":actor.weapon.recoil_compensation})
				SCCombat.record_shot(actor,rng,false)
			SCCombat.advance_recoil(actor,.001)
			peak=maxf(peak,actor.weapon.recoil_offset_degrees.y)
		rows.append({"skill":level,"abilities":actor.capabilities.values,"shots":shots,"peak":peak})
	var file=FileAccess.open("res://../.art-preview-local/shooting-factor-snapshot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  "))
	for row in rows:
		print("SKILL ",row.skill," peak=",row.peak," first10=",row.shots.slice(0,10)," last=",row.shots.back())
	quit()
