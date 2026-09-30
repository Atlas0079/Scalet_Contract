extends SceneTree
func _initialize():
	var failed=0
	for config in ["A","B","C"]:
		var w=SCWorld.new(config); var p=w.planner; var d=p.preview_task([1,2,3,4],"door_S_R","R","direct")[0]; p.submit_task(d)
		var started=Time.get_ticks_usec(); var worst=0; var samples=[]; var entered_corridor=false
		for i in range(3600):
			w.set_paused(false)
			var before=Time.get_ticks_usec(); w.update(1.0/60); var elapsed=Time.get_ticks_usec()-before; worst=maxi(worst,elapsed); samples.append(elapsed)
			for t in p.tasks.values():
				if t.phase=="blocked": p.retry_task(t.id)
			if p.tasks.is_empty() and not entered_corridor:
				var living=w.actors.filter(func(a): return a.alive and a.team=="red").map(func(a): return a.id)
				p.submit(living,"guard",{"cell":Vector2i(28,20),"angle":-PI/2}); entered_corridor=true
			if w.winner!=null: break
		samples.sort(); var seconds=(Time.get_ticks_usec()-started)/1000000.0
		print("BATTLE ",config," sim=",w.time,"s cpu=",seconds,"s tick p95=",samples[int(samples.size()*0.95)]/1000.0,"ms max=",worst/1000.0,"ms rounds=",w.stats.rounds," survivors=",w.actors.filter(func(a): return a.alive and a.team=="red").size()," enemies=",w.actors.filter(func(a): return a.alive and a.team=="blue").size()," tasks=",p.tasks.size())
		if w.stats.rounds==0: failed+=1
	print("LIVE BATTLE: ",failed," failures"); quit(0 if failed==0 else 1)
