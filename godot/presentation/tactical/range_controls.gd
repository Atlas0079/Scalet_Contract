extends RefCounted

# Presentation-only editors use the same capability sources and weapon instance
# as the simulation. The catalog remains the baseline for the next experiment.
var scene: Node2D
var actor_fields := {}
var weapon_fields := {}
var derived: Label
var render_info: Label
var syncing := false

func _init(owner: Node2D):
	scene = owner
	var abilities := panel(Vector2(24, 104), "01  角色能力", "种族转换后的通用能力")
	var gear := panel(Vector2(384, 104), "02  武器与弹药", "当前试验实例 · 修改后开始新一组")
	add_note(abilities, "角色模板 / P")
	scene.profile_button = add_button(abilities, "", scene.cycle_profile)
	add_note(abilities, "机器人由测试机师控制。\n以下输入沿用通用能力来源计算。")
	actor_fields.shooting = number(abilities, "射击技能 / 0–20", 0, 20, 1, edit_skill)
	actor_fields.force_n = number(abilities, "力量 / N", 50, 5000, 10, edit_actor.bind("force_n"))
	actor_fields.manipulation_rate = number(abilities, "精细操作 / 倍率", .05, 3, .05, edit_actor.bind("manipulation_rate"))
	actor_fields.identification_rate = number(abilities, "感知识别 / 倍率", .05, 3, .05, edit_actor.bind("identification_rate"))
	actor_fields.response_delay_seconds = number(abilities, "基础反应 / 秒", .01, 2, .01, edit_actor.bind("response_delay_seconds"))
	add_button(abilities, "恢复角色基准", restore_actor)
	add_note(abilities, "强弱对照：J 切换力量\n训练对照：K 切换技能\n修改只影响当前测试，不写入配置。")
	add_note(abilities, "实际射击能力", 26, "e0e2d2")
	derived = add_note(abilities, "")
	add_button(abilities, "查看完整能力来源 / F2", scene.show_abilities)
	add_note(gear, "武器模板 / V")
	scene.weapon_button = add_button(gear, "", scene.cycle_weapon)
	add_note(gear, "枪械后坐与机械散布", 26, "e0e2d2")
	for spec in [
		["interval", "射击间隔 / 秒", .04, 2, .01],
		["lateral", "左右随机冲量 / °/s", 0, 30, .1],
		["vertical", "上抬冲量 / °/s", 0, 60, .5],
		["support", "持枪支撑频率 / s⁻¹", .1, 15, .1],
		["spread_x", "枪械横向散布 / °", 0, 5, .05],
		["spread_y", "枪械纵向散布 / °", 0, 5, .05],
		["range", "射程 / m", 1, 100, 1]]:
		weapon_fields[spec[0]] = number(gear, spec[1], spec[2], spec[3], spec[4], edit_weapon.bind(spec[0]))
	add_note(gear, "弹药 · " + scene.character.weapon.ammunition.name, 26, "e0e2d2")
	for spec in [
		["speed", "弹丸速度 / m/s", 10, 1500, 10],
		["ammo_x", "弹药横向散布 / °", 0, 5, .05],
		["ammo_y", "弹药纵向散布 / °", 0, 5, .05]]:
		weapon_fields[spec[0]] = number(gear, spec[1], spec[2], spec[3], spec[4], edit_weapon.bind(spec[0]))
	add_button(gear, "恢复武器与弹药基准", restore_weapon)
	add_note(gear, "左右冲量由枪械提供范围；\n角色持枪能力决定实际冲量。\n测试场可持续供弹，换弹用于观察动作。")
	render_info = add_note(gear, "")
	sync_editors()

func panel(at: Vector2, title: String, subtitle: String) -> VBoxContainer:
	var backdrop := Panel.new()
	backdrop.position = at
	backdrop.size = Vector2(336, 1312)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182420")
	style.border_color = Color("354c40")
	style.set_border_width_all(1)
	backdrop.add_theme_stylebox_override("panel", style)
	scene.ui.add_child(backdrop)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(16, 16)
	scroll.size = Vector2(304, 1280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backdrop.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 16)
	scroll.add_child(contents)
	add_note(contents, title, 30, "e0e2d2")
	add_note(contents, subtitle, 20, "819b8d")
	return contents

func add_note(parent: Control, text: String, font_size := 22, color := "a6b9ae") -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", Color(color))
	parent.add_child(result)
	return result

