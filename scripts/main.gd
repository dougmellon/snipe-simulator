extends Node3D
## Game flow: a live AI race behind the start menu, then the player's races or free sailing.
## The simulation (fleet.gd) steps at 120 Hz in _physics_process; views interpolate between
## steps in _process.

const Lake := preload("res://scripts/lake.gd")
const Fleet := preload("res://scripts/fleet.gd")
const Race := preload("res://scripts/race.gd")
const WorldView := preload("res://scripts/world_view.gd")
const BoatView := preload("res://scripts/boat_view.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Audio := preload("res://scripts/audio.gd")
const Hud := preload("res://scripts/hud.gd")
const Minimap := preload("res://scripts/minimap.gd")
const Menu := preload("res://scripts/menu.gd")
const Overlay := preload("res://scripts/overlay.gd")
const Recorder := preload("res://scripts/recorder.gd")
const Analysis := preload("res://scripts/analysis.gd")
const Replay := preload("res://scripts/replay.gd")
const ReplayBar := preload("res://scripts/replay_bar.gd")
const Targets := preload("res://scripts/targets.gd")

const HULLS := [Color(0.85, 0.12, 0.1), Color(0.1, 0.25, 0.7), Color(0.95, 0.95, 0.92), Color(0.1, 0.45, 0.25),
	Color(0.95, 0.75, 0.1), Color(0.15, 0.15, 0.18), Color(0.55, 0.75, 0.9), Color(0.6, 0.2, 0.45),
	Color(0.9, 0.45, 0.1), Color(0.75, 0.75, 0.7)]
const PLAYER_HULL := Color(0.05, 0.55, 0.75)
const BoatSim := preload("res://scripts/boat_sim.gd")
## Rig controls on the keyboard: [boat field, action that lowers it, action that raises it, rate
## per second, low, high, name for messages]. Units are the guide's: inches (vang 0..1).
const RIG_KEYS := [
	["outhaul", "outhaul_flat", "outhaul_ease", 1.5, 0.0, BoatSim.OUTHAUL_MAX, "outhaul"],
	["cunningham", "cunningham_ease", "cunningham_on", 1.0, 0.0, BoatSim.CUNNINGHAM_MAX, "cunningham"],
	["vang", "vang_ease", "vang_on", 0.5, 0.0, 1.0, "vang"],
	["traveler", "traveler_up", "traveler_down", 3.0, 0.0, BoatSim.TRAVELER_MAX, "traveler"],
	["puller", "puller_aft", "pusher_fwd", 0.375, BoatSim.PULLER_MIN, BoatSim.PULLER_MAX, "mast pusher/puller"],
	["halyard", "halyard_on", "halyard_ease", 4.0, 0.0, BoatSim.HALYARD_THROW, "jib halyard"],
	["jib_lead", "lead_aft", "lead_fwd", 1.0, -BoatSim.LEAD_MAX, BoatSim.LEAD_MAX, "jib lead"],
]
const WARPS := [1, 2, 4, 8]
const KN := 0.514444

var lake
var fleet
var world
var views: Array = []
var cam
var audio
var hud
var minimap
var menu
var overlay
var cfg := {}
var state := "menu"  # menu, sailing, paused, results, replay
var warp_i := 0
var race_no := 1
var day := {}
var day_names := {}
var prev: Array = []
var ideal_t := 0.0
var menu_t := 0.0
var done_t := -1.0
var fast_forward := false
var started_banner := false
var sim := true
var tiller_mode := true  # keys move the tiller handle (realistic) rather than point the bow
var mouse_helm := false
var cut_hulls := true  # keep water out of the cockpits (off only for before/after checks)
## Each boat's recent track for its wake: [position, fleet time, speed], oldest first.
var tracks: Array = []
var track_t := 0.0
const TRACK_EVERY := 0.6
const TRACK_LEN := 19
## Session recording, debrief and replay (see scripts/recorder.gd, analysis.gd, replay.gd).
const REPLAY_SPEEDS := [1, 2, 4, 8]
var recorder
var session_id := ""
var session := {}
var analyses: Array = []
var replay
var replay_bar
var replay_t := 0.0
var replay_playing := true
var replay_speed_i := 0
var replay_follow := 0
var step_advance := 0.0  # how far the fleet clock moved in the last physics frame
## Game pad (PS5 / Xbox, SDL standard layout). pad_dev is the pad that gets rumble and the
## lightbar colour; -1 when none is connected.
var pad_dev := -1
var pad_helm := false   # the left stick is steering; centre the tiller when it lets go
var board_goal := 1.0       # where the player has put the daggerboard: down, or BoatSim.BOARD_UP
var pole_cmd_t := -10.0  # fleet time of the last pole command
var pad_look := false   # the right stick turned the camera; ease it back when it lets go
var rumble_t := 0.0
var flutter := false
var bump := Vector2.ZERO  # (weak, strong) motor burst for a knock, capsize or grounding
var bump_t := 0.0


func _ready() -> void:
	_setup_input()
	get_window().title = "Snipe: Union Reservoir"
	lake = Lake.new()
	world = WorldView.new()
	add_child(world)
	world.build(lake)
	cam = CameraRig.new()
	add_child(cam)
	cam.current = true
	audio = Audio.new()
	add_child(audio)
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	hud.hide()
	minimap = Minimap.new()
	ui.add_child(minimap)
	minimap.hide()
	overlay = Overlay.new()
	ui.add_child(overlay)
	overlay.resume.connect(_resume)
	overlay.restart.connect(_restart)
	overlay.retire.connect(_retire)
	overlay.next_race.connect(_next_race)
	overlay.to_menu.connect(_to_menu)
	overlay.quit_game.connect(func(): get_tree().quit())
	overlay.debrief.connect(_show_debrief)
	overlay.watch.connect(_start_replay)
	overlay.results_back.connect(_results_screen)
	replay_bar = ReplayBar.new()
	ui.add_child(replay_bar)
	replay_bar.hide()
	replay_bar.back.connect(_show_debrief)
	replay_bar.toggle_play.connect(func(): replay_playing = not replay_playing)
	replay_bar.cycle_speed.connect(func(): replay_speed_i = (replay_speed_i + 1) % REPLAY_SPEEDS.size())
	replay_bar.seek.connect(func(t: float): replay_t = t)
	menu = Menu.new()
	ui.add_child(menu)
	menu.start_requested.connect(_on_start)
	menu.quit_requested.connect(func(): get_tree().quit())
	Input.joy_connection_changed.connect(func(_d: int, _c: bool): _pick_pad())
	_pick_pad()
	hud.pad = pad_dev >= 0
	_start_demo()


## Use the first connected pad for rumble, and light its lightbar in your hull colour.
func _pick_pad() -> void:
	var pads := Input.get_connected_joypads()
	pad_dev = pads[0] if not pads.is_empty() else -1
	if pad_dev >= 0 and Input.has_joy_light(pad_dev):
		Input.set_joy_light(pad_dev, PLAYER_HULL)


# --- Sessions -------------------------------------------------------------------------

func _start_demo() -> void:
	state = "menu"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_load_fleet({"race": true, "player": false, "ai": 7, "skill": 0.8, "wind_from": rng.randf_range(0, 360), "wind_kn": 10.0,
		"gust": 0.5, "course": 0, "start": -75.0, "seed": rng.randi()})
	audio.master = 0.3
	if world.has_method("set_mark_labels_visible"):
		world.set_mark_labels_visible(true)
	menu.show()
	hud.hide()
	minimap.hide()
	overlay.hide()


func _on_start(c: Dictionary) -> void:
	cfg = c
	cfg["fleet_seed"] = randi()
	race_no = 1
	day.clear()
	day_names.clear()
	_begin()


func _begin() -> void:
	menu.hide()
	overlay.hide()
	_load_fleet(cfg)
	fleet.assist = cfg.get("assist", fleet.assist).duplicate()
	state = "sailing"
	warp_i = 0
	done_t = -1.0
	fast_forward = false
	started_banner = false
	audio.master = 1.0
	sim = cfg.get("sim", true)
	tiller_mode = cfg.get("tiller", true)
	hud.sim = sim
	hud.tiller_mode = tiller_mode
	if world.has_method("set_mark_labels_visible"):
		world.set_mark_labels_visible(not sim)
	hud.coach = false
	minimap.sim = sim
	for v in views:
		if v.has_method("set_label_visible"):
			v.set_label_visible(not sim)
	hud.fleet = fleet
	hud.messages.clear()
	hud.show()
	minimap.fleet = fleet
	minimap.show()
	_layout_map()
	# Rigged ashore for the forecast: every control set for the wind upwind, as a crew would.
	var pb = fleet.boats[fleet.player]
	pb.tws = fleet.wind.base_speed
	pb.twa = 0.7
	pb.auto_rig()
	cam.sim = fleet.boats[fleet.player]
	cam.view = views[fleet.player]
	cam.race = fleet.race
	cam.mode = CameraRig.Mode.HELM if sim else CameraRig.Mode.CHASE
	# Every race you sail is recorded for the debrief and replay.
	if fleet.race != null:
		recorder = Recorder.new()
		if recorder.open(cfg, fleet, "race%d" % race_no):
			fleet.recorder = recorder
		else:
			recorder = null
	if fleet.race != null:
		hud.add_message("Race %d. Wind %03d° at %.0f kn. Flag L is up: check in by sailing past the RC boat's transom on starboard." % [race_no, int(fleet.wind.base_from), fleet.wind.base_speed / KN] if fleet.race.phase == Race.Phase.CHECKIN else "Race %d. Wind %03d° at %.0f kn." % [race_no, int(fleet.wind.base_from), fleet.wind.base_speed / KN])
	else:
		hud.add_message("Free sail. Wind %03d° at %.0f kn. Marks 1-9 are out; the start line is not set." % [int(fleet.wind.base_from), fleet.wind.base_speed / KN])


func _load_fleet(c: Dictionary) -> void:
	_close_recorder()
	session_id = ""
	session = {}
	analyses = []
	replay = null
	if replay_bar != null:
		replay_bar.hide()
	for v in views:
		v.queue_free()
	views.clear()
	fleet = Fleet.new()
	fleet.setup(c, lake)
	world.set_race(fleet.race)
	if fleet.race != null:
		world.update_flags(fleet.race.flags, fleet.race.course_text)
	var ci := 0
	for i in fleet.boats.size():
		var v := BoatView.new()
		add_child(v)
		var is_player: bool = i == fleet.player
		v.setup(PLAYER_HULL if is_player else HULLS[ci % HULLS.size()], fleet.sails[i], is_player)
		if not is_player:
			ci += 1
		views.append(v)
	prev.clear()
	tracks.clear()
	for b in fleet.boats:
		prev.append([b.pos, b.heading, b.heel])
		tracks.append([])
	track_t = 0.0


func _next_race() -> void:
	race_no += 1
	cfg["seed"] = randi()
	# The wind moves around a bit between races, as it does.
	cfg["wind_from"] = fposmod(cfg["wind_from"] + randf_range(-20.0, 20.0), 360.0)
	_begin()


func _restart() -> void:
	cfg["seed"] = randi()
	_begin()


func _retire() -> void:
	if fleet.race != null:
		fleet.race.retire(fleet.race.entrants[fleet.player])
	_resume()


func _resume() -> void:
	overlay.hide()
	state = "sailing"
	get_tree().paused = false


func _to_menu() -> void:
	overlay.hide()
	get_tree().paused = false
	_start_demo()


# --- Loop ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if fleet == null or state == "paused" or state == "results" or state == "replay":
		return
	if state == "sailing":
		_player_input(delta)
	for i in fleet.boats.size():
		var b = fleet.boats[i]
		prev[i] = [b.pos, b.heading, b.heel]
	var w: int = WARPS[warp_i] if state == "sailing" else 1
	var steps := 1
	var dt := delta
	match w:
		2:
			dt = delta * 2.0
		4:
			steps = 2
			dt = delta * 2.0
		8:
			steps = 3
			dt = delta * 8.0 / 3.0
	var t_before: float = fleet.time
	for s in steps:
		fleet.step(dt)
	step_advance = fleet.time - t_before
	_record_tracks()
	_handle_events()


func _process(delta: float) -> void:
	if fleet == null:
		return
	if fast_forward and fleet.race != null and fleet.race.phase != Race.Phase.DONE:
		for s in 400:
			fleet.step(1.0 / 30.0)
			if fleet.race.phase == Race.Phase.DONE:
				break
		_handle_events()
	if state == "replay":
		# Draw the recording, not the physics: set every boat from the session at replay_t.
		if replay_playing:
			replay_t = minf(replay_t + delta * REPLAY_SPEEDS[replay_speed_i], replay.t1)
			if replay_t >= replay.t1:
				replay_playing = false
		replay_t = clampf(replay_t, replay.t0, replay.t1)
		replay.apply(replay_t, fleet.boats)
		fleet.time = replay_t
		for i in fleet.boats.size():
			var rb = fleet.boats[i]
			prev[i] = [rb.pos, rb.heading, rb.heel]
	# Draw every frame between the last two physics steps: position, heading and heel, and the
	# clock the sails, crew and water animate by, so nothing moves in 120 Hz steps.
	var a := Engine.get_physics_interpolation_fraction() if state != "replay" else 1.0
	var vt: float = fleet.time - (1.0 - a) * step_advance
	var hulls := PackedVector4Array()
	var speeds := PackedFloat32Array()
	for i in views.size():
		var b = fleet.boats[i]
		var p: Array = prev[i]
		var pos: Vector2 = b.pos
		var h: float = b.heading
		var hl: float = b.heel
		b.pos = p[0].lerp(pos, a)
		b.heading = lerp_angle(p[1], h, a)
		if not b.capsized:
			b.heel = lerpf(p[2], hl, a)
		views[i].sync(b, vt)
		hulls.append(Vector4(b.pos.x, b.pos.y, b.heading, b.heel))
		speeds.append(b.u)
		b.pos = pos
		b.heading = h
		b.heel = hl
	if state == "replay":
		# The recording keeps the mean wind, not the puffs, so the water shows no cat's paws.
		var w: Vector2 = replay.wind_at(replay_t)
		world.update_water(vt, w.x, w.y, PackedVector4Array())
	else:
		world.update_water(vt, fleet.wind.mean_from(), fleet.wind.base_speed, fleet.wind.shader_puffs())
	world.update_hulls(hulls if cut_hulls else PackedVector4Array())
	world.update_hull_speeds(speeds)
	world.update_wakes(replay.wake_tracks(replay_t, views) if state == "replay" else _wake_tracks())

	if state == "menu":
		_menu_camera(delta)
		return
	if state == "replay":
		cam.follow(delta)
		world.highlight_mark("")
		replay_bar.update_view(replay_t, replay_playing, REPLAY_SPEEDS[replay_speed_i], _replay_info())
		return
	# Right stick: turn your head the way you push it, right round to the stern at full
	# sideways, and up or down; it comes back ahead when you let go.
	var look := Input.get_axis("pad_look_left", "pad_look_right")
	var lookv := Input.get_axis("pad_look_down", "pad_look_up")
	if look != 0.0 or lookv != 0.0:
		pad_look = true
		cam.yaw_off = signf(look) * pow(absf(look), 1.3) * 2.95
		cam.pitch_off = lookv * 0.9
	elif pad_look:
		var kb := clampf(delta * 6.0, 0.0, 1.0)
		cam.yaw_off = lerpf(cam.yaw_off, 0.0, kb)
		cam.pitch_off = lerpf(cam.pitch_off, 0.0, kb)
		if absf(cam.yaw_off) < 0.01 and absf(cam.pitch_off) < 0.01:
			cam.yaw_off = 0.0
			cam.pitch_off = 0.0
			pad_look = false
	cam.follow(delta)
	_pad_feedback(delta)
	var b = fleet.boats[fleet.player]
	var luff := clampf(1.0 - absf(b.main_alpha) / 0.09, 0.0, 1.0) if not b.capsized else 0.0
	audio.ambience(b.aws, b.speed(), luff)
	hud.warp = WARPS[warp_i]
	hud.helm_view = cam.mode == CameraRig.Mode.HELM
	hud.cam_name = CameraRig.NAMES[cam.mode]
	ideal_t -= delta
	if ideal_t <= 0.0:
		ideal_t = 0.25
		var best: Vector2 = b.best_sheets()
		hud.ideal = best
	if fleet.race != null and fleet.race.phase != Race.Phase.DONE:
		var e = fleet.race.entrants[fleet.player]
		var next := ""
		if not sim and e.started and fleet.race.is_mark(e.leg) and e.active():
			next = fleet.race.course[e.leg]
		world.highlight_mark(next)
	if state == "sailing" and done_t >= 0.0:
		done_t -= delta
		if done_t <= 0.0:
			_show_results()


## Rumble while sailing: a light buzz that builds with the load on the rudder, a flutter when
## the main luffs, and a thump when you capsize, touch a boat or mark, or run aground.
func _pad_feedback(delta: float) -> void:
	bump_t -= delta
	rumble_t -= delta
	if pad_dev < 0 or state != "sailing" or rumble_t > 0.0:
		return
	rumble_t = 0.1
	var b = fleet.boats[fleet.player]
	var weak := 0.0
	var strong := 0.0
	if not b.capsized:
		weak = clampf((b.rudder_load - 40.0) / 320.0, 0.0, 0.35)
		if absf(b.main_alpha) < 0.08 and b.aws > 2.0:
			flutter = not flutter
			weak = maxf(weak, 0.32 if flutter else 0.12)
		# Pulling the main in on R2: the sheet gets harder the closer the boom comes to the
		# centreline and the more the sail is loaded, and it thumps at the stop. (The pad's
		# triggers can't be stiffened from Godot, so the motors do it.)
		var pull := Input.get_action_strength("pad_sheet_in")
		if pull > 0.1:
			var near := 1.0 - smoothstep(0.0, 0.4, float(b.main_sheet))
			var load := clampf(float(b.main_load) / 300.0, 0.0, 1.0)
			weak = maxf(weak, pull * (0.06 + 0.5 * near) * (0.5 + 0.5 * load))
			strong = maxf(strong, pull * 0.45 * near * near * load)
			if b.main_sheet <= 0.001:
				strong = maxf(strong, 0.4 * pull)
	if bump_t > 0.0:
		weak = maxf(weak, bump.x)
		strong = maxf(strong, bump.y)
	if weak > 0.01 or strong > 0.01:
		Input.start_joy_vibration(pad_dev, weak, strong, 0.15)


func _bump(weak: float, strong: float, seconds: float) -> void:
	bump = Vector2(weak, strong)
	bump_t = seconds
	rumble_t = 0.0


func _menu_camera(delta: float) -> void:
	menu_t += delta
	var c: Vector3 = Lake.to_3d(lake.marks["1"], 0.0)
	var a := menu_t * 0.05
	cam.global_position = c + Vector3(cos(a) * 140.0, 38.0, sin(a) * 140.0) + Vector3(-60, 0, 0)
	cam.look_at(c + Vector3(-60, 2, 0), Vector3.UP)


func _handle_events() -> void:
	var race = fleet.race
	for ev: Dictionary in fleet.events:
		if state != "sailing" or (ev["boat"] != fleet.player and ev.get("other", -1) != fleet.player):
			continue
		match ev["type"]:
			"capsize":
				hud.flash("Capsized!")
				hud.add_message("Capsized. The crew rights her in a few seconds (R or Triangle to hurry).", true)
				_bump(0.6, 1.0, 0.7)
			"aground":
				hud.add_message("Aground! Steer back toward open water.", true)
				_bump(0.3, 0.7, 0.4)
			"contact":
				_bump(0.5, 0.8, 0.25)
			"mark":
				_bump(0.4, 0.55, 0.2)
	fleet.events.clear()
	if race == null:
		return
	if state == "menu":
		race.events.clear()
		if race.phase == Race.Phase.DONE:
			_start_demo()
		return
	for ev: Dictionary in race.events:
		match ev["type"]:
			"horn":
				# From the committee boat, arriving late by the time the sound takes to get here.
				var rc3: Vector3 = Lake.to_3d(race.rc_pos, 2.2)
				audio.set_horn_position(rc3)
				audio.signal_pattern(ev["pattern"], cam.global_position.distance_to(rc3) / Audio.SOUND_SPEED)
			"msg":
				hud.add_message(ev["text"], ev.get("player", false))
			"flags", "course":
				world.update_flags(race.flags, race.course_text)
			"done":
				if done_t < 0.0:
					done_t = 2.5
	race.events.clear()
	if state != "sailing":
		return
	var e = race.entrants[fleet.player]
	if not started_banner and race.phase == Race.Phase.RACING:
		started_banner = true
		hud.flash("OVER EARLY!  Return below the line" if e.ocs else "START!")
	if e.finished and not e.has_meta("banner"):
		e.set_meta("banner", true)
		hud.flash("FINISHED  %s" % _ordinal(race.place_of(e)) if e.status == "" else "FINISHED (%s)" % e.status)
		hud.add_message("Press Enter (Triangle on the pad) to skip ahead to the results.", true)
	elif e.status != "" and not e.finished and not e.has_meta("banner"):
		e.set_meta("banner", true)
		hud.add_message("Press Enter (Triangle on the pad) to skip ahead to the results.", true)


func _show_results() -> void:
	mouse_helm = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var race = fleet.race
	done_t = -1.0
	fast_forward = false
	state = "results"
	var starters: int = race.entrants.size()
	var place := 1
	for e in race.standings():
		var pts := starters + 1
		if e.finished and e.status == "":
			pts = place
			place += 1
		if not day.has(e.sail):
			day[e.sail] = []
		day[e.sail].append(pts)
		day_names[e.sail] = e.name
	session_id = _close_recorder()
	_results_screen()


func _results_screen() -> void:
	state = "results"
	replay_bar.hide()
	minimap.show()
	overlay.show_results(fleet.race, race_no, day, day_names, session_id != "")


func _close_recorder() -> String:
	if recorder == null:
		return ""
	var id: String = recorder.close(fleet)
	if fleet != null:
		fleet.recorder = null
	recorder = null
	return id


## Loads the race just sailed and analyses every boat in it (once), then shows your debrief.
func _show_debrief() -> void:
	state = "results"
	replay_bar.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if session.is_empty() and session_id != "":
		session = Recorder.load_session(session_id)
	if session.is_empty():
		overlay.show_message("No recording", "This race wasn't recorded, so there's nothing to debrief.")
		return
	if analyses.is_empty():
		var targets := Targets.load_all()
		for i in fleet.boats.size():
			analyses.append(Analysis.run(session, i, targets))
	var me: int = fleet.player if fleet.player >= 0 else 0
	overlay.show_debrief(analyses[me], Analysis.fleet_compare(analyses, me), race_no, session["meta"])


## Replays the race from time t (fleet time), following your boat.
func _start_replay(t: float) -> void:
	if session.is_empty():
		return
	if replay == null:
		replay = Replay.new()
		replay.setup(session)
	overlay.hide()
	hud.hide()
	minimap.show()
	state = "replay"
	replay_t = clampf(t, replay.t0, replay.t1)
	replay_playing = true
	replay_speed_i = 0
	replay_follow = fleet.player if fleet.player >= 0 else 0
	_follow(replay_follow)
	var gun: Variant = session["meta"].get("gun_t")
	replay_bar.setup(replay.t0, replay.t1, float(gun) if gun != null else replay.t0)
	replay_bar.show()
	audio.master = 0.25


func _follow(i: int) -> void:
	replay_follow = i
	cam.sim = fleet.boats[i]
	cam.view = views[i]


## Who the camera follows, and the move they're in if there is one.
func _replay_info() -> String:
	var txt := "Following %s." % fleet.names[replay_follow]
	if replay_follow < analyses.size():
		for r: Dictionary in analyses[replay_follow]["moves"]:
			if absf(replay_t - float(r["t"])) <= 20.0:
				txt += "  %s at %s: %s." % [Analysis.move_name(r), Race.fmt_clock(r["clock"]),
					("lost %.1f m (%.1f lengths)" % [r["loss_m"], r["lengths"]]) if r["clean"] else "too close to another move to score"]
				break
	if hud.pad:
		return txt + "   Triangle play/pause, L3 speed, D-pad left/right 5 s, L1/R1 30 s, Cross camera, R3 next boat, Options debrief."
	return txt + "   Space play/pause, T speed, A/D or arrows 5 s (Shift 30 s), C camera, Tab next boat, Esc debrief."


func _replay_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("pause"):
		_show_debrief()
	elif ev.is_action_pressed("center_helm") or ev.is_action_pressed("board") or ev.is_action_pressed("skip"):
		replay_playing = not replay_playing
	elif ev.is_action_pressed("warp"):
		replay_speed_i = (replay_speed_i + 1) % REPLAY_SPEEDS.size()
	elif ev.is_action_pressed("steer_left") or ev.is_action_pressed("steer_right"):
		var jump := 30.0 if Input.is_key_pressed(KEY_SHIFT) else 5.0
		replay_t += -jump if ev.is_action_pressed("steer_left") else jump
	elif ev.is_action_pressed("vang_ease") or ev.is_action_pressed("vang_on"):
		replay_t += -5.0 if ev.is_action_pressed("vang_ease") else 5.0
	elif ev.is_action_pressed("jib_out") or ev.is_action_pressed("jib_in"):
		replay_t += -30.0 if ev.is_action_pressed("jib_out") else 30.0
	elif ev.is_action_pressed("camera"):
		cam.cycle()
	elif ev.is_action_pressed("standings") or ev.is_action_pressed("map"):
		_follow((replay_follow + 1) % fleet.boats.size())


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]


