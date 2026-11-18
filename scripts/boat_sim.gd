extends RefCounted
## Snipe dinghy physics: surge, sway, yaw and heel. The main, jib, centreboard and rudder are
## lifting surfaces fed by the local flow; the crew hikes to hold the boat flat.
##
## The sails are a reduced-order shape model (see "Rig and sail shape"). The controls a Snipe
## sailor has (outhaul, cunningham, vang, traveler, mast pusher/puller, jib halyard, jib lead,
## whisker pole, and ashore the spreaders, shrouds, rake and mast) set the mast bend and the
## forestay sag, and with them each sail's depth, draft position and twist. Each sail is worked
## as three horizontal strips, each in the wind at its own height, so twist, the wind gradient
## and the extra loading of a sail's head show up as the top luffing or stalling first.
##
## Sources: numbers marked (guide) are from the North Sails Snipe tuning guide. Everything else
## marked (est) is an estimate for a Snipe, not a measurement.
##
## Body frame: x forward, y to starboard. Positive yaw rate turns the bow to starboard.
## Positive heel puts the starboard rail down. World is Vector2(east, north); heading is a
## compass angle in radians (0 = north, increasing clockwise).

const KN := 0.514444
const G := 9.81
const RHO_W := 1000.0

# Snipe: LOA 4.72 m, beam 1.52 m, minimum hull weight 172 kg (guide: 381 lb), main 8.8 m2 +
# jib 3.0 m2.
const HULL_MASS := 172.0
const RIG_MASS := 25.0
const MAIN_AREA := 8.8
const JIB_AREA := 3.0
const BOOM_LEN := 2.9
const JIB_FOOT := 1.7
const MAST_X := 0.75
const JIB_TACK_X := 2.2
const MAIN_CE_H := 2.75     # only a scale for the heel penalty in best_sheets
const BOARD_X := 0.2
const BOARD_AREA := 0.26
const HULL_KEEL_AREA := 0.07
const BOARD_DEPTH := 0.55
# The Snipe's board is a daggerboard with two places: down (class maximum 851 mm below the keel)
# and raised to its limit band, where 305 mm (12 in) is left below the keel (class drawings:
# the band's top level with the deck; a safety line of at most 610 mm): 0.36 of it.
const BOARD_UP := 0.36
const RUDDER_X := -2.35
const RUDDER_AREA := 0.12
const RUDDER_DEPTH := 0.35
const MAX_RUDDER := 0.63  # 36 degrees
const BOW_X := 2.45
const STERN_X := -2.27
const HALF_BEAM := 0.76
const MAIN_MIN := 0.052
# The boom stops on the leeward shroud: at boom height the shroud is 0.65 m out and 0.18 m aft
# of the mast, which the boom reaches at about 72 degrees.
const MAIN_MAX := 1.25
const MAIN_SHEET_MAX := 1.48   # the sheet's full travel as a boom angle; past the shroud it just goes slack
const JIB_MIN := 0.175
const JIB_MAX := 0.9
const HIKE_MAX := 1.05
const CAPSIZE_HEEL := 1.4   # 80 degrees: the sails are on the water, she's over
# Stability and swamping (estimates for a Snipe, not measured): the hull and rig's righting arm
# grows like GM 0.66 m at small angles, peaks as the leeward rail goes under (about 30 degrees)
# and is gone by 69. Floated heeled at 347 kg (the view's hull lines, still water), the leeward
# rail goes under at about 28 degrees, but the cockpit edge, 0.32 m off the centreline with
# 0.45 m side decks, stays 15-20 cm above the water from 30 to 60 degrees. So what brings water
# in is waves and the bow wave running across the buried side deck: in full chop from about
# 31 degrees, in flat water not until about 50 (est).
const GZ_MAX := 0.22
const GZ_PEAK_HEEL := 0.52
const AVS := 1.2
const FLOOD_HEEL := 0.55       # flooding angle in full chop (31.5 degrees)
const FLOOD_HEEL_FLAT := 0.87  # and in flat water (50 degrees, est)
const FLOOD_RATE := 1.2      # fraction of a full cockpit per second per radian past FLOOD_HEEL
const WATER_KG := 220.0      # water in a swamped cockpit
const BOOM_H := 1.17         # boom height above the waterline
# Crew weight fore and aft. Floated on the view's hull lines at 347 kg the waterplane's
# longitudinal metacentric height is about 12 m, so moving the crew 1 m trims her about 2.1
# degrees. Off the best trim for her speed costs drag; trimmed bow-down the hull grips further
# forward (est).
const TRIM_GML := 12.0         # m (from the hull lines)
const CREW_X_FWD := 0.4        # how far forward of their usual seats the two can sit (est)
const CREW_X_AFT := 0.4        # and aft (est)
const CREW_X_RATE := 0.5       # m/s they shuffle fore and aft (est)
const TRIM_DRAG := 0.03        # extra hull drag per degree squared off the best trim (est)
# Best trim (degrees, + bow down) against boat speed (knots): bow down in light air, which lifts
# the transom clear and cuts wetted area; level around hull speed (about 4.8 kn); stern down
# planing (est).
const TRIM_BEST_KN := [0.0, 2.5, 4.0, 5.0, 6.5, 8.0, 16.0]
const TRIM_BEST_DEG := [0.6, 0.6, 0.25, 0.0, -0.5, -0.8, -0.8]
const TRIM_CLR := 0.2          # m the hull's own lateral area moves forward per degree bow down (est)
# Crew weight in the inertias: the old constants hold with the two sitting out at 0.6 m on their
# usual seats; hiked out or moved fore and aft, the crew's own share changes (est height of
# their weight above the roll axis, which cancels out of the change).
const CREW_REF_Y := 0.6
const CREW_SEAT_X := -0.275    # the two's usual seats, averaged (skipper -0.6, crew 0.05)
const RIGHT_DELAY := 18.0  # the crew swims round, stands on the board and brings her up
const RIGHT_MIN := 8.0

# Lift and drag against angle of attack to the chord (degrees). A cambered soft sail only
# fills once the flow is ~10 degrees past the chord; below that the luff backwinds. These
# stand for a sail of depth D_REF with its draft at DRAFT_REF; the shape model works from there.
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

# --- Rig and sail shape ---------------------------------------------------------------------
# Each sail is three strips: the lower, middle and top third of its luff height. STRIP_S is each
# third's centroid as a fraction of the luff, the _W arrays its share of the area, the _H arrays
# its height above the water (m: main from the boom at 1.2 m to the head at 6.55 m, jib from the
# tack at 0.55 m to the hounds at 5.25 m), MAIN_CHORD its chord (m, with the roach).
const STRIP_S := [0.156, 0.481, 0.778]
const MAIN_W := [0.53, 0.34, 0.13]
const JIB_W := [0.556, 0.333, 0.111]
const MAIN_H := [2.03, 3.77, 5.36]
const JIB_H := [1.28, 2.81, 4.21]
const MAIN_CHORD := [2.57, 1.75, 0.80]
const MAIN_H_REF := 3.05      # lift centroid of the main with every strip equally loaded
const JIB_H_REF := 2.12
const HOUNDS_H := 5.25
const STEP_DEPTH := 0.15      # the mast step under the waterline: the rig rakes about it (est)
const MAST_H := 6.83          # step to masthead (m)
# Our base rake, aft of vertical. The guide gives no rake number, only "set it so the helm is
# neutral with the boat hiked flat"; this is set so she has a light weather helm hiked flat in
# 10 kn (est, calibrated in the sim).
const RAKE_BASE := 0.08
const D_REF := 0.10            # depth the lift/drag tables stand for (est)
const DRAFT_REF := 0.48
const K_I := 0.07              # induced-drag part of the tables, CDi = K_I CL^2 (AR_eff ~4.5, est)
const TIP_LOAD := 0.12         # a triangle loads its head: ~7 degrees of twist evens it out (est)
const K_ENTRY := 0.5           # how much of a flatter entry angle the sail can point higher by (est)
const D_SEP := 0.10            # deeper than this, a section starts to lose flow off the leech, and
const C_SEP := 45.0            # the extra drag is C_SEP times the excess squared (est)
const HOOK_TWIST := 0.16       # rad of main twist below which a light-air leech hooks (est)
const LUFF_ROUND := 2.0        # in of mast bend the main's luff curve is cut for; past it the front
                               # of the sail inverts and wrinkles (overbend, est)
