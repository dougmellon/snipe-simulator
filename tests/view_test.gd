extends Node3D
## Visual check of the 3D views: the world, the committee boat, and Snipes in assorted states
## around the start line (hiking upwind on both tacks, reaching, running, luffing head to wind,
## capsized). Boats are posed, not simulated.
## Run windowed: godot --path . res://tests/view_test.tscn -- [cam=start|chase|high|rc|close|crew|helm|leeward|horizon]
##   [boat=0] [fov=60] [flags=L|PX] [shot=out.png] [frames=45] [perf=1] [wind=12]

const Lake := preload("res://scripts/lake.gd")
const Race := preload("res://scripts/race.gd")
const Wind := preload("res://scripts/wind.gd")
const BoatSim := preload("res://scripts/boat_sim.gd")
const WorldView := preload("res://scripts/world_view.gd")
const BoatView := preload("res://scripts/boat_view.gd")

const WIND_FROM := 270.0

var lake
var race
var wind
var world
var sims: Array = []
var views: Array = []
var cam: Camera3D
var args := {}
var t := 0.0
var frames := 0
var perf_t := 0.0
var perf_frames := 0
var shooting := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	lake = Lake.new()
	world = WorldView.new()
	add_child(world)
	world.build(lake)
	race = Race.new()
	race.setup(lake, WIND_FROM, 0, [], -170.0)
	world.set_race(race)
	var flags := {"L": true} if args.get("flags", "PX") == "L" else {"PORTSMOUTH": true, "X": true}
	world.update_flags(flags, race.course_text)
	world.highlight_mark(str(race.course[0]))
	world.set_line_visible(true)
	wind = Wind.new()
	wind.setup(WIND_FROM, float(args.get("wind", "12")), 0.6, 3, lake)
	_make_boats()
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 40000.0
	cam.fov = float(args.get("fov", "60"))
	add_child(cam)
	cam.current = true
	_place_camera()


## Posed boats: [dx downwind of the line, dy along it from the RC end, heading, boom, jib,
## heel, crew_y, awa, main_alpha, jib_alpha, u, tiller, board, colour, sail]
func _make_boats() -> void:
	var specs := [
		[18.0, -12.0, 225.0, -0.1, -0.19, -0.13, 1.02, 0.6, 0.22, 0.2, 3.3, 0.1, 1.0, Color(0.95, 0.95, 0.93), "31415"],
		[34.0, -30.0, 315.0, 0.11, 0.19, 0.12, -0.9, -0.6, 0.2, 0.18, 3.0, -0.1, 1.0, Color(0.1, 0.18, 0.42), "30577"],
		[52.0, -48.0, 180.0, -0.85, -0.62, -0.08, 0.7, 1.4, 0.5, 0.45, 4.2, 0.0, 0.6, Color(0.75, 0.1, 0.08), "29810"],
		[75.0, -20.0, 95.0, 1.3, -0.85, 0.02, -0.25, -2.85, 0.5, 0.4, 3.4, 0.2, 0.3, Color(0.95, 0.8, 0.15), "31102"],
		[28.0, -62.0, 272.0, 0.04, -0.06, 0.0, 0.3, 0.03, 0.015, 0.01, 0.2, 0.0, 1.0, Color(0.55, 0.75, 0.9), "28456"],
		[60.0, -75.0, 200.0, -0.4, -0.3, 1.45, 0.4, 0.8, 0.0, 0.0, 0.2, 0.0, 1.0, Color(0.15, 0.45, 0.25), "32091"],
		[44.0, -8.0, 350.0, 0.55, 0.45, 0.06, -0.55, -1.1, 0.25, 0.22, 2.0, 0.0, 1.0, Color(0.12, 0.12, 0.14), "30966"],
		[90.0, -55.0, 240.0, -0.3, -0.28, -0.1, 0.95, 0.9, 0.2, 0.2, 3.8, 0.0, 1.0, Color(0.75, 0.77, 0.8), "31777"],
		[-25.0, -35.0, 222.0, -0.1, -0.18, -0.15, 1.05, 0.62, 0.21, 0.19, 3.4, 0.05, 1.0, Color(0.9, 0.45, 0.1), "30215"],
		[110.0, -30.0, 318.0, 0.1, 0.18, 0.1, -0.95, -0.62, 0.23, 0.2, 3.2, -0.05, 1.0, Color(0.3, 0.55, 0.35), "29777"],
	]
	var up := Vector2(sin(deg_to_rad(WIND_FROM)), cos(deg_to_rad(WIND_FROM)))
	var along: Vector2 = (race.pin - race.rc_pos).normalized()
	for i in specs.size():
		var s: Array = specs[i]
		var b := BoatSim.new()
		b.pos = race.rc_pos - up * s[0] + along * -s[1]
		b.heading = deg_to_rad(s[2])
		b.boom = s[3]
		b.jib = s[4]
		b.heel = s[5]
		b.crew_y = s[6]
		b.awa = s[7]
		b.aws = 7.0
		b.main_alpha = s[8]
		b.jib_alpha = s[9]
		b.u = s[10]
		b.tiller = s[11]
		b.board = s[12]
		if absf(b.heel) > 1.0:
			b.capsized = true
			b.capsize_side = signf(b.heel)
		sims.append(b)
		var v := BoatView.new()
		add_child(v)
		v.setup(s[13], s[14], i == 0)
		views.append(v)


