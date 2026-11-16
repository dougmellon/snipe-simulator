extends RefCounted
## Snipe dinghy physics: surge, sway, yaw and heel. The main, jib, centreboard and rudder are
## lifting surfaces fed by the local flow; the crew hikes to hold the boat flat.
##
## Body frame: x forward, y to starboard. Positive yaw rate turns the bow to starboard.
## Positive heel puts the starboard rail down. World is Vector2(east, north); heading is a
## compass angle in radians (0 = north, increasing clockwise).

const KN := 0.514444
const G := 9.81
const RHO_W := 1000.0

# Snipe: LOA 4.72 m, beam 1.52 m, minimum hull weight 172 kg, main 8.8 m2 + jib 3.0 m2.
const HULL_MASS := 172.0
const RIG_MASS := 25.0
const MAIN_AREA := 8.8
const JIB_AREA := 3.0
const BOOM_LEN := 2.9
const JIB_FOOT := 1.7
const MAST_X := 0.75
const JIB_TACK_X := 2.2
const MAIN_CE_H := 2.75
const JIB_CE_H := 2.0
const BOARD_X := 0.2
const BOARD_AREA := 0.26
const HULL_KEEL_AREA := 0.07
const BOARD_DEPTH := 0.55
const RUDDER_X := -2.35
const RUDDER_AREA := 0.12
const RUDDER_DEPTH := 0.35
const MAX_RUDDER := 0.63  # 36 degrees
const BOW_X := 2.45
const STERN_X := -2.27
const HALF_BEAM := 0.76
const MAIN_MIN := 0.052
const MAIN_MAX := 1.48
const JIB_MIN := 0.175
const JIB_MAX := 0.9
const HIKE_MAX := 1.05
const CAPSIZE_HEEL := 1.22  # 70 degrees
const RIGHT_DELAY := 18.0  # the crew swims round, stands on the board and brings her up
const RIGHT_MIN := 8.0

# Lift and drag against angle of attack to the chord (degrees). A cambered soft sail only
# fills once the flow is ~10 degrees past the chord; below that the luff backwinds.
const SAIL_A := [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 25.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 120.0, 150.0, 180.0]
const SAIL_CL := [0.0, 0.15, 0.45, 0.85, 1.20, 1.40, 1.45, 1.38, 1.18, 0.95, 0.72, 0.50, 0.26, 0.02, -0.2, -0.5, -0.5, 0.0]
const SAIL_CD := [0.10, 0.10, 0.11, 0.15, 0.21, 0.28, 0.37, 0.46, 0.62, 0.79, 0.95, 1.08, 1.18, 1.22, 1.2, 1.05, 0.6, 0.3]
# Centreboard and rudder: thin foil, stalls near 15 degrees.
const FOIL_A := [0.0, 4.0, 8.0, 12.0, 15.0, 18.0, 25.0, 40.0, 60.0, 90.0, 120.0, 150.0, 170.0, 180.0]
const FOIL_CL := [0.0, 0.30, 0.58, 0.85, 0.95, 0.80, 0.75, 0.95, 0.85, 0.0, -0.8, -0.7, -0.4, 0.0]
const FOIL_CD := [0.012, 0.016, 0.030, 0.055, 0.080, 0.20, 0.40, 0.80, 1.25, 1.45, 1.25, 0.6, 0.15, 0.02]
# Bare-hull resistance in newtons against speed in knots (displacement hump, then planing).
const RES_KN := [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 5.5, 6.0, 7.0, 8.0, 9.0, 10.0, 12.0, 16.0]
const RES_N := [0.0, 4.0, 14.0, 32.0, 60.0, 115.0, 165.0, 220.0, 320.0, 410.0, 500.0, 590.0, 820.0, 1500.0]

var crew_mass := 150.0
var rho_air := 1.03  # thinner air at 1511 m

# State
var pos := Vector2.ZERO
var heading := 0.0
var u := 0.0
var v := 0.0
var r := 0.0
var heel := 0.0
var heel_rate := 0.0
var boom := -0.3
var jib := -0.25
var crew_y := 0.4
var capsized := false
var capsize_side := 1.0
var capsize_t := 0.0
var aground := false

