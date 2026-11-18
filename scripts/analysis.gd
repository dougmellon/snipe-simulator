extends RefCounted
## Session analytics for one boat, split the way data/targets.json is: steady sailing by wind
## bin and sector, and every move (tacks, gybes, roundings and the start) scored in time bins
## around it. Reads a session loaded by scripts/recorder.gd. Real-boat logs converted to the
## same columns will work too.

const Moves := preload("res://scripts/moves.gd")
const Targets := preload("res://scripts/targets.gd")
const Recorder := preload("res://scripts/recorder.gd")
const KN := 0.514444
const BOW_X := 2.45
const SECTORS := ["upwind", "reach", "downwind"]


## Returns {"boat", "name", "start": {...}, "moves": [...] (worst first), "wind": [...],
## "summary": {kind: {"n", "mean_lengths", "total_m"}, "penalty_m"}}.
static func run(session: Dictionary, boat: int, targets: Dictionary) -> Dictionary:
	var meta: Dictionary = session["meta"]
	var out := {"boat": boat, "name": meta["boats"][boat]["name"], "start": {}, "moves": [], "wind": [], "summary": {}}
	var s := Recorder.samples(session, boat)
	if s.size() < 10:
		return out
	var gun_v: Variant = meta.get("gun_t")
	var gun_t: float = float(gun_v) if gun_v != null else float(s[0]["t"])
	var t_start := INF
	var t_end: float = s[s.size() - 1]["t"]
	var pens := []
	var pen_from := -1.0
	var marks := []
	var ocs := false
	for ev: Dictionary in meta["events"]:
		if int(ev.get("boat", -1)) != boat:
			continue
		var t := float(ev["t"])
		match ev["type"]:
			"start":
				t_start = minf(t_start, t)
			"finish", "status":
				t_end = minf(t_end, t)
			"penalty":
				pen_from = t
			"penalty_done":
				if pen_from >= 0.0:
					pens.append([pen_from, t])
					pen_from = -1.0
			"round", "gate":
				var mk := ev.duplicate()
				# The race calls a rounding once she has swept far enough round, a few seconds after
				# she passed the mark. Time it from her closest approach instead.
				if ev["type"] == "round":
					mk["t"] = _closest_approach(s, _point(meta, int(ev["leg"])), t)
				marks.append(mk)
			"ocs":
				ocs = true
	if pen_from >= 0.0:
		pens.append([pen_from, t_end])
	var mv: Dictionary = targets["moves"]
	var bl := float(targets["boat_length_m"])
	var sk: Array = targets["polar"]["steady_skip_s"]
	var skip := []

	# Every move while racing, with the span it disturbs the boat's sailing: its scored bins,
	# leaving out the baseline (10 s before to 20 s after a tack or gybe, all of a rounding's
	# bins). A tack or gybe is only clean, and only counted, if no other move's span reaches into
	# its window. A rounding is scored against steady VMG, so tacks and gybes inside it are part
	# of it; only another mark or a penalty spoils it.
	var tb: Array = mv["time_bins_s"]
	var t_base: Array = mv["baseline_bins"]
	var scored := _scored_range(tb, t_base)
	var rb: Array = mv["rounding"]["time_bins_s"]
	var turns := []
	for m: Dictionary in Moves.find(s):
		if float(m["t"]) > t_start and float(m["t"]) < t_end:
			turns.append(m)
	var spans := []  # [from, to, t (or -1 for a penalty or capsize), is_rounding]
	if t_start < INF:
		spans.append([t_start + scored.x, t_start + scored.y, t_start, false])
	for m: Dictionary in turns:
		var t0: float = m["t"]
		spans.append([t0 + scored.x, t0 + scored.y, t0, false])
	for ev: Dictionary in marks:
		var t0 := float(ev["t"])
		spans.append([t0 + float(rb[0][0]), t0 + float(rb[rb.size() - 1][1]), t0, true])
	for sp: Array in spans:
		skip.append([sp[0], sp[1]])
	# Penalty turns and capsizes disturb her sailing too, but aren't moves to score themselves.
	for p: Array in pens:
		spans.append([float(p[0]), float(p[1]) + 20.0, -1.0, false])
	var cap_from := -1.0
	for x: Dictionary in s:
		if x["capsized"] and cap_from < 0.0:
			cap_from = x["t"]
		elif not x["capsized"] and cap_from >= 0.0:
			spans.append([cap_from - 5.0, float(x["t"]) + 20.0, -1.0, false])
			cap_from = -1.0
	# Steady sailing first: roundings are scored against it.
	out["wind"] = _wind_table(s, t_start, t_end, skip, pens, targets)
	for m: Dictionary in turns:
		var t0: float = m["t"]
		var r := Moves.score(s, m, tb, t_base)
		if r["complete"]:
			r["clean"] = not _overlaps(t0, [t0 + float(tb[0][0]), t0 + float(tb[tb.size() - 1][1])], spans, false)
			_label(r, s, gun_t, bl, pens, targets, mv[m["kind"]])
			out["moves"].append(r)
	for ev: Dictionary in marks:
		var t0 := float(ev["t"])
		var r := _rounding(s, ev, meta, mv["rounding"], out["wind"], targets)
		if r["complete"]:
			r["clean"] = not _overlaps(t0, [t0 + float(rb[0][0]), t0 + float(rb[rb.size() - 1][1])], spans, true)
			_label(r, s, gun_t, bl, pens, targets, mv["rounding"])
			out["moves"].append(r)
	for r: Dictionary in out["moves"]:
		if r["penalty"]:
			r["clean"] = false
	# Clean moves worst first, then the rest in time order.
	out["moves"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["clean"] != b["clean"]:
			return a["clean"]
		return a["loss_m"] > b["loss_m"] if a["clean"] else a["t"] < b["t"])
	out["start"] = _start(s, meta, gun_t, t_start, mv["start"], bl, ocs, targets)

	var summary := {"penalty_m": 0.0}
	for kind: String in ["tack", "gybe", "rounding"]:
		summary[kind] = {"n": 0, "mean_lengths": 0.0, "total_m": 0.0}
	for r: Dictionary in out["moves"]:
		if r["penalty"]:
			summary["penalty_m"] += r["loss_m"]
			continue
		if not r["clean"]:
			continue
		var k: Dictionary = summary[r["kind"]]
		k["n"] += 1
		k["total_m"] += r["loss_m"]
	for kind: String in ["tack", "gybe", "rounding"]:
		var k: Dictionary = summary[kind]
		if k["n"] > 0:
			k["mean_lengths"] = k["total_m"] / k["n"] / bl
	out["summary"] = summary
	return out


