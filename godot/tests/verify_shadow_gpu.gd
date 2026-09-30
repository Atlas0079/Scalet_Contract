extends SceneTree

var failures: Array[String] = []

func _initialize(): call_deferred("verify")

func verify():
	var scene = load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.demo = false
	var mask := SubViewport.new()
	mask.size = Vector2i(104,104)
	mask.transparent_bg = true
	mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mask)
	var shadow := Sprite2D.new()
	shadow.position = Vector2(52,52)
	shadow.texture = scene.shadows[1].texture
	shadow.material = scene.shadows[1].material
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mask.add_child(shadow)
	var captures: Array[Image] = []
	var max_alpha_error := 0.0
	var occupied := 0
	for heading in [0.0, PI / 2.0]:
		scene.facing = heading
		scene.desired_facing = heading
		scene.target = scene.world_position + Vector2.from_angle(heading) * 3
		for frame in range(30):
			scene.step(1.0 / 60.0, Vector2.ZERO)
			await process_frame
			await RenderingServer.frame_post_draw
		for frame in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var source: Image = scene.views[1].get_texture().get_image()
		var rendered := mask.get_texture().get_image()
		captures.append(rendered)
		for y in range(104):
			for x in range(104):
				var alpha := source.get_pixel(x,y).a
				max_alpha_error = maxf(max_alpha_error, absf(rendered.get_pixel(x,y).a - alpha * 0.42))
				if alpha > 0.5: occupied += 1
	var changed := 0
	for y in range(104):
		for x in range(104):
			if absf(captures[0].get_pixel(x,y).a - captures[1].get_pixel(x,y).a) > 0.1: changed += 1
	if occupied < 200: failures.append("Empty silhouette")
	if max_alpha_error > 0.02: failures.append("Shadow alpha differs from animated silhouette")
	if changed < 100: failures.append("Shadow did not rotate with actor")
	var report := {"failures":failures, "occupied_pixels":occupied, "changed_pixels_at_90_degrees":changed, "max_alpha_error":max_alpha_error}
	FileAccess.open("res://../.art-preview-local/shadow-gpu-verification.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SHADOW_GPU: ", JSON.stringify(report))
	scene.queue_free()
	mask.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
