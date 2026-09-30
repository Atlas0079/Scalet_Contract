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
	var folder:=ProjectSettings.globalize_path("res://../.art-preview-local/active-recoil-frames")
	DirAccess.make_dir_recursive_absolute(folder)
	for frame in range(156):
		if frame==12: scene.set_trigger(true,false)
		if frame==126: scene.set_trigger(false,false)
		scene.step(1.0/30,Vector2.ZERO)
		scene.title_label.text="冲量后坐 · 射击技能 10 · K 切换对比"
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png"%frame))
	print("ACTIVE_RECOIL_CAPTURE: ",scene.shots_fired," shots; 156 frames")
	quit()