const WIND_REF_H := 2.6        # the wind given to the boat is the wind at this height (est)
# Main depth (fraction of chord) per strip with the outhaul at the band and a straight mast;
# what each inch of outhaul eased adds, and each inch of low or top mast bend takes out (est).
const MAIN_D0 := [0.095, 0.125, 0.115]
const MAIN_OUT_K := [0.009, 0.003, 0.0]
const MAIN_BLOW_K := [0.004, 0.014, 0.004]
const MAIN_BTOP_K := [0.002, 0.014, 0.020]
# Jib depth per strip at 1.2" of forestay sag with the lead at neutral; what each inch of sag
# and each inch of lead forward adds (est).
const JIB_D0 := [0.100, 0.112, 0.105]
const JIB_SAG_K := [0.004, 0.010, 0.008]
const JIB_LEAD_K := [0.006, 0.002, 0.0]

# Ashore settings (start menu).
const SPREADER_LEN_GUIDE := 16.75   # in, side of mast to shroud (guide 16 3/4")
const SPREADER_TIPS_GUIDE := 29.25  # in, tip to tip (guide 29 1/4"; 29 3/4" heavy air = stiffer)
const SHROUD_GUIDE := 70.0          # in aft of the stem, as far forward as they go (guide)
const MAST_NAMES := ["soft", "medium", "stiff"]
const MAST_STIFF := [0.8, 1.0, 1.25]  # fore-and-aft bending stiffness, relative (est)
const RAKE_MAX := 4.0               # in at the masthead either way of the base rake (start menu, est)
var spreader_len := SPREADER_LEN_GUIDE
var spreader_tips := SPREADER_TIPS_GUIDE
var shroud_pos := SHROUD_GUIDE
var rake := 0.0     # in at the masthead, + aft of the base rake
var mast := 1       # 0 soft, 1 medium, 2 stiff

# Afloat controls, in the units the guide uses.
const OUTHAUL_MAX := 4.0       # in eased from the black band (est; the guide eases 2-3" downwind)
const CUNNINGHAM_MAX := 3.0    # in of luff pulled down (est)
const TRAVELER_MAX := 8.0      # in the traveler car drops to leeward (est)
const PULLER_MIN := -0.375     # in at the deck: the aft mark (guide)
const PULLER_MAX := 1.0        # in: the furthest forward mark (guide: 3/8, 3/4 and 1")
const HALYARD_THROW := 11.0    # in of jib halyard throw (guide: 10-12")
const LEAD_MAX := 2.0          # in either way of the neutral jib lead (est)

# Whisker pole, from the mast to the jib clew, holding the jib out wing and wing. Its length is
# an estimate (about the jib foot); with it the jib sits POLE_ANG off the centreline.
const POLE_LEN := 1.75
const POLE_ANG := 1.168        # rad, from the tack-mast-clew triangle with POLE_LEN
const POLE_SET_S := 1.5        # seconds to set it: a Snipe's pole is on a launcher line (est)
const POLE_STOW_S := 1.2       # to stow it (est)
const POLE_SWAP_S := 3.0       # to swap it to the other side through a gybe (est)
const POLE_MIN_TWA := 1.92     # 110 degrees true: any closer to the wind and the crew won't set it (est)
const POLE_ON_TWA := 2.76      # the crew sets it past 158 degrees true, where the sim says it pays
const POLE_OFF_TWA := 2.62     # and stows it inside 150
const POLE_ON_CLEW := 0.6      # pole_out from which its tip is on the jib's clew and holds it
const POLE_OFF_HOLD := 3.0     # s inside POLE_OFF_TWA before the crew stows it (a luff isn't a new course)
enum { POLE_STOWED, POLE_SETTING, POLE_SET, POLE_STOWING, POLE_SWAPPING }

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
var crew_x := 0.0      # the two's weight forward (+) or aft of their usual seats, m
var crew_y_rate := 0.0
var capsized := false
var capsize_side := 1.0
var capsize_t := 0.0
var aground := false

# Controls
var tiller := 0.0      # -1..1, positive turns to starboard
var main_sheet := 0.5  # 0 = sheeted hard, 1 = fully eased
var jib_sheet := 0.5
var hike := 0.5        # -1 crew to leeward, 0 sitting on the windward rail, 1 full hike
var trim_auto := true  # the crew sits fore and aft for the best trim; false: at trim_x
var trim_x := 0.0      # m forward of their usual seats, when not trim_auto
var board := 1.0       # 1 down, 0 up, anything between
var vang := 0.3        # 0 slack .. 1 hard on
var outhaul := 0.0     # in eased from the band
var cunningham := 0.0  # in on
var traveler := 0.0    # in down to leeward (0 = centred, the bridle just inside the boom)
var puller := 0.0      # in at the deck, + forward of neutral
var halyard := 1.0     # in eased from full tension
var jib_lead := 0.0    # in, + forward
var pole_state := POLE_STOWED
var pole_side := 1.0   # side the pole holds the clew out, +1 starboard
var pole_t := 0.0
var pole_out := 0.0    # 0 stowed .. 1 out; on the clew from POLE_ON_CLEW
var _pole_low_t := 0.0
var chop := 0.0        # 0 flat water .. 1 full-fetch chop (set by the fleet from the fetch)
var water_in := 0.0    # water left in the boat after a capsize, 0..1

# Telemetry (updated each step)
var tws := 0.0
var tw_from := 0.0      # degrees
var twa := 0.0          # signed radians, + = wind over the starboard side
var aws := 0.0
var awa := 0.0          # signed radians, + = from starboard
var main_alpha := 0.0   # effective angle of attack of the middle third
var jib_alpha := 0.0
var main_alphas := PackedFloat32Array([0.0, 0.0, 0.0])  # lower, middle, top third
var jib_alphas := PackedFloat32Array([0.0, 0.0, 0.0])
var drive := 0.0
var heel_ext := 0.0     # heeling moment from sails and foils last step (N m)
var main_load := 0.0    # force in the mainsail (N), which is what you pull against on the sheet
var jib_load := 0.0
var boom_dip := 0.0     # how far the boom end is under water (m)
var rudder_load := 0.0  # side force on the rudder (N), what the helm feels through the tiller
var just_capsized := false
# Shape telemetry, what a sailor sees looking up.
var bend_low := 0.0     # in of mast bend from pushing it forward at the deck and the vang
var bend_top := 0.0     # in from leech tension
var mast_bend := 0.0    # in, mid-height bow (bend_low + bend_top)
var mast_side := 0.0    # in, middle of the mast to leeward (+) or windward (-)
var stay_sag := 1.2     # in, forestay and jib luff sag
var rake_eff := 0.0     # in, rake as set plus the mast going forward on a slack rig
var leech_hold := 1.0   # 0 free .. 1 the mainsheet or vang holding the leech down
var main_twist := 0.0   # rad, how much further out the main's head chord is than the boom
var jib_twist := 0.0
var main_depth := PackedFloat32Array([0.1, 0.12, 0.11])
var jib_depth := PackedFloat32Array([0.1, 0.11, 0.1])
var main_draft := DRAFT_REF
var jib_draft := 0.42
var main_ce_h := 0.0    # height of the main's centre of effort (m)

