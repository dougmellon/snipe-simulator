extends Control
## Tactical map: shoreline, marks, the course, the start line, every boat, the wind, puffs,
## and the laylines to the player's next mark. North up. Small in a corner, or full screen.

const Race := preload("res://scripts/race.gd")

var fleet
var big := false
var sim := true  # chart only: no puffs, laylines, other boats or wind arrow
var player_color := Color(0.2, 0.9, 1.0)
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if fleet == null:
		return
	var lake = fleet.lake
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.04, 0.07, 0.1, 0.72))
	var bb: Rect2 = lake.bounds.grow(60.0)
	var sc := minf(size.x / bb.size.x, size.y / bb.size.y)
	var off := (size - bb.size * sc) * 0.5
	var to := func(p: Vector2) -> Vector2:
		return off + Vector2(p.x - bb.position.x, bb.end.y - p.y) * sc

	# Water, then puffs on it.
	var poly := PackedVector2Array()
	for p: Vector2 in lake.shore:
		poly.append(to.call(p))
	draw_colored_polygon(poly, Color(0.13, 0.33, 0.42, 0.95))
	for q: Dictionary in ([] if sim else fleet.wind.puffs):
		var env: float = fleet.wind._envelope(q)
		var s: float = q["strength"] * env
		if absf(s) < 0.03:
			continue
		var c := Color(0.02, 0.12, 0.22, clampf(s * 1.6, 0.0, 0.5)) if s > 0.0 else Color(0.5, 0.65, 0.7, clampf(-s * 1.6, 0.0, 0.35))
		draw_circle(to.call(q["pos"]), q["radius"] * sc, c)
	poly.append(poly[0])
	draw_polyline(poly, Color(0.75, 0.85, 0.8, 0.8), 1.5, true)

	var race = fleet.race
	var me = fleet.boats[fleet.player] if fleet.player >= 0 else null
	var me_e = race.entrants[fleet.player] if race != null and fleet.player >= 0 else null

	# Course legs.
	if race != null and race.course.size() > 0:
		var prev: Vector2 = to.call(race.line_center())
		for i in race.course.size():
			var p: Vector2 = to.call(race.point_of(i))
			var done: bool = me_e != null and me_e.started and i < me_e.leg
			var col := Color(1, 1, 1, 0.12) if done else Color(1.0, 0.7, 0.3, 0.45)
			draw_dashed_line(prev, p, col, 1.0, 5.0)
			prev = p
	# Marks.
	for k: String in lake.marks:
		var p: Vector2 = to.call(lake.marks[k])
		var next: bool = me_e != null and race.is_mark(me_e.leg) and race.course[me_e.leg] == k and not me_e.finished
		draw_circle(p, 4.0 if next else 2.5, Color(1.0, 0.55, 0.15) if next else Color(0.95, 0.95, 0.95))
		var fs := 13 if big else 10
		draw_string(_font, p + Vector2(5, -4), k, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
	# Start/finish line and RC boat.
	if race != null:
		draw_line(to.call(race.rc_pos), to.call(race.pin), Color(1.0, 0.5, 0.1), 2.0)
		draw_rect(Rect2(to.call(race.rc_pos) - Vector2(3, 3), Vector2(6, 6)), Color(0.9, 0.9, 0.95))
	# Laylines to the next mark (upwind legs), from the mark downwind.
	if not sim and me != null and race != null and me_e.started and not me_e.finished and race.is_mark(me_e.leg):
		var m: Vector2 = race.point_of(me_e.leg)
		var wf := deg_to_rad(fleet.wind.mean_from())
		var d_in: Vector2 = m - race.point_of(me_e.leg - 1)
		var up := Vector2(sin(wf), cos(wf))
		if d_in.normalized().dot(up) > 0.5:
			for s in [-1.0, 1.0]:
				var a: float = wf + PI + s * deg_to_rad(41.0)
				draw_line(to.call(m), to.call(m + Vector2(sin(a), cos(a)) * 500.0), Color(1, 1, 0.4, 0.3), 1.0)
	# Boats.
	for i in fleet.boats.size():
		if sim and i != fleet.player:
			continue
		var b = fleet.boats[i]
		var p: Vector2 = to.call(b.pos)
		var h: float = b.heading
		var f := Vector2(sin(h), -cos(h))
		var rt := Vector2(-f.y, f.x)
		var L := 7.0 if big else 5.0
		var tri := PackedVector2Array([p + f * L, p - f * L * 0.6 + rt * L * 0.45, p - f * L * 0.6 - rt * L * 0.45])
		var col := player_color if i == fleet.player else Color(0.95, 0.95, 0.95, 0.85)
		if race != null and not race.entrants[i].active():
			col.a = 0.35
		draw_colored_polygon(tri, col)
		if big and i != fleet.player:
			draw_string(_font, p + Vector2(6, 10), fleet.sails[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
	# Wind arrow.
	if sim:
		draw_string(_font, Vector2(8, 16), "N ↑   chart", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))
		if big:
			draw_string(_font, Vector2(8, size.y - 10), "Map data © OpenStreetMap contributors (ODbL). Marks approximate, from the USC reference map.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		return
	var wf2 := deg_to_rad(fleet.wind.mean_from())
	var c0 := Vector2(size.x - 30, 30)
	var d := Vector2(-sin(wf2), cos(wf2))  # direction the wind blows, screen coords (y down)
	draw_circle(c0, 20, Color(0, 0, 0, 0.35))
	draw_line(c0 - d * 15, c0 + d * 15, Color(1, 1, 1), 2.0)
	draw_line(c0 + d * 15, c0 + d * 15 - d.rotated(0.5) * 7, Color(1, 1, 1), 2.0)
	draw_line(c0 + d * 15, c0 + d * 15 - d.rotated(-0.5) * 7, Color(1, 1, 1), 2.0)
	draw_string(_font, Vector2(size.x - 52, 62), "%03d°" % int(round(fleet.wind.mean_from())), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))
	draw_string(_font, Vector2(8, 16), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))
	if big:
		draw_string(_font, Vector2(8, size.y - 10), "Map data © OpenStreetMap contributors (ODbL). Marks approximate, from the USC reference map.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
