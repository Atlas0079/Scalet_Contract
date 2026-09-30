class_name SCMapView
extends Control

const BG = Color("071112")
const LINE = Color("36585b")
const ACCENT = Color("9dffe3")
const TEXT = Color("dcf7ee")
const DIM = Color("819c99")
const WARN = Color("e8b86a")
const ENEMY = Color("ff796e")
var game
var zoom: float = 19.0
var camera: Vector2 = Vector2(24, 18)
var font: Font
var pan_start = null
var left_start = null
var right_start = null
var right_append = false
var left_toggle = false
var drag_phase: String = ""
var mouse_world: Vector2 = Vector2.ZERO
var preview: Dictionary = {}
var preview_key = []
var view_saved = null


func _ready():
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	font = load("res://assets/NotoSansSC-Regular.ttf")
	var display_material = ShaderMaterial.new()
	display_material.shader = load("res://presentation/display.gdshader")
	display_material.set_shader_parameter("strength", float(game.effects))
	material = display_material
	resized.connect(cancel_gesture)


func fit_map():
	zoom = clampf(minf(size.x / 50.0, size.y / 38.0), 12.0, 64.0)
	camera = Vector2(24, 18)
	queue_redraw()


func to_screen(p: Vector2) -> Vector2:
	return (p - camera) * zoom + size * 0.5


func to_world(p: Vector2) -> Vector2:
	return (p - size * 0.5) / zoom + camera


func focus_point(p: Vector2):
	camera = p
	queue_redraw()


func focus_draft():
	if view_saved == null:
		view_saved = [camera, zoom]
	camera = SCData.center(game.draft.inside)
	zoom = maxf(zoom, 32.0)
	queue_redraw()


func restore_camera():
	if view_saved != null:
		camera = view_saved[0]
		zoom = view_saved[1]
		view_saved = null
	queue_redraw()


func cancel_gesture():
	right_start = null
	left_start = null
	pan_start = null
	preview.clear()
	preview_key = []
	queue_redraw()


func actor_at(p: Vector2):
	var candidates = []
	for a in game.world.actors:
		if a.team == "blue" and not game.world.perception.player_visible.has(a.id):
			continue
		if a.alive and to_screen(a.position).distance_to(p) <= maxf(10.0, a.radius * zoom + 3):
			candidates.append(a)
	return null if candidates.is_empty() else candidates[0]


func targets_at(p: Vector2) -> Array:
	var world_pos = to_world(p)
	var targets = []
	var w = game.world
	for a in w.actors:
		if not a.alive or a.team == "blue" and not w.perception.player_visible.has(a.id):
			continue
		if to_screen(a.position).distance_to(p) <= maxf(10.0, a.radius * zoom + 3):
			targets.append(
				{
					"kind": "actor",
					"id": a.id,
					"label": "%s %s" % [str(a.id) if a.team == "red" else "敌人", a.actor_name]
				}
			)
	for id in w.grid.entrances:
		var e = w.grid.entrances[id]
		var center = (SCData.center(e.a) + SCData.center(e.b)) * 0.5
		var horizontal = e.a.y != e.b.y
		var delta = world_pos - center
		if (
			absf(delta.x) < (0.55 if horizontal else 0.24)
			and absf(delta.y) < (0.24 if horizontal else 0.55)
		):
			targets.append(
				{
					"kind": "door",
					"id": id,
					"label":
					"门 · " + w.grid.zones[e.zone_a].label + " / " + w.grid.zones[e.zone_b].label
				}
			)
	for obj in w.loot.objects.values():
		if (
			obj.discovered
			and to_screen(SCData.center(obj.cell)).distance_to(p) < maxf(11, zoom * 0.48)
		):
			targets.append({"kind": "loot", "id": obj.id, "label": obj.name})
	return targets


