extends Control

const BG = Color("071112")
const PANEL = Color("0c1c1e")
const LINE = Color("36585b")
const ACCENT = Color("9dffe3")
const TEXT = Color("dcf7ee")
const DIM = Color("819c99")
const WARN = Color("e8b86a")
var world: SCWorld
var in_mission = false
var selected: Array = [1, 2, 3, 4]
var groups = {KEY_F1: [1, 2], KEY_F2: [3, 4]}
var focus_kind = "actors"
var focus_id = null
var personal_id = null
var draft = null
var saved_draft = null
var editing = false
var plan_phase = "stack"
var plan_actor = 1
var plan_append = false
var undo_history: Array = []
var pick_mode = ""
var guard_cell = null
var room_pick = false
var speed = 1.0
var modal_open = false
var modal: Control
var map_view: SCMapView
var sidebar: VBoxContainer
var sidebar_scroll: ScrollContainer
var cards: HBoxContainer
var top: HBoxContainer
var pause_button: Button
var clock_label: Label
var mission_label: Label
var status_label: Label
var loot_button: Button
var draft_button: Button
var popup: PopupMenu
var popup_actions: Array = []
var loot_window: PanelContainer
var loot_content: VBoxContainer
var loot_id = null
var loot_actor = 1
var audio_players: Array = []
var audio_streams = {}
var volume = 0.5
var effects = 1
var auto_contact = false
var refresh_timer = 0.0
var sidebar_key = ""
var last_number = 0
var last_number_time = 0
var active_config = "A"
var screenshot_path = ""
var snapshot_count = 0


func style(fill: Color, border: Color = LINE) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


func _ready():
	if not SCData.ensure_valid(get_tree()): return
	var t = Theme.new()
	t.default_font = load("res://assets/NotoSansSC-Regular.ttf")
	t.default_font_size = 16
	for kind in ["Label", "Button", "CheckButton", "OptionButton", "PopupMenu"]:
		t.set_color("font_color", kind, TEXT)
	t.set_stylebox("normal", "Button", style(PANEL))
	t.set_stylebox("hover", "Button", style(Color("25473f"), ACCENT))
	t.set_stylebox("pressed", "Button", style(Color("25473f"), ACCENT))
	t.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), ACCENT))
	t.set_stylebox("disabled", "Button", style(BG))
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_stylebox("panel", "PanelContainer", style(PANEL))
	t.set_stylebox("panel", "PopupMenu", style(PANEL, ACCENT))
	theme = t
	get_window().min_size = Vector2i(1280, 720)
	build_layout()
	setup_audio()
	show_title()
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--capture" and i + 1 < args.size():
			screenshot_path = args[i + 1]
		if args[i] == "--config" and i + 1 < args.size():
			active_config = args[i + 1]
	if "--start" in args or not screenshot_path.is_empty():
		start_mission()


