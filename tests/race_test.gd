extends SceneTree
## Full AI-only races, headless: start sequence, recalls, roundings, finish, time limit.
## Checks most boats finish legally and nothing gets stuck.
## Run: godot --headless --path . --script res://tests/race_test.gd -- [wind_from=270] [kn=10] [course=0] [ai=8] [seed=1] [verbose=0]

const Fleet := preload("res://scripts/fleet.gd")
const Race := preload("res://scripts/race.gd")

var fails := 0
var ran := 0


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var cases := []
	if args.has("wind_from"):
		cases.append([float(args["wind_from"]), float(args.get("kn", "10")), int(args.get("course", "0")), int(args.get("seed", "1"))])
	else:
		cases = [[270.0, 10.0, 0, 1], [200.0, 14.0, 2, 2], [45.0, 7.0, 1, 3], [330.0, 18.0, 3, 4]]
	var verbose: bool = args.get("verbose", "0") == "1"
	for c: Array in cases:
		run(c[0], c[1], c[2], c[3], int(args.get("ai", "8")), verbose)
	check(ran == cases.size(), "all cases ran (%d of %d)" % [ran, cases.size()])
	print("race_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func run(wind_from: float, kn: float, course: int, seed: int, n_ai: int, verbose: bool) -> void:
	var f := Fleet.new()
	f.setup({"wind_from": wind_from, "wind_kn": kn, "gust": 0.5, "ai": n_ai, "skill": 0.8, "course": course, "seed": seed, "player": false})
	var dt := 1.0 / 60.0
	var counts := {"contact": 0, "mark": 0, "aground": 0, "capsize": 0}
	var t0 := Time.get_ticks_msec()
	var steps := 0
	while f.race.phase != Race.Phase.DONE and f.time < 4000.0:
		f.step(dt)
		steps += 1
		for ev: Dictionary in f.events:
			counts[ev["type"]] += 1
			if verbose and ev["type"] != "contact" and ev["type"] != "mark":
				print("  %7s %s %s" % [Race.fmt_clock(f.race.clock), ev["type"], f.names[ev["boat"]]])
		f.events.clear()
		for ev: Dictionary in f.race.events:
			if verbose and ev["type"] == "msg":
				print("  %7s %s" % [Race.fmt_clock(f.race.clock), ev["text"]])
		f.race.events.clear()
		if verbose and steps % (60 * 60) == 0:
			var line := "  %7s |" % Race.fmt_clock(f.race.clock)
			for i in f.boats.size():
				var e = f.race.entrants[i]
				line += " %s:%d/%s(%.1fkn)" % [f.names[i].substr(0, 4), e.leg, f.ais[i].debug.substr(0, 14), f.boats[i].u / 0.5144]
			print(line)
	var ms := Time.get_ticks_msec() - t0
	print("wind %03d %.0f kn, course %s: %s, %.0f s simulated in %d ms" % [wind_from, kn, f.race.course_text, "done" if f.race.phase == Race.Phase.DONE else "NOT DONE", f.time, ms])
	var ok := 0
	for e in f.race.standings():
		var line := "  %-10s %-6s start %6s  legs %d  " % [e.name, e.status if e.status != "" else "OK", Race.fmt_clock(e.start_time) if e.started else "-", e.leg]
		line += ("finish %s" % Race.fmt_clock(e.finish_time)) if e.finished else ""
		print(line)
		if e.finished and e.status == "":
			ok += 1
	print("  events: %s" % counts)
	check(f.race.phase == Race.Phase.DONE, "race finished")
	check(ok >= int(ceil(n_ai * 0.75)), "%d of %d finished legally" % [ok, n_ai])
	ran += 1


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: " + what)
