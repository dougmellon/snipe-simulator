extends RefCounted
## Target numbers from data/targets.json, and checking a sim result against them.
## A measured or model-check target that is missed is a FAIL. A first-principles or estimate
## target that is missed is a WARN, since nobody has confirmed it on a real Snipe yet.

const PATH := "res://data/targets.json"
const HARD_SOURCES := ["measured", "model check"]


static func load_all() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if d is Dictionary else {}


## Name of the wind bin holding `kn` (bins are [low, high) knots), or "" if none does.
static func wind_bin(t: Dictionary, kn: float) -> String:
	for b: Dictionary in t.get("wind_bins", []):
		var r: Array = b["tws_kn"]
		if kn >= float(r[0]) and kn < float(r[1]):
			return b["name"]
	return ""


## The [low, high] range for a wind bin, falling back to "all". null when there's no target.
static func range_for(entry: Dictionary, bin: String) -> Variant:
	if entry.has(bin):
		return entry[bin]
	return entry.get("all")


## Checks `value` against `entry` for a wind bin. Returns {"status": "ok" | "warn" | "fail" |
## "none", "text": one line for the test output}.
static func check(name: String, entry: Dictionary, bin: String, value: float) -> Dictionary:
	var r: Variant = range_for(entry, bin)
	var src: String = str(entry.get("source")) if entry.get("source") != null else "no source"
	if r == null:
		return {"status": "none", "text": "%s [%s] %.2f: no target yet" % [name, bin, value]}
	var lo := float(r[0])
	var hi := float(r[1])
	if value >= lo and value <= hi:
		return {"status": "ok", "text": "%s [%s] %.2f within %.2f-%.2f (%s)" % [name, bin, value, lo, hi, src]}
	var status := "fail" if HARD_SOURCES.has(src) else "warn"
	return {"status": status, "text": "%s [%s] %.2f outside %.2f-%.2f (%s)" % [name, bin, value, lo, hi, src]}