# --- Input --------------------------------------------------------------------------------

## With a tiller the keys (and stick, and mouse) move the tiller handle: push it to port and
## the bow swings to starboard. BoatSim.tiller is + for "turn to starboard", i.e. handle to port.
func _helm_sign() -> float:
	return -1.0 if tiller_mode else 1.0


func _player_input(delta: float) -> void:
	var b = fleet.boats[fleet.player]
	var steer := Input.get_axis("steer_left", "steer_right")
	# On a pad the left stick is the tiller handle itself: where the stick is, the handle is,
	# with a little expo so small corrections are fine. Let go and it centres. (The keys move
	# the handle at a rate and leave it where it is.)
	var stick := Input.get_axis("pad_tiller_port", "pad_tiller_stbd")
	# A hand on the extension moves the tiller about full throw in half a second; Alt is the
	# fingertip adjustment you make when she's in the groove.
	var rate := 0.6 if Input.is_key_pressed(KEY_ALT) else 2.0
	if stick != 0.0:
		pad_helm = true
		b.tiller = _helm_sign() * signf(stick) * pow(absf(stick), 1.5)
	elif pad_helm:
		pad_helm = false
		b.tiller = 0.0
	elif steer != 0.0:
		b.tiller = move_toward(b.tiller, _helm_sign() * steer, delta * rate)
	elif not sim:
		b.tiller = move_toward(b.tiller, 0.0, delta * 3.0)
	# In the simulator the helm stays where you leave it; Space brings it back to the middle.
	if Input.is_action_pressed("center_helm"):
		b.tiller = move_toward(b.tiller, 0.0, delta * 3.0)
	# Rig controls: touching one takes it over from the crew (the pause menu hands it back).
	for rk: Array in RIG_KEYS:
		var ax := Input.get_axis(rk[1], rk[2])
		if ax == 0.0:
			continue
		_take_rig(rk[0], rk[6])
		b.set(rk[0], clampf(float(b.get(rk[0])) + ax * delta * float(rk[3]), rk[4], rk[5]))
	# The daggerboard goes to where the player last put it; while the crew has it, follow them.
	if fleet.rig_manual.has("board") or not fleet.assist.get("rig", false):
		b.board = move_toward(b.board, board_goal, delta * 1.6)
	else:
		board_goal = 1.0 if b.board > 0.6 else BoatSim.BOARD_UP
	# R2 pulls the main in, L2 eases it; how hard you squeeze sets how fast. It comes in slower
	# under load and over the last of it to the centreline (BoatSim.sheet_rate).
	var main := Input.get_axis("main_in", "main_out") + Input.get_axis("pad_sheet_in", "pad_sheet_out")
	if absf(main) > 0.15:
		if fleet.assist["main"]:
			fleet.assist["main"] = false
			hud.add_message("Auto main off: you're trimming the main (K to turn it back on).", true)
		b.main_sheet = clampf(b.main_sheet + main * delta * b.sheet_rate(main > 0.0), 0.0, 1.0)
	var jib := Input.get_axis("jib_in", "jib_out")
	if jib != 0.0:
		if fleet.assist["jib"]:
			fleet.set_assist("jib", false)
			hud.add_message("Auto jib off: you're trimming the jib and handling the pole (J gives them back).", true)
		b.jib_sheet = clampf(b.jib_sheet + jib * delta * 0.5, 0.0, 1.0)
	var hk := Input.get_axis("hike_in", "hike_out")
	if hk != 0.0:
		if fleet.assist["hike"]:
			fleet.assist["hike"] = false
			hud.add_message("Auto hike off: %s (H for auto)." % ("Circle hikes out, Square moves in" if hud.pad else "Shift hikes out, Ctrl moves in"), true)
		b.hike = clampf(b.hike + hk * delta * 1.2, -1.0, 1.0)