func add_button(parent: Control, text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 48
	result.focus_mode = Control.FOCUS_NONE
	result.add_theme_font_size_override("font_size", 22)
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func number(parent: Control, title: String, low: float, high: float, step: float, callback: Callable) -> SpinBox:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	add_note(column, title, 22)
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.custom_minimum_size.y = 46
	input.add_theme_font_size_override("font_size", 24)
	input.get_line_edit().add_theme_font_size_override("font_size", 24)
	input.value_changed.connect(callback)
	input.get_line_edit().text_submitted.connect(func(_text): input.get_line_edit().release_focus())
	column.add_child(input)
	return input

func sync_editors():
	syncing = true
	for key in actor_fields:
		actor_fields[key].set_value_no_signal(scene.character.capabilities.skills.shooting if key == "shooting" else scene.character.capabilities.values[key])
	var w: Dictionary = scene.character.weapon
	var values := {"interval":w.definition.fire_interval, "lateral":w.definition.recoil.impulse_degrees_per_second[0],
		"vertical":w.definition.recoil.impulse_degrees_per_second[1], "support":w.definition.recoil.support_frequency,
		"spread_x":w.definition.accuracy_degrees[0], "spread_y":w.definition.accuracy_degrees[1],
		"range":w.definition.range, "speed":w.ammunition.speed_mps,
		"ammo_x":w.ammunition.accuracy_degrees[0], "ammo_y":w.ammunition.accuracy_degrees[1]}
	for key in weapon_fields: weapon_fields[key].set_value_no_signal(values[key])
	syncing = false
	refresh()

func edit_actor(value: float, key: String):
	if syncing: return
	scene.set_trigger(false, false)
	var actor: SCActor = scene.character
	var source_id: String = actor.identity + ":range_input:" + key
	actor.remove_source(source_id)
	actor.refresh_capabilities()
	var baseline: float = actor.capabilities.values[key]
	var entry := SCAbilityRules.contribution(key, "capability", key, value - baseline)
	var source := SCAbilityRules.source(source_id, "actor", actor.identity, "trait", "body", [entry])
	source.definition_id = "测试场通用能力输入"
	actor.sources.append(source)
	actor.refresh_capabilities()
	scene.reset_experiment()
	sync_editors()

func edit_skill(value: float):
	if syncing: return
	for entry in SCSkills.learners(scene.character): entry.holder.xp.shooting = value * value * 100.0
	scene.test_pilot.refresh_capabilities()
	scene.character.refresh_capabilities()
	scene.reset_experiment()
	sync_editors()

func edit_weapon(value: float, key: String):
	if syncing: return
	var w: Dictionary = scene.character.weapon
	match key:
		"interval": w.definition.fire_interval = value
		"lateral": w.definition.recoil.impulse_degrees_per_second[0] = value
		"vertical": w.definition.recoil.impulse_degrees_per_second[1] = value
		"support": w.definition.recoil.support_frequency = value
		"spread_x": w.definition.accuracy_degrees[0] = value
		"spread_y": w.definition.accuracy_degrees[1] = value
		"range": w.definition.range = value
		"speed": w.ammunition.speed_mps = value
		"ammo_x": w.ammunition.accuracy_degrees[0] = value
		"ammo_y": w.ammunition.accuracy_degrees[1] = value
	for unit in scene.units: unit.configure_weapon(w)
	scene.reset_experiment()
	sync_editors()

func restore_actor():
	for source in scene.character.sources.duplicate():
		if ":range_input:" in source.source_id or source.source_id.ends_with(":range_force"):
			scene.character.remove_source(source.source_id)
	for entry in SCSkills.learners(scene.character): entry.holder.xp.shooting = scene.character.initial_skills.shooting
	scene.test_pilot.refresh_capabilities()
	scene.character.refresh_capabilities()
	scene.force_index = 1
	scene.reset_experiment()
	sync_editors()

func restore_weapon():
	scene.character.weapon = SCData.weapon(scene.weapon_choices[scene.weapon_index])
	for unit in scene.units: unit.configure_weapon(scene.character.weapon)
	scene.reset_experiment()
	sync_editors()

func refresh():
	var v: Dictionary = scene.character.capabilities.values
	derived.text = "识别后坐  %.3f s\n建立补偿  %.3f s\n压枪上限  %.1f °/s²\n精细修正  %.2f s⁻¹\n提前预测  %.0f%%\n单次过补偿  %.2f°\n瞄准增速  %.2f /s\n稳定散布  ±%.2f / %.2f°" % [v.recoil_response_delay_seconds, v.recoil_compensation_build_seconds, v.recoil_control_acceleration, v.recoil_control_frequency, v.recoil_prediction_scale * 100, v.recoil_overshoot_degrees, v.aim_gain_per_second, v.aim_settled_degrees.x, v.aim_settled_degrees.y]
	render_info.text = "角色纹理 %d × %d\n2K 等比画布 · 4× MSAA" % [scene.views[0].size.x, scene.views[0].size.y]
