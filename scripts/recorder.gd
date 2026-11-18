extends RefCounted
## Records a session. Every boat goes into a CSV five times a second; race events, the course,
## the line, the wind and the results go into a JSON file beside it. Both live in
## user://sessions/ and share a name. The CSV columns are the ones a real-boat log will be
## converted to, so the same analysis reads both.
##
## Units: metres, seconds, m/s, degrees. hdg is compass degrees, twa and awa are signed
## (+ = wind over the starboard side), heel is + with the starboard side down.
## Rig columns (after capsized) are in the tuning guide's units: outhaul (in eased), cunningham
## (in on), traveler (in down), puller (in forward of neutral at the deck), halyard (in eased),
## jib_lead (in forward), pole (how far out, 0..1, + to starboard), and what the shape came to:
## main_twist (degrees), mast_bend and stay_sag (in). The loader reads columns by name, so older
## sessions (which had a "flatten" column instead) still load.

const DIR := "user://sessions"
const EVERY := 0.2
const WIND_EVERY := 1.0
const CONTACT_GAP := 3.0
const COLUMNS := ["t", "boat", "x", "y", "hdg", "spd", "heel", "twa", "tws", "awa", "aws", "boom", "jib",
	"tiller", "main", "jibsheet", "hike", "vang", "board", "main_aoa", "jib_aoa", "crew_y", "capsized",
	"outhaul", "cunningham", "traveler", "puller", "halyard", "jib_lead", "pole", "main_twist", "mast_bend", "stay_sag", "crew_x"]

var id := ""
var csv_path := ""
var meta_path := ""
var meta := {}
var _f: FileAccess
var _next := 0.0
var _wind_next := 0.0
var _prev: Array = []
var _contact := {}
var _gun := false


## Starts a session file for this fleet. Returns false if the file can't be written.
func open(cfg: Dictionary, fleet, label := "", dir := DIR) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	id = stamp + ("_" + label if label != "" else "")
	csv_path = dir.path_join(id + ".csv")
	meta_path = dir.path_join(id + ".json")
	_f = FileAccess.open(csv_path, FileAccess.WRITE)
	if _f == null:
		return false
	_f.store_line(",".join(COLUMNS))
	var boats := []
	for i in fleet.boats.size():
		boats.append({"name": fleet.names[i], "sail": fleet.sails[i], "player": i == fleet.player})
	var marks := {}
	for k: String in fleet.lake.marks:
		marks[k] = _xy(fleet.lake.marks[k])
	meta = {
		"version": 1, "id": id, "created": Time.get_datetime_string_from_system(false, true),
		"cfg": _plain(cfg), "player": fleet.player, "boats": boats, "every_s": EVERY, "columns": COLUMNS,
		"marks": marks, "events": [], "wind": [], "gun_t": null, "start_t": fleet.time, "end_t": null,
		"complete": false, "course": [], "course_text": "", "results": [],
	}
	var race = fleet.race
	if race != null:
		meta["rc"] = _xy(race.rc_pos)
		meta["pin"] = _xy(race.pin)
		meta["line_up"] = _xy(race.line_up)
		for e in race.entrants:
			_prev.append(_snap(e))
	_next = fleet.time
	_wind_next = fleet.time
	return true


func is_open() -> bool:
	return _f != null


## Called by the fleet after every step.
func tick(fleet) -> void:
	if _f == null:
		return
	var t: float = fleet.time
	_poll_race(fleet, t)
	if t + 1e-6 >= _next:
		while _next <= t + 1e-6:
			_next += EVERY
		for i in fleet.boats.size():
			_f.store_line(_row(t, i, fleet.boats[i]))
	if t + 1e-6 >= _wind_next:
		while _wind_next <= t + 1e-6:
			_wind_next += WIND_EVERY
		meta["wind"].append([snappedf(t, 0.01), snappedf(fleet.wind.mean_from(), 0.1), snappedf(fleet.wind.base_speed, 0.01)])


