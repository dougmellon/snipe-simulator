extends SceneTree
## Speed polar for the physics model: steady speed at each true wind angle with auto trim and
## auto hike, plus best upwind and downwind VMG. Checks the numbers are in a sane Snipe range.
## Run: godot --headless --path . --script res://tests/polar_test.gd

const BoatSim := preload("res://scripts/boat_sim.gd")
const KN := 0.514444

var fails := 0


func _init() -> void:
	for tws_kn in [6.0, 10.0, 14.0, 18.0]:
		var line := "TWS %4.1f kn |" % tws_kn
		var best_up := Vector2(0, -1)
		var best_dn := Vector2(0, -1)
		var capsizes := 0
		for twa_deg in range(30, 181, 10):
			var res := steady(tws_kn, float(twa_deg))
			line += " %d:%.1f" % [twa_deg, res.x / KN]
			capsizes += int(res.y)
		for twa_deg in range(34, 60, 2):
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
		check(best_up.x >= 33 and best_up.x <= 52, "upwind angle %d at %.0f kn" % [best_up.x, tws_kn])
		var reach := steady(tws_kn, 100.0).x / KN
		check(reach > 0.35 * tws_kn and reach < 0.9 * tws_kn + 1.0, "beam reach %.1f kn at %.0f kn" % [reach, tws_kn])
	# Sail shape: depowering pays in a breeze and costs in light air.
	var vmg := func(kn: float, rig: Vector2) -> float:
		return steady(kn, 42.0, rig).x * cos(deg_to_rad(42.0)) / KN
	var heavy_flat: float = vmg.call(18.0, Vector2(1.0, 0.2))
	var heavy_full: float = vmg.call(18.0, Vector2(0.0, 1.0))
	var light_flat: float = vmg.call(6.0, Vector2(1.0, 0.2))
	var light_full: float = vmg.call(6.0, Vector2(0.0, 1.0))
	print("rig: 18 kn flat %.2f vs full %.2f | 6 kn flat %.2f vs full %.2f (VMG kn)" % [heavy_flat, heavy_full, light_flat, light_full])
	check(heavy_flat > heavy_full, "flattening pays in 18 kn")
	check(light_full > light_flat, "a full sail pays in 6 kn")
	print("polar_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


## Returns Vector2(mean speed m/s over the last 20 s, 1 if it capsized). rig = Vector2(flatten,
## vang), or negative for the crew's auto rig tune.
func steady(tws_kn: float, twa_deg: float, rig := Vector2(-1, -1)) -> Vector2:
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
			if rig.x < 0.0:
				b.auto_rig()
			else:
				b.flatten = rig.x
				b.vang = rig.y
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