## The rest of the fleet for comparison: mean loss per move kind (boat lengths) and mean
## upwind VMG per wind bin, over every boat except `boat`.
static func fleet_compare(all: Array, boat: int) -> Dictionary:
	var kinds := {}
	var vmg := {}
	for a: Dictionary in all:
		if a["boat"] == boat or a["summary"].is_empty():
			continue
		for kind: String in ["tack", "gybe", "rounding"]:
			var k: Dictionary = a["summary"][kind]
			if k["n"] > 0:
				if not kinds.has(kind):
					kinds[kind] = []
				kinds[kind].append(k["mean_lengths"])
		for row: Dictionary in a["wind"]:
			var key: String = row["bin"] + "|" + row["sector"]
			if not vmg.has(key):
				vmg[key] = []
			vmg[key].append(row["vmg_kn"])
	var out := {"kinds": {}, "vmg": {}}
	for kind in kinds:
		out["kinds"][kind] = _mean(kinds[kind])
	for key in vmg:
		out["vmg"][key] = _mean(vmg[key])
	return out


static func move_name(r: Dictionary) -> String:
	match r["kind"]:
		"tack":
			return "Tack"
		"gybe":
			return "Gybe"
		"rounding":
			return "Gate" if r.get("mark", "") == "G" else "Mark %s" % r.get("mark", "")
	return str(r["kind"])


# --- Pieces -----------------------------------------------------------------------------------

static func _label(r: Dictionary, s: Array, gun_t: float, bl: float, pens: Array, targets: Dictionary, tk: Dictionary) -> void:
	var t0: float = r["t"]
	r["clock"] = t0 - gun_t
	r["lengths"] = float(r["loss_m"]) / bl
	r["penalty"] = _inside(t0, pens)
	var i := clampi(Moves.first_index(s, t0), 0, s.size() - 1)
	var bin := Targets.wind_bin(targets, float(s[i]["tws"]) / KN)
	r["wind_bin"] = bin
	r["check"] = Targets.check("loss (lengths)", tk["loss_boat_lengths"], bin, r["lengths"]) if tk.has("loss_boat_lengths") else {}