## Fleet events (contact, mark, aground, capsize). Contact between the same two boats is only
## logged again after a gap, since it's reported every step they touch.
func event(t: float, d: Dictionary) -> void:
	if _f == null:
		return
	if d["type"] == "contact":
		var key := "%d-%d" % [mini(d["boat"], d["other"]), maxi(d["boat"], d["other"])]
		var last: float = _contact.get(key, -INF)
		_contact[key] = t
		if t - last < CONTACT_GAP:
			return
	var ev := {"t": snappedf(t, 0.01)}
	for k in d:
		ev[k] = d[k]
	meta["events"].append(ev)


## Finishes the files. Returns the session id ("" if nothing was open).
func close(fleet) -> String:
	if _f == null:
		return ""
	_f.close()
	_f = null
	meta["end_t"] = snappedf(fleet.time, 0.01)
	var race = fleet.race
	if race != null:
		meta["course"] = race.course.duplicate()
		meta["course_text"] = race.course_text
		meta["complete"] = race.phase == race.Phase.DONE
		var res := []
		var place := 1
		for e in race.standings():
			var ok: bool = e.finished and e.status == ""
			res.append({"boat": race.entrants.find(e), "place": place if ok else null, "status": e.status,
				"start_clock": snappedf(e.start_time, 0.01) if e.started else null,
				"finish_clock": snappedf(e.finish_time, 0.01) if e.finished else null})
			if ok:
				place += 1
		meta["results"] = res
	var mf := FileAccess.open(meta_path, FileAccess.WRITE)
	if mf != null:
		mf.store_string(JSON.stringify(meta, " "))
		mf.close()
	return id


func _poll_race(fleet, t: float) -> void:
	var race = fleet.race
	if race == null:
		return
	if not _gun and (race.phase == race.Phase.RACING or race.phase == race.Phase.DONE):
		_gun = true
		meta["gun_t"] = snappedf(t - race.clock, 0.001)
		for i in race.entrants.size():
			if race.entrants[i].ocs:
				meta["events"].append({"t": snappedf(t, 0.01), "boat": i, "type": "ocs"})
	for i in race.entrants.size():
		var e = race.entrants[i]
		var p: Dictionary = _prev[i]
		var evs := []
		if e.started and not p["started"]:
			evs.append({"type": "start"})
		if e.leg > p["leg"]:
			for k in range(p["leg"], e.leg):
				var el: String = race.course[k]
				if race.is_mark(k):
					evs.append({"type": "round", "mark": el, "leg": k})
				elif el == "G":
					evs.append({"type": "gate", "leg": k})
		if e.finished and not p["finished"]:
			evs.append({"type": "finish"})
		if e.penalty_turns > p["pen"]:
			evs.append({"type": "penalty", "turns": e.penalty_turns, "reason": e.penalty_reason})
		elif e.penalty_turns == 0 and p["pen"] > 0 and e.active():
			evs.append({"type": "penalty_done"})
		if e.status != p["status"] and e.status != "":
			evs.append({"type": "status", "code": e.status})
		for ev: Dictionary in evs:
			ev["t"] = snappedf(t, 0.01)
			ev["boat"] = i
			meta["events"].append(ev)
		_prev[i] = _snap(e)


static func _snap(e) -> Dictionary:
	return {"started": e.started, "leg": e.leg, "finished": e.finished, "pen": e.penalty_turns, "status": e.status}


static func _row(t: float, i: int, b) -> String:
	return "%.3f,%d,%.2f,%.2f,%.1f,%.2f,%.1f,%.1f,%.2f,%.1f,%.2f,%.1f,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.1f,%.1f,%.2f,%d,%.2f,%.2f,%.2f,%.3f,%.2f,%.2f,%.2f,%.1f,%.2f,%.2f,%.2f" % [
		t, i, b.pos.x, b.pos.y, rad_to_deg(b.heading), b.u, rad_to_deg(b.heel), rad_to_deg(b.twa), b.tws,
		rad_to_deg(b.awa), b.aws, rad_to_deg(b.boom), rad_to_deg(b.jib), b.tiller, b.main_sheet, b.jib_sheet,
		b.hike, b.vang, b.board, rad_to_deg(b.main_alpha), rad_to_deg(b.jib_alpha), b.crew_y,
		1 if b.capsized else 0, b.outhaul, b.cunningham, b.traveler, b.puller, b.halyard, b.jib_lead,
		b.pole_out * b.pole_side, rad_to_deg(b.main_twist), b.mast_bend, b.stay_sag, b.crew_x]


