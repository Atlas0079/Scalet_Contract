class_name SCInterface
extends RefCounted


static func cards(g):
	if g.world == null:
		return
	for id in range(1, 5):
		var a = g.world.actor(id)
		var fresh = g.cards.get_child_count() < id
		var b = Button.new() if fresh else g.cards.get_child(id - 1)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		var action = "无计划 · 原地观察"
		if not a.alive:
			action = "阵亡"
		elif not a.queue.is_empty():
			var n = a.queue[0]
			action = SCPlanner.LABELS.get(n.kind, n.kind)
			if g.world.planner.tasks.has(n.task_id):
				var t = g.world.planner.tasks[n.task_id]
				action = (
					SCPlanner.STAGES.get(t.phase, t.phase)
					+ " · "
					+ g.world.grid.zones[t.draft.room].label
				)
		var injury = ""
		if (a.speed / 2.0) < 0.99:
			injury += "移动受限 "
		if a.capabilities.values.manipulation_rate < 0.99:
			injury += "操作受限 "
		if a.stunned > 0:
			injury += "震撼 "
		if not a.blocked_reason.is_empty():
			injury += "挂起 "
		b.text = (
			"%d / %s       %d / %d\n%s%s\n%.1f / %.1f kg   闪光 %d · 包扎 %d"
			% [
				id,
				a.actor_name,
				a.weapon.ammo,
				a.weapon.reserve_ammo,
				injury,
				action,
				g.world.loot.weight(a),
				a.capacity,
				a.available("flashbang"),
				a.available("bandage")
			]
		)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override(
			"normal", g.style(g.PANEL, g.ACCENT if id in g.selected else g.LINE)
		)
		if fresh:
			b.pressed.connect(
				func():
					if g.world.actor(id).alive:
						g.select_ids([id], Input.is_key_pressed(KEY_SHIFT))
			)
			b.gui_input.connect(
				func(event):
					if (
						event is InputEventMouseButton
						and event.pressed
						and event.button_index == MOUSE_BUTTON_RIGHT
						and not g.editing
					):
						g.set_focus("personal", id)
			)
			g.cards.add_child(b)


static func sidebar(g):
	var scroll = g.sidebar_scroll.scroll_vertical
	var s = g.sidebar
	g.clear(s)
	if g.world == null:
		return
	if g.editing:
		plan(g)
		return
	if g.draft != null:
		g.label(s, g.world.grid.zones[g.draft.room].label + " · 行动", 20, g.ACCENT)
		g.label(s, g.world.planner.task_label({"draft": g.draft}))
		g.label(s, "参与队员：" + str(g.draft.actors), 14, g.DIM)
		g.button(
			s,
			"立即下令",
			func():
				if g.draft.item != null and g.draft.landing == null:
					g.pick_mode = "quick_flash"
					g.status("在房间内左键选择闪光落点")
				else:
					g.submit_draft()
		)
		g.button(s, "编排站位", g.begin_edit)
		g.button(
			s,
			"返回",
			func():
				g.draft = null
				g.refresh_sidebar()
		)
		g.label(s, g.world.planner.takeover_text(g.draft.actors), 13, g.WARN)
		return
	if g.focus_kind in ["door", "room"]:
		g.label(
			s,
			"门口行动" if g.focus_kind == "door" else g.world.grid.zones[g.focus_id].label,
			20,
			g.ACCENT
		)
		g.label(s, "执行队员：" + str(g.selected), 14, g.DIM)
		for pair in [
			["直接突入", "direct"],
			["破门突入", "breach"],
			["闪光突入", "flash"],
			["门外集结", "stack"],
			["守住门口", "guarddoor"],
			["开门", "open"],
			["踹开", "kick"]
		]:
			g.button(s, pair[0], func(): g.choose_action(pair[1]))
		if g.focus_kind == "room":
			g.separator(s)
			g.button(
				s,
				"搜索物资 · 全员",
				func(): g.result(g.world.planner.submit_loot_task(g.selected, g.focus_id))
			)
			g.button(
				s,
				"搜索物资 · 最后一人警戒",
				func():
					g.result(
						g.world.planner.submit_loot_task(
							g.selected,
							g.focus_id,
							[g.selected.back()] if not g.selected.is_empty() else []
						)
					)
			)
			g.button(
				s,
				"定点警戒…",
				func():
					g.pick_mode = "guard_cell"
					g.status("左键选择警戒位置")
			)
	elif g.focus_kind == "loot":
		loot_panel(g)
	elif g.focus_kind == "inventory":
		inventory(g)
	else:
		actor_panel(g)
	if g.focus_kind != "actors":
		g.button(s, "返回队员指挥", func(): g.set_focus("actors"))
	g.sidebar_scroll.set_deferred("scroll_vertical", scroll)