var jib_backed := false
var _grad_p := 0.12
var _side_force := 0.0
var _flow_m: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _flow_j: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _cl := PackedFloat32Array([0.0, 0.0, 0.0])
var _cd := PackedFloat32Array([0.0, 0.0, 0.0])
var _q := PackedFloat32Array([0.0, 0.0, 0.0])
var _att := PackedFloat32Array([0.0, 0.0, 0.0])
var _sa := PackedFloat32Array([0.0, 0.0, 0.0])
# Results of _sail(): force on the boat (body frame), heeling moment about the waterline,
# yaw moment about the centre of gravity, height of the centre of effort.
var _sf := Vector2.ZERO
var _sheel := 0.0
var _syaw := 0.0
var _sh := 0.0


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
	pole_state = POLE_STOWED
	pole_out = 0.0
	crew_y_rate = 0.0
	crew_x = auto_trim() if trim_auto else trim_x


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
	_step_pole(dt)
	_update_booms(dt)
	_update_rig(dt)
	_prepare_sails()
	main_twist = _main_twist(main_sheet)
	_sail(true, boom, main_twist, main_depth, main_draft, MAIN_AREA)
	var fm := _sf
	var fm_heel := _sheel
	var fm_yaw := _syaw
	main_ce_h = _sh
	main_alphas = _sa.duplicate()
	main_alpha = main_alphas[1]
	main_load = fm.length()
	var jk := _jib_work() * 0.95
	jib_twist = _jib_twist(jib_sheet)
	_sail(false, jib, jib_twist, jib_depth, jib_draft, JIB_AREA * _jib_area(jib))
	var fj := _sf * jk
	var fj_heel := _sheel * jk
	var fj_yaw := _syaw * jk
	jib_alphas = _sa.duplicate()
	jib_alpha = jib_alphas[1]
	jib_load = fj.length()
	_side_force = absf(fm.y + fj.y)
	var ch := cos(heel)
	drive = fm.x + fj.x

	# Windage of hull, rig and crew, acting ahead of the board so a stalled boat falls off.
	var fw := va * (0.5 * rho_air * 0.9 * 1.0 * aws)
	var fw_b := Vector2(fw.dot(f), fw.dot(s))
	var pw := Vector2(0.9, 0.0)

	# --- Foils -----------------------------------------------------------------------
	# A daggerboard lifts straight up. Its after edge is vertical and its forward edge raked, so the
	# part left in the water when it is raised is narrower and centred about 9 cm further aft.
	var bd := clampf(board, 0.0, 1.0)
	var board_area := BOARD_AREA * bd + HULL_KEEL_AREA
	var board_x := BOARD_X - 0.14 * (1.0 - bd)
	var flow_b := -Vector2(u, v + r * board_x)
	var fb := _surface(flow_b, PI, board_area, RHO_W, FOIL_A, FOIL_CL, FOIL_CD)
	fb.y *= ch
	var delta := clampf(tiller, -1.0, 1.0) * MAX_RUDDER
	# Sailing forward, the rudder works in the board's downwash, which takes out part of the
	# leeway it sees (est). Not when she's stopped, going astern or sliding sideways.
	var wash := 0.45 * bd * smoothstep(0.3, 1.2, u) * (1.0 - smoothstep(0.25, 0.6, absf(atan2(v, maxf(u, 0.01)))))
	var flow_r := -Vector2(u, v * (1.0 - wash) + r * RUDDER_X)
	var fr := _surface(flow_r, PI - delta, RUDDER_AREA, RHO_W, FOIL_A, FOIL_CL, FOIL_CD)
	fr.y *= ch
	rudder_load = absf(fr.y)

	# --- Hull ------------------------------------------------------------------------
	var res := _interp(RES_KN, RES_N, absf(u) / KN) * (1.0 + 0.8 * sin(heel) * sin(heel)) * (1.0 + 0.6 * water_in)
	# The crew sit fore and aft for the trim they want; off the best trim costs drag.
	crew_x = move_toward(crew_x, auto_trim() if trim_auto else clampf(trim_x, -CREW_X_AFT, CREW_X_FWD), CREW_X_RATE * dt)
	var trim_deg := rad_to_deg(trim())
	var trim_off := trim_deg - _interp(TRIM_BEST_KN, TRIM_BEST_DEG, absf(u) / KN)
	res *= 1.0 + TRIM_DRAG * trim_off * trim_off
	# Punching into chop upwind costs speed.
	res += 0.48 * tws * tws * chop * maxf(cos(twa), 0.0) * clampf(u / 2.0, 0.0, 1.0)
	# Bailers drain her as she moves; past the flooding angle water comes over the side deck.
	# Waves bring it in sooner: the angle falls from FLOOD_HEEL_FLAT in flat water to FLOOD_HEEL
	# in full chop.
	water_in = maxf(water_in - dt * (0.01 + 0.025 * maxf(u, 0.0)), 0.0)
	var flood := lerpf(FLOOD_HEEL_FLAT, FLOOD_HEEL, clampf(chop, 0.0, 1.0))
	if absf(heel) > flood:
		water_in = minf(water_in + dt * FLOOD_RATE * (absf(heel) - flood), 1.0)
	if u < 0.0:
		res *= 2.0
	var x_hull := -signf(u) * res
	var y_hull := -0.5 * RHO_W * 0.3 * 1.0 * v * absf(v)
	var n_hull := -110.0 * r * (absf(u) + 0.2) - 450.0 * r * absf(r)
	# A heeled hull wants to turn away from the side that is down (weather helm).
	n_hull += -70.0 * heel * u * absf(u)

	# Boom in the water: heeled toward the boom far enough, its end digs in and drags.
	var yb := BOOM_LEN * sin(boom)
	boom_dip = maxf(yb * sin(heel) - BOOM_H * cos(heel), 0.0)
	var f_dip := Vector2.ZERO
	var p_dip := Vector2(MAST_X - BOOM_LEN * cos(boom), yb)
	if boom_dip > 0.0:
		f_dip = Vector2(-signf(u) * 400.0 * minf(boom_dip, 0.5) * (u * u + 1.0), 0.0)

	var fx := fm.x + fj.x + fw_b.x + fb.x + fr.x + x_hull + f_dip.x
	var fy := (fm.y + fj.y) * ch + fw_b.y + fb.y + fr.y + y_hull
	# Trimmed bow down the hull's own share of the lateral area grips further forward.
	var clr_x := board_x + TRIM_CLR * trim_deg * HULL_KEEL_AREA / board_area
	var n := fm_yaw + fj_yaw + _cross(pw, fw_b) \
		+ _cross(Vector2(clr_x, 0.0), fb) + _cross(Vector2(RUDDER_X, 0.0), fr) + n_hull + _cross(p_dip, f_dip)

	# --- Heel ------------------------------------------------------------------------
	heel_ext = fm_heel + fj_heel + fw_b.y * 1.2 - fb.y * BOARD_DEPTH * (0.45 + 0.55 * bd) - fr.y * RUDDER_DEPTH
	var side := -signf(boom) if absf(boom) > 0.02 else signf(awa)
	var target_y := 0.0
	if hike >= 0.0:
		target_y = side * lerpf(0.35, HIKE_MAX, clampf(hike, 0.0, 1.0))
	else:
		target_y = side * lerpf(0.35, -0.3, clampf(-hike, 0.0, 1.0))
	var cy0 := crew_y
	crew_y = move_toward(crew_y, target_y, 1.4 * dt)
	crew_y_rate = (crew_y - cy0) / dt if dt > 0.0 else 0.0
	var m_crew := crew_mass * G * crew_y * cos(heel)
	var m_form := -mass() * G * _gz(heel)
	# Water in the cockpit runs to the low side and holds her down.
	var m_water := signf(heel) * water_in * WATER_KG * G * 0.3 * clampf(absf(heel) / 0.35, 0.0, 1.0)
	var m_damp := -700.0 * heel_rate - 500.0 * heel_rate * absf(heel_rate)
	# Roll inertia: the old 480 with the two sitting out at CREW_REF_Y; hiked further out it grows
	# with the square of their distance, and as they move out it slows the roll (angular momentum).
	var ix := 480.0 + crew_mass * (crew_y * crew_y - CREW_REF_Y * CREW_REF_Y)
	var ix_rate := 2.0 * crew_mass * crew_y * crew_y_rate

	# --- Integrate -------------------------------------------------------------------
	var m := mass() + water_in * WATER_KG
	var mx := m * 1.08
	var my := m * 1.6
	# Yaw inertia likewise counts the crew's distance out and fore and aft of the centre.
	var xc := CREW_SEAT_X + crew_x
	var iz := m * 1.35 + crew_mass * (crew_y * crew_y - CREW_REF_Y * CREW_REF_Y + xc * xc - CREW_SEAT_X * CREW_SEAT_X)
	u += (fx + my * v * r) / mx * dt
	v += (fy - mx * u * r) / my * dt
	r += n / iz * dt
	# A boom in the water resists her coming back up.
	m_damp -= 3000.0 * minf(boom_dip, 0.3) * heel_rate
	heel_rate += (heel_ext + m_crew + m_form + m_water + m_damp - ix_rate * heel_rate) / ix * dt
	heel += heel_rate * dt
	u = clampf(u, -4.0, 12.0)
	heading = fposmod(heading + r * dt, TAU)
	pos += (fwd() * u + stb() * v) * dt

	if absf(heel) > CAPSIZE_HEEL:
		capsized = true
		just_capsized = true
		capsize_side = signf(heel)
		capsize_t = 0.0
		pole_state = POLE_STOWED
		pole_out = 0.0


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
	main_alphas.fill(0.0)
	jib_alphas.fill(0.0)
	drive = 0.0
	main_load = 0.0
	jib_load = 0.0
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
	var lim := minf(lerpf(MAIN_MIN, MAIN_SHEET_MAX, clampf(main_sheet, 0.0, 1.0)), MAIN_MAX)
	var want := side * (minf(lim, absf(awa)) if side == -signf(awa) else lim)
	var rate := 5.0 if signf(want) != signf(boom) and absf(boom) > 0.3 else 2.5
	boom = move_toward(boom, want, rate * dt)

	# On the pole the clew is held out where the pole puts it; easing the sheet lets the pole
	# swing forward.
	jib_backed = false
	# The launcher line pulls the clew across to the pole as it goes out, so the jib starts over
	# as soon as the crew sets it, and stays held until the pole is nearly off again.
	if pole_state == POLE_SET or pole_state == POLE_SETTING or (pole_state == POLE_SWAPPING and pole_out > 0.0) 			or (pole_state == POLE_STOWING and pole_out > POLE_ON_CLEW):
		jib = move_toward(jib, pole_side * (POLE_ANG - 0.45 * clampf(jib_sheet, 0.0, 1.0)), 3.5 * dt)
		return
	# In irons the crew backs the jib (holds the clew out to windward, which pulls it flat) to
	# push the bow off, until she has fallen off to a close reach or has way on. The angle and
	# when they let go are estimates, set so she falls out of irons as the tests expect.
	jib_backed = absf(awa) < 0.8 and u < 0.5 and absf(awa) > 0.02
	if jib_backed:
		# Backed on the side the wind comes from, it pushes her off on the tack she's on; when
		# the helm is turning her, the crew backs it to help the turn (through a tack, say).
		var bs := signf(awa)
		if absf(tiller) > 0.3:
			bs = -signf(tiller)
		jib = move_toward(jib, bs * 0.35, 3.0 * dt)
		return
	var jside := signf(jib) if absf(jib) > 0.001 else -signf(awa)
	if signf(awa) == jside and absf(awa) < 2.95:
		jside = -jside
	var jlim := lerpf(JIB_MIN, JIB_MAX, clampf(jib_sheet, 0.0, 1.0))
	var jwant := jside * (minf(jlim, absf(awa)) if jside == -signf(awa) else jlim)
	jib = move_toward(jib, jwant, 4.0 * dt)


