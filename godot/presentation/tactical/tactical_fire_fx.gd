extends RefCounted

# World-space effects shared by the 1x and 3x views of one character.
# No particles are parented to the moving character after emission.
const CELL := 40.0
var casing_settings: Dictionary
var flash_settings: Dictionary
var tracer_settings: Dictionary
var casings: Array[Dictionary] = []
var smoke: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var impacts: Array[Dictionary] = []
var targets: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
var hit_marks: Array[Dictionary] = []
var shooter_position := Vector2.ZERO
var selected_target_id := ""
var last_impact := "尚未射击"
var total_blocked := 0
var last_hit_height := -1.0
var reticle := {"valid": false}
var weapon_state: Dictionary
var total_hits := 0
var tracer_every: int
var bullet_speed: float
var tracer_length: float
var tracer_brightness: float
var bullet_range: float
var muzzle := Vector2.ZERO
var forward := Vector2.UP
var total_shots := 0
var total_ejected := 0
var total_landed := 0
var elapsed := 0.0
var rng := RandomNumberGenerator.new()
var paper_plane: Dictionary = {}
var paper_shots: Array[Dictionary] = []
var paper_sequence := 0

class View extends Node2D:
	var effects: RefCounted
	var ground := false
	var origin := Vector2.ZERO
	var pixels_per_cell := 40.0
	func _draw():
		if effects:
			if ground: effects.draw_ground(self, origin, pixels_per_cell)
			else: effects.draw_air(self, origin, pixels_per_cell)

func _init(weapon: Dictionary):
	configure(weapon)
	build_range()

func configure(weapon: Dictionary):
	weapon_state = weapon
	var presentation: Dictionary = SCData.catalog.presentation.weapons[weapon.definition.presentation]
	casing_settings = presentation.casings
	flash_settings = presentation.flash
	tracer_settings = SCData.catalog.presentation.tracers[weapon.ammunition.tracer_presentation]
	tracer_every = int(weapon.ammunition.tracer_every_n_shots)
	bullet_speed = SCData.projectile_speed(weapon)
	bullet_range = weapon.definition.range
	tracer_length = tracer_settings.length_m
	tracer_brightness = tracer_settings.brightness

func build_range():
	targets.clear()
	obstacles.clear()
	for spec in SCData.study.range.targets:
		targets.append({"id":spec.id, "label":spec.label, "position":SCCombat.pair(spec.position_m),
			"radius":float(SCData.study.target.radius_m), "height":float(SCData.study.target.height_m), "hits":0})
	for spec in SCData.study.range.obstacles:
		var box: Array = spec.rect_m
		obstacles.append({"id":spec.id, "label":spec.label, "kind":spec.kind,
			"rect":Rect2(box[0], box[1], box[2], box[3]), "height":float(spec.height_m)})

func target_by_id(id: String) -> Dictionary:
	for entry in targets:
		if entry.id == id: return entry
	return {}

func obstacle_hit(start: Vector3, end: Vector3) -> Dictionary:
	var result := {"fraction": 1.0, "id": "", "label": ""}
	for obstacle in obstacles:
		var rect: Rect2 = obstacle.rect
		var box := AABB(Vector3(rect.position.x, 0, rect.position.y), Vector3(rect.size.x, obstacle.height, rect.size.y))
		var hit := SCCombat.box_hit_fraction(start, end, box)
		if hit >= 0.0 and hit <= result.fraction:
			result = {"fraction":hit, "id":obstacle.id, "label":obstacle.label}
	return result

func clear_muzzle_origin(body: Vector3, muzzle_point: Vector3) -> Vector3:
	# An extended gun cannot spawn a bullet through the far side of a wall.
	var hit := obstacle_hit(body, muzzle_point)
	if hit.id.is_empty(): return muzzle_point
	return body.lerp(muzzle_point, minf(1.0, hit.fraction + 0.00001))

func clear():
	clear_paper()
	bullets.clear()
	impacts.clear()
	hit_marks.clear()
	last_impact = "尚未射击"
	for entry in targets: entry.hits = 0
	total_hits = 0
	total_blocked = 0
	last_hit_height = -1.0
	casings.clear()
	smoke.clear()
	flashes.clear()
	total_shots = 0
	total_ejected = 0
	total_landed = 0
	elapsed = 0.0

