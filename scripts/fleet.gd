extends RefCounted
## Everything that moves on the water, stepped together: wind, boats (player and AI), the race,
## wind shadows, and contact with other boats, marks, the RC boat and the shore.
## No nodes here, so the whole race can run headless in tests.

const Lake := preload("res://scripts/lake.gd")
const Wind := preload("res://scripts/wind.gd")
const BoatSim := preload("res://scripts/boat_sim.gd")
const Race := preload("res://scripts/race.gd")
const AI := preload("res://scripts/ai.gd")

const BOAT_R := 0.6
const MARK_R := 0.45
const PIN_R := 0.6
const RC_R := 1.3
const MAX_FLEET := 10
const AI_NAMES := ["Sandpiper", "Osprey", "Pelican", "Heron", "Kestrel", "Merlin", "Plover", "Avocet", "Tern", "Grebe", "Killdeer", "Curlew"]

var lake
var wind
var race  # null when free sailing
var boats: Array = []
var ais: Array = []
var names: Array = []
var sails: Array = []
var player := -1
var assist := {"jib": true, "hike": true, "main": false, "rig": false}
var time := 0.0
var rng := RandomNumberGenerator.new()
var local := []        # per boat: Vector2(from_deg, speed) at the boat, refreshed at 30 Hz
var wind_t := 0.0
var assist_t := 0.0
var events: Array = []  # {"type": "aground"|"capsize"|"contact"|"mark", "boat": i, ...}
var aground_t := []
var chop_t := []


## cfg keys: wind_from, wind_kn, gust, ai (count), skill, course (type), seed, start (clock),
## race (bool), player (bool), fleet ("PORTSMOUTH"/"LMS"), crew_kg
func setup(cfg: Dictionary, lake_ref = null) -> void:
	lake = lake_ref if lake_ref != null else Lake.new()
	rng.seed = cfg.get("seed", 1)
	wind = Wind.new()
	wind.setup(cfg.get("wind_from", 270.0), cfg.get("wind_kn", 10.0), cfg.get("gust", 0.5), rng.randi(), lake)
	boats.clear()
	ais.clear()
	names.clear()
	sails.clear()
	player = -1
	var with_player: bool = cfg.get("player", true)
	# Fleets are capped at 10 boats, the player included.
	var n_ai: int = clampi(cfg.get("ai", 5), 0, MAX_FLEET - (1 if with_player else 0))
	var total := n_ai + (1 if with_player else 0)
	var wf: float = wind.mean_from()
	var up := Vector2(sin(deg_to_rad(wf)), cos(deg_to_rad(wf)))
	var left := up.rotated(PI * 0.5)
	var m1: Vector2 = lake.marks["1"]
	var used_names := AI_NAMES.duplicate()
	# Names, sail numbers and skills come from their own seed so a day of races keeps the fleet.
	var frng := RandomNumberGenerator.new()
	frng.seed = cfg.get("fleet_seed", cfg.get("seed", 1))
	for i in total:
		var b := BoatSim.new()
		b.crew_mass = cfg.get("crew_kg", 150.0)
		var is_player := with_player and i == 0
		var p: Vector2
		var h: float
		if is_player:
			# Reaching in on starboard toward the RC boat, a few metres below its transom, so the
			# flag-L check-in is right there on the way in.
			p = m1 - up * 19.0 - left * 90.0
			h = deg_to_rad(wf) - deg_to_rad(90.0)
		else:
			p = m1 - up * rng.randf_range(50.0, 160.0) + left * rng.randf_range(-40.0, 110.0)
			h = deg_to_rad(wf) + deg_to_rad(rng.randf_range(60.0, 120.0)) * (1 if rng.randf() < 0.5 else -1)
		b.place(p, fposmod(h, TAU), 1.5)
		boats.append(b)
		if is_player:
			player = i
			ais.append(null)
			names.append(cfg.get("player_name", "You"))
			sails.append(str(cfg.get("player_sail", "31415")))
		else:
			var ai := AI.new()
			ai.setup(rng.randi(), cfg.get("skill", 0.8) + frng.randf_range(-0.1, 0.1))
			ais.append(ai)
			var nm: String = used_names.pop_at(frng.randi() % used_names.size())
			names.append(nm)
			sails.append(str(frng.randi_range(28000, 32999)))
	assist = cfg.get("assist", assist).duplicate()
	local.resize(boats.size())
	aground_t.resize(boats.size())
	aground_t.fill(-100.0)
	chop_t.resize(boats.size())
	chop_t.fill(0.0)
	_refresh_wind()
	race = null
	if cfg.get("race", true):
		race = Race.new()
		var entries := []
		for i in boats.size():
			entries.append({"boat": boats[i], "name": names[i], "sail": sails[i], "player": i == player})
		race.setup(lake, wf, cfg.get("course", 0), entries, cfg.get("start", -300.0), cfg.get("fleet", "PORTSMOUTH"), rng.randf_range(-6.0, 6.0))