# --- Rig and sail shape ------------------------------------------------------------------

## Fore-and-aft stiffness of the mast as rigged: the mast itself, the spreaders (more tip to tip
## is stiffer, guide) and the shrouds (further aft is stiffer, guide). The sizes are estimates.
func mast_stiffness() -> float:
	return float(MAST_STIFF[clampi(mast, 0, 2)]) * (1.0 + 0.2 * (spreader_tips - SPREADER_TIPS_GUIDE)) * (1.0 + 0.06 * (shroud_pos - SHROUD_GUIDE))


## Mast bend, sideways bend, forestay sag and rake from the controls and the loads of the last
## step, then the depth and draft of both sails.
## Mast bend (in, mid-height bow, est): pushing the mast forward at the deck bends it low (guide:
## light air, mast forward, "bends mast, opens main leech, sags jib luff"); the vang bends it low
## too, unless the puller holds it back at the deck (guide: in a breeze pull it to the aft mark);
## leech tension from the sheet bends the top. A stiffer rig bends less.
## Forestay sag (in, est): grows with the jib's load against the rig tension the halyard sets,
## with the halyard right off (guide: off fully dead downwind), and with mast bend.
func _update_rig(dt: float) -> void:
	var ln := minf(main_load / 300.0, 2.5)
	var stiff := mast_stiffness()
	var restrain := clampf(0.55 + 0.45 * puller, 0.25, 1.0)
	leech_hold = _leech_hold(main_sheet)
	var bl := clampf(0.9 * puller, -0.4, 1.0) + clampf(vang, 0.0, 1.0) * (0.3 + ln) * 1.1 * restrain / stiff
	var bt := (0.5 + 0.7 * leech_hold) * ln * 1.2 / stiff
	var k := clampf(dt / 0.25, 0.0, 1.0)
	bend_low = lerpf(bend_low, bl, k)
	bend_top = lerpf(bend_top, bt, k)
	mast_bend = bend_low + bend_top
	# Sideways: longer spreaders push the middle of the mast to leeward under load, shorter ones
	# let it go to windward (guide); at the guide's 16 3/4" this mast stands straight (est).
	mast_side = 1.2 * (spreader_len - SPREADER_LEN_GUIDE) * minf(_side_force / 350.0, 2.0)
	var e := clampf(halyard / HALYARD_THROW, 0.0, 1.0)
	var jn := minf(jib_load / 120.0, 2.5)
	stay_sag = 0.4 + (0.6 + 1.8 * jn) * (0.3 + 0.7 * e) + 2.5 * e * e \
		+ 0.9 * maxf(bend_low, 0.0) + 0.15 * bend_top + 0.25 * maxf(mast_side, 0.0)
	# A slack rig lets the mast go forward until the shrouds stop it: ~6" at the head (est).
	rake_eff = rake - 6.0 * e
	_main_shape(ln)
	_jib_shape(jn)


