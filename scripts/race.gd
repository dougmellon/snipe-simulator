extends RefCounted
## Race management under the Union Sailing Club 2026 sailing instructions (SI) and the Racing
## Rules of Sailing 2025-2028 (RRS):
##   SI 8   course posted on the RC board at the Attention signal; marks rounded to port
##   SI 9.3 "G" makes the start/finish line a gate
##   SI 10  Appendix U audible starts, individual recall with flag X, DNS after 5 minutes
##   SI 11  start and finish line between the RC boat (moored at mark 1) and an orange pin
##   SI 12  check-in: sail past the RC boat's transom on starboard tack while flag L flies
##   SI 14  RRS 44.1 penalty turns (one turn for touching a mark, two for a Part 2 foul)
##   SI 15  boats finishing more than 20 minutes after the first finisher are TLE
## Clock is seconds relative to the starting signal (negative before it).

const Course := preload("res://scripts/course.gd")
const Rules := preload("res://scripts/rules.gd")

enum Phase { CHECKIN, SEQUENCE, RACING, DONE }

# RRS Appendix U: seconds before the start -> sounds (L long, S short).
const SIGNALS := [
	[-180.0, "LLL"], [-120.0, "LL"], [-90.0, "LSSS"], [-60.0, "L"], [-30.0, "SSS"],
	[-20.0, "SS"], [-10.0, "S"], [-5.0, "S"], [-4.0, "S"], [-3.0, "S"], [-2.0, "S"], [-1.0, "S"],
	[0.0, "L"],
]
const DNS_AFTER := 300.0
const RECALL_MAX := 240.0
const TIME_LIMIT := 1200.0
const MAX_RACE := 5400.0
const ROUND_TOL := 0.6
const MARK_NEAR := 80.0
const RC_LENGTH := 7.0


class Entrant:
	var boat
	var name := ""
	var sail := ""
	var is_player := false
	var checked_in := false
	var ocs := false
	var cleared := false
	var started := false
	var start_time := 0.0
	var leg := 0
	var accum := 0.0
	var prev_angle := 0.0
	var near := false
	var prev_bow := Vector2.ZERO
	var finished := false
	var finish_time := 0.0
	var status := ""
	var penalty_turns := 0
	var penalty_reason := ""
	var pen_accum := 0.0
	var pen_max := 0.0
	var pen_tacks := 0
	var pen_gybes := 0
	var pen_tack_side := 0
	var prev_heading := 0.0
	var marks_rounded := 0

	func active() -> bool:
		return not finished and status == ""


var lake
var entrants: Array = []
var course: Array = []
var course_type := 0
var course_text := ""
var required: Array = []  # sweep needed at each mark leg (radians)
var fleet_flag := "PORTSMOUTH"
var clock := -300.0
var phase := Phase.CHECKIN
var rc_pos := Vector2.ZERO
var rc_heading := 0.0
var pin := Vector2.ZERO
var line_up := Vector2.UP
var flags := {}
var any_ocs := false
var next_signal := 0
var first_finish := -1.0
var events: Array = []
var contact_cooldown := {}
var wind_from_at_attention := 0.0


func setup(lake_ref, wind_from: float, type: int, boats: Array, start_offset := -300.0, fleet := "PORTSMOUTH", line_bias_deg := 0.0) -> void:
	lake = lake_ref
	course_type = type
	fleet_flag = fleet
	clock = start_offset
	var up := Vector2(sin(deg_to_rad(wind_from)), cos(deg_to_rad(wind_from)))
	line_up = up
	# The RC boat lies to its mooring on mark 1, bow to the wind; its flag is the starboard end.
	rc_pos = lake.marks["1"] - up * (RC_LENGTH * 0.5 + 5.0)
	rc_heading = deg_to_rad(wind_from)
	var length := clampf(boats.size() * 7.0 + 25.0, 45.0, 110.0)
	var left := up.rotated(PI * 0.5).rotated(deg_to_rad(line_bias_deg))
	pin = rc_pos + left * length
	entrants.clear()
	for b: Dictionary in boats:
		var e := Entrant.new()
		e.boat = b["boat"]
		e.name = b.get("name", "")
		e.sail = b.get("sail", "")
		e.is_player = b.get("player", false)
		e.checked_in = not e.is_player
		e.prev_bow = e.boat.bow()
		e.prev_heading = e.boat.heading
		e.pen_tack_side = e.boat.tack()
		entrants.append(e)
	next_signal = 0
	while next_signal < SIGNALS.size() and SIGNALS[next_signal][0] < clock:
		next_signal += 1
	flags.clear()
	if clock < -180.0:
		phase = Phase.CHECKIN
		flags["L"] = true
	else:
		phase = Phase.SEQUENCE
		flags[fleet_flag] = true
		_post_course(wind_from)
		for e: Entrant in entrants:
			e.checked_in = true


