extends RefCounted
## Plays a recorded session back through the normal boat views. apply() sets each BoatSim's
## drawn fields from the recording at time t, interpolated between samples, without stepping
## any physics. The views, cameras, water and minimap then draw it as usual.

const Recorder := preload("res://scripts/recorder.gd")
const TRACK_EVERY := 0.6
const TRACK_LEN := 19

var session := {}
var t0 := 0.0
var t1 := 0.0
var _times := PackedFloat64Array()
var _vals := PackedFloat32Array()
var _nb := 0
var _nc := 0
var _c := {}


func setup(ses: Dictionary) -> void:
	session = ses
	_times = ses["t"]
	_vals = ses["vals"]
	_nb = ses["nb"]
	_nc = ses["nc"]
	_c = ses["col"]
	t0 = _times[0]
	t1 = _times[_times.size() - 1]


## Sample index k and fraction a, so that t lies a of the way from sample k to k + 1.
func _locate(t: float) -> Array:
	var n := _times.size()
	var k := clampi(_times.bsearch(t, true) - 1, 0, n - 2)
	var span := _times[k + 1] - _times[k]
	var a := clampf((t - _times[k]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	return [k, a]


func _v(k: int, boat: int, col: String) -> float:
	return _vals[(k * _nb + boat) * _nc + int(_c[col])]


func _lerp(k: int, a: float, boat: int, col: String) -> float:
	return lerpf(_v(k, boat, col), _v(k + 1, boat, col), a)


func _lerp_deg(k: int, a: float, boat: int, col: String) -> float:
	return lerp_angle(deg_to_rad(_v(k, boat, col)), deg_to_rad(_v(k + 1, boat, col)), a)


func position_of(boat: int, t: float) -> Vector2:
	var ka := _locate(t)
	return Vector2(_lerp(ka[0], ka[1], boat, "x"), _lerp(ka[0], ka[1], boat, "y"))


func apply(t: float, boats: Array) -> void:
	var ka := _locate(t)
	var k: int = ka[0]
	var a: float = ka[1]
	for i in mini(boats.size(), _nb):
		var b = boats[i]
		b.pos = Vector2(_lerp(k, a, i, "x"), _lerp(k, a, i, "y"))
		b.heading = fposmod(_lerp_deg(k, a, i, "hdg"), TAU)
		b.u = _lerp(k, a, i, "spd")
		b.v = 0.0
		b.r = 0.0
		b.heel = deg_to_rad(_lerp(k, a, i, "heel"))
		b.twa = _lerp_deg(k, a, i, "twa")
		b.tws = _lerp(k, a, i, "tws")
		b.awa = _lerp_deg(k, a, i, "awa")
		b.aws = _lerp(k, a, i, "aws")
		b.boom = _lerp_deg(k, a, i, "boom")
		b.jib = _lerp_deg(k, a, i, "jib")
		b.tiller = _lerp(k, a, i, "tiller")
		b.main_sheet = _lerp(k, a, i, "main")
		b.jib_sheet = _lerp(k, a, i, "jibsheet")
		b.hike = _lerp(k, a, i, "hike")
		b.vang = _lerp(k, a, i, "vang")
		b.board = _lerp(k, a, i, "board")
		# Rig columns (sessions recorded before the rig controls don't have them).
		for col: String in ["outhaul", "cunningham", "traveler", "puller", "halyard", "jib_lead"]:
			if _c.has(col):
				b.set(col, _lerp(k, a, i, col))
		b.main_alpha = deg_to_rad(_lerp(k, a, i, "main_aoa"))
		b.jib_alpha = deg_to_rad(_lerp(k, a, i, "jib_aoa"))
		b.crew_y = _lerp(k, a, i, "crew_y")
		if _c.has("crew_x"):
			b.crew_x = _lerp(k, a, i, "crew_x")
		b.capsized = _v(k if a < 0.5 else k + 1, i, "capsized") > 0.5
		if _c.has("pole"):
			var po := _lerp(k, a, i, "pole")
			b.pole_out = absf(po)
			b.pole_side = 1.0 if po >= 0.0 else -1.0
			b.pole_state = b.POLE_SET if b.pole_out > 0.98 else (b.POLE_SETTING if b.pole_out > 0.02 else b.POLE_STOWED)
		b.main_alphas.fill(b.main_alpha)
		b.jib_alphas.fill(b.jib_alpha)
		if _c.has("main_twist"):
			b.view_shape(deg_to_rad(_lerp(k, a, i, "main_twist")), _lerp(k, a, i, "mast_bend"), _lerp(k, a, i, "stay_sag"))


## Mean wind direction (degrees, from) and speed (m/s) at time t.
func wind_at(t: float) -> Vector2:
	var w: Array = session["meta"].get("wind", [])
	if w.is_empty():
		var cfg: Dictionary = session["meta"]["cfg"]
		return Vector2(float(cfg.get("wind_from", 270.0)), float(cfg.get("wind_kn", 10.0)) * 0.514444)
	var k := 0
	while k < w.size() - 1 and float(w[k + 1][0]) <= t:
		k += 1
	return Vector2(float(w[k][1]), float(w[k][2]))


## Wake tracks in the form world_view.update_wakes() takes: per boat, newest first, starting
## where the boat is drawn now.
func wake_tracks(t: float, views: Array) -> Array:
	var out := []
	for i in mini(views.size(), _nb):
		var ka := _locate(t)
		var list := [Vector4(views[i].position.x, -views[i].position.z, 0.0, maxf(_lerp(ka[0], ka[1], i, "spd"), 0.0))]
		for n in range(1, TRACK_LEN + 1):
			var tt := t - n * TRACK_EVERY
			if tt < t0:
				break
			var kb := _locate(tt)
			var p := Vector2(_lerp(kb[0], kb[1], i, "x"), _lerp(kb[0], kb[1], i, "y"))
			list.append(Vector4(p.x, p.y, t - tt, maxf(_lerp(kb[0], kb[1], i, "spd"), 0.0)))
		out.append(list)
	return out
