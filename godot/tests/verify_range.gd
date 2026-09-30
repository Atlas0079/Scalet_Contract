extends SceneTree

const FX = preload("res://presentation/tactical/tactical_fire_fx.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize():
	call_deferred("verify")

func shoot_lane(index: int, fps: float, origin_height := 1.25, aim_height := 1.25):
	var fx = FX.new(SCData.weapon("test_carbine"))
	var lane: Dictionary = SCData.study.range.lanes[index]
	var spawn := SCCombat.pair(lane.spawn_m)
	var target: Vector2 = fx.target_by_id(lane.target).position
	var origin := Vector3(spawn.x, origin_height, spawn.y)
	var direction := (Vector3(target.x, aim_height, target.y) - origin).normalized()
	fx.emit_shot(origin, origin, direction, Vector2.DOWN)
	for frame in range(ceili(fps * 0.08)): fx.advance(1.0 / fps)
	return fx

func verify():
	check(SCData.ensure_valid(self), "Configuration failed")
	for fps in [20.0, 30.0, 60.0, 144.0]:
		for lane in range(8):
			var fx = shoot_lane(lane, fps)
			var blocked := lane in [5, 6]
			check(fx.total_hits == (0 if blocked else 1), "Lane %d at %s fps: target result" % [lane, fps])
			check(fx.total_blocked == (1 if blocked else 0), "Lane %d at %s fps: obstacle result" % [lane, fps])
			check(fx.target_by_id(SCData.study.range.lanes[lane].target).hits == (0 if blocked else 1), "Per-target count")
			check(fx.hit_marks.size() == 1 and absf(fx.hit_marks[0].height - 1.25) < 0.0001, "Impact altitude / mark")
			if blocked: check(absf(fx.hit_marks[0].p.x - 21.0) < 0.0001, "Wall hit skipped front surface")
	check(shoot_lane(4, 60, 0.65, 0.65).total_blocked == 1, "Low cover did not stop low shot")
	check(shoot_lane(5, 60, 1.25, 1.65).total_hits == 1, "Elevated aim did not clear high cover")
	check(shoot_lane(6, 60, 1.25, 1.65).total_blocked == 1, "High aim passed full wall")
	var close_fx = FX.new(SCData.weapon("test_carbine"))
	var clipped: Vector3 = close_fx.clear_muzzle_origin(Vector3(20.65, 1.25, 1.2), Vector3(21.5, 1.25, 1.2))
	check(clipped.x >= 21 and clipped.x < 21.001, "Gun crossing wall was not clipped")
	close_fx.emit_shot(clipped, clipped, Vector3.RIGHT, Vector2.DOWN)
	close_fx.advance(0.05)
	check(close_fx.total_blocked == 1 and close_fx.total_hits == 0, "Muzzle bypassed wall")
	var nearest = FX.new(SCData.weapon("test_carbine"))
	nearest.targets.append({"id":"near", "label":"前靶", "position":Vector2(1.5,-3.6), "radius":0.23, "height":1.8, "hits":0})
	nearest.emit_shot(Vector3(0,1.25,-3.6), Vector3.ZERO, Vector3.RIGHT, Vector2.DOWN)
	nearest.advance(0.05)
	check(nearest.target_by_id("near").hits == 1 and nearest.target_by_id("open_3").hits == 0, "Far target intercepted nearer target")
	nearest.advance(9.0)
	check(nearest.hit_marks.is_empty(), "Impact marks never expired")
	var scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	for i in range(8):
		scene.choose_lane(i)
		check(scene.world_position.is_equal_approx(SCCombat.pair(SCData.study.range.lanes[i].spawn_m)), "Station spawn incorrect")
		check(scene.target.is_equal_approx(scene.units[0].effects.target_by_id(SCData.study.range.lanes[i].target).position), "Station aim incorrect")
	var stopped: Vector2 = scene.move_in_range(Vector2(18,1.2), Vector2(6,0))
	check(stopped.x < 21 - scene.character.radius and stopped.x > 20.5, "Character passed wall")
	var slid: Vector2 = scene.move_in_range(stopped, Vector2(1,0.25))
	check(absf(slid.y - stopped.y - 0.25) < 0.0001 and slid.x < 20.7, "Wall slide stuck")
	check(scene.move_in_range(Vector2(18,3.6), Vector2(6,0)).distance_to(Vector2(24,3.6)) < 0.0001, "Character cannot pass gap")
	check(scene.move_in_range(Vector2(18,-3.6), Vector2(6,0)).x < 20.7, "Character passed low cover")
	for i in range(2):
		check(scene.shadows[i].texture == scene.sprites[i].texture, "Shadow texture differs from current animated sprite")
		check(scene.zoom_shadows[i].texture == scene.zoom_sprites[i].texture, "Zoom shadow texture differs")
		check((scene.shadows[i].position - scene.sprites[i].position).is_equal_approx(Vector2(3,4)), "Shadow offset")
	scene.toggle_style()
	check(scene.shadows[scene.visible_style].visible and not scene.shadows[1-scene.visible_style].visible, "Shadow style visibility")
	scene.units[0].effects.target_by_id("open_3").hits = 2
	scene.select_lane(0)
	check(scene.units[0].effects.target_by_id("open_3").hits == 2, "Changing lane erased counts")
	scene.reset()
	check(scene.units[0].effects.target_by_id("open_3").hits == 0, "Reset retained counts")
	var problems := PackedStringArray()
	var broken: Dictionary = SCData.study.range.duplicate(true)
	broken.lanes[0].target = "missing"
	SCData.validate_range(broken, problems)
	check(not problems.is_empty(), "Invalid target reference accepted")
	scene.queue_free()
	await process_frame
	var report := {"checks":checks, "failures":failures, "tested_fps":[20,30,60,144], "lanes":8}
	FileAccess.open("res://../.art-preview-local/range-verification.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RANGE: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