func _unhandled_input(ev: InputEvent) -> void:
	# Left mouse held: the hand on the tiller and the mainsheet. Sideways moves the tiller,
	# drawing back pulls the sheet in (against the load), pushing forward lets it out.
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		mouse_helm = (ev as InputEventMouseButton).pressed and state == "sailing"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_helm else Input.MOUSE_MODE_VISIBLE
		return
	if ev is InputEventMouseMotion and mouse_helm and state == "sailing":
		var mb = fleet.boats[fleet.player]
		# Raw screen movement, so the feel doesn't change with the window size.
		var rel := (ev as InputEventMouseMotion).screen_relative
		mb.tiller = clampf(mb.tiller + _helm_sign() * rel.x * 0.0035, -1.0, 1.0)
		if absf(rel.y) > 0.0:
			if fleet.assist["main"]:
				fleet.assist["main"] = false
				hud.add_message("Auto main off: you're trimming the main (K to turn it back on).", true)
			var dy := rel.y * 0.0025
			mb.main_sheet = clampf(mb.main_sheet - dy * (mb.sheet_rate(false) / 0.55 if dy > 0.0 else 1.0), 0.0, 1.0)
		return
	if state == "menu":
		return
	if state == "replay":
		_replay_input(ev)
		return
	if ev.is_action_pressed("pause"):
		if state == "sailing":
			state = "paused"
			mouse_helm = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			overlay.show_pause(fleet.race != null, fleet)
		elif state == "paused":
			_resume()
		return
	if state != "sailing":
		return
	var b = fleet.boats[fleet.player]
	if ev.is_action_pressed("camera"):
		cam.cycle()
	elif ev.is_action_pressed("map"):
		minimap.big = not minimap.big
		_layout_map()
	elif ev.is_action_pressed("warp"):
		warp_i = (warp_i + 1) % WARPS.size()
	elif ev.is_action_pressed("help"):
		hud.show_help = not hud.show_help
	elif ev.is_action_pressed("standings"):
		hud.show_board = true
	elif ev.is_action_released("standings"):
		hud.show_board = false
	elif ev.is_action_pressed("pole") and _pole_ok(b):
		_pole_command(b)
	elif ev.is_action_pressed("tune"):
		hud.show_tune = not hud.show_tune
	elif ev.is_action_pressed("right_boat") and b.capsized:
		# (Only when she's over, so Triangle on the pad still reaches the skip below.)
		if b.capsize_t < b.RIGHT_MIN:
			hud.add_message("The crew is still swimming round to the centreboard.", true)
		b.right_now()
	elif ev.is_action_pressed("coach"):
		hud.coach = not hud.coach
		hud.add_message("Coach numbers " + ("on" if hud.coach else "off"), true)
	elif ev.is_action_pressed("board") or ev.is_action_pressed("board_up") or ev.is_action_pressed("board_down"):
		# Two places: down, or raised to the limit band.
		_take_rig("board", "daggerboard")
		if ev.is_action_pressed("board_up"):
			board_goal = BoatSim.BOARD_UP
		elif ev.is_action_pressed("board_down"):
			board_goal = 1.0
		else:
			board_goal = BoatSim.BOARD_UP if board_goal > 0.6 else 1.0
		hud.add_message("Daggerboard " + ("down" if board_goal > 0.6 else "raised to the band"), true)
	elif ev.is_action_pressed("auto_jib"):
		fleet.set_assist("jib", not fleet.assist["jib"])
		hud.add_message("Auto jib " + ("on: the crew trims the jib and handles the pole" if fleet.assist["jib"] else "off"), true)
	elif ev.is_action_pressed("auto_hike"):
		fleet.assist["hike"] = not fleet.assist["hike"]
		hud.add_message("Auto hike " + ("on" if fleet.assist["hike"] else "off"), true)
	elif ev.is_action_pressed("auto_main"):
		fleet.assist["main"] = not fleet.assist["main"]
		hud.add_message("Auto main " + ("on" if fleet.assist["main"] else "off"), true)
	elif ev.is_action_pressed("skip"):
		var race = fleet.race
		if race != null:
			var e = race.entrants[fleet.player]
			if e.finished or not e.active():
				fast_forward = true


