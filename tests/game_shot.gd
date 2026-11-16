extends SceneTree
## Runs the real game windowed and saves screenshots, for checking the whole thing by eye.
## Run: godot --path . --script res://tests/game_shot.gd -- out=C:/tmp/shots [plan=race]
## Plans:
##   menu  - the start menu over the live AI race
##   race  - start a race, shots through check-in, the sequence, the start and the first beat
##   free  - free sailing

const Main := preload("res://main.tscn")

var out := "user://shots"
var plan := "race"
var main
var frames := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2 and kv[0] == "out":
			out = kv[1]
		elif kv.size() == 2 and kv[0] == "plan":
			plan = kv[1]
	DirAccess.make_dir_recursive_absolute(out)
	main = Main.instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	await _wait(2.0)
	if plan == "menu":
		await _wait(6.0)
		await _shot("menu")
		quit()
		return
	if plan == "finish":
		await _finish_plan()
		quit()
		return
	if plan == "hull":
		await _hull_plan()
		quit()
		return
	if plan == "water":
		await _water_plan()
		quit()
		return
	var cfg: Dictionary = main.menu.build_cfg()
	cfg["race"] = plan != "free"
	cfg["ai"] = 7 if plan != "free" else 0
	cfg["wind_from"] = 270.0
	cfg["wind_kn"] = 11.0
	cfg["start"] = -200.0
	cfg["course"] = 0
	main._on_start(cfg)
	await _wait(3.0)
	await _shot("01_helm")
	main.cam.mode = main.CameraRig.Mode.CHASE
	await _wait(1.5)
	await _shot("02_chase")
	main.hud.coach = true
	await _shot("02b_coach")
	main.hud.coach = false
	main.cam.mode = main.CameraRig.Mode.LINE
	await _wait(1.0)
	await _shot("03_line")
	main.cam.mode = main.CameraRig.Mode.OVERHEAD
	await _wait(1.0)
	await _shot("04_overhead")
	main.cam.mode = main.CameraRig.Mode.CHASE
	main.minimap.big = true
	main._layout_map()
	await _wait(0.5)
	await _shot("05_map")
	main.minimap.big = false
	main._layout_map()
	if plan == "free":
		quit()
		return
	# Let the player's boat be driven by an AI so it actually races, and warp to the start.
	var AI := preload("res://scripts/ai.gd")
	var ai := AI.new()
	ai.setup(99, 0.9)
	main.fleet.ais[main.fleet.player] = ai
	main.warp_i = 3
	while main.fleet.race.clock < -12.0:
		await _wait(0.25)
	main.warp_i = 0
	await _shot("06_prestart")
	while main.fleet.race.clock < 1.0:
		await _wait(0.1)
	await _shot("07_start")
	main.warp_i = 3
	while main.fleet.race.clock < 150.0:
		await _wait(0.25)
	main.warp_i = 0
	await _wait(1.0)
	await _shot("08_beat")
	main.hud.show_board = true
	await _shot("09_standings")
	main.hud.show_board = false
	main.hud.show_help = true
	await _shot("10_help")
	quit()


## A short race sailed by an AI in the player's boat: finish, results, pause menu.
func _finish_plan() -> void:
	var cfg: Dictionary = main.menu.build_cfg()
	cfg["race"] = true
	cfg["ai"] = 4
	cfg["wind_from"] = 200.0
	cfg["wind_kn"] = 12.0
	cfg["start"] = -65.0
	cfg["course"] = 1
	main._on_start(cfg)
	var AI := preload("res://scripts/ai.gd")
	var ai := AI.new()
	ai.setup(7, 0.95)
	main.fleet.ais[main.fleet.player] = ai
	main.warp_i = 3
	var e = main.fleet.race.entrants[main.fleet.player]
	while not e.finished and e.active():
		await _wait(0.5)
	main.warp_i = 0
	await _wait(1.0)
	await _shot("11_finished")
	main.fast_forward = true
	while main.state != "results":
		await _wait(0.5)
	await _wait(0.5)
	await _shot("12_results")
	main._next_race()
	await _wait(2.0)
	main.state = "paused"
	main.overlay.show_pause(true, main.fleet)
	await _wait(0.5)
	await _shot("13_pause")


## Looking down into a heeled cockpit, with and without the hull cut-out in the water.
func _hull_plan() -> void:
	var cfg: Dictionary = main.menu.build_cfg()
	cfg["race"] = false
	cfg["ai"] = 0
	cfg["wind_from"] = 270.0
	cfg["wind_kn"] = 15.0
	main._on_start(cfg)
	main.fleet.assist["hike"] = false
	var b = main.fleet.boats[main.fleet.player]
	b.hike = -0.7
	main.cam.mode = main.CameraRig.Mode.CHASE
	main.cam.dist = 3.2
	main.cam.pitch = 0.6
	main.hud.hide()
	main.minimap.hide()
	await _wait(4.0)
	for side in [-1, 1]:
		main.cam.yaw_off = 0.8 * side
		await _wait(1.5)
		main.cut_hulls = false
		await _wait(0.2)
		await _shot("hull_before_%d" % side)
		main.cut_hulls = true
		await _wait(0.2)
		await _shot("hull_after_%d" % side)


## The water and the wakes: a fleet beating after the start, from several angles, then a breeze.
func _water_plan() -> void:
	for kn in [11.0, 18.0]:
		var cfg: Dictionary = main.menu.build_cfg()
		cfg["race"] = true
		cfg["ai"] = 7
		cfg["wind_from"] = 250.0
		cfg["wind_kn"] = kn
		cfg["start"] = -65.0
		cfg["course"] = 0
		main._on_start(cfg)
		var AI := preload("res://scripts/ai.gd")
		var ai := AI.new()
		ai.setup(3, 0.9)
		main.fleet.ais[main.fleet.player] = ai
		main.hud.hide()
		main.minimap.hide()
		main.warp_i = 2
		while main.fleet.race.clock < 45.0:
			await _wait(0.25)
		main.warp_i = 0
		var tag := "%d" % int(kn)
		main.cam.mode = main.CameraRig.Mode.CHASE
		main.cam.dist = 16.0
		main.cam.pitch = 0.32
		main.cam.yaw_off = 0.5
		await _wait(2.0)
		await _shot("w%s_chase" % tag)
		main.cam.mode = main.CameraRig.Mode.OVERHEAD
		main.cam.overhead_h = 55.0
		await _wait(2.0)
		await _shot("w%s_top" % tag)
		main.cam.mode = main.CameraRig.Mode.CHASE
		main.cam.dist = 70.0
		main.cam.pitch = 0.12
		main.cam.yaw_off = 2.6
		await _wait(2.5)
		await _shot("w%s_far" % tag)
		# Low, looking into the sun's glitter.
		main.cam.dist = 22.0
		main.cam.pitch = 0.1
		main.cam.yaw_off = deg_to_rad(235.0) - main.fleet.boats[main.fleet.player].heading
		await _wait(2.5)
		await _shot("w%s_sun" % tag)
		# High over the lake: puffs, lulls and the chop building with fetch.
		main.cam.mode = main.CameraRig.Mode.OVERHEAD
		main.cam.overhead_h = 600.0
		await _wait(3.0)
		await _shot("w%s_high" % tag)
		if kn < 12.0:
			main.cam.mode = main.CameraRig.Mode.HELM
			main.cam.yaw_off = 0.0
			await _wait(1.0)
			await _shot("w%s_helm" % tag)
