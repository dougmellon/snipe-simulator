extends RefCounted
## AI skipper. Reaches back and forth below the line before the start and times a run at it,
## sails the course with laylines and wind shifts, rounds marks to port, gives way when Part 2
## says it must, takes its penalty turns, and keeps off the shore, the marks and the RC boat.
## Trim and hiking use the same assists the player can switch on.

const Race := preload("res://scripts/race.gd")

const UP_TWA := deg_to_rad(41.0)
const DOWN_TWA := deg_to_rad(165.0)
const ORBIT_R := 7.0
const PLAN_DT := 0.05

var rng := RandomNumberGenerator.new()
var skill := 0.85
var line_frac := 0.5
var depth := 50.0
var tack_margin := 0.5
var speed_bias := 1.0
var t := 0.0
var last_tack_t := -100.0
var want_tack := 0
var trim_t := 0.0
var want := 0.0
var sheet_target := Vector2(0.6, 0.6)
var go := false
var reach_to_pin := true
var cleared_line := false
var pen_dir := 0
var slow_t := 0.0
var unstick_t := 0.0
var unstick_h := 0.0
var turn_dir := 0
var turn_is_tack := false
var turn_t := 0.0
var pen_tacking := false
var pen_tack_from := 0
var give_hold := Vector2.ZERO
var give_t := 0.0
var plan_t := 0.0
var plan_ease := 0.0
var plan_free := false
var debug := ""


func setup(seed: int, skill_level: float) -> void:
	rng.seed = seed
	skill = clampf(skill_level, 0.3, 1.0)
	line_frac = rng.randf_range(0.12, 0.88)
	depth = rng.randf_range(35.0, 75.0)
	reach_to_pin = rng.randf() < 0.5
	tack_margin = rng.randf_range(0.5, 1.2)
	speed_bias = 1.0 + rng.randf_range(-0.12, 0.12) * (1.1 - skill)


## Sets the boat's controls for this step. `wind` is Vector2(from_deg, speed) at the boat.
## Plans (heading and sheet ease) 20 times a second; steers and trims every step.
func drive(b, e, race, lake, wind: Vector2, others: Array, dt: float) -> void:
	t += dt
	plan_t -= dt
	if plan_t <= 0.0:
		_plan(b, e, race, lake, wind, others, PLAN_DT - plan_t)
		plan_t = PLAN_DT
	_steer_and_trim(b, deg_to_rad(wind.x), dt)


func _plan(b, e, race, lake, wind: Vector2, others: Array, dt: float) -> void:
	var wf := deg_to_rad(wind.x)
	var mode := "race"
	if race.phase == Race.Phase.CHECKIN or race.phase == Race.Phase.SEQUENCE:
		mode = "prestart"
	if e.finished or not e.active():
		mode = "done"
	if e.penalty_turns == 0:
		pen_dir = 0
		pen_tacking = false

	var ease := 0.0
	var free_heading := false  # true when the heading must not be bent by avoidance
	if unstick_t > 0.0:
		unstick_t -= dt
		want = unstick_h
		debug = "unsticking"
	elif mode != "done" and e.penalty_turns > 0 and _clear_of(b, others, 10.0) and lake.shore_distance(b.pos) < -30.0:
		# Keep turning the same way: bear away through the gybe, round up through the tack.
		if pen_dir == 0:
			pen_dir = -b.tack()
		# Bearing away is always possible; heading up into the tack needs speed, so without it
		# sail a close reach until she is moving, then keep turning.
		var bear_dir: int = -b.tack()
		if pen_tacking:
			want = b.heading + pen_dir * 1.2
			if b.tack() != pen_tack_from and absf(b.twa) > deg_to_rad(50.0):
				pen_tacking = false
		elif pen_dir == bear_dir or absf(b.twa) > deg_to_rad(75.0):
			want = b.heading + pen_dir * 1.2
		elif b.u > maxf(0.9, 0.3 * b.tws):
			pen_tacking = true
			pen_tack_from = b.tack()
			want = b.heading + pen_dir * 1.2
		else:
			want = wf - b.tack() * deg_to_rad(70.0)
		free_heading = true
		debug = "penalty turns"
	else:
		match mode:
			"prestart":
				var r := _prestart(b, race, wind)
				want = r.x
				ease = r.y
			"race":
				if not e.started:
					var r := _restart(b, e, race, wind)
					want = r.x
					ease = r.y
				else:
					want = _race_heading(b, e, race, lake, wf)
			"done":
				# Clear the finish line (SI 11.3), then sit head to wind.
				if not cleared_line and b.pos.distance_to(race.line_center()) < 60.0:
					want = wf + PI
				else:
					cleared_line = true
					want = wf - UP_TWA * b.tack()
					ease = 1.0

	if not free_heading:
		want = _avoid_obstacles(b, e, race, want, wf)
		want = _avoid_shore(b, lake, want, wf)
		if mode != "done":
			var give := _give_way(b, others, wf)
			# Hold a keep-clear move for a moment rather than re-deciding every step.
			if give != Vector2.ZERO:
				give_hold = give
				give_t = 1.5
			elif give_t > 0.0:
				give_t -= dt
				give = give_hold
			want += give.x
			ease = maxf(ease, give.y)

	# Stuck (in irons, pinned on something): reach off toward open water for a few seconds.
	if b.u < 0.35 and ease < 0.5 and not b.capsized:
		slow_t += dt
	else:
		slow_t = 0.0
	if slow_t > 7.0 and unstick_t <= 0.0:
		slow_t = 0.0
		unstick_t = 6.0
		var away: Vector2 = (-_shore_normal(lake, b.pos)).normalized()
		if lake.shore_distance(b.pos) < -60.0:
			away = Vector2(sin(b.heading), cos(b.heading))
		var h := atan2(away.x, away.y)
		# Make it a reach so there is drive.
		var twa_h := wrapf(wf - h, -PI, PI)
		if absf(twa_h) < deg_to_rad(80.0):
			h = wf - deg_to_rad(95.0) * (1.0 if twa_h >= 0.0 else -1.0)
		unstick_h = h
	plan_ease = ease
	plan_free = free_heading