# Controls
var tiller := 0.0      # -1..1, positive turns to starboard
var main_sheet := 0.5  # 0 = sheeted hard, 1 = fully eased
var jib_sheet := 0.5
var hike := 0.5        # -1 crew to leeward, 0 sitting on the windward rail, 1 full hike
var board := 1.0       # 1 down, 0 up
var vang := 0.5        # 0 slack (leech twists open) .. 1 hard on
var flatten := 0.2     # outhaul + cunningham: 0 full, deep sail .. 1 flat, depowered
var chop := 0.0        # 0 flat water .. 1 full-fetch chop (set by the fleet from the fetch)
var water_in := 0.0    # water left in the boat after a capsize, 0..1

# Telemetry (updated each step)
var tws := 0.0
var tw_from := 0.0      # degrees
var twa := 0.0          # signed radians, + = wind over the starboard side
var aws := 0.0
var awa := 0.0          # signed radians, + = from starboard
var main_alpha := 0.0
var jib_alpha := 0.0
var drive := 0.0
var heel_ext := 0.0     # heeling moment from sails and foils last step (N m)
var main_load := 0.0    # force in the mainsail (N), which is what you pull against on the sheet
var just_capsized := false


func mass() -> float:
	return HULL_MASS + RIG_MASS + crew_mass


func speed() -> float:
	return Vector2(u, v).length()


func fwd() -> Vector2:
	return Vector2(sin(heading), cos(heading))


func stb() -> Vector2:
	return Vector2(cos(heading), -sin(heading))


func velocity() -> Vector2:
	return fwd() * u + stb() * v


## +1 when the wind comes over the starboard side (boom to port) - "starboard tack" by RRS
## definition, which goes by the side opposite the main boom when running.
func tack() -> int:
	if absf(boom) > 0.02:
		return 1 if boom < 0.0 else -1
	return 1 if awa >= 0.0 else -1


func bow() -> Vector2:
	return pos + fwd() * BOW_X


func stern() -> Vector2:
	return pos + fwd() * STERN_X


func place(p: Vector2, heading_rad: float, speed_ms := 0.0) -> void:
	pos = p
	heading = heading_rad
	u = speed_ms
	v = 0.0
	r = 0.0
	heel = 0.0
	heel_rate = 0.0
	capsized = false
	aground = false


## The crew starts righting her now (only once they have had time to get to the board).
func right_now() -> void:
	if capsized and capsize_t >= RIGHT_MIN:
		capsize_t = maxf(capsize_t, RIGHT_DELAY)