func label(parent: Node, text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func button(parent: Node, text: String, action: Callable, tip: String = "") -> Button:
	var b = Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size.y = 34
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func row(parent: Node) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	return h


func clear(parent: Node):
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func separator(parent: Node):
	parent.add_child(HSeparator.new())


func build_layout():
	var layout = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var top_panel = PanelContainer.new()
	layout.add_child(top_panel)
	top = row(top_panel)
	mission_label = label(top, "SC / 灰港档案室", 19, ACCENT)
	mission_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label = label(top, "00:00", 18, ACCENT)
	clock_label.custom_minimum_size.x = 82
	pause_button = button(top, "Ⅱ 暂停中", toggle_pause)
	pause_button.custom_minimum_size.x = 125
	button(top, "1 倍速", func(): speed = 0.5 if speed == 1 else 1.0).name = "Speed"
	button(top, "操作说明", show_help)
	button(top, "设置", show_settings)
	var main = HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	layout.add_child(main)
	var map_column = VBoxContainer.new()
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(map_column)
	var toolbar = row(map_column)
	button(
		toolbar,
		"房间操作",
		func():
			room_pick = true
			status("右键选择区域")
	)
	button(toolbar, "全图", func(): map_view.fit_map())
	button(toolbar, "返回原视野", func(): map_view.restore_camera())
	button(
		toolbar,
		"聚焦入口",
		func():
			if draft != null:
				map_view.focus_draft()
	)
	draft_button = button(toolbar, "恢复草稿", restore_draft)
	map_view = SCMapView.new()
	map_view.game = self
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.add_child(map_view)
	status_label = label(map_column, "", 14, DIM)
	status_label.custom_minimum_size.y = 32
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = 310
	main.add_child(panel)
	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 290
	panel.add_child(side)
	sidebar_scroll = ScrollContainer.new()
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(sidebar_scroll)
	sidebar = VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 8)
	sidebar_scroll.add_child(sidebar)
	separator(side)
	button(side, "近期事件", show_events)
	loot_button = button(side, "待分配 0 · L", show_pending)
	var bottom = PanelContainer.new()
	bottom.custom_minimum_size.y = 112
	layout.add_child(bottom)
	cards = row(bottom)
	popup = PopupMenu.new()
	add_child(popup)
	popup.id_pressed.connect(
		func(id):
			if id >= 0 and id < popup_actions.size():
				popup_actions[id].call()
	)
	loot_window = PanelContainer.new()
	loot_window.hide()
	loot_window.custom_minimum_size = Vector2(360, 320)
	loot_window.size = Vector2(360, 320)
	map_view.add_child(loot_window)
	var loot_scroll = ScrollContainer.new()
	loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	loot_window.add_child(loot_scroll)
	loot_content = VBoxContainer.new()
	loot_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_scroll.add_child(loot_content)


func setup_audio():
	for name in [
		"confirm", "door", "flash", "hit", "hover", "kick", "ready", "reject", "reload", "rifle"
	]:
		audio_streams[name] = load("res://assets/" + name + ".wav")
	for i in range(8):
		var player = AudioStreamPlayer.new()
		add_child(player)
		audio_players.append(player)


func play_sound(id: String):
	if not audio_streams.has(id) or volume <= 0:
		return
	for player in audio_players:
		if not player.playing:
			player.stream = audio_streams[id]
			player.volume_db = linear_to_db(volume)
			player.play()
			return


func start_mission():
	close_modal()
	world = SCWorld.new(active_config)
	world.auto_contact = auto_contact
	selected = [1, 2, 3, 4]
	focus_kind = "actors"
	focus_id = null
	personal_id = null
	draft = null
	saved_draft = null
	editing = false
	undo_history.clear()
	pick_mode = ""
	loot_id = null
	loot_window.hide()
	in_mission = true
	map_view.cancel_gesture()
	map_view.view_saved = null
	fit_initial_camera()
	refresh_sidebar()
	refresh_cards()
	status("开局暂停 · 右键门安排突入，右键黄色物资搜索 · 空格执行")


func fit_initial_camera():
	await get_tree().process_frame
	await get_tree().process_frame
	map_view.fit_map()


func show_title():
	in_mission = false
	var box = open_modal("SCARLET CONTRACT / 灰港档案室")
	label(box, "四人小队 · 实时战术指挥 · 自由暂停", 20, ACCENT)
	label(box, "确认未知区域，部署小队并执行行动。随时暂停，为队员调整路线、朝向和行动顺序。")
	var options = row(box)
	for config in ["A", "B", "C"]:
		button(
			options,
			"配置 " + config + (" · 已选" if config == active_config else ""),
			func():
				active_config = config
				show_title()
		)
	button(box, "开始行动", show_briefing)
	button(box, "操作说明", show_help)
	button(box, "设置", show_settings)
	button(box, "退出", func(): get_tree().quit())


func show_briefing():
	var box = open_modal("任务简报 · 配置 " + active_config)
	label(box, "四人从南侧进入。已知建筑布局，敌人位置需要观察确认。清除十名敌人后，可继续搜索场内物资。")
	label(box, "微操会接管关联行动；指挥其中一人会取消整组突入。\n分配只预约拿取，指定队员必须实际到场。", 16, WARN)
	button(box, "进入关卡", start_mission)
	button(box, "返回", show_title)