func _gui_input(event):
	if game == null or not game.in_mission or game.modal_open:
		return
	if event is InputEventMouseMotion:
		mouse_world = to_world(event.position)
		if pan_start != null:
			camera -= event.relative / zoom
		update_preview()
		queue_redraw()
	if event is InputEventMouseButton:
		grab_focus()
		mouse_world = to_world(event.position)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var before = to_world(event.position)
			zoom = clampf(
				zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), 12, 64
			)
			camera += before - to_world(event.position)
			accept_event()
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			pan_start = event.position if event.pressed else null
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if game.pick_mode != "":
					game.map_pick(mouse_world)
					accept_event()
					return
				if game.editing:
					var slots = (
						game.draft.stacks if game.plan_phase == "stack" else game.draft.entries
					)
					for id in slots:
						if (
							to_screen(SCData.center(slots[id])).distance_to(event.position)
							< maxf(10, zoom * 0.4)
						):
							game.plan_actor = id
							game.refresh_sidebar()
							return
					var a = actor_at(event.position)
					if a != null and a.id in game.draft.actors:
						game.plan_actor = a.id
						game.refresh_sidebar()
					return
				left_start = event.position
				left_toggle = event.shift_pressed
			elif left_start != null:
				if event.position.distance_to(left_start) > 5:
					var rect = Rect2(left_start, event.position - left_start).abs()
					var ids = []
					for a in game.world.actors:
						if a.team == "red" and a.alive and rect.has_point(to_screen(a.position)):
							ids.append(a.id)
					game.select_ids(ids, left_toggle)
				else:
					var a = actor_at(event.position)
					if a != null and a.team == "red":
						game.select_ids([a.id], left_toggle)
					else:
						game.select_ids([], false)
				left_start = null
				queue_redraw()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				right_append = event.shift_pressed
				if game.editing:
					if game.plan_phase == "flash":
						game.edit_landing(SCData.cell_of(mouse_world))
						return
					right_start = mouse_world
					drag_phase = game.plan_phase
					return
				if game.pick_mode != "":
					game.cancel_pick()
					return
				if event.ctrl_pressed or game.room_pick:
					var room = game.world.grid.zone_id(SCData.cell_of(mouse_world))
					if room != null:
						game.room_pick = false
						game.set_focus("room", room)
					return
				var targets = targets_at(event.position)
				if targets.size() > 1:
					game.target_menu(targets, get_global_mouse_position())
					return
				if targets.size() == 1:
					game.inspect_target(targets[0])
					return
				right_start = mouse_world
				drag_phase = "move"
				update_preview()
			elif right_start != null:
				var start = right_start
				right_start = null
				var delta = mouse_world - start
				var angle = delta.angle() if delta.length() >= 0.5 else null
				if game.editing:
					game.edit_station(SCData.cell_of(start), angle)
				else:
					game.command(
						"move_face" if angle != null else "move",
						{"cell": SCData.cell_of(start), "angle": angle, "append": right_append}
					)
				preview.clear()
				preview_key = []
				queue_redraw()


func _input(event):
	if event is InputEventMouseButton and not event.pressed:
		if not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
			if event.button_index == MOUSE_BUTTON_RIGHT:
				right_start = null
				preview.clear()
				preview_key = []
			if event.button_index == MOUSE_BUTTON_LEFT:
				left_start = null
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			pan_start = null


func update_preview():
	if game == null or game.editing or right_start == null:
		return
	var cell = SCData.cell_of(right_start)
	var ids = game.command_ids()
	var key = [ids, cell, right_append, game.world.grid.revision]
	if key == preview_key:
		return
	preview_key = key
	var result = game.world.planner.movement_targets(ids, cell, right_append)
	preview = {"assigned": result[0], "error": result[1], "paths": {}}
	for id in result[0]:
		preview.paths[id] = game.world.planner.path(
			game.world.actor(id),
			result[0][id],
			{
				"start":
				game.world.planner.origin(
					game.world.actor(id),
					game.world.planner.micro_append(game.world.actor(id), right_append)
				)
			}
		)


func _process(delta):
	if game == null or not game.in_mission:
		return
	if not game.modal_open and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var motion = Vector2(
			(
				float(Input.is_key_pressed(KEY_D))
				- float(Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_CTRL))
			),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		)
		camera += motion * 600.0 * delta / zoom
		camera.x = clampf(
			camera.x, 1 - size.x / (2 * zoom), game.world.grid.width - 1 + size.x / (2 * zoom)
		)
		camera.y = clampf(
			camera.y, 1 - size.y / (2 * zoom), game.world.grid.height - 1 + size.y / (2 * zoom)
		)
	queue_redraw()


func label_at(p: Vector2, text: String, color: Color = DIM, font_size: int = 14):
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func line_world(a: Vector2, b: Vector2, color: Color, width: float = 1.0):
	draw_line(to_screen(a), to_screen(b), color, width, true)