## The player takes a rig control over from the crew, if the crew had it.
func _take_rig(field: String, label: String) -> void:
	if fleet.assist.get("rig", false) and not fleet.rig_manual.has(field):
		fleet.rig_manual[field] = true
		hud.add_message("You have the %s now (the pause menu hands the rig back to the crew)." % label, true)


## The pole button works while she's upright and still racing. (On the pad it is Triangle, which
## rights a capsized boat and skips to the results after the finish the rest of the time.)
func _pole_ok(b) -> bool:
	if b.capsized:
		return false
	var race = fleet.race
	if race != null:
		var e = race.entrants[fleet.player]
		if e.finished or not e.active():
			return false
	return true


## Whisker pole: set it, stow it, or swap it to the new side after a gybe. Pressing it takes the
## pole over from the crew.
func _pole_command(b) -> void:
	# One press, one command: a pad that shows up as two devices sends every press twice.
	if fleet.time - pole_cmd_t < 0.4:
		return
	pole_cmd_t = fleet.time
	if fleet.assist["jib"] and not fleet.rig_manual.has("pole"):
		fleet.rig_manual["pole"] = true
		hud.add_message("You have the whisker pole now (J, or the pause menu, gives it back to the crew).", true)
	var st: int = b.pole_state
	if st == BoatSim.POLE_STOWED:
		if b.pole_set():
			hud.add_message("Crew setting the whisker pole.", true)
		else:
			hud.add_message("Too close to the wind for the pole: bear away past a broad reach first.", true)
	elif st == BoatSim.POLE_SET:
		if b.pole_wrong_side():
			b.pole_swap()
			hud.add_message("Crew swapping the pole to the new side.", true)
		else:
			b.pole_stow()
			hud.add_message("Crew stowing the pole.", true)
	elif st == BoatSim.POLE_SETTING:
		hud.add_message("The pole is on its way out; press again once it's set to stow it.", true)
	else:
		hud.add_message("The crew is busy with the pole.", true)