static func _xy(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


## JSON-safe copy of a config (vectors and colours become lists and strings).
static func _plain(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _plain(v[k])
		return d
	if v is Array:
		return (v as Array).map(func(x): return _plain(x))
	if v is Vector2:
		return _xy(v)
	if v is Color:
		return (v as Color).to_html()
	return v


# --- Reading a session back ----------------------------------------------------------------

## Sessions on disk, newest first: Array of ids.
static func list(dir := DIR) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	out.reverse()
	return out


## Loads a session: {"meta", "t": PackedFloat64Array of sample times, "vals": every value
## row-major (sample time, then boat, then column), "nb": boats, "nc": columns, "col": {name:
## index}}. Read values with value(). Every boat is sampled at the same times, as the recorder
## writes them. Empty on failure.
static func load_session(session_id: String, dir := DIR) -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(session_id + ".json")))
	var f := FileAccess.open(dir.path_join(session_id + ".csv"), FileAccess.READ)
	if not (m is Dictionary) or f == null:
		return {}
	var header := f.get_line().split(",")
	var src := PackedInt32Array()
	var col := {}
	for k in header.size():
		if header[k] != "t" and header[k] != "boat":
			col[header[k]] = src.size()
			src.append(k)
	var ti := header.find("t")
	var bi := header.find("boat")
	var nb: int = (m["boats"] as Array).size()
	var nc := src.size()
	# Packed arrays are values in Godot 4: fill local ones, never ones fetched from a container.
	var times := PackedFloat64Array()
	var vals := PackedFloat32Array()
	var expect := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		var parts := line.split(",")
		var i := parts[bi].to_int()
		if i != expect:
			push_warning("session %s: rows out of order at t=%s" % [session_id, parts[ti]])
			break
		if i == 0:
			times.append(parts[ti].to_float())
		for k in nc:
			vals.append(parts[src[k]].to_float())
		expect = (i + 1) % nb
	f.close()
	# Drop a sample time whose rows were cut short.
	var full := vals.size() / (nb * nc)
	if times.size() > full:
		times.resize(full)
	vals.resize(full * nb * nc)
	return {"meta": m, "t": times, "vals": vals, "nb": nb, "nc": nc, "col": col}


static func size(session: Dictionary) -> int:
	return (session["t"] as PackedFloat64Array).size()


## The value of `column` for `boat` at sample index `k`.
static func value(session: Dictionary, boat: int, column: String, k: int) -> float:
	var nb: int = session["nb"]
	var nc: int = session["nc"]
	return session["vals"][(k * nb + boat) * nc + int(session["col"][column])]


## One boat's samples in the form scripts/moves.gd reads: {"t", "speed" m/s, "twa" rad, "tws"
## m/s, "pos" Vector2, "hdg" rad, "capsized" bool}.
static func samples(session: Dictionary, boat: int) -> Array:
	var times: PackedFloat64Array = session["t"]
	var vals: PackedFloat32Array = session["vals"]
	var nb: int = session["nb"]
	var nc: int = session["nc"]
	var c: Dictionary = session["col"]
	var cx: int = c["x"]
	var cy: int = c["y"]
	var ch: int = c["hdg"]
	var cs: int = c["spd"]
	var ct: int = c["twa"]
	var cw: int = c["tws"]
	var cc: int = c["capsized"]
	var out := []
	out.resize(times.size())
	for k in times.size():
		var o := (k * nb + boat) * nc
		out[k] = {"t": times[k], "speed": vals[o + cs], "twa": deg_to_rad(vals[o + ct]), "tws": vals[o + cw],
			"pos": Vector2(vals[o + cx], vals[o + cy]), "hdg": deg_to_rad(vals[o + ch]), "capsized": vals[o + cc] > 0.5}
	return out
