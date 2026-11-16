extends SceneTree
## The real game with synthetic input: the tiller works like a tiller (handle to port, bow to
## starboard), the arcade option points the bow, the helm stays put when let go in the
## simulator, the mainsheet comes in slower under load, and the mouse drives tiller and sheet.
## Run: godot --headless --path . --script res://tests/controls_test.gd

const Main := preload("res://main.tscn")

var main
var fails := 0


func _init() -> void:
	main = Main.instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _start(tiller: bool, kn: float) -> Object:
	var cfg: Dictionary = main.menu.build_cfg()
	cfg["race"] = false
	cfg["ai"] = 0
	cfg["sim"] = true
	cfg["tiller"] = tiller
	cfg["wind_from"] = 270.0
	cfg["wind_kn"] = kn
	cfg["gust"] = 0.0
	main._on_start(cfg)
	var b = main.fleet.boats[main.fleet.player]
	# Close reach on starboard, heading south-west-ish, moving.
	b.place(b.pos, deg_to_rad(200.0), 2.5)
	b.tiller = 0.0
	return b


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


func _run() -> void:
	await _frames(5)
	print("tiller steering")
	var b = _start(true, 10.0)
	await _frames(30)
	var h0: float = b.heading
	await _hold("steer_left", 36)
	check(b.tiller > 0.5, "A pushes the tiller to port (rudder turns her to starboard): tiller %.2f" % b.tiller)
	await _frames(90)
	check(wrapf(b.heading - h0, -PI, PI) > 0.1, "...and the bow swings to starboard (%.0f°)" % rad_to_deg(wrapf(b.heading - h0, -PI, PI)))
	var t_hold: float = b.tiller
	await _frames(40)
	check(absf(b.tiller - t_hold) < 0.01, "let go, the tiller stays where it was")
	await _hold("center_helm", 60)
	check(absf(b.tiller) < 0.05, "Space brings it back to the centreline")

	print("arcade steering")
	b = _start(false, 10.0)
	await _frames(30)
	h0 = b.heading
	await _hold("steer_left", 36)
	await _frames(90)
	check(wrapf(b.heading - h0, -PI, PI) < -0.1, "A points the bow to port (%.0f°)" % rad_to_deg(wrapf(b.heading - h0, -PI, PI)))

	print("mainsheet under load")
	var gained := []
	for kn in [6.0, 18.0]:
		b = _start(true, kn)
		main.fleet.assist["main"] = false
		b.main_sheet = 0.8
		await _frames(120)
		var s0: float = b.main_sheet
		await _hold("main_in", 60)
		gained.append(s0 - b.main_sheet)
		print("    %d kn: pulled in %.2f of the sheet in half a second (load %d N)" % [kn, s0 - b.main_sheet, b.main_load])
	check(gained[1] < gained[0] * 0.85, "the sheet comes in slower in 18 kn than in 6 kn")
	var e0: float = b.main_sheet
	await _hold("main_out", 30)
	check(b.main_sheet - e0 > 0.15, "easing lets it run quickly (%.2f in 0.25 s)" % (b.main_sheet - e0))

	print("mouse")
	b = _start(true, 10.0)
	main.fleet.assist["main"] = false
	b.main_sheet = 0.6
	await _frames(10)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(-120, 60)
	mv.screen_relative = Vector2(-120, 60)
	Input.parse_input_event(mv)
	await _frames(2)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)
	check(b.tiller > 0.3, "dragging left moves the tiller handle to port (tiller %.2f)" % b.tiller)
	check(b.main_sheet < 0.6, "drawing the mouse back pulls the main in (%.2f)" % b.main_sheet)
	check(not main.mouse_helm, "releasing the button lets go")

	print("controls_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