func clear_paper():
	paper_plane = {}
	paper_shots.clear()
	paper_sequence = 0


func prepare_paper(bullet: Dictionary, aim: Vector3):
	var start := Vector3(bullet.start.x,bullet.start_height,bullet.start.y)
	if paper_plane.is_empty():
		var normal := Vector2(aim.x-start.x,aim.z-start.z).normalized()
		if normal.length_squared()<.01: return
		paper_plane = {"center":aim,"normal":normal,"side":Vector2(-normal.y,normal.x),"target_id":selected_target_id,"distance":Vector2(aim.x-start.x,aim.z-start.z).length()}
	paper_sequence += 1
	var record := {"id":paper_sequence,"status":"flying","point":Vector2.ZERO,"distance":-1.0,"target_id":paper_plane.target_id}
	var normal:Vector2=paper_plane.normal
	var forward:Vector3=bullet.direction_3d
	var denominator:=Vector2(forward.x,forward.z).dot(normal)
	var offset:Vector3=paper_plane.center-start
	if denominator>.000001:
		record.distance=Vector2(offset.x,offset.z).dot(normal)/denominator
	if record.distance<=0:
		record.status="背向靶面"
	else:
		var intersection:Vector3=start+forward*record.distance
		var delta:Vector3=intersection-paper_plane.center
		record.point=Vector2(Vector2(delta.x,delta.z).dot(paper_plane.side),delta.y)
	paper_shots.append(record)
	if paper_shots.size()>120: paper_shots.pop_front()
	# Keep the record on the actual projectile, so birth-frame hits and later
	# collisions settle exactly once. Clearing the panel drops old references.
	bullet["paper_record"]=record


func settle_paper(bullet: Dictionary):
	if not bullet.has("paper_record"): return
	var record:Dictionary=bullet.paper_record
	if record.status!="flying": return
	if bullet.travelled+.00001>=record.distance:
		record.status="passed"
	elif bullet.get("hit_target_id","")==record.target_id and not record.target_id.is_empty():
		# The physical target is a cylinder. A real front-surface hit is projected
		# onto the same center plane so hits and near misses share one chart.
		record.status="hit"
	elif bullet.finished:
		record.status=bullet.get("stop_label","射程不足")


func emit_shot(socket: Vector3, port: Vector3, direction_3d: Vector3, right: Vector2, elapsed_since_shot := 0.0, paper_aim = null):
	total_shots += 1
	total_ejected += 1
	rng.seed = 71093 + total_shots * 193
	var direction := Vector2(direction_3d.x, direction_3d.z).normalized()
	forward = direction
	muzzle = Vector2(socket.x, socket.z)
	# Every shot exists, even if this ammunition only shows every Nth tracer.
	var bullet := SCCombat.projectile(socket, direction_3d, weapon_state)
	bullet.speed = bullet_speed
	bullet.range = bullet_range
	bullet.tracer_visible = (total_shots - 1) % tracer_every == 0
	if paper_aim != null: prepare_paper(bullet,paper_aim)
	advance_bullet(bullet, elapsed_since_shot)
	if bullet.afterglow < tracer_settings.fade_seconds: bullets.append(bullet)
	if bullets.size() > 128: bullets.pop_front()
	var flash := {"age": elapsed_since_shot, "scale": rng.randf_range(0.85, 1.2), "skew": rng.randf_range(-0.16, 0.16)}
	if flash.age < flash_settings.life_seconds: flashes.append(flash)
	var planar := right.rotated(rng.randf_range(-0.25, 0.25)) * rng.randf_range(casing_settings.ejection_min_mps, casing_settings.ejection_max_mps) + direction * rng.randf_range(-0.2, 0.1)
	var shell := {"id": total_ejected, "p": port, "v": Vector3(planar.x, rng.randf_range(0.75, 1.2), planar.y), "age": 0.0,
		"angle": rng.randf_range(-PI, PI), "spin": rng.randf_range(14, 23), "bounces": 0, "settled": false}
	advance_casing(shell, elapsed_since_shot)
	casings.append(shell)
	if casings.size() > int(casing_settings.maximum): casings.pop_front()
	if total_shots % 2 == 0:
		var drift := direction * 0.18 + Vector2(-0.09, -0.03)
		smoke.append({"p": muzzle + direction * 0.12 + drift * elapsed_since_shot, "v": drift, "age": elapsed_since_shot, "life": rng.randf_range(0.48, 0.70), "seed": rng.randf()})

