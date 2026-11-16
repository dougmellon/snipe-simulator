extends SceneTree
## Debug trace of chosen AI boats in a headless race.
## Run: godot --headless --path . --script res://tests/trace.gd -- names=Pelican,Avocet from=600 to=900 every=5 [wind_from=270 kn=10 course=0 seed=1 ai=8]
const Fleet := preload("res://scripts/fleet.gd")
const Race := preload("res://scripts/race.gd")
func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var f := Fleet.new()
	f.setup({"wind_from": float(args.get("wind_from", "270")), "wind_kn": float(args.get("kn", "10")), "gust": 0.5, "ai": int(args.get("ai", "8")), "skill": 0.8, "course": int(args.get("course", "0")), "seed": int(args.get("seed", "1")), "player": false})
	var watch: PackedStringArray = args.get("names", "").split(",")
	var t_from := float(args.get("from", "0"))
	var t_to := float(args.get("to", "600"))
	var every := int(float(args.get("every", "5")) * 60)
	var dt := 1.0 / 60.0
	print("rc %s pin %s course %s" % [f.race.rc_pos, f.race.pin, f.race.course_text])
	var n := 0
	while f.race.clock < t_to and f.race.phase != Race.Phase.DONE:
		f.step(dt)
		n += 1
		for ev in f.race.events:
			if ev["type"] == "course":
				print("course ", ev["text"])
		f.events.clear()
		f.race.events.clear()
		if f.race.clock >= t_from and n % every == 0:
			for i in f.boats.size():
				if f.names[i] in watch:
					var b = f.boats[i]
					var e = f.race.entrants[i]
					print("%6s %-8s pos (%4.0f,%4.0f) hdg %3.0f want %3.0f u %4.1f twa %4.0f leg %d acc %4.0f near %s pen %d pacc %4.0f pmax %4.0f tk %d gy %d st %s | %s" % [Race.fmt_clock(f.race.clock), f.names[i], b.pos.x, b.pos.y, rad_to_deg(b.heading), fposmod(rad_to_deg(f.ais[i].want), 360), b.u / 0.514, rad_to_deg(b.twa), e.leg, rad_to_deg(e.accum), e.near, e.penalty_turns, rad_to_deg(e.pen_accum), rad_to_deg(e.pen_max), e.pen_tacks, e.pen_gybes, e.started, f.ais[i].debug])
	quit()