## Main depth per strip and draft position. Outhaul eased deepens the foot; mast bend takes the
## luff curve out of the middle and top; the cunningham pulls the draft forward and flattens a
## little (guide); load stretches the cloth, deepening the sail and moving the draft aft.
func _main_shape(ln: float) -> void:
	var cun := clampf(cunningham / CUNNINGHAM_MAX, 0.0, 1.0)
	var lw := minf(ln, 2.0)
	main_draft = clampf(0.44 + 0.03 * lw - 0.08 * cun + 0.012 * maxf(mast_bend, 0.0), 0.32, 0.6)
	for i in 3:
		main_depth[i] = clampf(float(MAIN_D0[i]) + float(MAIN_OUT_K[i]) * outhaul + 0.004 * lw
			- float(MAIN_BLOW_K[i]) * bend_low - float(MAIN_BTOP_K[i]) * bend_top - 0.006 * cun, 0.035, 0.2)


## Jib depth per strip and draft position: forestay sag makes it fuller; the lead forward
## deepens the foot; a few inches of halyard off puts wrinkles in the luff and lets the draft
## go aft.
func _jib_shape(jn: float) -> void:
	var wr := clampf(halyard / 3.0, 0.0, 1.0)
	jib_draft = clampf(0.40 + 0.06 * wr + 0.03 * minf(jn, 2.0), 0.3, 0.6)
	for i in 3:
		jib_depth[i] = clampf(float(JIB_D0[i]) + float(JIB_SAG_K[i]) * (stay_sag - 1.2) + float(JIB_LEAD_K[i]) * jib_lead, 0.04, 0.2)


## How hard the leech is held down, 0..1. The mainsheet pulls down while the boom is over the
## traveler car and mostly in once it is out past it; the vang holds it whatever the sheet does
## (guide: vang on so a puff can be eased without losing leech tension).
func _leech_hold(sheet: float) -> float:
	var lim := lerpf(MAIN_MIN, MAIN_SHEET_MAX, clampf(sheet, 0.0, 1.0))
	var car := 0.05 + 0.24 * clampf(traveler / TRAVELER_MAX, 0.0, 1.0)
	var by_sheet := 1.0 - smoothstep(car, car + 0.32, lim)
	return 1.0 - (1.0 - by_sheet) * (1.0 - clampf(vang, 0.0, 1.0))


## Main twist (rad, head chord beyond the boom) for a mainsheet setting: a free leech falls
## open; top mast bend and the cunningham open it (guide); a mast sagging to leeward opens it.
func _main_twist(sheet: float) -> float:
	var hold := _leech_hold(sheet)
	return maxf(0.04 + 0.40 * (1.0 - hold) + 0.04 * bend_top + 0.05 * maxf(bend_low, 0.0)
		+ 0.04 * clampf(cunningham / CUNNINGHAM_MAX, 0.0, 1.0) * minf(main_load / 300.0, 1.0) + 0.02 * mast_side, 0.0)


## Jib twist for a jib sheet setting: easing the sheet lets the clew rise and the leech open;
## the lead forward closes it, aft opens it (guide: top luffs first, move the lead forward); a
## tight halyard opens it (guide: very heavy air, tighten the luff smooth to open the leech).
func _jib_twist(sheet: float) -> float:
	if pole_state == POLE_SET:
		return 0.06
	if jib_backed:
		return 0.0
	var wr := clampf(halyard / 3.0, 0.0, 1.0)
	return maxf(0.10 + 0.30 * clampf(sheet, 0.0, 1.0) - 0.035 * jib_lead + 0.04 * (1.0 - wr), 0.0)


## Apparent wind at each strip's height. The true wind grows with height over the water (a power
## law, steeper in light air: est), so the apparent wind is freer aloft.
func _prepare_sails() -> void:
	_grad_p = lerpf(0.16, 0.10, smoothstep(2.0, 7.0, tws))
	for i in 3:
		_flow_m[i] = _flow_at(MAIN_H[i])
		_flow_j[i] = _flow_at(JIB_H[i])


func _flow_at(h: float) -> Vector2:
	var g := pow(h / WIND_REF_H, _grad_p)
	var ax := -tws * g * cos(twa) - u
	var ay := -tws * g * sin(twa) - v
	return Vector2(ax, ay * cos(heel))