func advance(delta: float):
	elapsed += delta
	advance_bullets(delta)
	for flash in flashes: flash.age += delta
	flashes = flashes.filter(func(f): return f.age < flash_settings.life_seconds)
	for puff in smoke:
		puff.age += delta
		puff.p += puff.v * delta
	smoke = smoke.filter(func(p): return p.age < p.life)
	for shell in casings: advance_casing(shell, delta)
	casings = casings.filter(func(c): return c.age < casing_settings.life_seconds)

func advance_casing(shell: Dictionary, delta: float):
	shell.age += delta
	if shell.settled: return
	var remaining := delta
	while remaining > 0.000001:
		var dt := minf(remaining, 1.0 / 240.0)
		remaining -= dt
		shell.p += shell.v * dt + Vector3.DOWN * (casing_settings.gravity_mps2 * 0.5) * dt * dt
		shell.v.y -= casing_settings.gravity_mps2 * dt
		shell.angle += shell.spin * dt
		if shell.p.y <= 0.0:
			shell.p.y = 0.0
			if shell.bounces == 0:
				shell.bounces = 1
				shell.v.y = -shell.v.y * 0.23
				shell.v.x *= 0.42
				shell.v.z *= 0.42
				shell.spin *= 0.3
			else:
				shell.settled = true
				shell.v = Vector3.ZERO
				total_landed += 1
				break

func advance_bullets(delta: float):
	for mark in hit_marks: mark.age += delta
	hit_marks = hit_marks.filter(func(m): return m.age < SCData.study.range.impact_lifetime_seconds)
	for impact in impacts: impact.age += delta
	impacts = impacts.filter(func(i): return i.age < 0.18)
	for bullet in bullets: advance_bullet(bullet, delta)
	bullets = bullets.filter(func(b): return b.afterglow < tracer_settings.fade_seconds)

func advance_bullet(bullet: Dictionary, delta: float):
	bullet.age += delta
	if bullet.finished:
		bullet.afterglow += delta
		return
	var distance := minf(bullet.speed * delta, bullet.range - bullet.travelled)
	var start: Vector2 = bullet.end
	var end: Vector2 = start + bullet.direction * bullet.horizontal_factor * distance
	var h0: float = bullet.height
	var h1: float = h0 + bullet.direction_3d.y * distance
	var best := 1.0
	var blocked := false
	var ground := SCCombat.ground_fraction(h0, h1)
	if ground >= 0.0:
		best = ground
		blocked = true
	var obstacle := obstacle_hit(Vector3(start.x, h0, start.y), Vector3(end.x, h1, end.y))
	var hit_label := "地面" if blocked else ""
	if not obstacle.id.is_empty() and obstacle.fraction <= best:
		best = obstacle.fraction
		blocked = true
		hit_label = obstacle.label
	var hit_target: Dictionary = {}
	for entry in targets:
		var t := SCCombat.cylinder_hit_fraction(start, end, h0, h1, entry.position, entry.position, entry.radius, 0.0, entry.height)
		if t >= 0.0 and (t < best or not blocked and t <= best):
			best = t
			blocked = false
			hit_target = entry
	if not hit_target.is_empty():
		total_hits += 1
		hit_target.hits += 1
		last_hit_height = lerpf(h0, h1, best)
		hit_label = hit_target.label
		bullet["hit_target_id"] = hit_target.id
	if not hit_target.is_empty() or blocked:
		bullet.finished = true
		bullet.blocked = blocked
		bullet["stop_label"] = hit_label+"截停"
		if blocked: total_blocked += 1
		var height := lerpf(h0, h1, best)
		last_impact = "%s · 弹高 %.2f m" % [hit_label, height]
		var impact_age := maxf(0.0, delta - distance * best / bullet.speed)
		var at := start.lerp(end, best)
		if impact_age < 0.18: impacts.append({"p": at, "age": impact_age})
		hit_marks.append({"p":at, "height":height, "blocked":blocked, "age":impact_age})
		if hit_marks.size() > int(SCData.study.range.maximum_impacts): hit_marks.pop_front()
	bullet.travelled += distance * best
	bullet.end = start.lerp(end, best)
	bullet.height = lerpf(h0, h1, best)
	if bullet.travelled >= bullet.range - 0.00001: bullet.finished = true
	settle_paper(bullet)
	if bullet.finished: bullet.afterglow += maxf(0.0, delta - distance * best / bullet.speed)

