extends RefCounted
## Moves (tacks and gybes) in a time series, and what each one cost, in time bins around it.
## The same code reads sim runs now and real-boat logs later.
##
## A sample is a Dictionary {"t": seconds, "speed": m/s, "twa": signed radians, + = wind over
## the starboard side}. Speed should be through the water or over the ground, whichever the
## log has. VMG is speed * cos(twa) upwind and the opposite downwind; leeway is ignored.

const MIN_GAP_S := 5.0   # crossings closer together than this are one move (wobbles in irons)
const ZONE_DEG := 5.0    # how far inside the baseline angle counts as "in the move"


## Every tack (twa crossing 0) and gybe (twa crossing 180) as {"kind", "t"}, where t is the
## interpolated moment of head to wind or dead downwind.
static func find(samples: Array) -> Array:
	var out := []
	var last := {"tack": -INF, "gybe": -INF}
	for i in range(1, samples.size()):
		var a: float = samples[i - 1]["twa"]
		var b: float = samples[i]["twa"]
		if a == 0.0 or signf(a) == signf(b):
			continue
		var kind := ""
		var frac := 0.0
		if absf(a) < PI / 2.0 and absf(b) < PI / 2.0:
			kind = "tack"
			frac = absf(a) / (absf(a) + absf(b))
		elif absf(a) > PI / 2.0 and absf(b) > PI / 2.0:
			kind = "gybe"
			frac = (PI - absf(a)) / ((PI - absf(a)) + (PI - absf(b)))
		else:
			continue
		var t0: float = samples[i - 1]["t"]
		var t1: float = samples[i]["t"]
		var t := lerpf(t0, t1, frac)
		if t - float(last[kind]) < MIN_GAP_S:
			continue
		last[kind] = t
		out.append({"kind": kind, "t": t})
	return out


## Index of the first sample at or after time `t` (samples are in time order).
static func first_index(samples: Array, t: float) -> int:
	var lo := 0
	var hi := samples.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if float(samples[mid]["t"]) < t:
			lo = mid + 1
		else:
			hi = mid
	return lo


static func vmg(s: Dictionary, kind: String) -> float:
	var v: float = float(s["speed"]) * cos(float(s["twa"]))
	return v if kind == "tack" else -v


## Scores one move. `bins` is an Array of [from_s, to_s] relative to the move; `baseline` is
## the index (or an Array of indices) of the bins of steady sailing the others are scored
## against. With a bin before and one after, a tack on a wind shift comes out even.
## Returns {"kind", "t", "complete", "ref_speed", "ref_vmg", "ref_twa_deg", "bins": [{"from",
## "to", "speed", "vmg", "loss_m"}], "loss_m", "min_speed_ratio", "duration_s"}.
static func score(samples: Array, move: Dictionary, bins: Array, baseline: Variant) -> Dictionary:
	var bases: Array = []
	for b in (baseline if baseline is Array else [baseline]):
		bases.append(int(b))  # JSON numbers are floats; has() below compares with ints
	var kind: String = move["kind"]
	var t0: float = move["t"]
	var first := t0 + float(bins[0][0])
	var end := t0 + float(bins[bins.size() - 1][1])
	var acc := []
	for b in bins:
		acc.append({"from": float(b[0]), "to": float(b[1]), "dur": 0.0, "dist": 0.0, "made": 0.0, "twa": 0.0, "min": INF})
	var covered_from := INF
	var covered_to := -INF
	var i0 := maxi(1, first_index(samples, first - 1.0))
	for i in range(i0, samples.size()):
		var s: Dictionary = samples[i]
		var t: float = s["t"]
		if t > end + 1.0:
			break
		var dt: float = t - float(samples[i - 1]["t"])
		var rel := t - t0
		for a: Dictionary in acc:
			if rel > a["from"] and rel <= a["to"]:
				a["dur"] += dt
				a["dist"] += float(s["speed"]) * dt
				a["made"] += vmg(s, kind) * dt
				a["twa"] += absf(float(s["twa"])) * dt
				a["min"] = minf(a["min"], float(s["speed"]))
		if t >= first and t <= end:
			covered_from = minf(covered_from, t)
			covered_to = maxf(covered_to, t)
	var base := {"dur": 0.0, "dist": 0.0, "made": 0.0, "twa": 0.0}
	var every_base := true
	for k in bases:
		var a: Dictionary = acc[int(k)]
		every_base = every_base and a["dur"] > 0.0
		for f in base:
			base[f] += a[f]
	var res := {"kind": kind, "t": t0, "bins": [], "loss_m": 0.0, "min_speed_ratio": 0.0, "duration_s": 0.0}
	res["complete"] = every_base and covered_from - first < 0.5 and end - covered_to < 0.5
	if base["dur"] <= 0.0:
		return res
	var ref_speed: float = base["dist"] / base["dur"]
	var ref_vmg: float = base["made"] / base["dur"]
	var ref_twa: float = base["twa"] / base["dur"]
	res["ref_speed"] = ref_speed
	res["ref_vmg"] = ref_vmg
	res["ref_twa_deg"] = rad_to_deg(ref_twa)
	var min_speed := INF
	for k in acc.size():
		if bases.has(k):
			continue
		var a: Dictionary = acc[k]
		var d: float = maxf(a["dur"], 1e-6)
		var loss: float = ref_vmg * a["dur"] - a["made"]
		res["bins"].append({"from": a["from"], "to": a["to"], "speed": a["dist"] / d, "vmg": a["made"] / d, "loss_m": loss})
		res["loss_m"] += loss
		min_speed = minf(min_speed, a["min"])
	res["min_speed_ratio"] = min_speed / maxf(ref_speed, 1e-6)
	# Time spent inside the baseline angle: closer to the wind than close-hauled for a tack,
	# deeper than the baseline angle for a gybe.
	var zone := deg_to_rad(ZONE_DEG)
	for i in range(i0, samples.size()):
		var s: Dictionary = samples[i]
		var t: float = s["t"]
		if t > end:
			break
		if t <= first:
			continue
		var w := absf(float(s["twa"]))
		var inside: bool = (w < ref_twa - zone) if kind == "tack" else (w > ref_twa + zone)
		if inside:
			res["duration_s"] += t - float(samples[i - 1]["t"])
	return res