func step(dt: float, wind: Vector2) -> void:
	just_capsized = false
	var f := fwd()
	var s := stb()
	var vel := f * u + s * v
	tws = wind.length()
	tw_from = fposmod(rad_to_deg(atan2(-wind.x, -wind.y)), 360.0)
	twa = atan2(-wind.dot(s), -wind.dot(f))
	var va := wind - vel
	var ax := va.dot(f)
	var ay := va.dot(s)
	aws = sqrt(ax * ax + ay * ay)
	awa = atan2(-ay, -ax)

	if capsized:
		_step_capsized(dt, f, s)
		return

	# --- Sails -----------------------------------------------------------------------
	_update_booms(dt)
	var flow_s := Vector2(ax, ay * cos(heel))
	var main_chord := Vector2(-cos(boom), sin(boom))
	var jib_chord := Vector2(-cos(jib), sin(jib))
	var mt := main_tune()
	var fm := _surface(flow_s, main_chord.angle(), MAIN_AREA, rho_air, SAIL_A, SAIL_CL, SAIL_CD, true, mt.x, mt.y)
	main_alpha = _last_alpha
	main_load = fm.length()
	var jib_cover := 1.0 - 0.4 * smoothstep(1.9, 2.6, absf(awa))
	var fj := _surface(flow_s, jib_chord.angle(), JIB_AREA * jib_cover, rho_air, SAIL_A, SAIL_CL, SAIL_CD, true) * 0.95
	jib_alpha = _last_alpha
	var pm := Vector2(MAST_X, 0.0) + main_chord * (0.4 * BOOM_LEN)
	var pj := Vector2(JIB_TACK_X, 0.0) + jib_chord * (0.45 * JIB_FOOT)
	pm.y += MAIN_CE_H * mt.z * sin(heel)
	pj.y += JIB_CE_H * sin(heel)
	var ch := cos(heel)
	var fm_h := Vector2(fm.x, fm.y * ch)
	var fj_h := Vector2(fj.x, fj.y * ch)
	drive = fm.x + fj.x

	# Windage of hull, rig and crew, acting ahead of the board so a stalled boat falls off.
	var fw := va * (0.5 * rho_air * 0.9 * 1.0 * aws)
	var fw_b := Vector2(fw.dot(f), fw.dot(s))
	var pw := Vector2(0.9, 0.0)

	# --- Foils -----------------------------------------------------------------------
	var board_area := BOARD_AREA * clampf(board, 0.0, 1.0) + HULL_KEEL_AREA
	var flow_b := -Vector2(u, v + r * BOARD_X)
	var fb := _surface(flow_b, PI, board_area, RHO_W, FOIL_A, FOIL_CL, FOIL_CD, false)
	fb.y *= ch
	var delta := clampf(tiller, -1.0, 1.0) * MAX_RUDDER
	var flow_r := -Vector2(u, v + r * RUDDER_X)
	var fr := _surface(flow_r, PI - delta, RUDDER_AREA, RHO_W, FOIL_A, FOIL_CL, FOIL_CD, false)
	fr.y *= ch

	# --- Hull ------------------------------------------------------------------------
	var res := _interp(RES_KN, RES_N, absf(u) / KN) * (1.0 + 0.8 * sin(heel) * sin(heel)) * (1.0 + 0.6 * water_in)
	# Punching into chop upwind costs speed.
	res += 0.48 * tws * tws * chop * maxf(cos(twa), 0.0) * clampf(u / 2.0, 0.0, 1.0)
	water_in = maxf(water_in - dt * (0.01 + 0.025 * maxf(u, 0.0)), 0.0)
	if u < 0.0:
		res *= 2.0
	var x_hull := -signf(u) * res
	var y_hull := -0.5 * RHO_W * 0.3 * 1.0 * v * absf(v)
	var n_hull := -110.0 * r * (absf(u) + 0.2) - 450.0 * r * absf(r)
	# A heeled hull wants to turn away from the side that is down (weather helm).
	n_hull += -70.0 * heel * u * absf(u)

	var fx := fm_h.x + fj_h.x + fw_b.x + fb.x + fr.x + x_hull
	var fy := fm_h.y + fj_h.y + fw_b.y + fb.y + fr.y + y_hull
	var n := _cross(pm, fm_h) + _cross(pj, fj_h) + _cross(pw, fw_b) \
		+ _cross(Vector2(BOARD_X, 0.0), fb) + _cross(Vector2(RUDDER_X, 0.0), fr) + n_hull

	# --- Heel ------------------------------------------------------------------------
	heel_ext = fm.y * MAIN_CE_H * mt.z + fj.y * JIB_CE_H + fw_b.y * 1.2 - fb.y * BOARD_DEPTH - fr.y * RUDDER_DEPTH
	var side := -signf(boom) if absf(boom) > 0.02 else signf(awa)
	var target_y := 0.0
	if hike >= 0.0:
		target_y = side * lerpf(0.35, HIKE_MAX, clampf(hike, 0.0, 1.0))
	else:
		target_y = side * lerpf(0.35, -0.3, clampf(-hike, 0.0, 1.0))
	crew_y = move_toward(crew_y, target_y, 1.4 * dt)
	var m_crew := crew_mass * G * crew_y * cos(heel)
	var m_form := -mass() * G * _gz(heel)
	var m_damp := -700.0 * heel_rate - 500.0 * heel_rate * absf(heel_rate)
	var ix := 480.0

	# --- Integrate -------------------------------------------------------------------
	var m := mass()
	var mx := m * 1.08
	var my := m * 1.6
	var iz := m * 1.35
	u += (fx + my * v * r) / mx * dt
	v += (fy - mx * u * r) / my * dt
	r += n / iz * dt
	heel_rate += (heel_ext + m_crew + m_form + m_damp) / ix * dt
	heel += heel_rate * dt
	u = clampf(u, -4.0, 12.0)
	heading = fposmod(heading + r * dt, TAU)
	pos += (fwd() * u + stb() * v) * dt

	if absf(heel) > CAPSIZE_HEEL:
		capsized = true
		just_capsized = true
		capsize_side = signf(heel)
		capsize_t = 0.0


func _step_capsized(dt: float, f: Vector2, s: Vector2) -> void:
	capsize_t += dt
	var k := exp(-1.5 * dt)
	u *= k
	v *= k
	r *= exp(-2.5 * dt)
	heading = fposmod(heading + r * dt, TAU)
	pos += (f * u + s * v) * dt
	main_alpha = 0.0
	jib_alpha = 0.0
	drive = 0.0
	main_load = 0.0
	if capsize_t < RIGHT_DELAY:
		heel = move_toward(heel, capsize_side * 1.45, 1.2 * dt)
	else:
		heel = move_toward(heel, 0.0, 0.6 * dt)
		if absf(heel) < 0.01:
			capsized = false
			heel = 0.0
			heel_rate = 0.0
			main_sheet = 1.0
			jib_sheet = 1.0
			water_in = 1.0