func line_center() -> Vector2:
	return (rc_pos + pin) * 0.5


## +1 on the course side of the line (and its extensions), -1 on the pre-start side.
func line_side(p: Vector2) -> float:
	var s := signf((pin - rc_pos).cross(p - rc_pos))
	var c := signf((pin - rc_pos).cross(line_up))
	return s * c


func rc_stern() -> Vector2:
	return rc_pos - Vector2(sin(rc_heading), cos(rc_heading)) * RC_LENGTH * 0.5


## Where the element at course index `i` is ("G" and "F" are the line's middle).
func point_of(i: int) -> Vector2:
	if i < 0:
		return line_center()
	var el: String = course[mini(i, course.size() - 1)]
	if el == "G" or el == "F":
		return line_center()
	return lake.marks[el]


func is_mark(i: int) -> bool:
	return i < course.size() and course[i] != "G" and course[i] != "F"


func update(dt: float, wind_from_now: float) -> void:
	if phase == Phase.DONE:
		return
	clock += dt
	while next_signal < SIGNALS.size() and clock >= SIGNALS[next_signal][0]:
		var sig: Array = SIGNALS[next_signal]
		events.append({"type": "horn", "pattern": sig[1]})
		if sig[0] == -180.0:
			phase = Phase.SEQUENCE
			flags.erase("L")
			flags[fleet_flag] = true
			_post_course(wind_from_now)
			events.append({"type": "msg", "text": "Attention signal: 3 minutes. Course on the RC board: %s" % course_text})
		elif sig[0] == -120.0:
			events.append({"type": "msg", "text": "2 minutes"})
		elif sig[0] == -60.0:
			events.append({"type": "msg", "text": "1 minute"})
		elif sig[0] == 0.0:
			flags.erase(fleet_flag)
			phase = Phase.RACING
			_start_signal()
		next_signal += 1
		events.append({"type": "flags"})

	for e: Entrant in entrants:
		_track_penalty(e)
		if phase == Phase.CHECKIN and not e.checked_in:
			_check_in(e)
		if phase == Phase.RACING and e.active():
			if not e.started:
				_try_start(e)
			else:
				_advance(e)
		e.prev_bow = e.boat.bow()

	if phase == Phase.RACING:
		if flags.has("X"):
			var all_back := entrants.all(func(e): return not e.ocs or e.cleared or not e.active())
			if all_back or clock >= RECALL_MAX:
				flags.erase("X")
				events.append({"type": "flags"})
		if clock >= DNS_AFTER:
			for e: Entrant in entrants:
				if e.active() and not e.started:
					_set_status(e, "OCS" if e.ocs else "DNS", "did not start within 5 minutes (SI 10.3)")
		if first_finish >= 0.0 and clock >= first_finish + TIME_LIMIT:
			for e: Entrant in entrants:
				if e.active():
					_set_status(e, "TLE", "20 minutes after the first finisher (SI 15.1)")
		if clock >= MAX_RACE:
			for e: Entrant in entrants:
				if e.active():
					_set_status(e, "DNF", "race abandoned for time")
		if entrants.all(func(e): return not e.active()):
			phase = Phase.DONE
			for e: Entrant in entrants:
				if e.is_player and not e.checked_in and not e.finished:
					e.status = "DNC"
			events.append({"type": "done"})


func _post_course(wind_from: float) -> void:
	wind_from_at_attention = wind_from
	course = Course.build(lake.marks, wind_from, course_type)
	course_text = Course.board_text(course)
	required.clear()
	for i in course.size():
		if not is_mark(i):
			required.append(0.0)
			continue
		var m: Vector2 = point_of(i)
		var a_in := (point_of(i - 1) - m).angle()
		var a_out := (point_of(i + 1) - m).angle()
		var need := fposmod(a_out - a_in, TAU)
		if need < deg_to_rad(45.0):
			need += TAU
		required.append(need)
	events.append({"type": "course", "text": course_text})