func open_modal(title: String) -> VBoxContainer:
	close_modal()
	modal_open = true
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 0)
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.custom_minimum_size.x = 630
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	label(box, title, 22, ACCENT)
	separator(box)
	return box


func close_modal():
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
	modal_open = false


func status(text: String, error: bool = false):
	status_label.text = text
	status_label.add_theme_color_override("font_color", WARN if error else DIM)
	if error:
		play_sound("reject")


func result(error: String):
	if not error.is_empty():
		status(error, true)
	elif world != null and not world.events.is_empty():
		status(world.events.back()[1])
	refresh_sidebar()
	refresh_cards()
	sidebar_key = ""


func command_ids() -> Array:
	return [personal_id] if personal_id != null else selected.duplicate()


func command(kind: String, options: Dictionary = {}):
	if in_mission and not editing:
		if not options.has("append"):
			options.append = Input.is_key_pressed(KEY_SHIFT)
		result(world.planner.submit(command_ids(), kind, options))


func select_ids(ids: Array, toggle: bool = false):
	map_view.cancel_gesture()
	if editing:
		if ids.size() == 1 and ids[0] in draft.actors:
			plan_actor = ids[0]
			refresh_sidebar()
		return
	pick_mode = ""
	guard_cell = null
	if toggle:
		for id in ids:
			if id in selected:
				selected.erase(id)
			else:
				selected.append(id)
	else:
		selected = ids.duplicate()
	selected.sort()
	personal_id = null
	focus_kind = "actors"
	focus_id = null
	draft = null
	refresh_sidebar()
	refresh_cards()


func set_focus(kind: String, id = null):
	map_view.cancel_gesture()
	pick_mode = ""
	guard_cell = null
	focus_kind = kind
	focus_id = id
	personal_id = id if kind == "personal" else null
	draft = null
	refresh_sidebar()
	refresh_cards()
	call_deferred("focus_sidebar")


func focus_sidebar():
	if modal_open:
		return
	for action in sidebar.find_children("*", "Button", true, false):
		if not action.disabled and action.is_visible_in_tree():
			action.grab_focus()
			break


func inspect_target(target: Dictionary):
	match target.kind:
		"actor":
			if world.actor(target.id).team == "red":
				set_focus("personal", target.id)
			else:
				command("attack", {"target_id": target.id})
		"door":
			set_focus("door", target.id)
		"loot":
			set_focus("loot", target.id)


func target_menu(targets: Array, at: Vector2):
	popup.clear()
	popup_actions.clear()
	for target in targets:
		popup.add_item(target.label, popup_actions.size())
		popup_actions.append(func(): inspect_target(target))
	popup.position = Vector2i(at)
	popup.popup()


func refresh_cards():
	SCInterface.cards(self)


func refresh_sidebar():
	SCInterface.sidebar(self)


func batch_supply(kind: String):
	var item = "rifle" if kind == "reload" else "bandage"
	var eligible = []
	var skipped = []
	for id in command_ids():
		var error = world.planner.item_error(world.actor(id), item, kind)
		if error.is_empty():
			eligible.append(id)
		else:
			skipped.append("%d 号：%s" % [id, error])
	if eligible.is_empty():
		status("；".join(skipped), true)
	else:
		result(world.planner.submit(eligible, kind, {"append": Input.is_key_pressed(KEY_SHIFT)}))


func begin_throw():
	var eligible = command_ids().filter(
		func(id): return world.planner.item_error(world.actor(id), "flashbang", "throw").is_empty()
	)
	if eligible.is_empty():
		status("所选队员没有可用闪光弹", true)
		return
	if eligible.size() == 1:
		personal_id = eligible[0]
		pick_mode = "throw"
		status("左键选择闪光落点 · 会震撼友军")
		return
	popup.clear()
	popup_actions.clear()
	for id in eligible:
		popup.add_item("%d 号投掷" % id, popup_actions.size())
		popup_actions.append(
			func():
				personal_id = id
				pick_mode = "throw"
				status("左键选择闪光落点")
		)
	popup.position = Vector2i(get_global_mouse_position())
	popup.popup()


