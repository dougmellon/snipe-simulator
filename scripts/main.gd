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

const HULLS := [Color(0.85, 0.12, 0.1), Color(0.1, 0.25, 0.7), Color(0.95, 0.95, 0.92), Color(0.1, 0.45, 0.25),
	Color(0.95, 0.75, 0.1), Color(0.15, 0.15, 0.18), Color(0.55, 0.75, 0.9), Color(0.6, 0.2, 0.45),
	Color(0.9, 0.45, 0.1), Color(0.75, 0.75, 0.7)]
const PLAYER_HULL := Color(0.05, 0.55, 0.75)
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
var state := "menu"  # menu, sailing, paused, results
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
	menu = Menu.new()
	ui.add_child(menu)
	menu.start_requested.connect(_on_start)
	menu.quit_requested.connect(func(): get_tree().quit())
	_start_demo()


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
	# Rigged ashore for the forecast: vang and outhaul set for the wind, as a crew would.
	var pb = fleet.boats[fleet.player]
	pb.tws = fleet.wind.base_speed
	pb.twa = 0.7
	pb.auto_rig()
	cam.sim = fleet.boats[fleet.player]
	cam.view = views[fleet.player]
	cam.race = fleet.race
	cam.mode = CameraRig.Mode.HELM if sim else CameraRig.Mode.CHASE
	if fleet.race != null:
		hud.add_message("Race %d. Wind %03d° at %.0f kn. Flag L is up: check in by sailing past the RC boat's transom on starboard." % [race_no, int(fleet.wind.base_from), fleet.wind.base_speed / KN] if fleet.race.phase == Race.Phase.CHECKIN else "Race %d. Wind %03d° at %.0f kn." % [race_no, int(fleet.wind.base_from), fleet.wind.base_speed / KN])
	else:
		hud.add_message("Free sail. Wind %03d° at %.0f kn. Marks 1-9 are out; the start line is not set." % [int(fleet.wind.base_from), fleet.wind.base_speed / KN])


func _load_fleet(c: Dictionary) -> void:
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
	if fleet == null or state == "paused" or state == "results":
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
	for s in steps:
		fleet.step(dt)
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
	var a := Engine.get_physics_interpolation_fraction()
	var hulls := PackedVector4Array()
	var speeds := PackedFloat32Array()
	for i in views.size():
		var b = fleet.boats[i]
		var p: Array = prev[i]
		var pos: Vector2 = b.pos
		var h: float = b.heading
		b.pos = p[0].lerp(pos, a)
		b.heading = lerp_angle(p[1], h, a)
		views[i].sync(b, fleet.time)
		hulls.append(Vector4(b.pos.x, b.pos.y, b.heading, b.heel))
		speeds.append(b.u)
		b.pos = pos
		b.heading = h
	world.update_water(fleet.time, fleet.wind.mean_from(), fleet.wind.base_speed, fleet.wind.shader_puffs())
	world.update_hulls(hulls if cut_hulls else PackedVector4Array())
	world.update_hull_speeds(speeds)
	world.update_wakes(_wake_tracks())

	if state == "menu":
		_menu_camera(delta)
		return
	cam.follow(delta)
	var b = fleet.boats[fleet.player]
	var luff := clampf(1.0 - absf(b.main_alpha) / 0.09, 0.0, 1.0) if not b.capsized else 0.0
	audio.ambience(b.aws, b.speed(), luff)
	hud.warp = WARPS[warp_i]
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


func _menu_camera(delta: float) -> void:
	menu_t += delta
	var c: Vector3 = Lake.to_3d(lake.marks["1"], 0.0)
	var a := menu_t * 0.05
	cam.global_position = c + Vector3(cos(a) * 140.0, 38.0, sin(a) * 140.0) + Vector3(-60, 0, 0)
	cam.look_at(c + Vector3(-60, 2, 0), Vector3.UP)


func _handle_events() -> void:
	var race = fleet.race
	for ev: Dictionary in fleet.events:
		if state != "sailing" or ev["boat"] != fleet.player:
			continue
		match ev["type"]:
			"capsize":
				hud.flash("Capsized!")
				hud.add_message("Capsized. The crew rights her in a few seconds (R to hurry).", true)
			"aground":
				hud.add_message("Aground! Steer back toward open water.", true)
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
		hud.add_message("Press Enter to skip ahead to the results.", true)
	elif e.status != "" and not e.finished and not e.has_meta("banner"):
		e.set_meta("banner", true)
		hud.add_message("Press Enter to skip ahead to the results.", true)


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
	overlay.show_results(race, race_no, day, day_names)


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
	var joy := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	# A hand on the extension moves the tiller about full throw in half a second; Alt is the
	# fingertip adjustment you make when she's in the groove.
	var rate := 0.6 if Input.is_key_pressed(KEY_ALT) else 2.0
	if absf(joy) > 0.15:
		b.tiller = _helm_sign() * joy
	elif steer != 0.0:
		b.tiller = move_toward(b.tiller, _helm_sign() * steer, delta * rate)
	elif not sim:
		b.tiller = move_toward(b.tiller, 0.0, delta * 3.0)
	# In the simulator the helm stays where you leave it; Space brings it back to the middle.
	if Input.is_action_pressed("center_helm"):
		b.tiller = move_toward(b.tiller, 0.0, delta * 3.0)
	var vg := Input.get_axis("vang_ease", "vang_on")
	var fl := Input.get_axis("outhaul_ease", "outhaul_flat")
	if vg != 0.0 or fl != 0.0:
		if fleet.assist.get("rig", false):
			fleet.assist["rig"] = false
			hud.add_message("You have the vang and outhaul now (pause menu hands them back to the crew).", true)
		b.vang = clampf(b.vang + vg * delta * 0.5, 0.0, 1.0)
		b.flatten = clampf(b.flatten + fl * delta * 0.5, 0.0, 1.0)
	var main := Input.get_axis("main_in", "main_out") + Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(main) > 0.15:
		if fleet.assist["main"]:
			fleet.assist["main"] = false
			hud.add_message("Auto main off: you're trimming the main (K to turn it back on).", true)
		b.main_sheet = clampf(b.main_sheet + main * delta * b.sheet_rate(main > 0.0), 0.0, 1.0)
	var jib := Input.get_axis("jib_in", "jib_out")
	if jib != 0.0:
		if fleet.assist["jib"]:
			fleet.assist["jib"] = false
			hud.add_message("Auto jib off: you're trimming the jib (J to turn it back on).", true)
		b.jib_sheet = clampf(b.jib_sheet + jib * delta * 0.5, 0.0, 1.0)
	var hk := Input.get_axis("hike_in", "hike_out")
	if hk != 0.0:
		if fleet.assist["hike"]:
			fleet.assist["hike"] = false
			hud.add_message("Auto hike off: Shift hikes out, Ctrl moves in (H for auto).", true)
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
	elif ev.is_action_pressed("right_boat"):
		if b.capsized and b.capsize_t < b.RIGHT_MIN:
			hud.add_message("The crew is still swimming round to the centreboard.", true)
		b.right_now()
	elif ev.is_action_pressed("coach"):
		hud.coach = not hud.coach
		hud.add_message("Coach numbers " + ("on" if hud.coach else "off"), true)
	elif ev.is_action_pressed("board"):
		b.board = 0.5 if b.board > 0.75 else (0.0 if b.board > 0.25 else 1.0)
	elif ev.is_action_pressed("auto_jib"):
		fleet.assist["jib"] = not fleet.assist["jib"]
		hud.add_message("Auto jib " + ("on" if fleet.assist["jib"] else "off"), true)
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
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


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