func step(dt: float) -> void:
	time += dt
	wind.update(dt)
	wind_t -= dt
	if wind_t <= 0.0:
		wind_t = 1.0 / 30.0
		_refresh_wind()
	assist_t -= dt
	var do_assist := assist_t <= 0.0
	if do_assist:
		assist_t = 0.25
	for i in boats.size():
		var b = boats[i]
		var w: Vector2 = local[i]
		if ais[i] != null and race != null:
			ais[i].drive(b, race.entrants[i], race, lake, w, boats, dt)
		elif ais[i] != null:
			pass
		else:
			_player_assists(b, do_assist, dt)
		var was_capsized: bool = b.capsized
		b.step(dt, Wind.from_to_vector(w.x, w.y))
		if b.just_capsized and not was_capsized:
			events.append({"type": "capsize", "boat": i})
	_collide()
	if race != null:
		race.update(dt, wind.mean_from())


func _player_assists(b, do_assist: bool, dt: float) -> void:
	if do_assist and assist.get("rig", false):
		b.auto_rig()
	if do_assist and (assist["jib"] or assist["main"]):
		var best: Vector2 = b.best_sheets()
		if assist["jib"]:
			b.set_meta("auto_jib", best.y)
		if assist["main"]:
			b.set_meta("auto_main", best.x)
	if assist["jib"] and b.has_meta("auto_jib"):
		b.jib_sheet = move_toward(b.jib_sheet, b.get_meta("auto_jib"), dt * 2.0)
	if assist["main"] and b.has_meta("auto_main"):
		b.main_sheet = move_toward(b.main_sheet, b.get_meta("auto_main"), dt * 1.5)
	if assist["hike"]:
		b.hike = lerpf(b.hike, b.auto_hike(4.0), clampf(dt * 3.0, 0.0, 1.0))


## Wind at each boat, including dirty air in the lee of boats upwind of it.
func _refresh_wind() -> void:
	for i in boats.size():
		var p: Vector2 = boats[i].pos
		var s: Vector2 = wind.sample(p)
		var flow := -Vector2(sin(deg_to_rad(s.x)), cos(deg_to_rad(s.x)))
		var factor := 1.0
		for j in boats.size():
			if j == i:
				continue
			var d: Vector2 = p - boats[j].pos
			var along := d.dot(flow)
			if along <= 0.0 or along > 40.0:
				continue
			var lateral := absf(d.cross(flow))
			var width := 2.5 + along * 0.18
			if lateral < width:
				factor *= 1.0 - 0.28 * (1.0 - along / 40.0) * (1.0 - lateral / width)
		local[i] = Vector2(s.x, s.y * factor)
		# Chop builds with the wind and with the fetch of open water upwind.
		chop_t[i] -= 1.0 / 30.0
		if chop_t[i] <= 0.0:
			chop_t[i] = 1.0
			var up := -flow
			var fetch: float = minf(lake.ray_to_shore(p, up, 1500.0), 1500.0)
			boats[i].chop = clampf(fetch / 900.0, 0.15, 1.0) * clampf((s.y - 1.5) / 5.0, 0.0, 1.0)


func local_wind(i: int) -> Vector2:
	return local[i]


# --- Contact ------------------------------------------------------------------------------

