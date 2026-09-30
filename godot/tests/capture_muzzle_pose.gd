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
	var folder:=ProjectSettings.globalize_path("res://../.art-preview-local/muzzle-pose-frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for frame in range(96):
		if frame<30: scene.character.aim_progress=0.0
		if frame==30: scene.set_trigger(true,false)
		if frame==72: scene.set_trigger(false,false)
		scene.step(1.0/30,Vector2.ZERO)
		scene.title_label.text="持枪晃动 · 未稳定瞄准" if frame<30 else ("持枪晃动 · 持续射击" if frame<72 else "持枪晃动 · 停火恢复")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png" % frame))
	print("MUZZLE_CAPTURE: ",scene.shots_fired," shots; 96 frames")
	quit()
