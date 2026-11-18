extends SceneTree
## Records an AI race to session files, reads them back, and runs the analytics on every boat.
## Checks the round trip (sample count, values, events) and that the analytics find the start,
## tacks and roundings with sane numbers.
## Run: godot --headless --path . --script res://tests/session_test.gd

const Fleet := preload("res://scripts/fleet.gd")
const Race := preload("res://scripts/race.gd")
const Recorder := preload("res://scripts/recorder.gd")
const Analysis := preload("res://scripts/analysis.gd")
const Targets := preload("res://scripts/targets.gd")
const KN := 0.514444
const DIR := "user://test_sessions"

var fails := 0


func _init() -> void:
	var cfg := {"race": true, "player": false, "ai": 5, "skill": 0.85, "wind_from": 250.0, "wind_kn": 11.0,
		"gust": 0.5, "course": 1, "start": -65.0, "seed": 4242}
	var f := Fleet.new()
	f.setup(cfg)
	var rec := Recorder.new()
	check(rec.open(cfg, f, "test", DIR), "session files open")
	f.recorder = rec
	var t0 := Time.get_ticks_msec()
	while f.race.phase != Race.Phase.DONE and f.time < 3600.0:
		f.step(1.0 / 60.0)
		f.events.clear()
		f.race.events.clear()
	var id := rec.close(f)
	print("raced %.0f s (%s) in %d ms" % [f.time, f.race.course_text, Time.get_ticks_msec() - t0])
	check(f.race.phase == Race.Phase.DONE, "race finished")

	t0 = Time.get_ticks_msec()
	var ses := Recorder.load_session(id, DIR)
	print("loaded %s in %d ms" % [id, Time.get_ticks_msec() - t0])
	check(not ses.is_empty(), "session loads")
	if ses.is_empty():
		_done()
		return
	var meta: Dictionary = ses["meta"]
	var times: PackedFloat64Array = ses["t"]
	var expect := int(f.time / Recorder.EVERY)
	check(absi(times.size() - expect) <= 2, "%d samples per boat, expected about %d" % [times.size(), expect])
	check((ses["vals"] as PackedFloat32Array).size() == times.size() * f.boats.size() * int(ses["nc"]), "every boat has a sample at every time")
	check(meta["complete"], "meta says the race completed")
	check((meta["course"] as Array).size() > 0, "course saved")
	check(absf(float(meta["gun_t"]) - 65.0) < 0.05, "gun at 65 s (got %s)" % str(meta["gun_t"]))
	# The last row should match the boats where they stopped, to the CSV's rounding.
	var last := times.size() - 1
	for i in f.boats.size():
		var b = f.boats[i]
		var dx := absf(Recorder.value(ses, i, "x", last) - b.pos.x) + absf(Recorder.value(ses, i, "y", last) - b.pos.y)
		check(dx < 0.6, "boat %d last position matches (off by %.2f m)" % [i, dx])
	# Every legal finisher has a start, a finish and one rounding or gate event per course element.
	var legs := 0
	for el: String in meta["course"]:
		if el != "F":
			legs += 1
	for i in f.boats.size():
		var e = f.race.entrants[i]
		if not (e.finished and e.status == ""):
			continue
		var kinds := {}
		for ev: Dictionary in meta["events"]:
			if int(ev.get("boat", -1)) == i:
				kinds[ev["type"]] = int(kinds.get(ev["type"], 0)) + 1
		check(kinds.get("start", 0) == 1 and kinds.get("finish", 0) == 1, "%s has one start and one finish event" % f.names[i])
		check(int(kinds.get("round", 0)) + int(kinds.get("gate", 0)) == legs, "%s has %d roundings/gates (got %d)" % [f.names[i], legs, int(kinds.get("round", 0)) + int(kinds.get("gate", 0))])

	var targets := Targets.load_all()
	t0 = Time.get_ticks_msec()
	var all := []
	for i in f.boats.size():
		all.append(Analysis.run(ses, i, targets))
	print("analysed %d boats in %d ms" % [all.size(), Time.get_ticks_msec() - t0])
	for a: Dictionary in all:
		var e = f.race.entrants[a["boat"]]
		if not (e.finished and e.status == ""):
			continue
		var st: Dictionary = a["start"]
		check(st.get("complete", false), "%s: start scored" % a["name"])
		if st.get("complete", false):
			check(absf(st["behind_m"]) < 150.0 and st["speed_kn"] >= 0.0 and st["speed_kn"] < 12.0, "%s: start numbers sane" % a["name"])
		# Every boat's tacks are found; whether any is clean enough to score (no other move in
		# its window) depends on how the race goes, so that is checked across the fleet below.
		var n_tacks := 0
		for r: Dictionary in a["moves"]:
			if r["kind"] == "tack":
				n_tacks += 1
		var n_round: int = a["summary"]["rounding"]["n"]
		check(n_tacks >= 1, "%s: found tacks (%d)" % [a["name"], n_tacks])
		check(n_round >= 1, "%s: scored roundings (%d)" % [a["name"], n_round])
		check(not a["wind"].is_empty(), "%s: has steady sailing rows" % a["name"])
		for r: Dictionary in a["moves"]:
			check(is_finite(r["loss_m"]) and absf(r["loss_m"]) < 200.0, "%s: %s loss %.1f m is sane" % [a["name"], Analysis.move_name(r), r["loss_m"]])
	# Clean tacks cost distance: across the fleet the average must be a loss, not a gain.
	var tack_m := 0.0
	var tack_n := 0
	for a: Dictionary in all:
		tack_m += a["summary"]["tack"]["total_m"]
		tack_n += a["summary"]["tack"]["n"]
	print("fleet: %d clean tacks, mean %.1f m" % [tack_n, tack_m / maxi(tack_n, 1)])
	check(tack_n >= 5 and tack_m / tack_n > 0.0, "clean tacks lose distance on average")
	# Print one boat's debrief for a look by eye.
	var a: Dictionary = all[0]
	print("--- %s" % a["name"])
	var st: Dictionary = a["start"]
	if st.get("complete", false):
		print("start: %.1f m behind the line at the gun at %.1f kn (%.0f%% of steady), crossed %s s after, %.1f m (%.2f lengths) behind a perfect start at +30 s%s" % [
			st["behind_m"], st["speed_kn"], 100.0 * st["speed_ratio"], "%.1f" % st["late_s"] if st["late_s"] != null else "-",
			st["loss_m"], st["lengths"], " (OCS)" if st["ocs"] else ""])
	for row: Dictionary in a["wind"]:
		print("  %-6s %-8s %5.0f s  %.2f kn  VMG %.2f kn  TWA %.0f" % [row["bin"], row["sector"], row["time_s"], row["speed_kn"], row["vmg_kn"], row["twa_deg"]])
	for r: Dictionary in a["moves"]:
		var parts := []
		for b: Dictionary in r["bins"]:
			parts.append("%+d..%+d %.1f" % [int(b["from"]), int(b["to"]), b["loss_m"]])
		print("  %6s %-8s %5.1f m (%.2f L) %-6s%s  %s%s" % [Race.fmt_clock(r["clock"]), Analysis.move_name(r), r["loss_m"], r["lengths"],
			"clean" if r["clean"] else "near", " penalty" if r["penalty"] else "", ", ".join(parts),
			("  legs %s, steady %.2f / %.2f m/s" % [str(r["legs"]), r["ref_in"], r["ref_out"]]) if r.has("legs") else ""])
	print("summary: %s" % str(a["summary"]))
	print("fleet: %s" % str(Analysis.fleet_compare(all, 0)))
	_done()


func _done() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		for fn in d.get_files():
			d.remove(fn)
	print("session_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: " + what)
