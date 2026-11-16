extends SceneTree
## Unit checks for the race rules: check-in, OCS and the X flag, port roundings (and that a
## starboard rounding doesn't count), finishing direction, penalty turns, and right of way.
## Run: godot --headless --path . --script res://tests/rules_test.gd

const Lake := preload("res://scripts/lake.gd")
const BoatSim := preload("res://scripts/boat_sim.gd")
const Race := preload("res://scripts/race.gd")
const Rules := preload("res://scripts/rules.gd")

var fails := 0
var lake


func _init() -> void:
	lake = Lake.new()
	test_checkin()
	test_ocs()
	test_rounding(true)
	test_rounding(false)
	test_finish_direction()
	test_penalty_turns()
	test_right_of_way()
	print("rules_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _race(boats: Array, start := -300.0, wind := 270.0) -> Race:
	var r := Race.new()
	var entries := []
	for i in boats.size():
		entries.append({"boat": boats[i], "name": "B%d" % i, "sail": str(100 + i), "player": i == 0})
	r.setup(lake, wind, 0, entries, start)
	return r


## Move a boat along a path of points at `speed`, heading along the path, stepping the race.
func _drive(r: Race, b, path: Array, speed := 2.0) -> void:
	for k in range(path.size() - 1):
		var a: Vector2 = path[k]
		var z: Vector2 = path[k + 1]
		var d := z - a
		var n := int(d.length() / (speed / 60.0))
		for s in n:
			b.pos = a + d * (float(s) / n)
			b.heading = atan2(d.x, d.y)
			b.u = speed
			r.update(1.0 / 60.0, 270.0)


func test_checkin() -> void:
	print("check-in (SI 12)")
	var b := BoatSim.new()
	var r := _race([b])
	check(r.flags.has("L"), "flag L flies before the attention signal")
	# Starboard tack with the wind from the west means heading roughly south: boom to port.
	b.boom = -0.5
	var stern: Vector2 = r.rc_stern()
	var aft := -Vector2(sin(r.rc_heading), cos(r.rc_heading))
	_drive(r, b, [stern + aft * 6.0 + Vector2(0, 30), stern + aft * 6.0 + Vector2(0, -30)])
	check(r.entrants[0].checked_in, "passing the RC transom on starboard checks in")
	var b2 := BoatSim.new()
	var r2 := _race([b2])
	b2.boom = 0.5  # port tack
	_drive(r2, b2, [stern + aft * 6.0 + Vector2(0, 30), stern + aft * 6.0 + Vector2(0, -30)])
	check(not r2.entrants[0].checked_in, "passing on port tack does not")


func test_ocs() -> void:
	print("start, OCS and flag X (SI 10, 11)")
	var early := BoatSim.new()
	var good := BoatSim.new()
	var r := _race([early, good], -5.0)
	var c := r.line_center()
	early.pos = c + r.line_up * 6.0
	early.heading = atan2(r.line_up.x, r.line_up.y)
	good.pos = c - r.line_up * 10.0
	good.heading = early.heading
	for i in 6 * 60:
		r.update(1.0 / 60.0, 270.0)
	check(r.phase == Race.Phase.RACING, "starting signal made")
	check(r.entrants[0].ocs and r.flags.has("X"), "boat over early is OCS and X flies")
	check(not r.entrants[1].ocs, "boat behind the line is fine")
	_drive(r, good, [good.pos, c + r.line_up * 20.0])
	check(r.entrants[1].started, "the good boat starts by crossing the line")
	# The OCS boat crossing forward again without returning does not start.
	_drive(r, early, [early.pos, early.pos + r.line_up * 10.0])
	check(not r.entrants[0].started, "OCS boat hasn't started until it returns")
	_drive(r, early, [early.pos, c - r.line_up * 15.0, c + r.line_up * 10.0])
	check(r.entrants[0].cleared and r.entrants[0].started, "after dipping back below the line it starts")
	check(not r.flags.has("X"), "X comes down when every OCS boat has returned")


func test_rounding(port: bool) -> void:
	print("rounding the windward mark %s" % ("to port" if port else "to starboard (wrong way)"))
	var b := BoatSim.new()
	var r := _race([b], -1.0)
	for i in 70:
		r.update(1.0 / 60.0, 270.0)
	var c := r.line_center()
	b.pos = c - r.line_up * 5.0
	_drive(r, b, [b.pos, c + r.line_up * 10.0])
	check(r.entrants[0].started, "started")
	var m: Vector2 = r.point_of(0)
	var up: Vector2 = r.line_up
	var right := Vector2(up.y, -up.x)
	var side := right if port else -right
	# Approach from below, pass the mark on the chosen side, go round the top, come back down.
	_drive(r, b, [b.pos, m - up * 30.0 + side * 8.0, m + side * 8.0, m + up * 8.0, m - side * 8.0, m - side * 8.0 - up * 40.0])
	if port:
		check(r.entrants[0].leg == 1, "port rounding counts (now on leg %d)" % (r.entrants[0].leg + 1))
	else:
		check(r.entrants[0].leg == 0, "starboard rounding does not count")


func test_finish_direction() -> void:
	print("finish direction")
	var b := BoatSim.new()
	var r := Race.new()
	r.setup(lake, 270.0, 1, [{"boat": b, "name": "B", "sail": "1"}], -1.0)  # short W-L: W L F
	for i in 70:
		r.update(1.0 / 60.0, 270.0)
	var e = r.entrants[0]
	e.started = true
	e.leg = 2  # heading for the finish from the leeward mark (downwind of the line)
	var c := r.line_center()
	b.pos = c + r.line_up * 10.0
	e.prev_bow = b.bow()
	_drive(r, b, [b.pos, c - r.line_up * 10.0])
	check(not e.finished, "crossing from the wrong side is not a finish")
	_drive(r, b, [b.pos, c + r.line_up * 10.0])
	check(e.finished, "crossing from the leeward mark's side finishes")


func test_penalty_turns() -> void:
	print("penalty turns (RRS 44.1)")
	var b := BoatSim.new()
	var r := _race([b], -1.0)
	for i in 70:
		r.update(1.0 / 60.0, 270.0)
	var e = r.entrants[0]
	r.give_penalty(e, 1, "test")
	check(e.penalty_turns == 1, "one-turn penalty given")
	# Turn a full circle: the tack side changes twice (a tack and a gybe).
	b.pos = Vector2(0, -600)
	for k in 360 * 2:
		var h := deg_to_rad(k * 0.5)
		b.heading = h
		# Wind from the west: boom to leeward.
		var twa := wrapf(deg_to_rad(270.0) - h, -PI, PI)
		b.awa = twa
		b.boom = -signf(twa) * 0.5
		r.update(1.0 / 60.0, 270.0)
	check(e.penalty_turns == 0, "a full turn with a tack and a gybe completes it")


func test_right_of_way() -> void:
	print("right of way (RRS 10, 11, 12)")
	var s := BoatSim.new()
	var p := BoatSim.new()
	s.boom = -0.3  # starboard tack
	p.boom = 0.3   # port tack
	s.pos = Vector2(0, 0)
	p.pos = Vector2(3, 0)
	var res := Rules.adjudicate(s, p, 0.0)
	check(res["fault"] == 1 and res["rule"].begins_with("rule 10"), "port tack keeps clear (rule 10)")
	var a := BoatSim.new()
	var w := BoatSim.new()
	a.boom = -0.3
	w.boom = -0.3
	a.heading = deg_to_rad(315.0)
	w.heading = deg_to_rad(315.0)
	a.pos = Vector2(0, 0)
	w.pos = Vector2(1, 1.5)  # further upwind (wind from the north), overlapped
	res = Rules.adjudicate(a, w, 0.0)
	check(res["fault"] == 1 and res["rule"].begins_with("rule 11"), "windward boat keeps clear (rule 11)")
	var ahead := BoatSim.new()
	var behind := BoatSim.new()
	ahead.boom = -0.3
	behind.boom = -0.3
	ahead.heading = 0.0
	behind.heading = 0.0
	ahead.pos = Vector2(0, 5)
	behind.pos = Vector2(0, 0)
	res = Rules.adjudicate(ahead, behind, 90.0)
	check(res["fault"] == 1 and res["rule"].begins_with("rule 12"), "boat clear astern keeps clear (rule 12)")
