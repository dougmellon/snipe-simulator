extends Camera3D
## Cameras: chase (behind the boat, mouse-orbitable), helm (from the skipper's seat), line
## (from the RC boat down the start line) and overhead (tactical, north up).

const Lake := preload("res://scripts/lake.gd")

enum Mode { CHASE, HELM, LINE, OVERHEAD }
const NAMES := ["Chase", "Helm", "Start line", "Overhead"]

var mode := Mode.CHASE
var sim  # BoatSim of the boat we follow
var view  # its BoatView, for the skipper's eye point
var race  # for the line camera
var dist := 13.0
var yaw_off := 0.0
var pitch := 0.28
var overhead_h := 110.0
var dragging := false
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _yaw := 0.0


func _ready() -> void:
	fov = 62.0
	near = 0.1
	far = 40000.0


func cycle() -> void:
	mode = ((int(mode) + 1) % 4) as Mode
	if mode == Mode.LINE and race == null:
		mode = Mode.OVERHEAD
	yaw_off = 0.0


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(dist * 0.9, 5.0)
			overhead_h = maxf(overhead_h * 0.9, 40.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(dist * 1.1, 90.0)
			overhead_h = minf(overhead_h * 1.1, 2600.0)
	elif ev is InputEventMouseMotion and dragging:
		var mm := ev as InputEventMouseMotion
		yaw_off -= mm.relative.x * 0.006
		pitch = clampf(pitch + mm.relative.y * 0.004, -0.15 if mode == Mode.HELM else 0.05, 1.35)


func follow(dt: float) -> void:
	if sim == null:
		return
	if view != null and view.has_method("set_crew_visible"):
		# Looking out from the helm, you don't see yourself.
		view.set_crew_visible(mode != Mode.HELM, mode != Mode.HELM)
	# Follow the drawn (interpolated) boat, not the physics step, so the view doesn't judder.
	var boat := Lake.to_3d(sim.pos, 0.0)
	if view != null:
		boat = Vector3(view.global_position.x, 0.0, view.global_position.z)
	var h: float = sim.heading
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var k := 1.0 - exp(-dt * 5.0)
	match mode:
		Mode.CHASE:
			# Swing round slowly behind the boat so tacks don't whip the view.
			_yaw = lerp_angle(_yaw, h, 1.0 - exp(-dt * 1.2))
			var a := _yaw + yaw_off
			var back := -Vector3(sin(a), 0.0, -cos(a))
			var want := boat + back * dist * cos(pitch) + Vector3.UP * (1.5 + dist * sin(pitch))
			_pos = _pos.lerp(want, k) if _pos != Vector3.ZERO else want
			_look = _look.lerp(boat + Vector3.UP * 2.0, k) if _look != Vector3.ZERO else boat
			global_position = _pos
			look_at(_look, Vector3.UP)
		Mode.HELM:
			var side: float = clampf(sim.crew_y, -1.0, 1.0)
			var right := Vector3(cos(h), 0.0, sin(h))
			var eye := boat + fwd * -1.4 + right * side + Vector3.UP * (1.05 - absf(sim.heel) * 0.3)
			if view != null and view.has_method("skipper_eye"):
				eye = view.skipper_eye()
			global_position = eye
			var a := h + yaw_off
			var dir := Vector3(sin(a), -0.08 + (pitch - 0.28) * 0.6, -cos(a))
			look_at(eye + dir, Vector3.UP.rotated(fwd, -sim.heel * 0.8))
		Mode.LINE:
			if race == null:
				mode = Mode.OVERHEAD
				return
			var rc := Lake.to_3d(race.rc_pos, 3.2)
			var pin := Lake.to_3d(race.pin, 0.5)
			var along := (pin - rc).normalized()
			global_position = rc - along * 6.0 + Vector3.UP * 1.0
			look_at(pin.lerp(boat, 0.25), Vector3.UP)
		Mode.OVERHEAD:
			var want := boat + Vector3.UP * overhead_h + Vector3(0, 0, overhead_h * 0.02)
			_pos = _pos.lerp(want, k)
			global_position = _pos
			look_at(boat, Vector3.FORWARD)