## A rounding (or the gate), scored as VMC toward the mark before it and toward the next mark
## after it, against the boat's own steady VMG for each leg's sector in this wind bin (from
## `wind_rows`, her steady-sailing table). Upwind and downwind legs use VMG to the wind; reaches
## use VMC to the mark. Loss is the distance a boat holding that steady VMG would gain on her.
static func _rounding(s: Array, ev: Dictionary, meta: Dictionary, cfgr: Dictionary, wind_rows: Array, targets: Dictionary) -> Dictionary:
	var k := int(ev["leg"])
	var here := _point(meta, k)
	var next := _point(meta, k + 1)
	var t0 := float(ev["t"])
	var res := {"kind": "rounding", "mark": ev.get("mark", "G"), "t": t0, "bins": [], "loss_m": 0.0, "complete": false}
	var at := _at(s, t0)
	if at.is_empty():
		return res
	var up := _wind_up(meta, t0)
	var sec_in := _leg_sector(here - _point(meta, k - 1), up, targets)
	var sec_out := _leg_sector(next - here, up, targets)
	var bin := Targets.wind_bin(targets, float(at["tws"]) / KN)
	var ref_in := _steady_vmg(wind_rows, bin, sec_in)
	var ref_out := _steady_vmg(wind_rows, bin, sec_out)
	if ref_in <= 0.0 or ref_out <= 0.0:
		return res
	res["legs"] = [sec_in, sec_out]
	res["ref_in"] = ref_in
	res["ref_out"] = ref_out
	var bins: Array = cfgr["time_bins_s"]
	var acc := []
	for b in bins:
		acc.append({"from": float(b[0]), "to": float(b[1]), "dur": 0.0, "made": 0.0, "dist": 0.0})
	var last := t0 + float(bins[bins.size() - 1][1])
	for i in range(maxi(1, Moves.first_index(s, t0 + float(bins[0][0]) - 1.0)), s.size()):
		var x: Dictionary = s[i]
		var t: float = x["t"]
		if t > last + 1.0:
			break
		var rel := t - t0
		var dt: float = t - float(s[i - 1]["t"])
		for a: Dictionary in acc:
			if rel > a["from"] and rel <= a["to"]:
				var before: bool = a["to"] <= 0.0
				a["dur"] += dt
				a["made"] += _leg_vmg(x, sec_in if before else sec_out, here if before else next) * dt
				a["dist"] += float(x["speed"]) * dt
	for a: Dictionary in acc:
		if a["dur"] < 0.8 * (a["to"] - a["from"]):
			return res
	res["complete"] = true
	for a: Dictionary in acc:
		var ref := ref_in if a["to"] <= 0.0 else ref_out
		var loss: float = ref * a["dur"] - a["made"]
		res["bins"].append({"from": a["from"], "to": a["to"], "speed": a["dist"] / a["dur"], "vmg": a["made"] / a["dur"], "loss_m": loss})
		res["loss_m"] += loss
	return res


## Time of the boat's closest approach to `mark` in the minute before `t_event` (and a few
## seconds after it).
static func _closest_approach(s: Array, mark: Vector2, t_event: float) -> float:
	var best := INF
	var best_t := t_event
	for i in range(Moves.first_index(s, t_event - 60.0), s.size()):
		var x: Dictionary = s[i]
		if float(x["t"]) > t_event + 5.0:
			break
		var d := Vector2(x["pos"]).distance_squared_to(mark)
		if d < best:
			best = d
			best_t = x["t"]
	return best_t


## Unit vector pointing up wind at time t, from the session's wind series.
static func _wind_up(meta: Dictionary, t: float) -> Vector2:
	var from := 0.0
	var best := INF
	for w: Array in meta.get("wind", []):
		var d := absf(float(w[0]) - t)
		if d < best:
			best = d
			from = float(w[1])
	if best == INF and meta["cfg"].has("wind_from"):
		from = float(meta["cfg"]["wind_from"])
	return Vector2(sin(deg_to_rad(from)), cos(deg_to_rad(from)))


static func _leg_sector(dir: Vector2, up: Vector2, targets: Dictionary) -> String:
	var sec: Dictionary = targets["polar"]["sectors_deg"]
	var a := rad_to_deg(acos(clampf(dir.normalized().dot(up), -1.0, 1.0)))
	if a < float(sec["upwind"][1]):
		return "upwind"
	if a >= float(sec["downwind"][0]):
		return "downwind"
	return "reach"


## VMG in a leg's terms: to the wind upwind and downwind, toward the mark on a reach.
static func _leg_vmg(x: Dictionary, sector: String, mark: Vector2) -> float:
	var spd: float = x["speed"]
	match sector:
		"upwind":
			return spd * cos(float(x["twa"]))
		"downwind":
			return -spd * cos(float(x["twa"]))
	var vel := Vector2(sin(x["hdg"]), cos(x["hdg"])) * spd
	return vel.dot((mark - Vector2(x["pos"])).normalized())