func _start_signal() -> void:
	for e: Entrant in entrants:
		if not e.active():
			continue
		if line_side(e.boat.bow()) > 0.0:
			e.ocs = true
			any_ocs = true
	if any_ocs:
		flags["X"] = true
		events.append({"type": "horn", "pattern": "S"})
		events.append({"type": "msg", "text": "Individual recall: flag X. Boats over early must return to the pre-start side."})
		for e: Entrant in entrants:
			if e.ocs and e.is_player:
				events.append({"type": "msg", "text": "You were over the line at the start! Get your whole hull back behind the line, then start.", "player": true})
	else:
		events.append({"type": "msg", "text": "Start! Clean start for the whole fleet."})


func _try_start(e: Entrant) -> void:
	var b = e.boat
	if e.ocs and not e.cleared:
		if line_side(b.bow()) < 0.0 and line_side(b.stern()) < 0.0:
			e.cleared = true
			if e.is_player:
				events.append({"type": "msg", "text": "Cleared. Now start properly.", "player": true})
		return
	if _crossed_line(e) and line_side(b.bow()) > 0.0:
		e.started = true
		e.start_time = clock
		_begin_leg(e, 0)
		if e.is_player:
			events.append({"type": "msg", "text": "Started at %s. First mark: %s" % [fmt_clock(clock), course[0]], "player": true})


func _crossed_line(e: Entrant) -> bool:
	return Geometry2D.segment_intersects_segment(e.prev_bow, e.boat.bow(), rc_pos, pin) != null


func _begin_leg(e: Entrant, leg: int) -> void:
	e.leg = leg
	e.accum = 0.0
	e.near = false
	if is_mark(leg):
		e.prev_angle = (e.boat.pos - point_of(leg)).angle()


func _advance(e: Entrant) -> void:
	var b = e.boat
	var el: String = course[e.leg]
	if is_mark(e.leg):
		var m := point_of(e.leg)
		var ang: float = (b.pos - m).angle()
		e.accum += wrapf(ang - e.prev_angle, -PI, PI)
		e.prev_angle = ang
		if b.pos.distance_to(m) < MARK_NEAR:
			e.near = true
		if e.near and e.accum >= required[e.leg] - ROUND_TOL:
			e.marks_rounded += 1
			if e.is_player:
				events.append({"type": "msg", "text": "Rounded mark %s. Next: %s" % [el, _next_name(e.leg + 1)], "player": true})
			_begin_leg(e, e.leg + 1)
		return
	# Gate or finish: cross the line coming from the previous mark's side.
	if _crossed_line(e) and signf(line_side(b.bow())) != signf(line_side(point_of(e.leg - 1))):
		if el == "G":
			if e.is_player:
				events.append({"type": "msg", "text": "Through the gate. Next: %s" % _next_name(e.leg + 1), "player": true})
			_begin_leg(e, e.leg + 1)
		else:
			e.finished = true
			e.finish_time = clock
			if first_finish < 0.0:
				first_finish = clock
			events.append({"type": "horn", "pattern": "S"})
			if e.penalty_turns > 0:
				_set_status(e, "DSQ", "finished without taking a penalty (RRS 44.1)")
			elif e.is_player:
				events.append({"type": "msg", "text": "Finished! Elapsed %s, place %d" % [fmt_clock(clock), place_of(e)], "player": true})


func _next_name(i: int) -> String:
	if i >= course.size():
		return "-"
	var el: String = course[i]
	if el == "G":
		return "the gate (start/finish line)"
	if el == "F":
		return "the finish"
	return "mark " + el


func _check_in(e: Entrant) -> void:
	var b = e.boat
	var stern := rc_stern()
	var aft := -Vector2(sin(rc_heading), cos(rc_heading))
	if b.pos.distance_to(stern) < 14.0 and (b.pos - stern).dot(aft) > 0.0 and b.tack() == 1 and b.speed() > 0.4:
		e.checked_in = true
		events.append({"type": "msg", "text": "Checked in. You hail: \"Snipe, sail %s!\"  RC: \"%s, got you.\"" % [e.sail, e.sail], "player": e.is_player})