## One sail from its three strips: fills _sf, _sheel, _syaw, _sh and _sa (each strip's
## effective angle of attack). foot: chord angle of the lowest strip (the boom or jib angle);
## twist: how much further out the head's chord is; depth per strip; draft position.
## Shape sets the aerodynamics (est): a flatter entry fills at a lower angle (it can point
## higher); depth scales lift; depth and a draft aft of half way add profile drag; induced drag
## grows as the lift centroid comes down (shorter effective span); a deep or closed leech loses
## its flow early in light air.
func _sail(is_main: bool, foot: float, twist: float, depth: PackedFloat32Array, draft: float, area: float, with_yaw := true) -> void:
	_sf = Vector2.ZERO
	_sheel = 0.0
	_syaw = 0.0
	_sh = MAIN_H_REF if is_main else JIB_H_REF
	_sa.fill(0.0)
	if area <= 0.0:
		return
	var w: Array = MAIN_W if is_main else JIB_W
	var hs: Array = MAIN_H if is_main else JIB_H
	var flows: Array[Vector2] = _flow_m if is_main else _flow_j
	var side := signf(foot) if absf(foot) > 0.001 else -signf(awa)
	var light := clampf((6.0 - aws) / 4.0, 0.0, 1.0)
	var entry_ref := atan(2.0 * D_REF / DRAFT_REF)
	var exit_ref := atan(2.0 * D_REF / (1.0 - DRAFT_REF))
	var sum_wq := 0.0
	var sum_cl := 0.0
	var sum_l := 0.0
	var sum_lh := 0.0
	for i in 3:
		var fl: Vector2 = flows[i]
		var sp2 := fl.length_squared()
		_q[i] = 0.5 * rho_air * sp2
		_cl[i] = 0.0
		_cd[i] = 0.0
		_att[i] = 1.0
		if sp2 < 1e-6:
			continue
		var s: float = STRIP_S[i]
		var b := foot + side * twist * s
		var a := wrapf(fl.angle() - (PI - b), -PI, PI)
		var d: float = depth[i]
		var ad := rad_to_deg(absf(a))
		var shift := rad_to_deg(K_ENTRY * (entry_ref - atan(2.0 * d / draft)) + TIP_LOAD * (s - 0.35))
		# (Only for a sail that is drawing: a luffing one gets no lift from its shape.)
		var ae := maxf(ad + shift * smoothstep(2.0, 10.0, ad) * (1.0 - smoothstep(30.0, 60.0, ad)), 0.0)
		_sa[i] = deg_to_rad(ae) * (1.0 if a >= 0.0 else -1.0)
		var cl := _deg_lut(_sail_cl, ae)
		var cd0 := _deg_lut(_sail_cd, ae) - K_I * cl * cl
		var att := 1.0 - smoothstep(22.0, 45.0, ae)
		_att[i] = att
		# Depth buys lift, but less so in light air, where a deep section can't keep its flow.
		# Draft aft loads the back of the sail: more lift at the same angle.
		cl *= pow(d / D_REF, lerpf(0.25, lerpf(0.45, 0.12, light), att)) * (1.0 + 0.6 * att * (draft - 0.45))
		cd0 *= 1.0 + att * 2.5 * (d - D_REF) + (1.0 - att) * 3.0 * (d - D_REF)
		# A deep section, or one with its draft well aft, loses the flow off its leech.
		cd0 += att * (C_SEP * pow(maxf(d - D_SEP, 0.0), 2.0) + 0.3 * maxf(draft - 0.48, 0.0))
		# Light air: the flow leaves a deep, closed or draft-aft leech early (low Reynolds number).
		cd0 += 0.12 * light * smoothstep(15.0, 27.0, ae + 0.5 * rad_to_deg(atan(2.0 * d / (1.0 - draft)) - exit_ref)) 			* (d / D_REF) * (d / D_REF) * (1.0 + 3.0 * maxf(draft - 0.45, 0.0))
		# Light air: with no load to open it, a leech twisted less than ~8 degrees hooks and the
		# flow leaves the upper main (guide: open the leech in light air).
		if is_main and i > 0:
			cd0 += 1.5 * light * maxf(HOOK_TWIST - twist, 0.0) * (1.0 if i == 2 else 0.6)
		# Mast bent past the luff curve: the front of the main inverts (lower two thirds).
		if is_main and i < 2:
			cd0 += 0.04 * maxf(bend_low + 0.6 * bend_top - LUFF_ROUND, 0.0)
		# Near the luffing point the front of the sail bubbles and flogs: easing to depower or
		# pinching both cost drag, which is why real crews flatten the sail instead.
		cd0 += 0.12 * (1.0 - smoothstep(4.0, 15.0, ae))
		_cl[i] = cl * (1.0 if a >= 0.0 else -1.0)
		_cd[i] = cd0
		var wq: float = float(w[i]) * _q[i]
		sum_wq += wq
		sum_cl += wq * _cl[i]
		sum_l += wq * absf(cl)
		sum_lh += wq * absf(cl) * float(hs[i])
	if sum_wq <= 0.0:
		return
	var cl_sail := sum_cl / sum_wq
	var h_ref := MAIN_H_REF if is_main else JIB_H_REF
	var hc := sum_lh / sum_l if sum_l > 1e-6 else h_ref
	var ki := K_I * clampf((h_ref / hc) * (h_ref / hc), 0.7, 1.6)
	var rk := tan(RAKE_BASE + rake_eff * 0.0254 / MAST_H)
	var x_head := MAST_X - (HOUNDS_H + STEP_DEPTH) * rk
	var sh := sin(heel)
	var chl := cos(heel)
	var fy_h := 0.0
	var fy_sum := 0.0
	for i in 3:
		if _q[i] <= 0.0:
			continue
		var dn: Vector2 = flows[i].normalized()
		var lift_dir := Vector2(-dn.y, dn.x)
		var cd := _cd[i] + ki * absf(_cl[i] * cl_sail)
		var fi := (lift_dir * _cl[i] + dn * cd) * (_q[i] * area * float(w[i]))
		_sf += fi
		var h: float = hs[i]
		_sheel += fi.y * h
		fy_h += absf(fi.y) * h
		fy_sum += absf(fi.y)
		if not with_yaw:
			continue
		var s: float = STRIP_S[i]
		var b := foot + side * twist * s
		var cdir := Vector2(-cos(b), sin(b))
		var cp := lerpf(0.5, 0.25 + 0.4 * draft, _att[i])
		var p: Vector2
		if is_main:
			p = Vector2(MAST_X - (h + STEP_DEPTH) * rk, 0.0) + cdir * (cp * float(MAIN_CHORD[i]))
		else:
			p = Vector2(lerpf(JIB_TACK_X, x_head, s), 0.0) + cdir * (cp * JIB_FOOT * (1.0 - s))
		p.y += h * sh
		_syaw += _cross(p, Vector2(fi.x, fi.y * chl))
	if fy_sum > 1e-6:
		_sh = fy_h / fy_sum


## Jib area factor: behind the main on a run it is blanketed, unless the pole holds it out on the
## other side. With the halyard off the luff goes forward and out and the jib projects (est).
func _jib_area(jangle: float) -> float:
	var e := clampf(halyard / HALYARD_THROW, 0.0, 1.0)
	var k := 1.0 + 0.06 * e * smoothstep(2.0, 2.6, absf(awa))
	if pole_state == POLE_SET and absf(boom) > 0.02 and signf(jangle) != signf(boom):
		return k
	return k * (1.0 - 0.5 * smoothstep(1.9, 2.75, absf(awa)) * (1.0 - 0.3 * e))


## While the crew is setting, stowing or swapping the pole the jib is half let go.
func _jib_work() -> float:
	match pole_state:
		POLE_SETTING, POLE_STOWING:
			return 0.5
		POLE_SWAPPING:
			return 0.3
	return 1.0


## Telltale angle (effective angle of attack) at height fraction v of a sail, between strips.
func alpha_at(is_main: bool, v_frac: float) -> float:
	var a: PackedFloat32Array = main_alphas if is_main else jib_alphas
	if v_frac <= STRIP_S[1]:
		return lerpf(a[0], a[1], clampf((v_frac - STRIP_S[0]) / (STRIP_S[1] - STRIP_S[0]), 0.0, 1.0))
	return lerpf(a[1], a[2], clampf((v_frac - STRIP_S[1]) / (STRIP_S[2] - STRIP_S[1]), 0.0, 1.0))


## For the replay: shape telemetry from recorded controls and wind, without stepping physics.
func view_shape(main_twist_rad: float, bend: float, sag: float) -> void:
	var q := 0.5 * rho_air * aws * aws
	main_load = q * MAIN_AREA * 0.9
	jib_load = q * JIB_AREA * 0.8
	bend_low = 0.4 * bend
	bend_top = 0.6 * bend
	mast_bend = bend
	stay_sag = sag
	main_twist = main_twist_rad
	jib_twist = _jib_twist(jib_sheet)
	_main_shape(minf(main_load / 300.0, 2.5))
	_jib_shape(minf(jib_load / 120.0, 2.5))


# --- Whisker pole ---------------------------------------------------------------------------

func _step_pole(dt: float) -> void:
	_pole_low_t = _pole_low_t + dt if absf(twa) < POLE_OFF_TWA else 0.0
	match pole_state:
		POLE_SETTING:
			pole_t += dt
			pole_out = clampf(pole_t / POLE_SET_S, 0.0, 1.0)
			if pole_t >= POLE_SET_S:
				pole_state = POLE_SET
				pole_out = 1.0
		POLE_STOWING:
			pole_t += dt
			pole_out = 1.0 - clampf(pole_t / POLE_STOW_S, 0.0, 1.0)
			if pole_t >= POLE_STOW_S:
				pole_state = POLE_STOWED
				pole_out = 0.0
		POLE_SWAPPING:
			# Off the old clew and the mast, across, and out on the new side.
			pole_t += dt
			pole_out = clampf((pole_t - 0.4 * POLE_SWAP_S) / (0.6 * POLE_SWAP_S), 0.0, 1.0)
			if pole_t >= POLE_SWAP_S:
				pole_state = POLE_SET
				pole_out = 1.0


## Side the pole goes for wing and wing: away from the boom.
func _wing_side() -> float:
	if absf(boom) > 0.02:
		return -signf(boom)
	return 1.0 if awa >= 0.0 else -1.0