func _place_camera() -> void:
	var mode: String = args.get("cam", "start")
	var bi := clampi(int(args.get("boat", "0")), 0, sims.size() - 1)
	var b = sims[bi]
	var bp := Lake.to_3d(b.pos)
	var fwd := Vector3(sin(b.heading), 0.0, -cos(b.heading))
	var stb := Vector3(cos(b.heading), 0.0, sin(b.heading))
	var lc: Vector2 = race.line_center()
	match mode:
		"chase":
			cam.position = bp - fwd * 10.5 + Vector3(0, 4.2, 0) - stb * 2.0
			cam.look_at(bp + fwd * 4.0 + Vector3(0, 2.2, 0))
		"close":
			# The whole rig from the windward bow quarter: telltales.
			var side := 1.0 if b.crew_y >= 0.0 else -1.0
			cam.position = bp + stb * side * 5.2 + fwd * 4.2 + Vector3(0, 2.6, 0)
			cam.look_at(bp + Vector3(0, 3.1, 0) - fwd * 0.6)
		"crew":
			var side := 1.0 if b.crew_y >= 0.0 else -1.0
			cam.position = bp + stb * side * 4.2 + fwd * 3.2 + Vector3(0, 2.2, 0)
			cam.look_at(bp + Vector3(0, 1.6, 0) - fwd * 0.3)
		"helm":
			# Skipper's eye on the windward side deck, looking forward at the jib luff.
			var v: Node3D = views[bi].pivot
			var side := 1.0 if b.crew_y >= 0.0 else -1.0
			cam.position = v.global_transform * Vector3(side * 0.5, 1.05, -BoatView.SKIPPER_X)
			cam.look_at(v.global_transform * Vector3(0.0, 2.1, -BoatView.SKIPPER_X - 3.4))
		"leeward":
			var side := -1.0 if b.crew_y >= 0.0 else 1.0
			cam.position = bp + stb * side * 5.5 + fwd * 1.5 + Vector3(0, 2.0, 0)
			cam.look_at(bp + Vector3(0, 2.2, 0))
		# Close looks at the boat model itself.
		"profile":
			cam.position = bp + stb * 6.5 + Vector3(0, 0.9, 0)
			cam.look_at(bp + Vector3(0, 0.55, 0))
		"quarter":
			var side := 1.0 if b.crew_y >= 0.0 else -1.0
			cam.position = bp - fwd * 4.2 + stb * side * 2.6 + Vector3(0, 2.6, 0)
			cam.look_at(bp + fwd * 0.4 + Vector3(0, 0.3, 0))
		"bowq":
			var side := -1.0 if b.crew_y >= 0.0 else 1.0
			cam.position = bp + fwd * 4.6 + stb * side * 2.8 + Vector3(0, 1.0, 0)
			cam.look_at(bp + Vector3(0, 0.6, 0))
		"stern":
			cam.position = bp - fwd * 4.5 + Vector3(0, 0.8, 0)
			cam.look_at(bp + Vector3(0, 0.5, 0))
		"top":
			cam.position = bp + Vector3(0, 7.0, 0) - fwd * 0.4
			cam.look_at(bp, fwd)
		"cockpit":
			cam.position = bp - fwd * 1.6 + stb * 0.9 + Vector3(0, 1.9, 0)
			cam.look_at(bp + fwd * 0.6 - stb * 0.1 + Vector3(0, 0.2, 0))
		"high":
			cam.position = Vector3(1050.0, 600.0, 1500.0)
			cam.look_at(Lake.to_3d(Vector2(-700.0, 700.0)))
		"rc":
			var rc := Lake.to_3d(race.rc_pos)
			var h: float = race.rc_heading
			var aft := Vector3(-sin(h), 0.0, cos(h))
			var right := Vector3(cos(h), 0.0, sin(h))
			cam.position = rc + aft * 11.0 + right * 10.0 + Vector3(0, 3.0, 0)
			cam.look_at(rc + Vector3(0, 2.4, 0))
		"horizon":
			cam.position = Lake.to_3d(lc + Vector2(120.0, 0.0), 2.5)
			cam.look_at(Lake.to_3d(lc + Vector2(-1000.0, 60.0), 40.0))
		_:
			cam.position = Lake.to_3d(lc + Vector2(72.0, -48.0), 30.0)
			cam.look_at(Lake.to_3d(lc + Vector2(22.0, -5.0)))


func _process(delta: float) -> void:
	t += delta
	frames += 1
	wind.update(delta)
	world.update_water(t, wind.mean_from(), wind.base_speed, wind.shader_puffs())
	# Cut the hulls out of the water, as main.gd does, so waves don't show inside cockpits.
	var hulls := PackedVector4Array()
	var speeds := PackedFloat32Array()
	for i in views.size():
		views[i].sync(sims[i], t)
		hulls.append(Vector4(sims[i].pos.x, sims[i].pos.y, sims[i].heading, sims[i].heel))
		speeds.append(sims[i].u)
	world.update_hulls(hulls)
	world.update_hull_speeds(speeds)
	_place_camera()
	if args.has("perf"):
		if t > 3.0:
			perf_t += delta
			perf_frames += 1
		if perf_t > 5.0:
			print("fps %.1f  draw calls %d  primitives %d" % [perf_frames / perf_t,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			get_tree().quit()
	elif args.has("shot") and not shooting and frames >= int(args.get("frames", "45")):
		shooting = true
		_shoot(args["shot"])


func _shoot(path: String) -> void:
	for _k in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("saved %s (%s)" % [path, error_string(err)])
	get_tree().quit()