func _update_booms(dt: float) -> void:
	var cur := signf(boom) if absf(boom) > 0.001 else -signf(awa)
	var side := cur
	# The boom stays put when sailing slightly by the lee; otherwise it goes to leeward.
	if signf(awa) == cur and absf(awa) < 2.8:
		side = -cur
	var lim := lerpf(MAIN_MIN, MAIN_MAX, clampf(main_sheet, 0.0, 1.0))
	var want := side * (minf(lim, absf(awa)) if side == -signf(awa) else lim)
	var rate := 5.0 if signf(want) != signf(boom) and absf(boom) > 0.3 else 2.5
	boom = move_toward(boom, want, rate * dt)

	# In irons the crew backs the jib (holds it to windward) to push the bow off.
	if absf(awa) < 0.55 and u < 0.35 and absf(awa) > 0.02:
		jib = move_toward(jib, signf(awa) * 0.6, 3.0 * dt)
		return
	var jside := signf(jib) if absf(jib) > 0.001 else -signf(awa)
	if signf(awa) == jside and absf(awa) < 2.95:
		jside = -jside
	var jlim := lerpf(JIB_MIN, JIB_MAX, clampf(jib_sheet, 0.0, 1.0))
	var jwant := jside * (minf(jlim, absf(awa)) if jside == -signf(awa) else jlim)
	jib = move_toward(jib, jwant, 4.0 * dt)


var _last_alpha := 0.0


## Force of a lifting surface on the boat (body frame) for fluid flowing past it at `flow`.
## `chord_angle` is the direction from leading to trailing edge.
func _surface(flow: Vector2, chord_angle: float, area: float, rho: float, ta: Array, tcl: Array, tcd: Array, is_sail: bool, cl_k := 1.0, cd_add := 0.0) -> Vector2:
	var sp2 := flow.length_squared()
	if sp2 < 1e-6 or area <= 0.0:
		_last_alpha = 0.0
		return Vector2.ZERO
	var a := wrapf(flow.angle() - chord_angle, -PI, PI)
	_last_alpha = a
	var ad := rad_to_deg(absf(a))
	var cl := _interp(ta, tcl, ad) * signf(a)
	var cd := _interp(ta, tcd, ad)
	if cl_k != 1.0:
		# Less lift from a flatter or more twisted sail also means less induced drag, which is
		# most of a sail's drag while the flow is attached.
		var attached := 1.0 - smoothstep(22.0, 45.0, ad)
		cl *= lerpf(1.0, cl_k, 0.4 + 0.6 * attached)
		cd *= lerpf(1.0, 0.15 + 0.85 * cl_k * cl_k, attached)
	cd += cd_add
	if is_sail:
		# Near the luffing point the front of the sail bubbles and flogs: easing to depower or
		# pinching both cost drag, which is why real crews flatten the sail instead.
		cd += 0.12 * (1.0 - smoothstep(4.0, 15.0, ad))
	var d := flow / sqrt(sp2)
	var lift_dir := Vector2(-d.y, d.x)
	return (lift_dir * cl + d * cd) * (0.5 * rho * sp2 * area)


## Main sail shape from the vang and the outhaul/cunningham: Vector3(lift factor, extra drag,
## centre-of-effort height factor). A loose vang twists the leech open (less power, lower
## heeling arm); a flat sail makes less lift but less drag; in light air a hard vang stalls
## the leech.
func main_tune() -> Vector3:
	var twist := 1.0 - clampf(vang, 0.0, 1.0)
	var flat := clampf(flatten, 0.0, 1.0)
	var light := clampf((4.0 - aws) / 3.0, 0.0, 1.0)
	if absf(awa) > 1.9:
		# Off the wind a loose vang lets the boom lift and the head fall off.
		return Vector3((1.0 - 0.12 * flat) * (1.0 - 0.12 * twist), 0.0, 1.0)
	var cl_k := (1.0 - 0.35 * flat) * (1.0 - 0.2 * twist)
	var extra := 0.07 * (1.0 - twist) * light
	return Vector3(cl_k, extra, 1.0 - 0.14 * twist - 0.04 * flat)