## Steady VMG (m/s) for a sector in a wind bin, or over every bin if that one has none.
static func _steady_vmg(rows: Array, bin: String, sector: String) -> float:
	var made := 0.0
	var time := 0.0
	for r: Dictionary in rows:
		if r["sector"] != sector:
			continue
		if r["bin"] == bin:
			return float(r["vmg_kn"]) * KN
		made += float(r["vmg_kn"]) * KN * float(r["time_s"])
		time += float(r["time_s"])
	return made / time if time > 0.0 else 0.0


## The start: where the bow was at the gun, how fast, how late across, and how far behind a
## boat that hit the line at the gun at her own steady upwind VMG she is 30 s later.
static func _start(s: Array, meta: Dictionary, gun_t: float, t_start: float, cfgs: Dictionary, bl: float, ocs: bool, targets: Dictionary) -> Dictionary:
	if not meta.has("rc") or meta.get("gun_t") == null:
		return {}
	var rc := _v(meta["rc"])
	var along := (_v(meta["pin"]) - rc).normalized()
	var n := Vector2(-along.y, along.x)
	if n.dot(_v(meta["line_up"])) < 0.0:
		n = -n
	var base: Array = cfgs["baseline_s"]
	var at_gun := _at(s, gun_t)
	# Steady upwind VMG from 30-60 s after she crossed the line (or the gun, if she was on time).
	var base_t := maxf(gun_t, t_start) if t_start < INF else gun_t
	if at_gun.is_empty() or float(s[s.size() - 1]["t"]) < base_t + float(base[1]):
		return {"complete": false}
	var dist := func(x: Dictionary) -> float:
		var bow: Vector2 = x["pos"] + Vector2(sin(x["hdg"]), cos(x["hdg"])) * BOW_X
		return (bow - rc).dot(n)
	var sum_v := 0.0
	var sum_s := 0.0
	var dur := 0.0
	for i in range(maxi(1, Moves.first_index(s, base_t + float(base[0]))), s.size()):
		var x: Dictionary = s[i]
		if float(x["t"]) > base_t + float(base[1]):
			break
		var dt: float = float(x["t"]) - float(s[i - 1]["t"])
		sum_v += float(x["speed"]) * cos(float(x["twa"])) * dt
		sum_s += float(x["speed"]) * dt
		dur += dt
	if dur <= 0.0:
		return {"complete": false}
	var ref_vmg := sum_v / dur
	var ref_speed := sum_s / dur
	var at30 := _at(s, gun_t + 30.0)
	var loss: float = ref_vmg * 30.0 - float(dist.call(at30))
	var bins := []
	for b in cfgs["time_bins_s"]:
		var spd := 0.0
		var d := 0.0
		for i in range(maxi(1, Moves.first_index(s, gun_t + float(b[0]))), s.size()):
			var x: Dictionary = s[i]
			if float(x["t"]) > gun_t + float(b[1]):
				break
			var dt: float = float(x["t"]) - float(s[i - 1]["t"])
			spd += float(x["speed"]) * dt
			d += dt
		var end_at := _at(s, gun_t + float(b[1]))
		bins.append({"from": float(b[0]), "to": float(b[1]), "speed_kn": (spd / d / KN) if d > 0.0 else 0.0,
			"line_m": float(dist.call(end_at)) if not end_at.is_empty() else 0.0})
	var bin := Targets.wind_bin(targets, float(at_gun["tws"]) / KN)
	var res := {
		"complete": true, "ocs": ocs, "wind_bin": bin,
		"behind_m": -float(dist.call(at_gun)), "speed_kn": float(at_gun["speed"]) / KN,
		"speed_ratio": float(at_gun["speed"]) / maxf(ref_speed, 0.1),
		"late_s": (t_start - gun_t) if t_start < INF else null,
		"ref_vmg_kn": ref_vmg / KN, "loss_m": loss, "lengths": loss / bl, "bins": bins,
	}
	res["checks"] = [
		Targets.check("behind the line (m)", cfgs["behind_line_m"], bin, res["behind_m"]),
		Targets.check("speed ratio at gun", cfgs["speed_ratio_at_gun"], bin, res["speed_ratio"]),
		Targets.check("start loss (lengths)", cfgs["loss_boat_lengths"], bin, res["lengths"]),
	]
	return res