func _layout_map() -> void:
	var vp := get_viewport().get_visible_rect().size
	if minimap.big:
		minimap.position = Vector2(vp.x * 0.5 - 380, 90)
		minimap.size = Vector2(760, vp.y - 260)
	else:
		minimap.position = Vector2(vp.x - 296, 16)
		minimap.size = Vector2(280, 340)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and minimap != null:
		_layout_map()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		# Quitting mid-race still leaves a readable (incomplete) session.
		_close_recorder()


func _setup_input() -> void:
	var keys := {
		"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT],
		"main_in": [KEY_W, KEY_UP], "main_out": [KEY_S, KEY_DOWN],
		"jib_in": [KEY_E], "jib_out": [KEY_Q],
		"hike_out": [KEY_SHIFT], "hike_in": [KEY_CTRL],
		"camera": [KEY_C], "map": [KEY_M], "warp": [KEY_T], "help": [KEY_F1, KEY_SLASH],
		"standings": [KEY_TAB], "right_boat": [KEY_R], "board": [KEY_B],
		"auto_jib": [KEY_J], "auto_hike": [KEY_H], "auto_main": [KEY_K],
		"pause": [KEY_ESCAPE, KEY_P], "skip": [KEY_ENTER, KEY_KP_ENTER],
		"center_helm": [KEY_SPACE], "vang_ease": [KEY_Z], "vang_on": [KEY_X],
		"outhaul_ease": [KEY_V], "outhaul_flat": [KEY_F], "coach": [KEY_I],
		"cunningham_ease": [KEY_L], "cunningham_on": [KEY_O],
		"traveler_down": [KEY_BRACKETLEFT], "traveler_up": [KEY_BRACKETRIGHT],
		"puller_aft": [KEY_COMMA], "pusher_fwd": [KEY_PERIOD],
		"halyard_ease": [KEY_MINUS], "halyard_on": [KEY_EQUAL],
		"lead_aft": [KEY_SEMICOLON], "lead_fwd": [KEY_APOSTROPHE],
		"board_up": [KEY_U], "board_down": [KEY_N], "pole": [KEY_G], "tune": [KEY_Y],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	# Game pad buttons (SDL standard layout; on a PS5 pad A = Cross, B = Circle, X = Square,
	# Y = Triangle, Back = Create, Start = Options).
	var pad_buttons := {
		"camera": [JOY_BUTTON_A], "right_boat": [JOY_BUTTON_Y], "skip": [JOY_BUTTON_Y], "pole": [JOY_BUTTON_Y],
		"hike_out": [JOY_BUTTON_B], "hike_in": [JOY_BUTTON_X],
		"jib_out": [JOY_BUTTON_LEFT_SHOULDER], "jib_in": [JOY_BUTTON_RIGHT_SHOULDER],
		"board_up": [JOY_BUTTON_DPAD_UP], "board_down": [JOY_BUTTON_DPAD_DOWN],
		"vang_ease": [JOY_BUTTON_DPAD_LEFT], "vang_on": [JOY_BUTTON_DPAD_RIGHT],
		"coach": [JOY_BUTTON_TOUCHPAD], "help": [JOY_BUTTON_BACK], "pause": [JOY_BUTTON_START],
		"warp": [JOY_BUTTON_LEFT_STICK], "map": [JOY_BUTTON_RIGHT_STICK],
	}
	for action: String in pad_buttons:
		for btn in pad_buttons[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = btn
			ev.device = -1
			InputMap.action_add_event(action, ev)
	# Sticks and triggers, as analogue actions with a small deadzone: strength rises from 0 at
	# the deadzone to 1 at full travel.
	var pad_axes := {
		"pad_tiller_port": [JOY_AXIS_LEFT_X, -1.0], "pad_tiller_stbd": [JOY_AXIS_LEFT_X, 1.0],
		"pad_sheet_in": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "pad_sheet_out": [JOY_AXIS_TRIGGER_LEFT, 1.0],
		"pad_look_left": [JOY_AXIS_RIGHT_X, -1.0], "pad_look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"pad_look_up": [JOY_AXIS_RIGHT_Y, -1.0], "pad_look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	}
	for action: String in pad_axes:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.12)
		var ev := InputEventJoypadMotion.new()
		ev.axis = pad_axes[action][0]
		ev.axis_value = pad_axes[action][1]
		ev.device = -1
		InputMap.action_add_event(action, ev)


## The HUD and help show pad controls once you use the pad, and keys once you use the keys.
func _input(ev: InputEvent) -> void:
	if hud == null:
		return
	if ev is InputEventJoypadButton or (ev is InputEventJoypadMotion and absf((ev as InputEventJoypadMotion).axis_value) > 0.4):
		hud.pad = true
	elif ev is InputEventKey or ev is InputEventMouseButton:
		hud.pad = false


func _record_tracks() -> void:
	if fleet.time - track_t < TRACK_EVERY:
		return
	track_t = fleet.time
	for i in fleet.boats.size():
		var b = fleet.boats[i]
		var tr: Array = tracks[i]
		tr.append([b.pos, fleet.time, maxf(b.u, 0.0)])
		if tr.size() > TRACK_LEN:
			tr.pop_front()


## Newest first, starting from where each boat is drawn right now.
func _wake_tracks() -> Array:
	var out := []
	for i in fleet.boats.size():
		var b = fleet.boats[i]
		var list := [Vector4(views[i].position.x, -views[i].position.z, 0.0, maxf(b.u, 0.0))]
		var tr: Array = tracks[i]
		for k in range(tr.size() - 1, -1, -1):
			var pt: Array = tr[k]
			var p: Vector2 = pt[0]
			list.append(Vector4(p.x, p.y, fleet.time - pt[1], pt[2]))
		out.append(list)
	return out