## Vang and outhaul settings a good crew would use for this wind (assists and the AI).
func auto_rig() -> void:
	var kn := tws / KN
	if absf(twa) < 1.9:
		# Full and powered up to about 12 kn, then flatten and let the top twist off.
		flatten = clampf((kn - 11.0) / 6.0, 0.0, 1.0)
		vang = lerpf(0.9, 0.25, clampf((kn - 13.0) / 5.0, 0.0, 1.0))
	else:
		flatten = clampf((kn - 14.0) / 8.0, 0.0, 0.5)
		vang = 0.7


## Righting arm of hull and rig alone (m), falling off once the rail goes under.
func _gz(h: float) -> float:
	var a := absf(h)
	var gz := 0.2 * sin(2.0 * minf(a, 0.785))
	if a > 0.785:
		gz *= clampf(1.0 - (a - 0.785) / 0.7, 0.0, 1.0)
	return gz * signf(h)


static func _cross(p: Vector2, force: Vector2) -> float:
	return p.x * force.y - p.y * force.x


static func _interp(xs: Array, ys: Array, x: float) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			var t: float = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
			return lerpf(ys[i - 1], ys[i], t)
	return ys[ys.size() - 1]


# --- Assists used by the AI and the player's auto options ---------------------------------

## Sheet settings that give the most drive for the current apparent wind without heeling the
## boat more than a fully hiked crew can hold. Returns Vector2(main_sheet, jib_sheet).
func best_sheets() -> Vector2:
	var flow_s := Vector2(-aws * cos(awa), -aws * sin(awa) * cos(heel))
	var hold := crew_mass * G * HIKE_MAX * 0.97 + mass() * G * _gz(0.2)
	var side := -signf(awa) if absf(awa) > 0.01 else -1.0
	var mt := main_tune()
	var mains := []
	for i in 21:
		var b := side * minf(lerpf(MAIN_MIN, MAIN_MAX, i / 20.0), absf(awa))
		mains.append(_surface(flow_s, Vector2(-cos(b), sin(b)).angle(), MAIN_AREA, rho_air, SAIL_A, SAIL_CL, SAIL_CD, true, mt.x, mt.y))
	var jib_cover := 1.0 - 0.4 * smoothstep(1.9, 2.6, absf(awa))
	var jibs := []
	for i in 9:
		var b := side * minf(lerpf(JIB_MIN, JIB_MAX, i / 8.0), absf(awa))
		jibs.append(_surface(flow_s, Vector2(-cos(b), sin(b)).angle(), JIB_AREA * jib_cover, rho_air, SAIL_A, SAIL_CL, SAIL_CD, true) * 0.95)
	var best := Vector2(1, 1)
	var best_score := -INF
	for i in mains.size():
		for j in jibs.size():
			var fm: Vector2 = mains[i]
			var fj: Vector2 = jibs[j]
			var m := absf(fm.y) * (MAIN_CE_H * mt.z + BOARD_DEPTH) + absf(fj.y) * (JIB_CE_H + BOARD_DEPTH)
			# Past what the crew can hold, extra side force only heels the boat: count it heavily.
			var score := fm.x + fj.x - maxf(m - hold, 0.0) * 1.5 / (MAIN_CE_H + BOARD_DEPTH)
			# Tiny preference for easing, so a luffing-edge tie goes to the eased setting.
			score += (i + j) * 0.01
			if score > best_score:
				best_score = score
				best = Vector2(i / 20.0, j / 8.0)
	return best


## How fast a hand on the mainsheet moves it (fraction of full travel per second): letting it
## run is quick, pulling it in against the load gets slow in a breeze.
func sheet_rate(easing: bool) -> float:
	if easing:
		return 0.9
	return 0.55 / (1.0 + main_load / 220.0)


## Hike setting that holds about `target_deg` of heel to leeward.
func auto_hike(target_deg := 4.0) -> float:
	var side := -signf(boom) if absf(boom) > 0.02 else signf(awa)
	var target := -side * deg_to_rad(target_deg)
	var need_y := -(heel_ext - mass() * G * _gz(target)) / (crew_mass * G * cos(heel))
	var y := need_y * side
	if y >= 0.35:
		return clampf((y - 0.35) / (HIKE_MAX - 0.35), 0.0, 1.0)
	return clampf(-(0.35 - y) / 0.65, -1.0, 0.0)