func arrow(p: Vector2, angle: float, color: Color, length: float = 1.0):
	var end = p + Vector2.from_angle(angle) * length
	line_world(p, end, color, 1.4)
	for side in [-0.55, 0.55]:
		line_world(end, end - Vector2.from_angle(angle + side) * 0.24, color, 1.2)


func marker(c: Vector2i, id: int, angle: float, color: Color):
	var p = SCData.center(c)
	var screen = to_screen(p)
	var r = zoom * 0.35
	draw_polyline(
		PackedVector2Array(
			[
				screen + Vector2(0, -r),
				screen + Vector2(r, 0),
				screen + Vector2(0, r),
				screen + Vector2(-r, 0),
				screen + Vector2(0, -r)
			]
		),
		color,
		1.4,
		true
	)
	label_at(screen + Vector2(-4, 5), str(id), TEXT, 15)
	arrow(p, angle, color)


func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if game == null or game.world == null:
		return
	var w = game.world
	var g = w.grid
	for c in g.zone_cells:
		var rect = Rect2(to_screen(Vector2(c)), Vector2.ONE * zoom)
		if not rect.intersects(Rect2(Vector2.ZERO, size)):
			continue
		if w.perception.visible_cells.has(c):
			draw_rect(rect, Color(0.61, 1.0, 0.89, 0.065))
		elif w.perception.explored.has(c):
			draw_rect(rect, Color(0.17, 0.28, 0.27, 0.12))
		if zoom >= 18:
			draw_rect(rect, Color(0.21, 0.35, 0.36, 0.13), false, 1.0)
	var ctrl = Input.is_key_pressed(KEY_CTRL) or game.room_pick
	var hovered_room = g.zone_id(SCData.cell_of(mouse_world))
	for room in g.zones:
		var r = g.zones[room].rect
		var rect = Rect2(
			to_screen(Vector2(r[0], r[1])), Vector2(r[2] - r[0] + 1, r[3] - r[1] + 1) * zoom
		)
		if ctrl and room == hovered_room:
			draw_rect(rect, Color(0.61, 1, 0.89, 0.07))
			draw_rect(rect, ACCENT, false, 1.0)
		var text_pos = rect.get_center() + Vector2(-30, -8)
		if ctrl or text_pos.distance_to(get_local_mouse_position()) > 85:
			label_at(text_pos, room + " / " + g.zones[room].label, DIM, 14)
		if w.room_checked.has(room):
			label_at(text_pos + Vector2(0, 18), "已检查威胁", ACCENT, 12)
	for c in g.cell_features:
		if not g.zone_cells.has(c):
			continue
		var f = g.cell_features[c]
		var rect = Rect2(to_screen(Vector2(c)) + Vector2.ONE * 3, Vector2.ONE * (zoom - 6))
		draw_rect(rect, LINE, false, 1.0)
		if f.height < 1.25:
			draw_line(rect.position, rect.end, LINE, 1, true)
		elif zoom > 22:
			draw_rect(rect.grow(-3), LINE, false, 1.0)
	var seen = {}
	for f in g.edge_features.values():
		if seen.has(f.id) or f.kind == "door":
			continue
		seen[f.id] = true
		var c = Vector2(f.cell)
		var start = c
		var end = c
		match f.direction:
			"N":
				end += Vector2(1, 0)
			"S":
				start += Vector2(0, 1)
				end += Vector2(1, 1)
			"E":
				start += Vector2(1, 0)
				end += Vector2(1, 1)
			"W":
				end += Vector2(0, 1)
		line_world(start, end, LINE, 2.0 if f.kind == "wall" else 1.0)
		if f.kind == "window":
			line_world(start.lerp(end, 0.15), start.lerp(end, 0.85), DIM, 1.0)
	for id in g.entrances:
		var e = g.entrances[id]
		var center = (SCData.center(e.a) + SCData.center(e.b)) * 0.5
		var tangent = Vector2(1, 0) if e.a.y != e.b.y else Vector2(0, 1)
		var state = w.perception.doors.get(id, "unknown")
		var color = WARN if state in ["locked", "unknown"] else ACCENT
		if state == "unknown":
			for i in range(4):
				line_world(
					center + tangent * (-0.5 + i * 0.25),
					center + tangent * (-0.38 + i * 0.25),
					color
				)
			label_at(to_screen(center) + Vector2(3, -5), "?", WARN)
		elif state == "broken":
			line_world(center - tangent * 0.5, center - tangent * 0.32, color, 2)
			line_world(center + tangent * 0.32, center + tangent * 0.5, color, 2)
		elif state == "open":
			var hinge = center - tangent * 0.5
			line_world(hinge, hinge + Vector2(e.b - e.a), color, 2)
		else:
			line_world(center - tangent * 0.5, center + tangent * 0.5, color, 2)
			if state == "locked":
				label_at(to_screen(center) + Vector2(3, -5), "锁", WARN)
	for obj in w.loot.objects.values():
		if not obj.discovered:
			continue
		var p = to_screen(SCData.center(obj.cell))
		var radius = zoom * 0.32
		var color = Color("ffe45c") if obj.kind == "ground" or not obj.opened else Color("927a2c")
		if obj.kind == "corpse":
			draw_line(p + Vector2(-radius, -radius), p + Vector2(radius, radius), color, 1.4, true)
			draw_line(p + Vector2(radius, -radius), p + Vector2(-radius, radius), color, 1.4, true)
		elif obj.kind == "ground":
			draw_colored_polygon(
				PackedVector2Array(
					[
						p + Vector2(0, -radius),
						p + Vector2(radius, radius),
						p + Vector2(-radius, radius)
					]
				),
				Color(color, 0.18)
			)
			draw_polyline(
				PackedVector2Array(
					[
						p + Vector2(0, -radius),
						p + Vector2(radius, radius),
						p + Vector2(-radius, radius),
						p + Vector2(0, -radius)
					]
				),
				color,
				1,
				true
			)
		else:
			draw_rect(Rect2(p - Vector2.ONE * radius, Vector2.ONE * radius * 2), color, false, 1.5)
		if obj.searched and obj.known.is_empty():
			label_at(p + Vector2(6, -5), "空", DIM, 12)
	for id in game.selected:
		var a = w.actor(id)
		if a == null:
			continue
		if a.alive:
			for angle in [a.facing - a.view_angle * 0.5, a.facing + a.view_angle * 0.5]:
				var end = (
					a.position + Vector2.from_angle(angle) * a.view_distance
				)
				var hit = g.raycast(a.position, end)
				line_world(a.position, a.position.lerp(end, hit[0]), Color(ACCENT, 0.16))
		var points = PackedVector2Array([to_screen(a.position)])
		for c in a.route:
			points.append(to_screen(SCData.center(c)))
		if points.size() > 1:
			draw_polyline(points, Color(ACCENT, 0.55), 1.0, true)
	if game.draft != null:
		var d = game.draft
		var slots = d.stacks if game.plan_phase == "stack" else d.entries
		var angles = d.stack_angles if game.plan_phase == "stack" else d.entry_angles
		for index in range(d.actors.size()):
			var id = d.actors[index]
			var angle = angles.get(
				id,
				(
					(d.angle if index < 3 else d.angle + PI)
					if game.plan_phase == "stack"
					else w.planner.room_angle(d.room, slots[id])
				)
			)
			marker(slots[id], id, angle, ACCENT if id == game.plan_actor else Color(ACCENT, 0.6))
		if d.landing != null:
			var p = to_screen(SCData.center(d.landing))
			draw_arc(p, zoom * 4, 0, TAU, 64, Color(WARN, 0.5), 1.0, true)
			draw_circle(p, 4, WARN)
	for a in w.actors:
		if not a.alive:
			continue
		if a.team == "blue" and not w.perception.player_raw.has(a.id):
			continue
		var p = to_screen(a.position)
		var radius = maxf(5, a.radius * zoom)
		var color = ACCENT if a.team == "red" else ENEMY
		if a.team == "blue" and not w.perception.player_visible.has(a.id):
			label_at(p, "?", WARN)
			continue
		if a.hit_flash > 0:
			color = TEXT
		if a.team == "red":
			draw_arc(p, radius, 0, TAU, 32, color, 1.7, true)
			label_at(p + Vector2(-4, 5), str(a.id), TEXT, 13)
		else:
			draw_polyline(
				PackedVector2Array(
					[
						p + Vector2(0, -radius),
						p + Vector2(radius, 0),
						p + Vector2(0, radius),
						p + Vector2(-radius, 0),
						p + Vector2(0, -radius)
					]
				),
				color,
				1.7,
				true
			)
		line_world(
			a.position, a.position + Vector2.from_angle(a.facing) * (a.radius + 0.32), color, 1.5
		)
		if a.id in game.selected:
			draw_rect(
				Rect2(p - Vector2.ONE * (radius + 5), Vector2.ONE * (radius + 5) * 2),
				ACCENT,
				false,
				1.0
			)
		if a.current_action != null:
			var action = a.current_action
			var progress = clampf(action.timer / maxf(0.001, action.duration), 0, 1)
			draw_rect(Rect2(p + Vector2(-20, -radius - 12), Vector2(40, 3)), LINE)
			draw_rect(Rect2(p + Vector2(-20, -radius - 12), Vector2(40 * progress, 3)), color)
		if a.stunned > 0:
			label_at(p + Vector2(8, -10), "震撼", WARN, 12)
		elif not a.blocked_reason.is_empty():
			label_at(p + Vector2(8, -10), "!", WARN, 16)
	for shot in w.shots:
		if shot.team == "red" or w.perception.player_visible.has(shot.shooter_id):
			if shot.tracer_visible:
				var tail: Vector2 = shot.end - shot.direction * shot.horizontal_factor * minf(shot.tracer_length, shot.travelled)
				var alpha: float = shot.tracer_brightness * (shot.timer / shot.duration if shot.finished else 1.0)
				line_world(tail, shot.end, Color(Color("ffe091"), alpha), 1.5)
	for sound in w.sounds:
		if sound.audible and sound.team != "red":
			var p = to_screen(Vector2(sound.area) + Vector2(1.5, 1.5))
			draw_arc(
				p,
				(2 - sound.timer) * zoom * 0.75,
				0,
				TAU,
				32,
				Color(WARN, sound.timer / 5),
				1.0,
				true
			)
	for explosion in w.explosions:
		if w.perception.visible_cells.has(SCData.cell_of(explosion.position)):
			draw_arc(
				to_screen(explosion.position),
				explosion.radius * zoom * (1 - explosion.timer / 0.45),
				0,
				TAU,
				64,
				Color(TEXT, explosion.timer),
				2,
				true
			)
	for projectile in w.projectiles:
		var progress = clampf(
			(w.time - projectile.release) / (projectile.explode_at - projectile.release), 0, 1
		)
		var point = projectile.start.lerp(projectile.end, progress)
		if projectile.team == "red" or w.perception.visible_cells.has(SCData.cell_of(point)):
			draw_circle(to_screen(point) + Vector2(0, -sin(progress * PI) * zoom * 0.6), 3, WARN)
	if game.loot_window.visible and w.loot.objects.has(game.loot_id):
		var anchor = to_screen(SCData.center(w.loot.objects[game.loot_id].cell))
		draw_line(
			anchor,
			game.loot_window.position + Vector2(0, game.loot_window.size.y * 0.5),
			WARN,
			1.0,
			true
		)
	if right_start != null:
		var delta = mouse_world - right_start
		var angle = delta.angle() if delta.length() >= 0.5 else null
		if game.editing:
			marker(
				SCData.cell_of(right_start),
				game.plan_actor,
				angle if angle != null else game.draft.angle,
				WARN
			)
		elif not preview.is_empty():
			for id in preview.assigned:
				var points = PackedVector2Array()
				for c in preview.paths[id]:
					points.append(to_screen(SCData.center(c)))
				if points.size() > 1:
					draw_polyline(points, ACCENT, 1, true)
				marker(
					preview.assigned[id],
					id,
					angle if angle != null else game.world.actor(id).facing,
					ACCENT
				)
			if not preview.error.is_empty():
				label_at(to_screen(right_start) + Vector2(12, -12), preview.error, WARN, 15)
	if left_start != null and get_local_mouse_position().distance_to(left_start) > 5:
		draw_rect(
			Rect2(left_start, get_local_mouse_position() - left_start).abs(), Color(ACCENT, 0.1)
		)
		draw_rect(
			Rect2(left_start, get_local_mouse_position() - left_start).abs(), ACCENT, false, 1.0
		)
