extends Camera3D
## Cameras: chase (behind the boat, mouse-orbitable), helm (from the skipper's seat), line
## (from the RC boat down the start line) and overhead (tactical, north up).

const Lake := preload("res://scripts/lake.gd")
const BoatView := preload("res://scripts/boat_view.gd")

enum Mode { CHASE, HELM, LINE, OVERHEAD }
const NAMES := ["Chase", "Helm", "Start line", "Overhead"]

var mode := Mode.CHASE
var sim  # BoatSim of the boat we follow
var view  # its BoatView, for the skipper's eye point
var race  # for the line camera
var dist := 13.0
var yaw_off := 0.0
var pitch_off := 0.0   # the pad's look up (+) / down, radians
var pitch := 0.28
var overhead_h := 110.0
var dragging := false
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _yaw := 0.0
var _eye := Vector3.ZERO
var _hyaw := 0.0
var _roll := 0.0
# The helm view is what the skipper sees from the weather rail: the crew just ahead, the cockpit
# below, the jib luff a little inboard, the horizon in the top third. So it looks a little
# inboard of straight ahead (full once the two sit out), down a little, and a little wider than
# the other cameras (set by eye).
var helm_fov := 72.0
var helm_down := 0.24      # slope of the line of sight below the horizontal
var helm_inboard := 0.2    # radians toward the centreline


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
	fov = helm_fov if mode == Mode.HELM else 62.0
	# Follow the drawn (interpolated) boat, not the physics step, so the view doesn't judder.
	var boat := Lake.to_3d(sim.pos, 0.0)
	if view != null:
		boat = Vector3(view.global_position.x, 0.0, view.global_position.z)
	# Heading and heel as drawn this frame (interpolated between physics steps), not the raw
	# 120 Hz values, so the view never steps.
	var h: float = -view.rotation.y if view != null else sim.heading
	var heel: float = view.drawn_heel if view != null and "drawn_heel" in view else sim.heel
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var k := 1.0 - exp(-dt * 5.0)
	match mode:
		Mode.CHASE:
			# Swing round slowly behind the boat so tacks don't whip the view.
			_yaw = lerp_angle(_yaw, h, 1.0 - exp(-dt * 1.2))
			var a := _yaw + yaw_off
			var back := -Vector3(sin(a), 0.0, -cos(a))
			var pc := clampf(pitch - pitch_off, 0.05, 1.35)
			var want := boat + back * dist * cos(pc) + Vector3.UP * (1.5 + dist * sin(pc))
			_pos = _pos.lerp(want, k) if _pos != Vector3.ZERO else want
			_look = _look.lerp(boat + Vector3.UP * 2.0, k) if _look != Vector3.ZERO else boat
			global_position = _pos
			look_at(_look, Vector3.UP)
		Mode.HELM:
			var side: float = clampf(sim.crew_y, -1.0, 1.0)
			var right := Vector3(cos(h), 0.0, sin(h))
			var eye := boat + fwd * BoatView.SKIPPER_X + right * side + Vector3.UP * (1.05 - absf(heel) * 0.3)
			if view != null and view.has_method("skipper_eye"):
				eye = view.skipper_eye()
			# Follow the skipper's eye through a short low-pass, so the crew shifting and the hull
			# working don't jerk the view; a jump (a new boat, a reset) snaps straight there.
			var ke := 1.0 - exp(-dt * 14.0)
			_eye = eye if _eye.distance_to(eye) > 2.0 else _eye.lerp(eye, ke)
			# Inboard is to port when the skipper sits to starboard; it swings across (through the
			# low-pass below) when they cross in a tack.
			var ss: float = view.skipper_side if view != null and "skipper_side" in view else signf(float(sim.crew_y))
			var inb := helm_inboard * ss
			_hyaw = lerp_angle(_hyaw, h + yaw_off - inb, 1.0 - exp(-dt * 12.0))
			_roll = lerpf(_roll, heel * 0.8, 1.0 - exp(-dt * 6.0))
			global_position = _eye
			var tilt := clampf(atan(-helm_down + (pitch - 0.28) * 0.6) + pitch_off, -1.3, 1.3)
			var dir := Vector3(sin(_hyaw) * cos(tilt), sin(tilt), -cos(_hyaw) * cos(tilt))
			look_at(_eye + dir, Vector3.UP.rotated(fwd, -_roll))
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
