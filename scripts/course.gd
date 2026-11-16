extends RefCounted
## Courses the race committee can post on the board (SI 8.3): a list of marks in order, "G" for
## the start/finish line used as a gate (SI 9.3) and "F" for the finish. Marks 2-9 ring mark 1,
## so the windward mark is whichever ring mark sits most directly upwind of mark 1.

const TYPES := ["Windward-leeward, 2 laps", "Windward-leeward, short", "Triangle", "Triangle + windward-leeward"]


## Ring mark whose bearing from mark 1 is closest to `bearing_deg`.
static func ring_mark(marks: Dictionary, bearing_deg: float) -> String:
	var c: Vector2 = marks["1"]
	var best := ""
	var best_d := INF
	for k: String in marks:
		if k == "1":
			continue
		var d: Vector2 = marks[k] - c
		var b := rad_to_deg(atan2(d.x, d.y))
		var diff := absf(wrapf(b - bearing_deg, -180.0, 180.0))
		if diff < best_d:
			best_d = diff
			best = k
	return best


## RC's pick for the conditions: short in light air, two laps otherwise.
static func rc_choice(wind_kn: float) -> int:
	return 1 if wind_kn < 7.0 else 0


static func build(marks: Dictionary, wind_from: float, type: int) -> Array:
	var w := ring_mark(marks, wind_from)
	var l := ring_mark(marks, wind_from + 180.0)
	# With every mark left to port the triangle goes anticlockwise: the wing mark sits 90
	# degrees to the left of the wind as seen from mark 1.
	var wing := ring_mark(marks, wind_from - 90.0)
	match type:
		0:
			return [w, l, "G", w, "F"]
		1:
			return [w, l, "F"]
		2:
			return [w, wing, l, "F"]
		3:
			return [w, wing, l, "G", w, "F"]
	return [w, l, "F"]


static func board_text(course: Array) -> String:
	return " ".join(course.map(func(e): return str(e)))
