extends RefCounted
## Who broke a rule when two boats touch (RRS Part 2, Section A and rule 13). Simplified: no
## mark-room (rule 18) or obstruction calls.

const TACKING_AWA := 0.45  # a boat this close to head-to-wind while turning counts as tacking


## Returns {"fault": 0 or 1 (index of the boat that must keep clear), "rule": String}.
static func adjudicate(a, b, wind_from_deg: float) -> Dictionary:
	var boats := [a, b]
	# Rule 13: a boat past head to wind and not yet close-hauled keeps clear.
	var tacking := []
	for x in boats:
		tacking.append(absf(x.awa) < TACKING_AWA and absf(x.r) > 0.15)
	if tacking[0] != tacking[1]:
		return {"fault": 0 if tacking[0] else 1, "rule": "rule 13 (while tacking)"}
	var ta: int = a.tack()
	var tb: int = b.tack()
	if ta != tb:
		# Rule 10: port-tack boat keeps clear of a starboard-tack boat.
		return {"fault": 0 if ta < 0 else 1, "rule": "rule 10 (port/starboard)"}
	if clear_astern(a, b):
		return {"fault": 0, "rule": "rule 12 (clear astern)"}
	if clear_astern(b, a):
		return {"fault": 1, "rule": "rule 12 (clear astern)"}
	# Rule 11: overlapped on the same tack, the windward boat keeps clear.
	var up := Vector2(sin(deg_to_rad(wind_from_deg)), cos(deg_to_rad(wind_from_deg)))
	var fa: bool = a.pos.dot(up) > b.pos.dot(up)
	return {"fault": 0 if fa else 1, "rule": "rule 11 (windward boat)"}


## True when `x` is clear astern of `y`: x's whole hull is behind a line abeam from y's stern.
static func clear_astern(x, y) -> bool:
	var f: Vector2 = y.fwd()
	var s: Vector2 = y.stern()
	return (x.bow() - s).dot(f) < 0.0 and (x.stern() - s).dot(f) < 0.0