func _collide() -> void:
	var n := boats.size()
	for i in n:
		for j in range(i + 1, n):
			var a = boats[i]
			var b = boats[j]
			if a.pos.distance_squared_to(b.pos) > 36.0:
				continue
			var pts := Geometry2D.get_closest_points_between_segments(a.stern(), a.bow(), b.stern(), b.bow())
			var d: Vector2 = pts[1] - pts[0]
			var dist := d.length()
			if dist >= BOAT_R * 2.0:
				continue
			var nrm: Vector2 = d / dist if dist > 1e-4 else (b.pos - a.pos).normalized()
			var push := (BOAT_R * 2.0 - dist) * 0.5
			a.pos -= nrm * push
			b.pos += nrm * push
			var va: Vector2 = a.velocity()
			var vb: Vector2 = b.velocity()
			var rel := (vb - va).dot(nrm)
			if rel < 0.0:
				va += nrm * rel * 0.5
				vb -= nrm * rel * 0.5
				_set_velocity(a, va)
				_set_velocity(b, vb)
			events.append({"type": "contact", "boat": i, "other": j})
			if race != null:
				race.report_contact(i, j, wind.mean_from())
	for i in n:
		var b = boats[i]
		_touch_marks(i, b)
		_touch_shore(i, b)


func _touch_marks(i: int, b) -> void:
	var hits := []
	for k: String in lake.marks:
		hits.append([k, lake.marks[k], MARK_R])
	if race != null:
		hits.append(["PIN", race.pin, PIN_R])
	for h: Array in hits:
		var c: Vector2 = h[1]
		if b.pos.distance_squared_to(c) > 16.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(c, b.stern(), b.bow())
		var d: Vector2 = q - c
		var dist := d.length()
		var r: float = h[2] + BOAT_R
		if dist < r:
			var nrm: Vector2 = d / dist if dist > 1e-4 else (b.pos - c).normalized()
			b.pos += nrm * (r - dist)
			var v: Vector2 = b.velocity()
			var vn := v.dot(nrm)
			if vn < 0.0:
				_set_velocity(b, v - nrm * vn)
			events.append({"type": "mark", "boat": i, "mark": h[0]})
			if race != null:
				race.report_mark_touch(i, h[0])
	if race != null:
		# The RC boat: a capsule along its length.
		var f := Vector2(sin(race.rc_heading), cos(race.rc_heading))
		var s0: Vector2 = race.rc_pos - f * (Race.RC_LENGTH * 0.5 - RC_R)
		var s1: Vector2 = race.rc_pos + f * (Race.RC_LENGTH * 0.5 - RC_R)
		if b.pos.distance_squared_to(race.rc_pos) < 64.0:
			var pts := Geometry2D.get_closest_points_between_segments(s0, s1, b.stern(), b.bow())
			var d: Vector2 = pts[1] - pts[0]
			var dist := d.length()
			if dist < RC_R + BOAT_R:
				var nrm: Vector2 = d / dist if dist > 1e-4 else (b.pos - race.rc_pos).normalized()
				b.pos += nrm * (RC_R + BOAT_R - dist)
				var v: Vector2 = b.velocity()
				var vn := v.dot(nrm)
				if vn < 0.0:
					_set_velocity(b, v - nrm * vn)
				events.append({"type": "mark", "boat": i, "mark": "RC"})
				race.report_mark_touch(i, "RC")


func _touch_shore(i: int, b) -> void:
	b.aground = false
	for p: Vector2 in [b.bow(), b.stern(), b.pos]:
		var d: float = lake.shore_distance(p)
		if d > -0.4:
			var e := 2.0
			var g := Vector2(lake.shore_distance(p + Vector2(e, 0)) - lake.shore_distance(p - Vector2(e, 0)),
				lake.shore_distance(p + Vector2(0, e)) - lake.shore_distance(p - Vector2(0, e))).normalized()
			b.pos -= g * (d + 0.4)
			var v: Vector2 = b.velocity()
			var vn := v.dot(g)
			if vn > 0.0:
				_set_velocity(b, (v - g * vn) * 0.6)
			b.aground = true
	if b.aground and time - aground_t[i] > 5.0:
		aground_t[i] = time
		events.append({"type": "aground", "boat": i})


static func _set_velocity(b, v: Vector2) -> void:
	b.u = v.dot(b.fwd())
	b.v = v.dot(b.stb())