func can_set_pole() -> bool:
	return not capsized and absf(twa) >= POLE_MIN_TWA


func pole_busy() -> bool:
	return pole_state == POLE_SETTING or pole_state == POLE_STOWING or pole_state == POLE_SWAPPING


## True when the pole is out on the same side as the boom, as it is after a gybe until the crew
## swaps it.
func pole_wrong_side() -> bool:
	return pole_state == POLE_SET and absf(boom) > 0.3 and signf(boom) == pole_side


func pole_set() -> bool:
	if pole_state != POLE_STOWED or not can_set_pole():
		return false
	pole_state = POLE_SETTING
	pole_t = 0.0
	pole_side = _wing_side()
	return true


func pole_stow() -> bool:
	if pole_state == POLE_STOWED or pole_state == POLE_STOWING:
		return false
	pole_t = (1.0 - pole_out) * POLE_STOW_S
	pole_state = POLE_STOWING
	return true


func pole_swap() -> bool:
	if pole_state != POLE_SET:
		return false
	pole_state = POLE_SWAPPING
	pole_t = 0.0
	pole_side = -pole_side
	return true


## The crew's pole handling, used by the crew assist and the AI: set it on a run or a broad
## reach, swap it after a gybe, stow it before heading up. stow: the helm wants it down now
## (a leeward mark coming).
func crew_pole(stow := false) -> void:
	var at := absf(twa)
	match pole_state:
		POLE_STOWED:
			if not stow and at > POLE_ON_TWA and aws > 0.5:
				pole_set()
		POLE_SETTING, POLE_SET:
			# Down for a mark, when she has been up on a reach for a few seconds, or at once if
			# she is brought right up.
			if stow or _pole_low_t > POLE_OFF_HOLD or at < POLE_MIN_TWA + 0.17:
				pole_stow()
			elif pole_wrong_side():
				pole_swap()


# --- Crew settings ----------------------------------------------------------------------------

## Every control set as the guide says for this wind and point of sail (the AI and the crew
## assist). keep: controls the player has taken over, which are left alone.
## Upwind (guide): outhaul tight except the very lightest air; cunningham loose until overpowered;
## vang slack until hiking hard, then the slack out, then harder as the breeze builds; traveler
## centred, dropped a little in heavy air; mast pushed forward with the crew inside in light air,
## neutral with the crew to windward, pulled back as it builds, soft masts to the aft mark in
## 15+ and stiff ones forward to neutral; jib luff with very slight wrinkles, tightened smooth in
## very heavy air; jib lead so the luff telltales break evenly.
## Off the wind (guide): outhaul eased 2-3"; cunningham off; vang so the top batten is parallel
## to the boom, looser in light air and firmer in heavy air; jib halyard 1/3 to 1/2 on reaching
## with the pole, off fully dead downwind. The board comes up part way (est).
## The crew blends from the upwind to the reaching tune as she cracks off between 55 and 75
## degrees true, and on to the running tune between 120 and 160, rather than switching.
func auto_rig(keep := {}) -> void:
	var kn := tws / KN
	var at := absf(twa)
	var w := smoothstep(0.96, 1.31, at)
	var run := smoothstep(2.09, 2.79, at)
	var up_out := 1.0 - smoothstep(4.5, 7.0, kn)
	var up_cun := CUNNINGHAM_MAX * smoothstep(11.5, 18.0, kn)
	var up_vang := 0.4 * smoothstep(8.5, 12.0, kn) + 0.2 * smoothstep(12.0, 17.0, kn)
	var up_trav := TRAVELER_MAX * 0.35 * smoothstep(15.0, 20.0, kn)
	var heavy_push: float = [-0.375, -0.19, 0.19][clampi(mast, 0, 2)]
	var up_push := lerpf(0.75, 0.0, smoothstep(6.0, 9.0, kn))
	up_push = lerpf(up_push, -0.19, smoothstep(10.0, 14.0, kn))
	up_push = lerpf(up_push, heavy_push, smoothstep(14.0, 16.0, kn))
	var up_hal := lerpf(2.0, 1.0, smoothstep(5.0, 10.0, kn))
	up_hal = lerpf(up_hal, 0.0, smoothstep(14.0, 19.0, kn))
	var off_out := lerpf(2.0, 2.5, run)
	var off_vang := lerpf(0.35, 0.75, smoothstep(7.0, 16.0, kn))
	var pole_hal := HALYARD_THROW * lerpf(0.6, 1.0, smoothstep(2.62, 3.0, at))
	var off_hal := lerpf(3.0, pole_hal, run)
	if not keep.has("outhaul"):
		outhaul = lerpf(up_out, off_out, w)
	if not keep.has("cunningham"):
		cunningham = lerpf(up_cun, 0.0, w)
	if not keep.has("vang"):
		vang = lerpf(up_vang, off_vang, w)
	if not keep.has("traveler"):
		traveler = lerpf(up_trav, 0.0, w)
	if not keep.has("puller"):
		puller = lerpf(up_push, 0.0, w)
	if not keep.has("halyard"):
		halyard = lerpf(up_hal, off_hal, w)
	if not keep.has("board"):
		# Up to the band on a run, down again as she comes up to a reach.
		if board > 0.6:
			board = BOARD_UP if at > 2.36 else 1.0
		else:
			board = 1.0 if at < 2.2 else BOARD_UP
	if not keep.has("jib_lead"):
		# Off the wind the telltales don't tell you much: back to neutral.
		jib_lead = lerpf(even_lead(), 0.0, smoothstep(1.6, 2.0, absf(awa)))


## Jib lead (in) at which the luff telltales break evenly top and bottom (guide): the twist that
## puts the top and bottom thirds at the same angle of attack, given the apparent wind's twist
## with height and the head's extra loading.
func even_lead() -> float:
	if pole_state == POLE_SET:
		return jib_lead
	_prepare_sails()
	var tw := _jib_twist(jib_sheet)
	_sail(false, jib, tw, jib_depth, jib_draft, JIB_AREA, false)
	var a0 := absf(_sa[0])
	var a2 := absf(_sa[2])
	if a0 <= 0.0 or a2 <= 0.0:
		return jib_lead
	# More twist takes angle off the top faster than the bottom: twist by the difference.
	var more := (a2 - a0) / (float(STRIP_S[2]) - float(STRIP_S[0]))
	return clampf(jib_lead - more / 0.035, -LEAD_MAX, LEAD_MAX)


## Righting arm of hull and rig (m): like GM 0.66 m at small angles, peaking as the leeward rail
## goes under at about 30 degrees, gone at 69 (the angle of vanishing stability); past that the
## rig pulls her over.
static func _gz(h: float) -> float:
	var a := absf(h)
	var gz: float
	if a <= GZ_PEAK_HEEL:
		gz = GZ_MAX * sin(PI * 0.5 * a / GZ_PEAK_HEEL)
	elif a <= AVS:
		gz = GZ_MAX * cos(PI * 0.5 * (a - GZ_PEAK_HEEL) / (AVS - GZ_PEAK_HEEL))
	else:
		gz = -0.06 * sin(PI * 0.5 * clampf((a - AVS) / (PI * 0.5 - AVS), 0.0, 1.0))
	return gz * signf(h)


var _last_alpha := 0.0