func point(world: Vector2, origin: Vector2, scale: float) -> Vector2:
	# Preserve the same pixel-sized marks in the enlarged inspection views.
	return origin + (world * CELL).round() * (scale / CELL)

func shell_alpha(shell: Dictionary) -> float:
	return 1.0 - smoothstep(casing_settings.fade_start_seconds, casing_settings.life_seconds, shell.age)

func draw_shell(canvas: CanvasItem, shell: Dictionary, origin: Vector2, scale: float):
	var pos := Vector2(shell.p.x, shell.p.z)
	if not shell.settled:
		pos += Vector2(-0.05, -0.065) * shell.p.y
	var center := point(pos, origin, scale)
	var half := Vector2.from_angle(shell.angle) * (1.15 * scale / CELL)
	var color := Color("b7a26a") if shell.settled else Color("eed5a0")
	color.a = shell_alpha(shell)
	canvas.draw_line(center - half, center + half, color, scale / CELL, false)

func draw_ground(canvas: CanvasItem, origin: Vector2, scale: float):
	for obstacle in obstacles:
		var rect := Rect2(point(obstacle.rect.position, origin, scale), obstacle.rect.size * scale)
		var color := Color("7c8072") if obstacle.kind == "wall" else Color("657869")
		canvas.draw_rect(rect, Color("172720"))
		canvas.draw_rect(rect.grow(-1.0 * scale / CELL), color)
		canvas.draw_rect(rect, Color("aab6a0"), false, scale / CELL)
		if scale == CELL:
			canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(-12, -8), "%s %.1fm" % [obstacle.label, obstacle.height], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("afc1ad"))
	for entry in targets:
		var target_center := point(entry.position, origin, scale)
		var color := Color("e1d29c") if entry.id == selected_target_id else Color("89aa98")
		canvas.draw_circle(target_center, entry.radius * scale, Color("263630"))
		canvas.draw_arc(target_center, entry.radius * scale, 0, TAU, 24, color, scale / CELL, false)
		canvas.draw_circle(target_center, 0.055 * scale, color)
		if scale == CELL:
			canvas.draw_string(ThemeDB.fallback_font, target_center + Vector2(-36, -17), entry.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
			canvas.draw_string(ThemeDB.fallback_font, target_center + Vector2(-36, 29), "距你 %.1fm · %d中" % [shooter_position.distance_to(entry.position), entry.hits], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	for mark in hit_marks:
		var color := Color("e69271") if mark.blocked else Color("e9d799")
		color.a = minf(1.0, (SCData.study.range.impact_lifetime_seconds - mark.age) / 1.5)
		var center := point(mark.p, origin, scale)
		canvas.draw_line(center - Vector2.ONE * scale / CELL, center + Vector2.ONE * scale / CELL, color, scale / CELL)
		canvas.draw_line(center + Vector2(-1, 1) * scale / CELL, center + Vector2(1, -1) * scale / CELL, color, scale / CELL)
	for shell in casings:
		if shell.settled:
			draw_shell(canvas, shell, origin, scale)
		else:
			var center := point(Vector2(shell.p.x, shell.p.z), origin, scale)
			canvas.draw_circle(center, 1.05 * scale / CELL, Color(0.03, 0.04, 0.025, shell_alpha(shell) * 0.35))
	for flash in flashes:
		var fade: float = pow(1.0 - flash.age / flash_settings.life_seconds, 2.0)
		var center := point(muzzle, origin, scale)
		for ring in range(5):
			canvas.draw_circle(center, lerpf(0.30, 0.07, ring / 4.0) * scale, Color(1.0, 0.75, 0.35, 0.025 * fade))

func flame_polygon(origin: Vector2, direction: Vector2, length: float, width: float, skew: float) -> PackedVector2Array:
	var side := direction.orthogonal()
	return PackedVector2Array([origin - direction * length * 0.08,
		origin + direction * length * 0.24 + side * width,
		origin + direction * length * 0.42 + side * width * 0.28,
		origin + direction * length + side * width * skew,
		origin + direction * length * 0.50 - side * width * 0.20,
		origin + direction * length * 0.15 - side * width * 0.85])

func draw_air(canvas: CanvasItem, origin: Vector2, scale: float):
	if reticle.has("center"):
		var aim_point:=point(reticle.center,origin,scale)
		canvas.draw_circle(aim_point,1.2*scale/CELL,Color("c3ddac"))
	if reticle.valid:
		var axis: Vector2 = reticle.axis
		var along := Vector2(-axis.y, axis.x)
		var color := Color("d8ad76").lerp(Color("c3ddac"), reticle.aim)
		var cap_width := minf(3.0 * scale / CELL, reticle.left.distance_to(reticle.right) * scale * 0.35)
		# Bracket separation is the actual lateral envelope at the aim plane.
		# Cap height is only a legibility mark; it does not represent altitude.
		for edge in [0, 1]:
			var p := point(reticle.left if edge == 0 else reticle.right, origin, scale)
			var inward := axis * (1.0 if edge == 0 else -1.0)
			var cap := along * 5.0 * scale / CELL
			canvas.draw_line(p - cap, p + cap, color, scale / CELL)
			canvas.draw_line(p - cap, p - cap + inward * cap_width, color, scale / CELL)
			canvas.draw_line(p + cap, p + cap + inward * cap_width, color, scale / CELL)
	for bullet in bullets:
		if not bullet.tracer_visible or bullet.travelled <= 0.0: continue
		var tail: Vector2 = bullet.end - bullet.direction * bullet.horizontal_factor * minf(tracer_length, bullet.travelled)
		var a := point(tail, origin, scale)
		var b := point(bullet.end, origin, scale)
		var alpha: float = tracer_brightness * (1.0 - bullet.afterglow / tracer_settings.fade_seconds)
		canvas.draw_line(a, b, Color(1.0, 0.65, 0.25, alpha * 0.19), 3.0 * scale / CELL, false)
		canvas.draw_line(a, b, Color(1.0, 0.88, 0.57, alpha), scale / CELL, false)
		canvas.draw_line(a.lerp(b, 0.65), b, Color(1.0, 0.98, 0.83, alpha), scale / CELL, false)
	for impact in impacts:
		var center := point(impact.p, origin, scale)
		var t: float = impact.age / 0.18
		for i in range(4):
			var ray := Vector2.from_angle(i * PI / 2.0 + 0.4)
			canvas.draw_line(center + ray * (0.03 + t * 0.07) * scale, center + ray * (0.09 + t * 0.12) * scale, Color(1.0, 0.87, 0.55, (1.0 - t) * 0.8), scale / CELL, false)
	for puff in smoke:
		var t: float = puff.age / puff.life
		var opacity := sin(t * PI) * 0.10
		var center := point(puff.p, origin, scale)
		# Nested, offset wisps soften the edge without a large opaque smoke disc.
		for layer in range(4):
			var radius := lerpf(0.045, 0.19, t) * (1.0 - layer * 0.18)
			var drift: Vector2 = Vector2(0.008 * layer, -0.006 * layer) * (0.6 + puff.seed)
			canvas.draw_circle(center + drift * scale, radius * scale, Color(0.65, 0.70, 0.64, opacity * 0.25))
			canvas.draw_circle(center + (Vector2(0.045, -0.03) - drift) * scale, radius * 0.62 * scale, Color(0.78, 0.77, 0.66, opacity * 0.11))
	for shell in casings:
		if not shell.settled: draw_shell(canvas, shell, origin, scale)
	for flash in flashes:
		var t: float = flash.age / flash_settings.life_seconds
		var center := point(muzzle, origin, scale)
		var size: float = flash.scale * (1.0 - t * 0.50)
		var alpha := 1.0 - smoothstep(0.45, 1.0, t)
		canvas.draw_colored_polygon(flame_polygon(center, forward, flash_settings.length_m * scale * size, flash_settings.width_m * scale * size, flash.skew), Color(1.0, 0.68, 0.24, alpha * 0.88))
		canvas.draw_colored_polygon(flame_polygon(center, forward, flash_settings.length_m * 0.64 * scale * size, flash_settings.width_m * 0.452 * scale * size, -flash.skew), Color(1.0, 0.90, 0.57, alpha))
		if flash.age < 0.027:
			canvas.draw_colored_polygon(flame_polygon(center, forward, flash_settings.length_m * 0.4 * scale, flash_settings.width_m * 0.37 * scale, 0), Color("fff7da"))
