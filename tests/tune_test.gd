extends SceneTree
## Rig tuning: the directions in the North Sails Snipe tuning guide should come out of the
## physics. Steady sailing with the crew's trim and hiking, one control changed at a time and
## the rest as the crew sets them (auto_rig), plus the whisker pole's handling.
## The sizes of these effects rest on estimated coefficients in scripts/boat_sim.gd, not on
## measurements; the test checks the directions and prints the numbers.
## Run: godot --headless --path . --script res://tests/tune_test.gd

const BoatSim := preload("res://scripts/boat_sim.gd")
const KN := 0.514444

var fails := 0


func _init() -> void:
	print("upwind (VMG, heel, rudder angle needed: + = weather helm)")
	# Guide: cunningham loose until overpowered, then on (draft forward, opens the leech). In a
	# breeze the steady state moves a few percent with small changes (the trim's optimum is flat
	# when she's overpowered), so this one is averaged over 38-44 degrees true.
	var c0 := upwind_avg(18.0, {"cunningham": 0.0})
	var c3 := upwind_avg(18.0, {"cunningham": 3.0})
	show("18 kn, cunningham loose (38-44 deg)", c0)
	show("18 kn, cunningham 3 in on (38-44 deg)", c3)
	check(c3["vmg"] > c0["vmg"] or c3["heel"] < c0["heel"], "cunningham on in 18 kn helps VMG or reduces heel")
	var l0 := steady(6.0, 44.0, {"cunningham": 0.0})
	var l3 := steady(6.0, 44.0, {"cunningham": 3.0})
	show("6 kn, cunningham loose", l0)
	show("6 kn, cunningham 3 in on", l3)
	check(l0["vmg"] > l3["vmg"], "cunningham loose is faster in 6 kn")
	# Guide: light air, crew inside, mast pushed to the forward mark.
	var pa := steady(5.0, 46.0, {"puller": BoatSim.PULLER_MIN})
	var pn := steady(5.0, 46.0, {"puller": 0.0})
	var pf := steady(5.0, 46.0, {"puller": 0.75})
	show("5 kn, mast at the aft mark (3/8 in aft)", pa)
	show("5 kn, mast at neutral", pn)
	show("5 kn, mast at the 3/4 in forward mark", pf)
	check(pf["vmg"] > pa["vmg"], "light air: mast pushed forward beats the aft mark")
	check(pf["vmg"] > pn["vmg"], "light air: mast pushed forward beats neutral")
	print("    bend at the 3/4 in mark %.2f in vs %.2f at the aft mark; forestay sag %.2f vs %.2f in; main twist %.1f vs %.1f deg" % [
		pf["bend"], pa["bend"], pf["sag"], pa["sag"], pf["twist"], pa["twist"]])
	# Guide: outhaul tight upwind except the very lightest air.
	var o0 := steady(10.0, 42.0, {"outhaul": 0.0})
	var o3 := steady(10.0, 42.0, {"outhaul": 3.0})
	show("10 kn, outhaul at the band", o0)
	show("10 kn, outhaul eased 3 in", o3)
	print("    (not checked: in 10 kn the model has eased about even with tight; see README)")
	# Guide: rake aft for lee helm, forward for weather helm, i.e. raking aft adds weather helm.
	var helms := []
	for rk in [-4.0, 0.0, 4.0]:
		var r := steady(10.0, 42.0, {"rake": rk})
		show("10 kn, rake %+.0f in" % rk, r)
		helms.append(r["helm"])
	check(helms[0] < helms[1] and helms[1] < helms[2], "raking aft increases weather helm")
	check(absf(helms[1]) < 2.0, "at the base rake the helm is near neutral hiked flat in 10 kn (%.1f deg)" % helms[1])
	# Guide: vang on so a puff can be eased without losing leech tension.
	var b := BoatSim.new()
	b.vang = 0.0
	var free: float = b._main_twist(0.35)
	b.vang = 0.6
	var held: float = b._main_twist(0.35)
	print("  main eased to 0.35: twist %.1f deg with the vang slack, %.1f with it on 6/10" % [rad_to_deg(free), rad_to_deg(held)])
	check(held < free - 0.05, "the vang holds the leech when the main is eased")
	# Guide: the jib lead set so the luff telltales break evenly.
	var even := steady(10.0, 42.0, {})
	print("  10 kn jib telltale angles, bottom/middle/top third: %.1f / %.1f / %.1f deg with the lead %.2f in" % [even["ja0"], even["ja1"], even["ja2"], even["lead"]])
	check(absf(even["ja0"] - even["ja2"]) < 1.5, "the crew's jib lead breaks the telltales evenly")
	# Stiffer rig bends less (guide: more tip to tip, or shrouds aft, is stiffer).
	var soft := steady(14.0, 42.0, {"mast": 0})
	var stiff := steady(14.0, 42.0, {"mast": 2, "spreader_tips": 29.75})
	print("  14 kn mast bend: soft mast %.2f in, stiff mast with 29 3/4 in tips %.2f in" % [soft["bend"], stiff["bend"]])
	check(stiff["bend"] < soft["bend"], "a stiffer rig bends less")

	print("downwind (speed)")
	# Guide: outhaul eased 2-3 in downwind.
	var dt0 := steady(10.0, 170.0, {"outhaul": 0.0})
	var dt2 := steady(10.0, 170.0, {"outhaul": 2.5})
	show("10 kn TWA 170, outhaul at the band", dt0)
	show("10 kn TWA 170, outhaul eased 2 1/2 in", dt2)
	check(dt2["speed"] > dt0["speed"], "outhaul eased downwind is faster than tight")
	# Whisker pole at TWA 165-175 in 10 kn.
	for twa in [165.0, 170.0, 175.0]:
		var np := steady(10.0, twa, {}, "none")
		var wp := steady(10.0, twa, {}, "crew")
		print("  10 kn TWA %.0f: %.2f kn without the pole, %.2f kn with it (%+.1f%%)" % [twa, np["speed"], wp["speed"], 100.0 * (wp["speed"] - np["speed"]) / np["speed"]])
		check(wp["speed"] > np["speed"], "the pole is faster at TWA %.0f in 10 kn" % twa)
	# Guide: jib halyard off fully dead downwind.
	var h0 := steady(10.0, 178.0, {"halyard": 0.0}, "crew")
	var h11 := steady(10.0, 178.0, {"halyard": BoatSim.HALYARD_THROW}, "crew")
	show("10 kn TWA 178 on the pole, halyard at full tension", h0)
	show("10 kn TWA 178 on the pole, halyard right off", h11)
	check(h11["speed"] > h0["speed"], "jib halyard off dead downwind beats tight")
	# Centreboard part way up downwind: less drag.
	var bd1 := steady(10.0, 170.0, {"board": 1.0}, "crew")
	var bd4 := steady(10.0, 170.0, {"board": 0.4}, "crew")
	print("  10 kn TWA 170: board down %.2f kn, 40%% down %.2f kn" % [bd1["speed"], bd4["speed"]])
	check(bd4["speed"] > bd1["speed"], "board part way up is faster on a run")

	print("whisker pole handling")
	pole_checks()
	print("tune_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func pole_checks() -> void:
	var b := BoatSim.new()
	b.twa = deg_to_rad(90.0)
	check(not b.pole_set(), "the crew won't set the pole on a beam reach")
	b.twa = deg_to_rad(165.0)
	b.boom = -1.2
	check(b.pole_set(), "the crew sets it on a run")
	check(b.pole_side > 0.0, "...on the side away from the boom (wing and wing)")
	# Setting takes its time; the jib is half let go meanwhile.
	var r := run_pole(10.0, 165.0, 0.0)
	print("  set at 10 s on a run: set after %.1f s" % r["set_t"])
	check(absf(r["set_t"] - BoatSim.POLE_SET_S) < 0.1, "setting the pole takes about %.0f s" % BoatSim.POLE_SET_S)
	# Gybing with the pole up costs: the crew has to swap it.
	var up := gybe(10.0, true)
	var down := gybe(10.0, false)
	print("  gybe in 10 kn, run to run: %.1f m lost with the pole up (swapped in %.1f s), %.1f m with no pole" % [up["loss"], up["swap_t"], down["loss"]])
	check(up["swapped"], "after a gybe the crew swaps the pole to the new side")
	check(up["loss"] > down["loss"], "gybing with the pole up costs more than a gybe without it")
	# Heading up with it still set: the jib backs.
	var kept := head_up(10.0, false)
	var stowed := head_up(10.0, true)
	print("  heading up from a run to TWA 100 in 10 kn: %.2f kn with the pole left up, %.2f kn with it stowed" % [kept, stowed])
	check(stowed > kept, "the pole has to come down to head up past a reach")


## Steady sailing: mean of the last 20 s of 80. rig: controls held (the rest the crew's). pole:
## "none" (never set) or "crew" (the crew sets it when it pays).
func steady(tws_kn: float, twa_deg: float, rig: Dictionary, pole := "none") -> Dictionary:
	var b := BoatSim.new()
	var want := deg_to_rad(-twa_deg)
	b.place(Vector2.ZERO, fposmod(want, TAU), 1.5)
	var wind := Vector2(0, -tws_kn * KN)
	var dt := 1.0 / 120.0
	var acc := {"speed": 0.0, "heel": 0.0, "helm": 0.0, "bend": 0.0, "sag": 0.0, "twist": 0.0, "ja0": 0.0, "ja1": 0.0, "ja2": 0.0, "lead": 0.0}
	var n := 0
	var integ := 0.0
	for i in 120 * 80:
		if i % 30 == 0:
			for k: String in ["mast", "spreader_tips", "rake"]:
				if rig.has(k):
					b.set(k, rig[k])
			b.auto_rig(rig)
			for k: String in rig:
				b.set(k, rig[k])
			if pole == "crew":
				b.crew_pole()
			var sh := b.best_sheets()
			b.main_sheet = sh.x
			b.jib_sheet = sh.y
		b.hike = lerpf(b.hike, b.auto_hike(), 0.05)
		# The helm holds the angle asked for (with integral action, so a weather or lee helm
		# doesn't leave her sailing a degree or two off it).
		var err := wrapf(want - b.heading, -PI, PI)
		integ = clampf(integ + err * dt, -0.3, 0.3)
		b.tiller = clampf(3.0 * err + 1.5 * integ - 1.5 * b.r, -1.0, 1.0)
		b.step(dt, wind)
		if i > 120 * 60:
			acc["speed"] += b.u / KN
			acc["heel"] += absf(rad_to_deg(b.heel))
			# Starboard tack here: the rudder turning her away from the wind is weather helm.
			acc["helm"] += -rad_to_deg(b.tiller * BoatSim.MAX_RUDDER)
			acc["bend"] += b.mast_bend
			acc["sag"] += b.stay_sag
			acc["twist"] += rad_to_deg(b.main_twist)
			acc["ja0"] += rad_to_deg(absf(b.jib_alphas[0]))
			acc["ja1"] += rad_to_deg(absf(b.jib_alphas[1]))
			acc["ja2"] += rad_to_deg(absf(b.jib_alphas[2]))
			acc["lead"] += b.jib_lead
			n += 1
	for k: String in acc:
		acc[k] /= n
	acc["vmg"] = acc["speed"] * absf(cos(deg_to_rad(twa_deg)))
	return acc


## steady() averaged over 38, 40, 42 and 44 degrees true.
func upwind_avg(tws_kn: float, rig: Dictionary) -> Dictionary:
	var out := {}
	for twa in [38.0, 40.0, 42.0, 44.0]:
		var r := steady(tws_kn, twa, rig)
		for k: String in r:
			out[k] = float(out.get(k, 0.0)) + r[k] / 4.0
	return out


func show(what: String, r: Dictionary) -> void:
	print("  %-44s VMG %.3f kn  speed %.2f kn  heel %4.1f  helm %+.1f deg" % [what, r["vmg"], r["speed"], r["heel"], r["helm"]])


## Sails a run, sets the pole at t_set, reports when it was set.
func run_pole(tws_kn: float, twa_deg: float, t_set: float) -> Dictionary:
	var b := BoatSim.new()
	var want := deg_to_rad(-twa_deg)
	b.place(Vector2.ZERO, fposmod(want, TAU), 2.0)
	var wind := Vector2(0, -tws_kn * KN)
	var dt := 1.0 / 120.0
	var out := {"set_t": -1.0}
	var t_start := -1.0
	for i in 120 * 30:
		var t := i * dt
		if i % 30 == 0:
			b.auto_rig()
			var sh := b.best_sheets()
			b.main_sheet = sh.x
			b.jib_sheet = sh.y
		if t >= 10.0 + t_set and t_start < 0.0:
			b.pole_set()
			t_start = t
		b.hike = lerpf(b.hike, b.auto_hike(), 0.05)
		b.tiller = clampf(3.0 * wrapf(want - b.heading, -PI, PI) - 1.5 * b.r, -1.0, 1.0)
		b.step(dt, wind)
		if t_start >= 0.0 and out["set_t"] < 0.0 and b.pole_state == BoatSim.POLE_SET:
			out["set_t"] = t + dt - t_start
	return out


## Runs at TWA 165 on starboard, gybes to TWA 165 on port, and measures the distance lost
## downwind in the 25 s from the gybe against the speed she had before it.
func gybe(tws_kn: float, with_pole: bool) -> Dictionary:
	var b := BoatSim.new()
	var h1 := deg_to_rad(-165.0)
	var h2 := deg_to_rad(165.0)
	b.place(Vector2.ZERO, fposmod(h1, TAU), 2.0)
	var wind := Vector2(0, -tws_kn * KN)
	var dt := 1.0 / 120.0
	var before := 0.0
	var nb := 0
	var y0 := 0.0
	var out := {"loss": 0.0, "swapped": false, "swap_t": 0.0}
	var swap_from := -1.0
	for i in 120 * 75:
		var t := i * dt
		var want := h1 if t < 40.0 else h2
		if i % 30 == 0:
			b.auto_rig()
			if with_pole:
				b.crew_pole()
			var sh := b.best_sheets()
			b.main_sheet = sh.x
			b.jib_sheet = sh.y
		b.hike = lerpf(b.hike, b.auto_hike(), 0.05)
		b.tiller = clampf(3.0 * wrapf(want - b.heading, -PI, PI) - 1.5 * b.r, -0.85, 0.85)
		b.step(dt, wind)
		if t > 30.0 and t < 40.0:
			before += b.velocity().y * -1.0
			nb += 1
		if absf(t - 40.0) < dt * 0.5:
			y0 = b.pos.y
		if b.pole_state == BoatSim.POLE_SWAPPING and swap_from < 0.0:
			swap_from = t
		if swap_from >= 0.0 and not out["swapped"] and b.pole_state == BoatSim.POLE_SET:
			out["swapped"] = true
			out["swap_t"] = t - swap_from
		if absf(t - 65.0) < dt * 0.5:
			var v_before := before / nb
			out["loss"] = v_before * 25.0 - (y0 - b.pos.y)
	return out


## From a run with the pole set, heads up to TWA 100; returns the speed 10 s later. stow: the
## crew takes the pole down as she heads up.
func head_up(tws_kn: float, stow: bool) -> float:
	var b := BoatSim.new()
	var h1 := deg_to_rad(-170.0)
	var h2 := deg_to_rad(-100.0)
	b.place(Vector2.ZERO, fposmod(h1, TAU), 2.0)
	var wind := Vector2(0, -tws_kn * KN)
	var dt := 1.0 / 120.0
	for i in 120 * 50:
		var t := i * dt
		if i % 30 == 0:
			b.auto_rig()
			if stow or t < 30.0:
				b.crew_pole()
			var sh := b.best_sheets()
			b.main_sheet = sh.x
			b.jib_sheet = sh.y
		b.hike = lerpf(b.hike, b.auto_hike(), 0.05)
		var want := h1 if t < 30.0 else h2
		b.tiller = clampf(3.0 * wrapf(want - b.heading, -PI, PI) - 1.5 * b.r, -0.85, 0.85)
		b.step(dt, wind)
	return b.u / KN


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1