func _steer_and_trim(b, wf: float, dt: float) -> void:
	var ease := plan_ease
	var free_heading := plan_free
	# Steer. A big turn through head-to-wind needs speed; without it, go round the other way
	# (gybe). When tacking, sheet in so the sails help her round.
	# Once a big turn is started it is finished the same way round, or she dithers.
	var err := wrapf(want - b.heading, -PI, PI)
	if turn_dir != 0:
		if signf(err) != turn_dir and absf(err) > 0.35:
			err -= signf(err) * TAU
		if turn_is_tack:
			ease = 0.0
		if absf(err) < 0.35 or t - turn_t > 15.0 or free_heading:
			turn_dir = 0
	elif not free_heading and absf(err) > 0.6 and _turn_crosses_wind(b.heading, err, wf):
		turn_is_tack = b.u >= 1.4
		if turn_is_tack:
			ease = 0.0
		else:
			err -= signf(err) * TAU
		turn_dir = int(signf(err))
		turn_t = t
	var noise := rng.randfn(0.0, 0.03 * (1.0 - skill))
	b.tiller = clampf(2.6 * (err + noise) - 1.3 * b.r, -1.0, 1.0)
	if b.u < -0.3:
		b.tiller = -b.tiller  # going astern, the rudder works backwards
	elif unstick_t <= 0.0:
		# A rudder jammed hard over is a brake; real helms tack with a smooth push.
		b.tiller = clampf(b.tiller, -0.85, 0.85)

	# Trim a few times a second, with a skill-dependent error.
	trim_t -= dt
	if trim_t <= 0.0:
		trim_t = 0.25
		b.auto_rig()
		var best: Vector2 = b.best_sheets()
		var e_sk := (1.0 - skill) * 0.25
		sheet_target = Vector2(clampf(best.x + rng.randf_range(-e_sk, e_sk), 0.0, 1.0), clampf(best.y + rng.randf_range(-e_sk, e_sk), 0.0, 1.0))
	var ms := lerpf(sheet_target.x, 1.0, clampf(ease, 0.0, 1.0))
	var js := lerpf(sheet_target.y, 1.0, clampf(ease, 0.0, 1.0))
	b.main_sheet = move_toward(b.main_sheet, ms, dt * 1.5)
	b.jib_sheet = move_toward(b.jib_sheet, js, dt * 2.0)
	b.hike = lerpf(b.hike, b.auto_hike(4.0), clampf(dt * 3.0, 0.0, 1.0))
	b.board = 1.0 if absf(b.twa) < 1.9 else 0.5
	if b.capsized and b.capsize_t > 3.0:
		b.right_now()


# --- Starting -------------------------------------------------------------------------

## Returns Vector2(heading, ease) for the pre-start.
func _prestart(b, race, wind: Vector2) -> Vector2:
	var wf := deg_to_rad(wind.x)
	var remaining: float = -race.clock
	var up: Vector2 = race.line_up
	var spot: Vector2 = race.rc_pos.lerp(race.pin, line_frac)
	var v_est := clampf(wind.y * 0.45, 1.1, 2.8) * speed_bias
	if race.line_side(b.bow()) > 0.0:
		debug = "back below line"
		return Vector2(_bearing(b.pos, spot - up * 25.0), 0.4)
	var dist: float = b.pos.distance_to(spot)
	var eta := dist / v_est + 5.0
	if not go and remaining <= eta + 2.0:
		go = true
	if not go:
		# Reach back and forth along the line, `depth` metres below it.
		var along: Vector2 = (race.pin - race.rc_pos).normalized()
		var a: Vector2 = race.rc_pos - up * depth - along * 15.0
		var z: Vector2 = race.pin - up * depth + along * 20.0
		var target := z if reach_to_pin else a
		if b.pos.distance_to(target) < 12.0:
			reach_to_pin = not reach_to_pin
			target = z if reach_to_pin else a
		debug = "reaching"
		return Vector2(_bearing(b.pos, target), 0.35)
	debug = "go"
	var early: float = remaining - eta
	var ease := clampf(early / 10.0, 0.0, 0.85) if early > 0.5 else 0.0
	return Vector2(_route(b, race.lake, spot + up * 10.0, wf), ease)