## Force of a foil on the boat (body frame) for water flowing past it at `flow`.
## `chord_angle` is the direction from leading to trailing edge.
func _surface(flow: Vector2, chord_angle: float, area: float, rho: float, ta: Array, tcl: Array, tcd: Array) -> Vector2:
	var sp2 := flow.length_squared()
	if sp2 < 1e-6 or area <= 0.0:
		_last_alpha = 0.0
		return Vector2.ZERO
	var a := wrapf(flow.angle() - chord_angle, -PI, PI)
	_last_alpha = a
	var ad := rad_to_deg(absf(a))
	var cl := _deg_lut(_foil_cl, ad) * signf(a)
	var cd := _deg_lut(_foil_cd, ad)
	var d := flow / sqrt(sp2)
	var lift_dir := Vector2(-d.y, d.x)
	return (lift_dir * cl + d * cd) * (0.5 * rho * sp2 * area)


static func _cross(p: Vector2, force: Vector2) -> float:
	return p.x * force.y - p.y * force.x


# The sail and foil tables at every whole degree from 0 to 180. Every breakpoint in them is a
# whole degree, so interpolating these gives exactly the tables' values, without a search.
static var _sail_cl := _degree_table(SAIL_A, SAIL_CL)
static var _sail_cd := _degree_table(SAIL_A, SAIL_CD)
static var _foil_cl := _degree_table(FOIL_A, FOIL_CL)
static var _foil_cd := _degree_table(FOIL_A, FOIL_CD)


static func _degree_table(xs: Array, ys: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(182)
	for d in 182:
		out[d] = _interp(xs, ys, float(d))
	return out


static func _deg_lut(lut: PackedFloat32Array, deg: float) -> float:
	var x := clampf(deg, 0.0, 180.0)
	var i := int(x)
	return lerpf(lut[i], lut[i + 1], x - i)


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
## boat more than a fully hiked crew can hold. Returns Vector2(main_sheet, jib_sheet). On the
## pole the jib sheet sets how far aft the pole is.
func best_sheets() -> Vector2:
	_prepare_sails()
	var hold := crew_mass * G * HIKE_MAX * 0.97 + mass() * G * _gz(0.2)
	var side := -signf(awa) if absf(awa) > 0.01 else -1.0
	var jk := _jib_work() * 0.95
	# With no way on the board can't hold side force: it only shoves her sideways and rounds
	# her up, so the crew eases until she's moving (est). Heeled well past her angle (towards
	# the boom), the crew dumps the sheets whatever the drive.
	var lee_heel := heel * signf(boom) if absf(boom) > 0.02 else absf(heel)
	var slow := 0.6 * (1.0 - smoothstep(0.3, 1.5, u)) + 1.5 * smoothstep(0.30, 0.55, lee_heel)
	# The crew trims the jib for itself, and the main is played against what's left of the
	# righting moment (guide: the mainsheet is the throttle). Each is a coarse search, then a
	# finer one around the best, so the trim doesn't jump between neighbouring settings.
	var js := _jib_search(side, hold, jk, slow, 0.0, 1.0 / 8.0, 9)
	js = _jib_search(side, hold, jk, slow, js - 1.0 / 8.0, 1.0 / 32.0, 9)
	var jf := _jib_force(side, jk, slow, js)
	var ms := _main_search(side, hold, slow, jf, 0.0, 1.0 / 12.0, 13)
	ms = _main_search(side, hold, slow, jf, ms - 1.0 / 12.0, 1.0 / 48.0, 9)
	return Vector2(ms, js)


## The jib's drive (less side force with no way on), its heeling moment about the board, and
## the sheet setting, for one jib sheet setting.
func _jib_force(side: float, jk: float, slow: float, sh: float) -> Vector3:
	var jb: float
	if pole_state == POLE_SET:
		jb = pole_side * (POLE_ANG - 0.45 * sh)
	else:
		jb = side * minf(lerpf(JIB_MIN, JIB_MAX, sh), absf(awa))
	_sail(false, jb, _jib_twist(sh), jib_depth, jib_draft, JIB_AREA * _jib_area(jb), false)
	return Vector3((_sf.x - slow * absf(_sf.y)) * jk, (absf(_sheel) + absf(_sf.y) * BOARD_DEPTH) * jk, sh)


func _jib_search(side: float, hold: float, jk: float, slow: float, j0: float, dj: float, nj: int) -> float:
	var best := 1.0
	var best_score := -INF
	for j in nj:
		var f := _jib_force(side, jk, slow, clampf(j0 + j * dj, 0.0, 1.0))
		# Tiny preference for easing, so a luffing-edge tie goes to the eased setting.
		var score := f.x - maxf(f.y - hold, 0.0) * 1.5 / (MAIN_CE_H + BOARD_DEPTH) + f.z * 0.07
		if score > best_score:
			best_score = score
			best = f.z
	return best


func _main_search(side: float, hold: float, slow: float, jf: Vector3, m0: float, dm: float, nm: int) -> float:
	var best := 1.0
	var best_score := -INF
	for i in nm:
		var sh := clampf(m0 + i * dm, 0.0, 1.0)
		var b := side * minf(minf(lerpf(MAIN_MIN, MAIN_SHEET_MAX, sh), MAIN_MAX), absf(awa))
		_sail(true, b, _main_twist(sh), main_depth, main_draft, MAIN_AREA, false)
		var fx := _sf.x - slow * absf(_sf.y)
		var m := absf(_sheel) + absf(_sf.y) * BOARD_DEPTH + jf.y
		# Past what the crew can hold, extra side force only heels the boat: count it heavily.
		var score := fx + jf.x - maxf(m - hold, 0.0) * 1.5 / (MAIN_CE_H + BOARD_DEPTH) + sh * 0.07
		if score > best_score:
			best_score = score
			best = sh
	return best


## How fast a hand on the mainsheet moves it (fraction of full travel per second): letting it
## run is quick, pulling it in against the load gets slow in a breeze.
func sheet_rate(easing: bool) -> float:
	if easing:
		return 0.9
	# Slower under load, and over the last of it to the centreline, where the sheet is pulling the
	# boom down against the leech more than in (est).
	return 0.55 / (1.0 + main_load / 220.0) * lerpf(0.4, 1.0, smoothstep(0.0, 0.3, main_sheet))


## Trim from the crew's weight fore and aft, radians, + bow down.
func trim() -> float:
	return crew_mass * crew_x / (mass() * TRIM_GML)


## Where the crew sit fore and aft (m forward of their usual seats) for the best trim at this
## speed: forward in light air, back on their seats around hull speed, aft once she planes.
func auto_trim() -> float:
	var want := deg_to_rad(_interp(TRIM_BEST_KN, TRIM_BEST_DEG, absf(u) / KN))
	return clampf(want * mass() * TRIM_GML / crew_mass, -CREW_X_AFT, CREW_X_FWD)


## Hike setting that holds about `target_deg` of heel to leeward.
func auto_hike(target_deg := 4.0) -> float:
	var side := -signf(boom) if absf(boom) > 0.02 else signf(awa)
	var target := -side * deg_to_rad(target_deg)
	var need_y := -(heel_ext - mass() * G * _gz(target)) / (crew_mass * G * cos(heel))
	var y := need_y * side
	var out: float
	if y >= 0.35:
		out = clampf((y - 0.35) / (HIKE_MAX - 0.35), 0.0, 1.0)
	else:
		out = clampf(-(0.35 - y) / 0.65, -1.0, 0.0)
	# Heeled well past the target to leeward (a puff, water in the boat), the crew hikes hard
	# whatever the sails say.
	var over := -heel * side - deg_to_rad(target_deg)
	if over > 0.12:
		out = maxf(out, smoothstep(0.12, 0.35, over))
	return out