func _track_penalty(e: Entrant) -> void:
	var b = e.boat
	var side: int = b.tack()
	if e.penalty_turns > 0:
		var dh := wrapf(b.heading - e.prev_heading, -PI, PI)
		e.pen_accum += dh
		e.pen_max = maxf(e.pen_max, absf(e.pen_accum))
		if e.pen_max - absf(e.pen_accum) > PI * 0.5:
			e.pen_accum = 0.0
			e.pen_max = 0.0
			e.pen_tacks = 0
			e.pen_gybes = 0
		if side != e.pen_tack_side:
			if absf(b.awa) < PI * 0.5:
				e.pen_tacks += 1
			else:
				e.pen_gybes += 1
		var n := e.penalty_turns
		if absf(e.pen_accum) >= n * TAU - 0.35 and e.pen_tacks >= n and e.pen_gybes >= n:
			e.penalty_turns = 0
			events.append({"type": "msg", "text": "%s completed %s." % [_who(e), "a one-turn penalty" if n == 1 else "a two-turn penalty"], "player": e.is_player})
	e.pen_tack_side = side
	e.prev_heading = b.heading


func give_penalty(e: Entrant, turns: int, reason: String) -> void:
	if not e.active():
		return
	if e.penalty_turns >= turns:
		return
	e.penalty_turns = turns
	e.penalty_reason = reason
	e.pen_accum = 0.0
	e.pen_max = 0.0
	e.pen_tacks = 0
	e.pen_gybes = 0
	var what := "One-Turn Penalty" if turns == 1 else "Two-Turns Penalty"
	events.append({"type": "msg", "text": "%s: %s. Take a %s (one tack and one gybe per turn)." % [_who(e), reason, what], "player": e.is_player})


func report_contact(i: int, j: int, wind_from: float) -> void:
	if phase == Phase.CHECKIN or phase == Phase.DONE:
		return
	var key := "%d-%d" % [mini(i, j), maxi(i, j)]
	if contact_cooldown.get(key, -INF) > clock:
		return
	contact_cooldown[key] = clock + 10.0
	var a: Entrant = entrants[i]
	var b: Entrant = entrants[j]
	if not a.active() or not b.active():
		return
	var res := Rules.adjudicate(a.boat, b.boat, wind_from)
	var at_fault: Entrant = a if res["fault"] == 0 else b
	var other: Entrant = b if res["fault"] == 0 else a
	give_penalty(at_fault, 2, "fouled %s, %s" % [_who(other).to_lower() if other.is_player else other.name, res["rule"]])


func report_mark_touch(i: int, mark_id: String) -> void:
	if phase == Phase.CHECKIN or phase == Phase.DONE:
		return
	var e: Entrant = entrants[i]
	var key := "%d-%s" % [i, mark_id]
	if contact_cooldown.get(key, -INF) > clock:
		return
	contact_cooldown[key] = clock + 10.0
	var of_course: bool = mark_id in course or mark_id == "RC" or mark_id == "PIN"
	if of_course:
		var label := "the RC boat" if mark_id == "RC" else ("the pin" if mark_id == "PIN" else "mark " + mark_id)
		give_penalty(e, 1, "touched %s (rule 31)" % label)


func retire(e: Entrant) -> void:
	if e.active():
		_set_status(e, "RET", "retired")


func _set_status(e: Entrant, code: String, why: String) -> void:
	e.status = code
	events.append({"type": "msg", "text": "%s: %s (%s)" % [_who(e), code, why], "player": e.is_player})


func _who(e: Entrant) -> String:
	return "You" if e.is_player else e.name


## Distance still to sail, roughly, for ranking boats that have not finished.
func remaining(e: Entrant) -> float:
	if e.finished:
		return -1.0
	if not e.started:
		return 1e6 + e.boat.pos.distance_to(line_center())
	var d: float = e.boat.pos.distance_to(point_of(e.leg))
	for i in range(e.leg, course.size() - 1):
		d += point_of(i).distance_to(point_of(i + 1))
	return d


func standings() -> Array:
	var list := entrants.duplicate()
	list.sort_custom(func(a: Entrant, b: Entrant) -> bool:
		var ka := _rank_key(a)
		var kb := _rank_key(b)
		if ka.x != kb.x:
			return ka.x < kb.x
		return ka.y < kb.y)
	return list


func _rank_key(e: Entrant) -> Vector2:
	if e.finished and e.status == "":
		return Vector2(0, e.finish_time)
	if e.status == "":
		return Vector2(1, remaining(e))
	var order := ["TLE", "DSQ", "OCS", "DNS", "DNF", "RET", "DNC"]
	return Vector2(2 + order.find(e.status), 0)


func place_of(e: Entrant) -> int:
	return standings().find(e) + 1


static func fmt_clock(t: float) -> String:
	var neg := t < 0.0
	var s := int(absf(t))
	return "%s%d:%02d" % ["-" if neg else "", s / 60, s % 60]
