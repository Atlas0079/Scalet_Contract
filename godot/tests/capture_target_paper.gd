extends SceneTree
func _initialize(): call_deferred("capture")
func capture():
	var scene=load("res://presentation/tactical/tactical.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.demo=false
	scene.choose_lane(1)
	scene.character.aim_progress=1
	for frame in range(105):
		if frame==12: scene.set_trigger(true,false)
		if frame==70: scene.set_trigger(false,false)
		scene.step(1.0/60,Vector2.ZERO)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../.art-preview-local/target-paper.png"))
	print("TARGET_PAPER_CAPTURE: ",scene.shots_fired)
	quit()