func cancel_pick():
	if pick_mode == "quick_flash":
		draft = null
		refresh_sidebar()
	pick_mode = ""
	guard_cell = null
	status("已取消选点")


func map_pick(pos: Vector2):
	var c = SCData.cell_of(pos)
	match pick_mode:
		"face":
			for id in command_ids():
				result(
					world.planner.submit(
						[id],
						"face",
						{
							"angle": (pos - world.actor(id).position).angle(),
							"append": Input.is_key_pressed(KEY_SHIFT)
						}
					)
				)
			pick_mode = ""
		"throw":
			result(world.planner.submit(command_ids(), "throw", {"cell": c}))
			pick_mode = ""
		"guard_cell":
			if not world.grid.walkable(c):
				status("警戒位置不可通行", true)
				return
			guard_cell = c
			pick_mode = "guard_angle"
			status("左键指定警戒朝向")
		"guard_angle":
			command(
				"guard", {"cell": guard_cell, "angle": (pos - SCData.center(guard_cell)).angle()}
			)
			cancel_pick()
		"quick_flash":
			var opts = draft.duplicate(true)
			opts.landing = c
			opts.append = plan_append
			var fresh = world.planner.preview_task(
				draft.actors, draft.door, draft.room, draft.method, opts
			)
			if not fresh[1].is_empty():
				status(fresh[1], true)
				return
			draft = fresh[0]
			pick_mode = ""
			submit_draft()


func choose_action(method: String):
	var candidate = world.planner.choose_entrance(
		selected,
		focus_id if focus_kind == "door" else null,
		focus_id if focus_kind == "room" else null,
		method
	)
	if candidate == null:
		status(world.planner.entrance_error, true)
		return
	draft = candidate
	plan_actor = draft.actors[0]
	plan_phase = "stack"
	plan_append = false
	undo_history.clear()
	refresh_sidebar()


func begin_edit():
	editing = true
	world.set_paused(true)
	plan_phase = "stack"
	map_view.cancel_gesture()
	map_view.focus_draft()
	refresh_sidebar()
	status("编排 · 左键选队员，右键设置位置，右键拖动指定朝向")


func push_undo():
	undo_history.append({"draft": draft.duplicate(true), "append": plan_append})
	if undo_history.size() > 100:
		undo_history.pop_front()


func apply_draft(opts: Dictionary, order = null) -> bool:
	opts.append = plan_append
	var fresh = world.planner.preview_task(
		draft.actors if order == null else order,
		opts.get("door", draft.door),
		opts.get("room", draft.room),
		opts.get("method", draft.method),
		opts
	)
	if not fresh[1].is_empty():
		status(fresh[1], true)
		return false
	push_undo()
	draft = fresh[0]
	refresh_sidebar()
	return true


func edit_station(c: Vector2i, angle):
	var opts = draft.duplicate(true)
	var positions = "stack_overrides" if plan_phase == "stack" else "entry_overrides"
	var angles = "stack_angles" if plan_phase == "stack" else "entry_angles"
	opts[positions][plan_actor] = c
	if angle == null:
		opts[angles].erase(plan_actor)
	else:
		opts[angles][plan_actor] = angle
	apply_draft(opts)


func edit_landing(c: Vector2i):
	var opts = draft.duplicate(true)
	opts.landing = c
	apply_draft(opts)


func undo_plan():
	if not editing or undo_history.is_empty():
		return
	var previous = undo_history.pop_back()
	draft = previous.draft
	plan_append = previous.append
	refresh_sidebar()


