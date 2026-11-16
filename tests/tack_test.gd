extends SceneTree
## Manoeuvre checks: tacks and gybes from steady sailing, a tack with a moderate helm from a
## slow start, and a boat left dead in irons must fall off by itself.
## Run: godot --headless --path . --script res://tests/tack_test.gd
const BoatSim := preload("res://scripts/boat_sim.gd")
const KN := 0.514444
var fails := 0

func _init() -> void:
	for kn in [5.0, 10.0, 16.0]:
		turn(kn, true, 1.0, 0.0)
		turn(kn, false, 1.0, 0.0)
		turn(kn, true, 0.7, 3.0)
		irons(kn)
	print("tack_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)

## Steady close-hauled (or broad reach) 40 s, optionally slowed to `slow_kn`, then turn.
func turn(kn: float, is_tack: bool, helm: float, slow_kn: float) -> void:
	var b := BoatSim.new()
	var twa := 42.0 if is_tack else 150.0
	var want := deg_to_rad(-twa)
	b.place(Vector2.ZERO, fposmod(want, TAU), 2.0)
	var wind := Vector2(0, -kn * KN)
	var dt := 1.0 / 120.0
	var phase := 0
	var t_turn := 0.0
	var min_u := 99.0
	var start_u := 0.0
	var target := deg_to_rad(twa)
	for i in 120 * 90:
		if i % 30 == 0:
			var sh := b.best_sheets()
			b.main_sheet = sh.x
			b.jib_sheet = sh.y
		if slow_kn > 0.0 and phase == 0 and i > 120 * 30 and b.u > slow_kn * KN:
			b.main_sheet = 1.0
			b.jib_sheet = 1.0
		b.hike = lerpf(b.hike, b.auto_hike(), 0.05)
		if phase == 0 and i > 120 * 40 and (slow_kn == 0.0 or b.u <= slow_kn * KN):
			phase = 1
			start_u = b.u
		if phase == 1:
			b.tiller = helm if is_tack else -helm
			t_turn += dt
			min_u = minf(min_u, b.u)
			if absf(wrapf(target - b.heading, -PI, PI)) < 0.1:
				phase = 2
		else:
			var goal := want if phase == 0 else target
			b.tiller = clampf(3.0 * wrapf(goal - b.heading, -PI, PI) - 1.5 * b.r, -1.0, 1.0)
		b.step(dt, wind)
	var ok := phase == 2 and t_turn < 12.0
	print("%s %4.1f kn, helm %.1f, from %.1f kn: %s in %.1f s, min %.2f kn, after %.2f kn" % ["tack" if is_tack else "gybe", kn, helm, start_u / KN, "OK" if ok else "STUCK", t_turn, min_u / KN, b.u / KN])
	if not ok:
		fails += 1

## Dead in irons, helm centred: she should fall off onto a tack within 20 s.
func irons(kn: float) -> void:
	var b := BoatSim.new()
	b.place(Vector2.ZERO, deg_to_rad(3.0), 0.0)
	b.main_sheet = 0.3
	b.jib_sheet = 0.3
	var wind := Vector2(0, -kn * KN)
	var t := 0.0
	while t < 20.0 and absf(b.twa) < deg_to_rad(60.0):
		b.tiller = 0.0
		b.hike = lerpf(b.hike, b.auto_hike(), 0.05)
		b.step(1.0 / 120.0, wind)
		t += 1.0 / 120.0
	var ok := absf(b.twa) >= deg_to_rad(60.0)
	print("irons %4.1f kn: %s after %.1f s (twa %.0f)" % [kn, "fell off" if ok else "STUCK", t, rad_to_deg(b.twa)])
	if not ok:
		fails += 1
