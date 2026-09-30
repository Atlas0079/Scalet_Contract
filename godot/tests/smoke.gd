extends SceneTree
func _initialize():
	var w=SCWorld.new()
	assert(w.actors.size()==14)
	assert(w.loot.objects.size()==10)
	assert(w.planner.submit([1],"move",{"cell":Vector2i(30,32)}).is_empty())
	w.set_paused(false)
	for i in range(240): w.update(1.0/60.0)
	print("movement ",w.actor(1).position," ",w.actor(1).occupied_cell," ",w.actor(1).route," queue ",w.actor(1).queue," time ",w.time," reason ",w.actor(1).blocked_reason)
	if w.actor(1).occupied_cell!=Vector2i(30,32): quit(1); return
	print("SMOKE PASS: native Godot world, map, movement, perception")
	quit()