func submit_draft():
	if draft == null:
		return
	var error = world.planner.submit_task(draft, plan_append)
	if not error.is_empty():
		status(error, true)
		return
	if editing:
		world.set_paused(true)
	draft = null
	saved_draft = null
	editing = false
	focus_kind = "actors"
	focus_id = null
	personal_id = null
	pick_mode = ""
	map_view.cancel_gesture()
	refresh_sidebar()
	refresh_cards()
	status("计划已下达 · " + ("空格执行" if world.paused else "正在执行"))


func save_draft():
	if draft != null:
		saved_draft = {"draft": draft.duplicate(true), "append": plan_append}
	draft = null
	editing = false
	pick_mode = ""
	focus_kind = "actors"
	map_view.cancel_gesture()
	refresh_sidebar()


func restore_draft():
	if saved_draft == null:
		return
	var d = saved_draft.draft
	var opts = d.duplicate(true)
	opts.append = saved_draft.append
	var fresh = world.planner.preview_task(d.actors, d.door, d.room, d.method, opts)
	if not fresh[1].is_empty():
		status("草稿暂不可恢复：" + fresh[1], true)
		return
	draft = fresh[0]
	plan_append = saved_draft.append
	plan_actor = draft.actors[0]
	begin_edit()


func show_plan_settings():
	SCInterface.plan_settings(self)


func open_loot(id: String):
	SCInterface.open_loot(self, id)


func build_loot_window():
	SCInterface.loot_window(self)


func close_loot(finish: bool):
	if loot_id != null and finish:
		world.loot.results.erase(loot_id)
		world.loot.notifications.erase(loot_id)
	loot_id = null
	loot_window.hide()
	world.set_paused(true)
	refresh_sidebar()


func allocate_item(item_id: String, id: int):
	result(world.loot.allocate(loot_id, {item_id: id}, false))
	build_loot_window()


func next_loot(finish: bool):
	var old = loot_id
	var ids = world.loot.results.keys()
	var index = ids.find(old)
	if finish:
		world.loot.results.erase(old)
		world.loot.notifications.erase(old)
	for offset in range(1, ids.size() + 1):
		var id = ids[(index + offset) % ids.size()]
		if id != old and world.loot.results.has(id):
			open_loot(id)
			return
	close_loot(finish)


func show_pending():
	SCInterface.pending(self)


func show_details(id: int):
	SCInterface.details(self, id)


func show_events():
	SCInterface.events(self)


func show_help():
	SCInterface.help(self)


func show_settings():
	SCInterface.settings(self)


func show_result():
	SCInterface.result_panel(self)


func toggle_pause():
	if not in_mission or modal_open:
		return
	popup.hide()
	if editing:
		status("编排中 · 请先下达计划或退出草稿")
		return
	if loot_window.visible:
		status("请先完成或关闭当前物资分配")
		return
	world.set_paused(not world.paused)


