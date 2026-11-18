extends SceneTree
## Speed polar for the physics model: steady speed at each true wind angle with auto trim and
## auto hike, plus best upwind and downwind VMG, for each wind bin in data/targets.json.
## Hard checks: broad sanity ranges, no capsizes, smooth speed with angle, and the rig tune
## doing what it should. Target checks: data/targets.json, where estimates only warn.
## Run: godot --headless --path . --script res://tests/polar_test.gd

const BoatSim := preload("res://scripts/boat_sim.gd")
const Targets := preload("res://scripts/targets.gd")
const KN := 0.514444

var fails := 0
var warns := 0


func _init() -> void:
	var t := Targets.load_all()
	var polar: Dictionary = t["polar"]
	for wb: Dictionary in t["wind_bins"]:
		var bin: String = wb["name"]
		var tws_kn := float(wb["test_kn"])
		var line := "TWS %4.1f kn |" % tws_kn
		var best_up := Vector2(0, -1)
		var best_dn := Vector2(0, -1)
		var capsizes := 0
		var speeds := {}
		for twa_deg in range(30, 181, 10):
			var res := steady(tws_kn, float(twa_deg))
			speeds[twa_deg] = res.x / KN
			line += " %d:%.1f" % [twa_deg, res.x / KN]
			capsizes += int(res.y)
		for twa_deg in range(26, 60, 2):
			var sp := steady(tws_kn, float(twa_deg)).x
			var vmg := sp * cos(deg_to_rad(twa_deg))
			if vmg > best_up.y:
				best_up = Vector2(twa_deg, vmg)
		for twa_deg in range(120, 181, 5):
			var sp := steady(tws_kn, float(twa_deg)).x
			var vmg := -sp * cos(deg_to_rad(twa_deg))
			if vmg > best_dn.y:
				best_dn = Vector2(twa_deg, vmg)
		print(line)
		print("    upwind best TWA %d VMG %.2f kn | downwind best TWA %d VMG %.2f kn | capsizes %d" % [best_up.x, best_up.y / KN, best_dn.x, best_dn.y / KN, capsizes])
		var up_kn := best_up.y / KN
		check(up_kn > 1.2 and up_kn < 5.0, "upwind VMG %.2f kn at %.0f kn" % [up_kn, tws_kn])
		check(best_up.x > 26 and best_up.x < 58, "upwind angle %d at %.0f kn is at the edge of the search" % [best_up.x, tws_kn])
		check(capsizes == 0, "%d capsizes at %.0f kn" % [capsizes, tws_kn])
		var reach: float = speeds[100]
		check(reach > 0.35 * tws_kn and reach < 0.9 * tws_kn + 1.0, "beam reach %.1f kn at %.0f kn" % [reach, tws_kn])
		# Speed should rise to one reach peak and fall away after it. Picking up again once it has
		# started to drop means a settings switch, not physics. 0.02 kn of noise doesn't count as
		# a drop.
		var top := 0.0
		var dropped := false
		var regain := 0.0
		var regain_at := 0
		for twa_deg in range(40, 171, 10):
			var sp: float = speeds[twa_deg]
			if dropped and sp - float(speeds[twa_deg - 10]) > regain:
				regain = sp - float(speeds[twa_deg - 10])
				regain_at = twa_deg
			top = maxf(top, sp)
			if sp < top - 0.02:
				dropped = true
		target("largest regain after a drop (kn)" + (" at %d deg" % regain_at if regain_at > 0 else ""), polar["max_regain_kn"], bin, regain)
		target("upwind best TWA (deg)", polar["upwind_twa_deg"], bin, best_up.x)
		target("upwind VMG (kn)", polar["upwind_vmg_kn"], bin, up_kn)
		target("downwind VMG (kn)", polar["downwind_vmg_kn"], bin, best_dn.y / KN)
	# Sail shape: depowering pays in a breeze and costs in light air. "Flat" is the crew's
	# heavy-air tune from the guide (outhaul at the band, cunningham on, vang on, mast pulled
	# back, traveler down a little, halyard tight). "Full" is every control set for power
	# (outhaul eased 3 in, cunningham off, mast straight at the aft mark, halyard eased 3 in,
	# vang hard on).
	var flat := tune_for(18.0)
	var full := {"outhaul": 3.0, "cunningham": 0.0, "vang": 1.0, "traveler": 0.0, "puller": BoatSim.PULLER_MIN, "halyard": 3.0}
	var vmg := func(kn: float, rig: Dictionary) -> float:
		return steady(kn, 42.0, rig).x * cos(deg_to_rad(42.0)) / KN
	var heavy_flat: float = vmg.call(18.0, flat)
	var heavy_full: float = vmg.call(18.0, full)
	var light_flat: float = vmg.call(6.0, flat)
	var light_full: float = vmg.call(6.0, full)
	print("rig: 18 kn flat %.2f vs full %.2f | 6 kn flat %.2f vs full %.2f (VMG kn)" % [heavy_flat, heavy_full, light_flat, light_full])
	check(heavy_flat > heavy_full, "flattening pays in 18 kn")
	check(light_full > light_flat, "a full sail pays in 6 kn")
	print("polar_test: %s, %d target warning(s)" % ["PASS" if fails == 0 else "FAIL (%d)" % fails, warns])
	quit(1 if fails > 0 else 0)


## The upwind controls the crew sets for this wind (auto_rig), to sail in another wind.
func tune_for(kn: float) -> Dictionary:
	var b := BoatSim.new()
	b.tws = kn * KN
	b.twa = deg_to_rad(42.0)
	b.auto_rig()
	var out := {}
	for k: String in ["outhaul", "cunningham", "vang", "traveler", "puller", "halyard"]:
		out[k] = b.get(k)
	return out


## Returns Vector2(mean speed m/s over the last 20 s, 1 if it capsized). rig: controls to hold
## at these values; the rest are the crew's (auto_rig), and the crew handles the pole.
func steady(tws_kn: float, twa_deg: float, rig := {}) -> Vector2:
	var b := BoatSim.new()
	var wind_from := 0.0
	var want := deg_to_rad(wind_from - twa_deg)  # starboard tack
	b.place(Vector2.ZERO, fposmod(want, TAU), 1.5)
	var wind := Vector2(0, -tws_kn * KN)
	var dt := 1.0 / 120.0
	var sum := 0.0
	var n := 0
	var capsized := 0.0
	for i in 120 * 80:
		if i % 30 == 0:
			b.auto_rig(rig)
			for k: String in rig:
				b.set(k, rig[k])
			b.crew_pole()
			var sh := b.best_sheets()
			b.main_sheet = sh.x
			b.jib_sheet = sh.y
		b.hike = lerpf(b.hike, b.auto_hike(), 0.05)
		var err := wrapf(want - b.heading, -PI, PI)
		b.tiller = clampf(3.0 * err - 1.5 * b.r, -1.0, 1.0)
		b.step(dt, wind)
		if b.capsized:
			capsized = 1.0
		if i > 120 * 60:
			sum += b.u
			n += 1
	return Vector2(sum / n, capsized)


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: " + what)


func target(name: String, entry: Dictionary, bin: String, value: float) -> void:
	var c := Targets.check(name, entry, bin, value)
	match c["status"]:
		"fail":
			fails += 1
			print("  FAIL: " + c["text"])
		"warn":
			warns += 1
			print("  WARN: " + c["text"])
		"ok":
			print("  ok:   " + c["text"])
		_:
			print("  --    " + c["text"])