## After the gun, for a boat that has not started yet (OCS, or late).
func _restart(b, e, race, wind: Vector2) -> Vector2:
	var wf := deg_to_rad(wind.x)
	var spot: Vector2 = race.rc_pos.lerp(race.pin, line_frac)
	if (e.ocs and not e.cleared) or race.line_side(b.bow()) > 0.0:
		debug = "returning to start"
		# Dip back through the line away from the RC boat and the mark.
		return Vector2(_bearing(b.pos, spot - race.line_up * 20.0), 0.2)
	debug = "starting late"
	return Vector2(_limit_upwind(b, _bearing(b.pos, spot + race.line_up * 20.0), wf), 0.0)


# --- Racing ---------------------------------------------------------------------------

func _race_heading(b, e, race, lake, wf: float) -> float:
	if race.is_mark(e.leg):
		var m: Vector2 = race.point_of(e.leg)
		var d_in: Vector2 = (m - race.point_of(e.leg - 1)).normalized()
		var entry := m + _right(d_in) * ORBIT_R
		var dm: float = b.pos.distance_to(m)
		if dm < ORBIT_R * 3.2 or (e.near and dm < 30.0):
			debug = "rounding " + race.course[e.leg]
			return _orbit(b, m, wf)
		debug = "to mark " + race.course[e.leg]
		return _route(b, lake, entry, wf)
	# Gate or finish: aim through our spot on the line.
	var from_side: float = race.line_side(race.point_of(e.leg - 1))
	var spot: Vector2 = race.rc_pos.lerp(race.pin, clampf(line_frac, 0.3, 0.7))
	var through: Vector2 = spot - race.line_up * from_side * 15.0
	debug = "to line"
	return _route(b, lake, through, wf)


## Circle the mark anticlockwise (leaving it to port) at about ORBIT_R.
func _orbit(b, m: Vector2, wf: float) -> float:
	var p: Vector2 = b.pos - m
	var dist := maxf(p.length(), 0.1)
	var radial := p / dist
	var tangent := Vector2(-radial.y, radial.x)
	var dir := (tangent - radial * clampf((dist - ORBIT_R) / ORBIT_R, -1.0, 1.0) * 0.8).normalized()
	return _limit_upwind(b, atan2(dir.x, dir.y), wf)


## Heading toward `target`, beating or running with tacks and gybes when it is dead up or
## down wind. Tacks when the other tack points closer to the target by `tack_margin`
## (laylines, headers), or when the shore is close ahead.
func _route(b, lake, target: Vector2, wf: float) -> float:
	var brg := _bearing(b.pos, target)
	var twa_t := wrapf(wf - brg, -PI, PI)
	var tk: int = b.tack()
	# Stick with a tack or gybe we just started until the boat has come through it.
	if want_tack != 0 and t - last_tack_t < 8.0:
		tk = want_tack
	var upwind := absf(twa_t) < UP_TWA + 0.03
	var downwind := absf(twa_t) > DOWN_TWA
	if not upwind and not downwind:
		return brg
	var a := UP_TWA if upwind else DOWN_TWA
	var cur := wf - a * tk
	var oth := wf + a * tk
	var margin := tack_margin * 0.5 if upwind else 0.25
	var min_gap := 20.0 if upwind else 12.0
	var better := cos(oth - brg) > cos(cur - brg) + margin
	var blocked: bool = lake.ray_to_shore(b.pos, Vector2(sin(cur), cos(cur)), 45.0) < 45.0
	if (better and t - last_tack_t > min_gap) or (blocked and t - last_tack_t > 6.0):
		last_tack_t = t
		want_tack = -tk
		return oth
	return cur


## Never ask for a heading inside the no-go zone: sail close-hauled on the current tack.
func _limit_upwind(b, h: float, wf: float) -> float:
	var twa_h := wrapf(wf - h, -PI, PI)
	if absf(twa_h) < UP_TWA:
		return wf - UP_TWA * b.tack()
	return h