func _input(event):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F12:
		capture()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if popup.visible:
			popup.hide()
		elif modal_open:
			if in_mission:
				close_modal()
		elif map_view.right_start != null or map_view.left_start != null:
			map_view.cancel_gesture()
		elif not pick_mode.is_empty():
			cancel_pick()
		elif loot_window.visible:
			close_loot(true)
		elif editing:
			save_draft()
		elif draft != null:
			draft = null
			refresh_sidebar()
		elif focus_kind != "actors":
			set_focus("actors")
		else:
			select_ids([], false)
		get_viewport().set_input_as_handled()
		return
	if not in_mission or modal_open:
		return
	if event.keycode == KEY_SPACE:
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_TAB:
		speed = 0.5 if speed == 1 else 1.0
		get_viewport().set_input_as_handled()
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_4:
		var id = event.keycode - KEY_1 + 1
		var now = Time.get_ticks_msec()
		if editing:
			if id in draft.actors:
				plan_actor = id
				map_view.cancel_gesture()
				refresh_sidebar()
		elif world.actor(id).alive:
			select_ids([id], event.shift_pressed)
			if last_number == id and now - last_number_time < 350:
				map_view.focus_point(world.actor(id).position)
		last_number = id
		last_number_time = now
		get_viewport().set_input_as_handled()
		return
	if editing:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			undo_plan()
			get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_A:
		select_ids(
			(
				world
				. actors
				. filter(func(a): return a.team == "red" and a.alive)
				. map(func(a): return a.id)
			)
		)
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_F1, KEY_F2]:
		if event.ctrl_pressed:
			groups[event.keycode] = selected.duplicate()
		else:
			select_ids(groups[event.keycode].filter(func(id): return world.actor(id).alive))
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_R:
			batch_supply("reload")
		KEY_H:
			batch_supply("bandage")
		KEY_G:
			begin_throw()
		KEY_Q:
			pick_mode = "guard_cell"
			status("左键选择警戒位置，再选择朝向")
		KEY_X:
			world.planner.stop(command_ids())
			refresh_sidebar()
		KEY_I:
			var ids = command_ids()
			if not ids.is_empty():
				focus_kind = "inventory"
				focus_id = ids[0]
				refresh_sidebar()
		KEY_L:
			show_pending()
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta):
	if not in_mission or world == null:
		return
	if not modal_open and not loot_window.visible:
		world.update(delta * speed)
	var living = selected.filter(func(id): return world.actor(id) != null and world.actor(id).alive)
	if living != selected:
		selected = living
		refresh_sidebar()
		refresh_cards()
	for sound in world.audio_events:
		play_sound(sound)
	world.audio_events.clear()
	clock_label.text = "%02d:%02d" % [int(world.time) / 60, int(world.time) % 60]
	pause_button.text = "Ⅱ 暂停中" if world.paused else "▶ 运行中"
	top.get_node("Speed").text = "%s 倍速" % str(speed)
	mission_label.text = (
		"SC / 灰港档案室   配置 %s   消灭敌人 %d/10"
		% [
			world.config,
			world.actors.filter(func(a): return a.team == "blue" and not a.alive).size()
		]
	)
	draft_button.visible = saved_draft != null and not editing
	loot_button.text = "待分配 %d · L" % world.loot.results.size()
	if (
		not editing
		and not modal_open
		and not loot_window.visible
		and not world.loot.notifications.is_empty()
	):
		open_loot(world.loot.notifications[0])
	if loot_window.visible and world.loot.objects.has(loot_id):
		var anchor = map_view.to_screen(SCData.center(world.loot.objects[loot_id].cell))
		loot_window.position = Vector2(
			clampf(anchor.x + 24, 8, maxf(8, map_view.size.x - loot_window.size.x - 8)),
			clampf(
				anchor.y - loot_window.size.y * 0.5,
				8,
				maxf(8, map_view.size.y - loot_window.size.y - 8)
			)
		)
	refresh_timer += delta
	if refresh_timer >= 0.25:
		refresh_timer = 0.0
		refresh_cards()
		var state = [focus_kind, focus_id, selected, personal_id]
		for task in world.planner.tasks.values():
			state.append([task.id, task.phase, task.reason, task.ready, task.released])
		for id in range(1, 5):
			var a = world.actor(id)
			state.append([a.alive, a.response, a.fire_reason, a.blocked_reason, a.fire_mode])
			for n in a.queue:
				state.append([n.token, n.status, n.reason])
		var key = str(state)
		if key != sidebar_key and not editing and draft == null and not popup.visible:
			sidebar_key = key
			refresh_sidebar()
	if world.winner != null and not modal_open:
		show_result()
	if not screenshot_path.is_empty():
		snapshot_count += 1
		if snapshot_count == 8:
			capture(screenshot_path, true)


func capture(path: String = "", exit_after: bool = false):
	if path.is_empty():
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		path = "user://screenshots/capture-%d.png" % Time.get_unix_time_from_system()
	await RenderingServer.frame_post_draw
	var error = get_viewport().get_texture().get_image().save_png(path)
	status("截图已保存：" + ProjectSettings.globalize_path(path), error != OK)
	if exit_after:
		get_tree().quit(0 if error == OK else 1)