## Steady sailing by wind bin and sector: time, speed, VMG and angle, with target checks.
static func _wind_table(s: Array, t_start: float, t_end: float, skip: Array, pens: Array, targets: Dictionary) -> Array:
	var sec: Dictionary = targets["polar"]["sectors_deg"]
	var cells := {}
	for i in range(1, s.size()):
		var x: Dictionary = s[i]
		var t: float = x["t"]
		if t <= t_start or t > t_end or x["capsized"] or _inside(t, skip) or _inside(t, pens):
			continue
		var dt: float = t - float(s[i - 1]["t"])
		if dt > 1.0:
			continue
		var bin := Targets.wind_bin(targets, float(x["tws"]) / KN)
		if bin == "":
			continue
		var a := absf(rad_to_deg(float(x["twa"])))
		var sector := "upwind" if a < float(sec["upwind"][1]) else ("downwind" if a >= float(sec["downwind"][0]) else "reach")
		var spd: float = x["speed"]
		var vmg := spd * cos(float(x["twa"]))
		if sector == "downwind":
			vmg = -vmg
		elif sector == "reach":
			vmg = spd
		var key := bin + "|" + sector
		if not cells.has(key):
			cells[key] = {"time": 0.0, "dist": 0.0, "made": 0.0, "twa": 0.0}
		var c: Dictionary = cells[key]
		c["time"] += dt
		c["dist"] += spd * dt
		c["made"] += vmg * dt
		c["twa"] += a * dt
	var rows := []
	var polar: Dictionary = targets["polar"]
	for wb: Dictionary in targets["wind_bins"]:
		for sector: String in SECTORS:
			var key: String = wb["name"] + "|" + sector
			if not cells.has(key) or cells[key]["time"] < 20.0:
				continue
			var c: Dictionary = cells[key]
			var row := {"bin": wb["name"], "sector": sector, "time_s": c["time"], "speed_kn": c["dist"] / c["time"] / KN,
				"vmg_kn": c["made"] / c["time"] / KN, "twa_deg": c["twa"] / c["time"], "checks": []}
			if sector == "upwind":
				row["checks"].append(Targets.check("upwind angle (deg)", polar["upwind_twa_deg"], wb["name"], row["twa_deg"]))
				row["checks"].append(Targets.check("upwind VMG (kn)", polar["upwind_vmg_kn"], wb["name"], row["vmg_kn"]))
			elif sector == "downwind":
				row["checks"].append(Targets.check("downwind VMG (kn)", polar["downwind_vmg_kn"], wb["name"], row["vmg_kn"]))
			rows.append(row)
	return rows


static func _point(meta: Dictionary, i: int) -> Vector2:
	var course: Array = meta["course"]
	if i < 0 or i >= course.size() or course[i] == "G" or course[i] == "F":
		return (_v(meta["rc"]) + _v(meta["pin"])) * 0.5
	return _v(meta["marks"][course[i]])


## The sample nearest time t, or {} if t is outside the track.
static func _at(s: Array, t: float) -> Dictionary:
	if s.is_empty() or t < float(s[0]["t"]) - 0.5 or t > float(s[s.size() - 1]["t"]) + 0.5:
		return {}
	var i := clampi(Moves.first_index(s, t), 0, s.size() - 1)
	if i > 0 and absf(float(s[i - 1]["t"]) - t) < absf(float(s[i]["t"]) - t):
		i -= 1
	return s[i]


## From the start of the first scored (non-baseline) bin to the end of the last one.
static func _scored_range(bins: Array, baselines: Array) -> Vector2:
	var r := Vector2(INF, -INF)
	var base := baselines.map(func(b): return int(b))
	for k in bins.size():
		if not base.has(k):
			r.x = minf(r.x, float(bins[k][0]))
			r.y = maxf(r.y, float(bins[k][1]))
	return r


## True if the span of any move other than the one at t0 overlaps the window [w0, w1].
## With only_roundings, other tacks and gybes are ignored.
static func _overlaps(t0: float, w: Array, spans: Array, only_roundings: bool) -> bool:
	for sp: Array in spans:
		if absf(float(sp[2]) - t0) < 0.05 or (only_roundings and not sp[3] and float(sp[2]) >= 0.0):
			continue
		if float(sp[0]) < float(w[1]) and float(sp[1]) > float(w[0]):
			return true
	return false


static func _inside(t: float, windows: Array) -> bool:
	for w: Array in windows:
		if t >= float(w[0]) and t <= float(w[1]):
			return true
	return false


static func _v(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var t := 0.0
	for x in xs:
		t += float(x)
	return t / xs.size()