## Steer round marks we are not rounding, the pin and the RC boat.
func _avoid_obstacles(b, e, race, h: float, wf: float) -> float:
	var obs := []
	for k: String in race.lake.marks:
		var rounding: bool = e.started and race.is_mark(e.leg) and race.course[e.leg] == k
		if not rounding:
			obs.append([race.lake.marks[k], 3.5])
	obs.append([race.pin, 3.5])
	obs.append([race.rc_pos, 6.0])
	var dir := Vector2(sin(h), cos(h))
	var side := Vector2(dir.y, -dir.x)  # starboard
	var best_push := 0.0
	for o: Array in obs:
		var rel: Vector2 = o[0] - b.pos
		var ahead := rel.dot(dir)
		if ahead < 0.0 or ahead > 30.0:
			continue
		var lat := rel.dot(side)
		var clear: float = o[1]
		if absf(lat) > clear:
			continue
		# Pass on whichever side the obstacle is already off; turn harder the closer it is.
		var turn := (clear - absf(lat)) / maxf(ahead, 4.0) * 1.6
		var push := -turn if lat > 0.0 else turn
		if absf(push) > absf(best_push):
			best_push = push
	if best_push == 0.0:
		return h
	var nh := h + clampf(best_push, -0.8, 0.8)
	if absf(wrapf(wf - nh, -PI, PI)) < UP_TWA * 0.9:
		# Can't pass that way upwind: bear away round the other side instead.
		nh = h - clampf(best_push, -0.8, 0.8)
	debug += " avoiding"
	return nh


func _avoid_shore(b, lake, h: float, wf: float) -> float:
	var dir := Vector2(sin(h), cos(h))
	if lake.shore_distance(b.pos + dir * 30.0) < -12.0 and lake.shore_distance(b.pos) < -10.0:
		return h
	var best := h
	var best_score := INF
	for k in range(-6, 7):
		var cand := h + k * 0.3
		if absf(wrapf(wf - cand, -PI, PI)) < UP_TWA:
			continue
		var d: float = lake.shore_distance(b.pos + Vector2(sin(cand), cos(cand)) * 30.0)
		var score := d + absf(k) * 2.0
		if score < best_score:
			best_score = score
			best = cand
	debug += " shore"
	return best


## Part 2: returns Vector2(heading change, ease) when this boat must keep clear, plus a small
## last-moment swerve for the right-of-way boat when contact is close (rule 14).
func _give_way(b, others: Array, wf: float) -> Vector2:
	var out := Vector2.ZERO
	for o in others:
		if o == b:
			continue
		var dp: Vector2 = o.pos - b.pos
		if dp.length() > 40.0:
			continue
		var dv: Vector2 = o.velocity() - b.velocity()
		var tc := 0.0
		if dv.length_squared() > 0.01:
			tc = clampf(-dp.dot(dv) / dv.length_squared(), 0.0, 8.0)
		var miss := (dp + dv * tc).length()
		if miss > 7.0 or tc > 8.0:
			continue
		var must := false
		var mine: int = b.tack()
		var theirs: int = o.tack()
		if mine != theirs:
			must = mine < 0
		else:
			var up := Vector2(sin(wf), cos(wf))
			var me_behind: bool = (b.bow() - o.stern()).dot(o.fwd()) < 0.0
			var them_behind: bool = (o.bow() - b.stern()).dot(b.fwd()) < 0.0
			if me_behind:
				must = true
			elif not them_behind:
				must = b.pos.dot(up) > o.pos.dot(up)
		# Which way is away from them.
		var away := -1.0 if dp.dot(b.stb()) > 0.0 else 1.0
		if must:
			if mine != theirs and absf(b.twa) < 1.6:
				# Port tacker upwind ducks: bear away hard and go behind.
				out.x = -mine * 0.5
				debug += " ducking"
			else:
				out.x = away * 0.3
				out.y = maxf(out.y, 0.4)
				debug += " keeping clear"
		elif miss < 2.5 and tc < 2.5:
			out.x = away * 0.25
			debug += " rule 14"
	return out


static func _turn_crosses_wind(heading: float, err: float, wf: float) -> bool:
	for k in range(1, 9):
		if absf(wrapf(wf - (heading + err * k / 8.0), -PI, PI)) < 0.25:
			return true
	return false


func _clear_of(b, others: Array, dist: float) -> bool:
	for o in others:
		if o != b and o.pos.distance_to(b.pos) < dist:
			return false
	return true


static func _shore_normal(lake, p: Vector2) -> Vector2:
	var e := 3.0
	return Vector2(lake.shore_distance(p + Vector2(e, 0)) - lake.shore_distance(p - Vector2(e, 0)),
		lake.shore_distance(p + Vector2(0, e)) - lake.shore_distance(p - Vector2(0, e)))


static func _bearing(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)


static func _right(v: Vector2) -> Vector2:
	return Vector2(v.y, -v.x)
