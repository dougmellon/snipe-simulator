extends SceneTree
## When does she go over? Steady sailing in situations a Snipe sailor knows: she must capsize
## when she is overpowered and nobody eases (a puff on a reach with the sheets cleated, the
## crew not hiking in a breeze, the crew stuck out hiking when the sheets are let go), and must
## not when she is sailed well (trimmed for the puff, hiked flat upwind, light air with the crew
## to leeward).
## Run: godot --headless --path . --script res://tests/capsize_test.gd

const BoatSim := preload("res://scripts/boat_sim.gd")
const KN := 0.514444

var fails := 0


func _init() -> void:
	# [what, wind kn, twa deg, main sheet (-1 = trimmed to best all along, -2 = trimmed for
	# 12 kn and cleated before the puff hits), jib sheet (same), hike (99 = crew hikes as needed),
	# expect capsize?]
	var cases := [
		["22 kn puff on a beam reach, cleated, crew hiking", 22.0, 90.0, -2.0, -2.0, 99.0, false],
		["22 kn puff on a beam reach, cleated, crew sitting in", 22.0, 90.0, -2.0, -2.0, 0.0, true],
		["same puff, main and jib played for it", 22.0, 90.0, -1.0, -1.0, 99.0, false],
		["22 kn puff close-hauled, sheets cleated for 12 kn", 22.0, 45.0, -2.0, -2.0, 99.0, true],
		["upwind in 12 kn, trimmed hard, crew hiking", 12.0, 42.0, 0.05, 0.2, 99.0, false],
		["upwind in 16 kn, trimmed hard, crew sitting in", 16.0, 42.0, 0.05, 0.2, 0.0, true],
		["crew hiked out, sheets let fly in 10 kn", 10.0, 42.0, 1.0, 1.0, 1.0, true],
		["light air, crew to leeward, trimmed", 5.0, 42.0, 0.05, 0.2, -1.0, false],
	]
	for c: Array in cases:
		var r := run(c[1], c[2], c[3], c[4], c[5])
		var went: bool = r["capsized"]
		print("%-52s max heel %3.0f°  water %3.0f%%  boom in %.2f m  %s" % [c[0], r["max_heel"], 100.0 * r["max_water"], r["max_dip"],
			("CAPSIZED to %s after %.1f s" % [r["side"], r["t"]]) if went else "upright"])
		check(went == c[6], "%s: expected %s" % [c[0], "a capsize" if c[6] else "no capsize"])
	print("capsize_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func run(kn: float, twa_deg: float, main: float, jib: float, hike: float) -> Dictionary:
	var b := BoatSim.new()
	var want := deg_to_rad(-twa_deg)  # wind from the north, starboard tack
	b.place(Vector2.ZERO, fposmod(want, TAU), 3.0)
	b.tws = kn * KN
	b.twa = deg_to_rad(twa_deg)
	b.auto_rig()
	var wind := Vector2(0, -kn * KN)
	var dt := 1.0 / 120.0
	var out := {"capsized": false, "max_heel": 0.0, "max_water": 0.0, "max_dip": 0.0, "t": 0.0, "side": ""}
	# Cleated for 12 kn: sail 15 s in 12 kn trimmed to best, then the puff hits.
	var pre := 120 * 15 if main < -1.5 else 0
	for i in 120 * 40 + pre:
		var w := Vector2(0, -12.0 * KN) if i < pre else wind
		if i % 30 == 0 and (i < pre or main > -1.5):
			var sh := b.best_sheets()
			b.main_sheet = sh.x if main < 0.0 else main
			b.jib_sheet = sh.y if jib < 0.0 else jib
		b.hike = lerpf(b.hike, b.auto_hike(4.0), clampf(dt * 3.0, 0.0, 1.0)) if hike > 50.0 else hike
		b.tiller = clampf(3.0 * wrapf(want - b.heading, -PI, PI) - 1.5 * b.r, -1.0, 1.0)
		b.step(dt, w)
		if i < pre:
			continue
		out["max_heel"] = maxf(out["max_heel"], rad_to_deg(absf(b.heel)))
		out["max_water"] = maxf(out["max_water"], b.water_in)
		out["max_dip"] = maxf(out["max_dip"], b.boom_dip)
		if b.capsized:
			out["capsized"] = true
			out["t"] = (i - pre) * dt
			# Starboard tack: the wind comes over the starboard side, so starboard is to windward.
			out["side"] = "windward" if b.capsize_side > 0.0 else "leeward"
			break
	return out


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: " + what)
