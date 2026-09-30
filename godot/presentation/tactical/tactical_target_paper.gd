extends Control

signal clear_requested
const PLOT := Rect2(44, 112, 296, 296)
const SCALES := [25, 50, 100, 200, 500]
var scale_index := 2
var effects: RefCounted
var scale_button: Button

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	var clear_button := Button.new()
	clear_button.text = "清空弹着 / 新一组"
	clear_button.position = Vector2(16, 674)
	clear_button.size = Vector2(164, 36)
	clear_button.pressed.connect(func(): clear_requested.emit())
	add_child(clear_button)
	scale_button = Button.new()
	scale_button.position = Vector2(188, 674)
	scale_button.size = Vector2(160, 36)
	scale_button.pressed.connect(func():
		scale_index = (scale_index + 1) % SCALES.size()
		update_scale())
	add_child(scale_button)
	update_scale()

func update_scale():
	scale_button.text = "量程 ±%d cm" % SCALES[scale_index]
	queue_redraw()

func plot_position(point: Vector2) -> Vector2:
	return PLOT.get_center() + Vector2(point.x, -point.y) * (PLOT.size.x * 50.0 / SCALES[scale_index])

func ink(text: String, at: Vector2, font_size := 14, color := Color("a6b9ae")):
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color("182420"))
	ink("正面弹着 / 连射观察", Vector2(16, 30), 22, Color("e0e2d2"))
	ink("横向：左右偏差　纵向：高度偏差", Vector2(16, 58))
	var subtitle := "等待首发 · 固定本组瞄准点"
	if effects and not effects.paper_plane.is_empty():
		subtitle = "观察距离 %.2f m · 靶心高 %.2f m" % [effects.paper_plane.distance, effects.paper_plane.center.y]
	ink(subtitle, Vector2(16, 83))
	draw_rect(PLOT, Color("101b18"))
	for tick in range(-4, 5):
		var fraction := tick / 4.0
		var x := PLOT.get_center().x + fraction * PLOT.size.x / 2
		var y := PLOT.get_center().y - fraction * PLOT.size.y / 2
		var shade := Color("647d6d") if tick == 0 else Color("2c4036")
		draw_line(Vector2(x, PLOT.position.y), Vector2(x, PLOT.end.y), shade)
		draw_line(Vector2(PLOT.position.x, y), Vector2(PLOT.end.x, y), shade)
		if tick % 2 == 0:
			ink(str(fraction * SCALES[scale_index]), Vector2(x - 12, PLOT.end.y + 20), 12)
			ink(str(fraction * SCALES[scale_index]), Vector2(5, y + 4), 12)
	for radius in [37.0, 74.0, 111.0]:
		draw_arc(PLOT.get_center(), radius, 0, TAU, 80, Color("354c3e"), 1, true)
	draw_arc(PLOT.get_center(), 6, 0, TAU, 24, Color("c4c7ae"), 1.5, true)
	ink("cm", Vector2(316, 446), 12)
	var reached := 0
	var failed := 0
	var flying := 0
	var outside := 0
	if effects:
		for shot in effects.paper_shots:
			if shot.status == "flying":
				flying += 1
				continue
			if shot.status not in ["hit", "passed"]:
				failed += 1
				continue
			reached += 1
			var point := plot_position(shot.point)
			if not PLOT.grow(-5).has_point(point):
				outside += 1
				continue
			var age: float = float(shot.id - effects.paper_shots[0].id) / maxf(1, effects.paper_sequence - effects.paper_shots[0].id)
			var color := Color("5b8b97").lerp(Color("eaaa78"), age)
			if shot.id == 1: color = Color("ffe29b")
			draw_circle(point, 3.5, color)
			if shot.id == effects.paper_sequence: draw_arc(point, 7, 0, TAU, 24, color, 1, true)
			ink(str(shot.id), point + Vector2(-8 if point.x > PLOT.end.x - 24 else 6, 15 if point.y < PLOT.position.y + 16 else -5), 12, color)
	ink("已到靶面 %d · 未到 %d · 飞行中 %d" % [reached, failed, flying], Vector2(16, 475))
	ink("量程外 %d 发 · 保留最近 120 发" % outside, Vector2(16, 499))
	var latest := "尚未射击"
	if effects and not effects.paper_shots.is_empty():
		var shot: Dictionary = effects.paper_shots.back()
		latest = "第 %d 发 · " % shot.id
		if shot.status in ["hit", "passed"]:
			latest += "右 %+.1f / 上 %+.1f cm" % [shot.point.x * 100, shot.point.y * 100]
		elif shot.status == "flying": latest += "飞行中"
		else: latest += "未到靶面：" + shot.status
	ink(latest, Vector2(16, 532), 14, Color("e0d4b9"))
	ink("金色首发 · 蓝 → 橙表示射击顺序", Vector2(16, 572))
	ink("靶心固定于本组首发瞄准点", Vector2(16, 598))
	ink("命中靶体按同一正面平面投影", Vector2(16, 624))
	ink("掩体截停不画弹孔 · K 切换技能", Vector2(16, 650))