static func actor_panel(g):
	var s = g.sidebar
	var w = g.world
	var ids = g.command_ids()
	g.label(
		s,
		(
			"战局概况"
			if ids.is_empty()
			else ("个人指挥 · %d 号" % g.personal_id if g.personal_id != null else "队员指挥 · " + str(ids))
		),
		20,
		g.ACCENT
	)
	for id in ids:
		var a = w.actor(id)
		if a == null:
			continue
		g.label(
			s,
			(
				"%d / %s · %s"
				% [id, a.actor_name, a.response if not a.response.is_empty() else a.fire_reason]
			),
			15
		)
		if not a.blocked_reason.is_empty():
			g.label(s, a.blocked_reason, 14, g.WARN)
		for index in range(a.queue.size()):
			var n = a.queue[index]
			var title = SCPlanner.LABELS.get(n.kind, n.kind)
			if w.planner.tasks.has(n.task_id):
				var t = w.planner.tasks[n.task_id]
				title = w.planner.task_label(t) + " · " + SCPlanner.STAGES.get(t.phase, t.phase)
				if t.phase == "blocked":
					g.label(s, t.reason, 14, g.WARN)
					g.button(s, "继续关联行动", func(): g.result(w.planner.retry_task(t.id)))
			elif n.status == "blocked":
				g.label(s, n.reason, 14, g.WARN)
				g.button(s, "继续此人计划", func(): g.result(w.planner.retry_node(a, n)))
			var h = g.row(s)
			var l = g.label(h, title, 13, g.DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.button(
				h,
				"×",
				func():
					w.planner.delete_node(a, index)
					g.refresh_sidebar(),
				w.planner.takeover_text([id])
			)
	if not ids.is_empty():
		g.separator(s)
		var h = g.row(s)
		g.button(h, "换弹 R", func(): g.batch_supply("reload"))
		g.button(h, "包扎 H", func(): g.batch_supply("bandage"))
		g.button(s, "闪光弹 G · 选择落点", g.begin_throw)
		g.button(
			s,
			"定点警戒 Q",
			func():
				g.pick_mode = "guard_cell"
				g.status("左键选择警戒位置，再选择朝向")
		)
		g.button(
			s,
			"调整朝向…",
			func():
				g.pick_mode = "face"
				g.status("左键指定观察方向")
		)
		g.button(
			s,
			"自由开火 / 保持停火",
			func():
				var hold = ids.any(func(id): return w.actor(id).fire_mode != "hold_fire")
				for id in ids:
					w.actor(id).fire_mode = "hold_fire" if hold else "aimed_shot"
				g.refresh_sidebar()
		)
		g.button(
			s,
			"取消计划并停步 X",
			func():
				w.planner.stop(ids)
				g.refresh_sidebar(),
			w.planner.takeover_text(ids)
		)
		g.button(s, "伤势与携带详情", func(): g.show_details(ids[0]))
		g.button(
			s,
			"携带物品 I",
			func():
				g.focus_id = ids[0]
				g.focus_kind = "inventory"
				g.refresh_sidebar()
		)
	for sync in ["A", "B"]:
		if not ids.is_empty():
			g.button(s, "等待同步 " + sync, func(): g.command("wait", {"sync": sync}))
		var entries = w.planner.sync_status(sync)
		if not entries.is_empty():
			var ready = entries.filter(func(e): return e[1]).size()
			g.button(
				s,
				"同步 %s · 就绪 %d/%d · 放行" % [sync, ready, entries.size()],
				func(): g.result(w.planner.release(sync))
			)
	var takeover = w.planner.takeover_text(ids)
	if not takeover.is_empty():
		g.label(s, takeover, 13, g.WARN)


static func plan(g):
	var s = g.sidebar
	var d = g.draft
	g.label(s, "编排 · " + g.world.grid.zones[d.room].label, 20, g.ACCENT)
	g.label(s, "已暂停 · 尚未下达", 14, g.DIM)
	var stages = g.row(s)
	for pair in [["门外准备", "stack"], ["进门就位", "entry"]]:
		g.button(
			stages,
			pair[0],
			func():
				g.plan_phase = pair[1]
				g.map_view.cancel_gesture()
				g.refresh_sidebar()
		)
	if d.item != null:
		g.button(
			s,
			"闪光落点",
			func():
				g.plan_phase = "flash"
				g.refresh_sidebar()
		)
	g.label(
		s, "当前：" + {"stack": "门外准备", "entry": "进门就位", "flash": "闪光落点"}[g.plan_phase], 14, g.ACCENT
	)
	for index in range(d.actors.size()):
		var id = d.actors[index]
		var h = g.row(s)
		var b = g.button(
			h,
			"%02d 号 · %s" % [id, g.world.actor(id).actor_name],
			func():
				g.plan_actor = id
				g.map_view.cancel_gesture()
				g.refresh_sidebar()
		)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if id == g.plan_actor:
			b.add_theme_stylebox_override("normal", g.style(Color("25473f"), g.ACCENT))
		for direction in [-1, 1]:
			var arrow = g.button(
				h,
				"↑" if direction < 0 else "↓",
				func():
					var order = g.draft.actors.duplicate()
					var other = index + direction
					order[index] = order[other]
					order[other] = id
					g.apply_draft(g.draft.duplicate(true), order)
			)
			arrow.disabled = index + direction < 0 or index + direction >= d.actors.size()
	g.button(s, "撤销 Ctrl+Z", g.undo_plan).disabled = g.undo_history.is_empty()
	g.button(s, "计划设置…", g.show_plan_settings)
	g.separator(s)
	g.label(s, "影响队员：" + str(d.actors), 14)
	g.label(
		s,
		(
			("追加计划" if g.plan_append else "替换计划")
			+ " · "
			+ ("同步 " + d.sync if d.sync != null else "无同步")
			+ " · "
			+ ("就位警戒" if d.after_entry == "hold" else "检查威胁")
		),
		14,
		g.DIM
	)
	g.label(s, g.world.planner.takeover_text(d.actors), 13, g.WARN)
	for id in d.actors:
		var a = g.world.actor(id)
		if not a.queue.is_empty():
			g.label(
				s,
				"%d 号旧行动：%s" % [id, SCPlanner.LABELS.get(a.queue[0].kind, a.queue[0].kind)],
				13,
				g.DIM
			)
	g.button(s, "下达计划", g.submit_draft)
	g.button(s, "退出 · 留草稿", g.save_draft)
	g.label(s, "下达后保持暂停，空格执行。", 13, g.DIM)


static func plan_settings(g):
	var box = g.open_modal("计划设置")
	g.label(box, "每次调整立即校验；不可执行的设置不会覆盖草稿。", 14, g.DIM)
	var h = g.row(box)
	for pair in [["直接突入", "direct"], ["破门突入", "breach"], ["闪光突入", "flash"]]:
		g.button(
			h,
			pair[0],
			func():
				var opts = g.draft.duplicate(true)
				opts.method = pair[1]
				opts.opening = null
				if pair[1] == "flash":
					opts.item = "flashbang"
					opts.thrower = null
				if g.apply_draft(opts):
					g.close_modal()
		)
	var ends = g.row(box)
	for pair in [["就位警戒", "hold"], ["检查威胁", "search"]]:
		g.button(
			ends,
			pair[0],
			func():
				var opts = g.draft.duplicate(true)
				opts.after_entry = pair[1]
				if g.apply_draft(opts):
					g.close_modal()
		)
	var sync_row = g.row(box)
	for sync in ["无同步", "A", "B"]:
		g.button(
			sync_row,
			sync,
			func():
				var opts = g.draft.duplicate(true)
				opts.sync = null if sync == "无同步" else sync
				if g.apply_draft(opts):
					g.close_modal()
		)
	var modes = g.row(box)
	for append in [false, true]:
		g.button(
			modes,
			"追加" if append else "替换",
			func():
				var opts = g.draft.duplicate(true)
				opts.append = append
				var result = g.world.planner.preview_task(
					g.draft.actors, g.draft.door, g.draft.room, g.draft.method, opts
				)
				if not result[1].is_empty():
					g.status(result[1], true)
				else:
					g.push_undo()
					g.plan_append = append
					g.draft = result[0]
					g.close_modal()
					g.refresh_sidebar()
		)
	g.label(box, "切换入口", 15)
	for e in g.world.grid.entrances.values():
		if g.draft.room not in [e.zone_a, e.zone_b]:
			continue
		g.button(
			box,
			e.id,
			func():
				if e.id == g.draft.door:
					g.close_modal()
					return
				var opts = g.draft.duplicate(true)
				opts.door = e.id
				opts.stack_overrides = {}
				opts.entry_overrides = {}
				opts.stack_angles = {}
				opts.entry_angles = {}
				opts.landing = null
				if g.apply_draft(opts):
					g.close_modal()
					g.map_view.focus_draft()
		)
	g.button(box, "返回编排", g.close_modal)


static func loot_panel(g):
	var s = g.sidebar
	var w = g.world
	var obj = w.loot.objects.get(g.focus_id)
	if obj == null:
		g.label(s, "物品已离开来源")
		return
	g.label(s, obj.name, 20, g.ACCENT)
	g.label(s, "已搜索" if obj.searched else "未搜索", 14, g.DIM)
	if obj.searched:
		g.button(s, "查看物品与分配", func(): g.open_loot(obj.id))
	else:
		g.label(s, "选择搜索者", 15)
		for id in g.selected:
			var a = w.actor(id)
			if a != null and a.alive:
				g.button(
					s,
					"%d 号 · %s 搜索" % [id, a.actor_name],
					func(): g.result(w.planner.submit([id], "loot_search", {"object_id": obj.id}))
				)
	for a in w.actors:
		if a.team != "red" or not a.alive:
			continue
		g.label(
			s,
			(
				"%d %s · 距离 %.1f\n负重 %.1f / 18 kg · 移动能力 %.0f%%"
				% [
					a.id,
					a.actor_name,
					a.position.distance_to(SCData.center(obj.cell)),
					w.loot.weight(a),
					(a.speed / 2.0) * 100
				]
			),
			14,
			g.DIM
		)
		var impact = w.planner.takeover_text([a.id])
		if not impact.is_empty():
			g.label(s, impact, 12, g.WARN)
		g.button(s, "%d 号详情" % a.id, func(): g.show_details(a.id))


static func open_loot(g, id: String):
	var obj = g.world.loot.objects.get(id)
	if obj == null or not obj.searched:
		return
	g.world.set_paused(true)
	g.loot_id = id
	g.loot_window.show()
	g.focus_kind = "loot"
	g.focus_id = id
	g.world.loot.notifications.erase(id)
	var source = g.world.loot.results.get(id)
	g.loot_actor = (
		source.actor_id
		if source != null and source.actor_id != null
		else (g.selected[0] if not g.selected.is_empty() else 1)
	)
	loot_window(g)
	g.refresh_sidebar()


static func loot_window(g):
	g.clear(g.loot_content)
	if g.loot_id == null:
		return
	var obj = g.world.loot.objects.get(g.loot_id)
	if obj == null:
		g.close_loot(false)
		return
	g.label(g.loot_content, obj.name, 18, g.ACCENT)
	g.label(g.loot_content, "双击：%d 号拿取 · 右键：改派 / 撤销" % g.loot_actor, 13, g.DIM)
	for item_id in obj.known:
		var i = obj.known[item_id]
		var old = g.world.loot.pickup_reservation(obj.id, item_id)
		var text = "%s ×%d · %.2f kg" % [SCLoot.item_name(i), i.quantity, SCLoot.item_weight(i)]
		if old[1] != null:
			text += " → %d 号" % old[1].actor_id
		var b = g.button(g.loot_content, text, func(): pass)
		b.clip_text = true
		b.tooltip_text = text
		b.gui_input.connect(
			func(event):
				if event is InputEventMouseButton and event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
						g.allocate_item(item_id, g.loot_actor)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						pickup_menu(g, item_id)
		)
	if obj.known.is_empty():
		g.label(g.loot_content, "已知搜空", 15, g.DIM)
	g.button(g.loot_content, "完成此处分配", func(): g.close_loot(true))
	if g.world.loot.results.size() > 1:
		g.button(g.loot_content, "仅查看下一处", func(): g.next_loot(false))
		g.button(g.loot_content, "完成此处并处理下一处", func(): g.next_loot(true))


static func pickup_menu(g, item_id: String):
	g.popup.clear()
	g.popup_actions.clear()
	var source = g.loot_id
	for a in g.world.actors:
		if a.team != "red" or not a.alive:
			continue
		var error = g.world.loot.allocation_error(source, {item_id: a.id})
		g.popup.add_item(
			"%d %s%s" % [a.id, a.actor_name, " · " + error if not error.is_empty() else ""],
			g.popup_actions.size()
		)
		g.popup.set_item_disabled(g.popup_actions.size(), not error.is_empty())
		g.popup_actions.append(func(): g.allocate_item(item_id, a.id))
	var old = g.world.loot.pickup_reservation(source, item_id)
	if old[0] != null:
		g.popup.add_item("撤销此件预约", g.popup_actions.size())
		g.popup_actions.append(
			func():
				g.world.loot.cancel_pickup(old[0])
				loot_window(g)
				g.refresh_sidebar()
		)
	g.popup.position = Vector2i(g.get_global_mouse_position())
	g.popup.popup()


static func inventory(g):
	var a = g.world.actor(g.focus_id)
	var s = g.sidebar
	if a == null:
		return
	g.label(s, "%d 号 · 携带物品" % a.id, 20, g.ACCENT)
	g.label(
		s,
		(
			"%.2f / %.0f kg\n已装备：%s · 弹匣 %d"
			% [g.world.loot.weight(a), a.capacity, a.weapon.definition.item.name, a.weapon.ammo]
		),
		14,
		g.DIM
	)
	var carried = g.world.loot.carried(a)
	for id in carried:
		var i = carried[id]
		g.label(s, "%s ×%d" % [SCLoot.item_name(i), i.quantity], 15)
		var h = g.row(s)
		g.button(
			h, "放下", func(): g.result(g.world.planner.submit([a.id], "loot_drop", {"cargo_id": id}))
		)
		if i.weapon != null:
			g.button(
				h,
				"装备",
				func(): g.result(g.world.planner.submit([a.id], "loot_equip", {"cargo_id": id}))
			)
	g.button(s, "伤势详情", func(): g.show_details(a.id))


static func ability_text(a) -> String:
	var result := SCAbilityRules.explain(a)
	var v: Dictionary = result.values
	var lines := PackedStringArray(["%s · %s" % [a.actor_name,a.definition.name],
		"移动 %.2f m/s · 力量 %.0f N · 负重 %.1f kg" % [v.move_speed_mps,v.force_n,v.carry_capacity_kg],
		"换弹 ×%.2f · 医疗 ×%.2f · 维修 ×%.2f" % [v.reload_rate,v.treatment_rate,v.repair_rate],
		"瞄准增长 %.2f /秒 · 稳定误差 水平 %.3f° / 垂直 %.3f°" % [v.aim_gain_per_second,v.aim_settled_degrees.x,v.aim_settled_degrees.y],
		"后坐冲量 ×%.2f · 回正 ×%.2f · 视距 %.1f m" % [v.recoil_kick_scale,v.recoil_recovery_scale,v.view_distance_m]])
	if a.control_mode=="sia": lines.append("SIA：%s · 同步 %.0f%% / 上限 %.0f%%" % [a.pilot.actor_name,v.sync_current*100,v.sync_ceiling*100])
	lines.append("\n有效技能（0–20）")
	for key in result.skills: lines.append("%s：%.2f" % [SCData.catalog.skills.definitions[key].name,result.skills[key]])
	lines.append("\n技能经验持有者")
	for entry in SCSkills.learners(a):
		lines.append("%s · 权重 %.0f%% · %s" % ["自学习芯片" if entry.holder.kind=="chip" else "意识",entry.weight*100,entry.holder.id])
		var xp := PackedStringArray()
		for key in entry.holder.xp: xp.append("%s %.1f" % [SCData.catalog.skills.definitions[key].name,entry.holder.xp[key]])
		lines.append(" / ".join(xp))
	lines.append("\n属性与能力贡献明细（包含失效来源）")
	var origins := {"innate":"天生","structural_part":"部件基础","part_bonus":"部件加成","training":"训练","equipment":"装备","drug":"药效","trait":"特质"}
	for entry in result.explanation.sources:
		lines.append("%s · %s · %s %.3f%s\n  持有者 %s\n  来源 %s" % [origins.get(entry.origin_kind,entry.origin_kind),entry.target_id,entry.operation,entry.value,"" if entry.reason.is_empty() else "（未生效：%s）" % entry.reason,entry.owner_id,entry.source_id])
	return "\n".join(lines)


static func ability_view(a) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(600,440)
	text.add_theme_font_size_override("normal_font_size",16)
	text.text = ability_text(a)
	return text


static func show_abilities(g, a):
	var box = g.open_modal("角色属性与技能 · 当前快照")
	box.add_child(ability_view(a))
	g.button(box,"返回伤势与携带",func(): g.show_details(a.id))


static func details(g, id: int):
	var a = g.world.actor(id)
	var box = g.open_modal("%d / %s · 伤势与携带" % [id, a.actor_name])
	g.button(box, "属性、技能与来源", func(): show_abilities(g, a))
	g.label(
		box,
		(
			"移动 %.2f m/s · 操作 ×%.2f · 视距 %.1f m\n携带 %.2f / %.0f kg · 弹药 %d / %d"
			% [
				a.speed,
				a.capabilities.values.manipulation_rate,
				a.view_distance,
				g.world.loot.weight(a),
				a.capacity,
				a.weapon.ammo,
				a.weapon.reserve_ammo
			]
		)
	)
	var regions = {}
	for region in a.body_definition.regions:
		regions[region.id] = region.name
	g.label(
		box,
		(
			"已装备：%s · 已预约携带 %.2f kg"
			% [a.weapon.definition.item.name, g.world.loot.reserved_weight(a.id)]
		),
		14,
		g.ACCENT
	)
	var body_grid = GridContainer.new()
	body_grid.columns = 2
	box.add_child(body_grid)
	for key in regions:
		g.label(body_grid, "%s：%.0f%%" % [regions[key], a.region_fraction(key) * 100], 15, g.WARN if a.region_fraction(key) < 1 else g.DIM).custom_minimum_size.x = 295
	for kind in ["flashbang", "bandage"]:
		g.label(
			box,
			(
				"%s · 可用 %d · 已安排 %d"
				% [
					SCData.catalog.loot_kinds[kind][0],
					a.available(kind),
					a.quantities.get(kind, 0) - a.available(kind)
				]
			),
			15
		)
	var carried = g.world.loot.carried(a) if a.alive else {}
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for item in carried.values():
		g.label(
			list,
			"%s ×%d · %.2f kg" % [SCLoot.item_name(item), item.quantity, SCLoot.item_weight(item)],
			14
		)
	if carried.is_empty():
		g.label(list, "没有额外携带物品" if a.alive else "装备已留在尸体，需到场回收", 14, g.DIM)
	g.button(box, "返回", g.close_modal)


static func pending(g):
	if not g.in_mission:
		return
	var box = g.open_modal("待分配物资")
	if g.world.loot.results.is_empty():
		g.label(box, "没有等待分配的物资。")
	for id in g.world.loot.results:
		if g.world.loot.objects.has(id):
			g.button(
				box,
				g.world.loot.objects[id].name,
				func():
					g.close_modal()
					g.open_loot(id)
			)
	g.button(box, "返回", g.close_modal)


static func events(g):
	if g.world == null:
		return
	var box = g.open_modal("近期事件")
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 400
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for index in range(g.world.events.size() - 1, -1, -1):
		var e = g.world.events[index]
		g.label(list, "%02d:%02d  %s" % [int(e[0]) / 60, int(e[0]) % 60, e[1]], 14)
	g.button(box, "返回", g.close_modal)


static func help(g):
	var box = g.open_modal("操作说明")
	(
		g
		. label(
			box,
			"左键 / Shift 左键：选择 / 增减队员；空地拖动框选\n1—4：选择；连按居中；Ctrl+A：全选\n右键地面：移动；拖出半格：指定移动朝向\n右键门：房间行动；Ctrl+右键区域：房间操作\n空格：暂停 / 执行；Tab：半速 / 常速\nWASD / 中键：平移；滚轮：缩放\nQ：警戒；R：换弹；H：包扎；G：闪光弹\nI：携带物品；L：待分配；X：取消计划\nF1 / F2：编组；Ctrl+F1 / F2：保存编组\nShift 下令：追加微操；宏观接管仍取消整组\n编排中 Ctrl+Z：撤销；Esc：逐层返回\nF12：截图，状态栏显示保存位置"
		)
	)
	g.button(
		box,
		"返回",
		func():
			if g.in_mission:
				g.close_modal()
			else:
				g.show_title()
	)


static func settings(g):
	var box = g.open_modal("设置")
	g.button(
		box,
		"地图显示器特效：" + ["关闭", "轻度", "标准"][g.effects],
		func():
			g.effects = (g.effects + 1) % 3
			g.map_view.material.set_shader_parameter("strength", float(g.effects))
			settings(g)
	)
	g.label(box, "音效音量")
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = g.volume * 100
	slider.value_changed.connect(func(v): g.volume = v / 100.0)
	box.add_child(slider)
	var contact = CheckButton.new()
	contact.text = "首次发现敌人自动暂停"
	contact.button_pressed = g.auto_contact
	contact.toggled.connect(
		func(v):
			g.auto_contact = v
			if g.world != null:
				g.world.auto_contact = v
	)
	box.add_child(contact)
	g.button(
		box,
		"返回",
		func():
			if g.in_mission:
				g.close_modal()
			else:
				g.show_title()
	)
	if g.in_mission:
		g.button(
			box,
			"重新开始行动",
			func():
				var confirmation = g.open_modal("重新开始行动")
				g.label(confirmation, "当前行动进度、物资安排和草稿将被清空。")
				g.button(confirmation, "确认重开", g.start_mission)
				g.button(confirmation, "返回", g.close_modal)
		)
		g.button(box, "返回标题", g.show_title)


static func result_panel(g):
	var w = g.world
	var box = g.open_modal("行动结果")
	g.label(
		box, "威胁已清除" if w.winner == "red" else "小队全灭", 24, g.ACCENT if w.winner == "red" else g.WARN
	)
	var survived = w.actors.filter(func(a): return a.team == "red" and a.alive).size()
	g.label(
		box,
		(
			"存活 %d / 4 · 行动 %02d:%02d\n己方射击 %d 发 · 误伤 %d 次 · 友军闪光震撼 %d 次"
			% [
				survived,
				int(w.time) / 60,
				int(w.time) % 60,
				w.stats.rounds,
				w.stats.friendly_hits,
				w.stats.friendly_stuns
			]
		)
	)
	if w.winner == "red":
		g.button(
			box,
			"继续搜索",
			func():
				w.continue_looting()
				g.close_modal()
		)
	g.button(box, "重新行动", g.start_mission)
	g.button(box, "返回标题", g.show_title)
