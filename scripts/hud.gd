extends Control
## Heads-up display: race status, the RC's flags and course board, instruments, sail trim with
## telltales, messages, big banners, the leaderboard and the help card.

const Race := preload("res://scripts/race.gd")
const BoatSimRef := preload("res://scripts/boat_sim.gd")
const KN := 0.514444

var fleet
var messages: Array = []  # {text, t, player}
var banner := ""
var banner_t := 0.0
var show_help := false
var show_board := false
var warp := 1
var cam_name := ""
var ideal := Vector2(-1, -1)  # ideal main/jib sheet for the player's boat
var sim := true    # simulator: compass and watch only
var helm_view := false  # the camera is at the helm, where the compass on the foredeck shows the heading
var coach := false # show the coach numbers anyway
var tiller_mode := true  # the helm gauge shows where the tiller handle is
var pad := false   # show game pad controls instead of keys (set by main.gd from the last input)
var show_tune := false  # the rig tune panel (Y)
var _helm_avg := 0.0    # smoothed rudder angle she needs, + = weather helm (degrees)
var _guide := {}        # the crew's settings for this wind and angle, for the coach column
var _guide_t := 0.0
var _font: Font
var _bold: Font

const PANEL := Color(0.03, 0.06, 0.09, 0.62)
const DIM := Color(1, 1, 1, 0.6)
const ACCENT := Color(1.0, 0.62, 0.2)
const GOOD := Color(0.35, 0.9, 0.45)
const WARN := Color(1.0, 0.8, 0.25)
const BAD := Color(1.0, 0.35, 0.3)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_default_font()
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI Semibold", "Segoe UI", "Arial"])
	sf.font_weight = 600
	_bold = sf


func add_message(text: String, player := false) -> void:
	messages.append({"text": text, "t": 0.0, "player": player})
	if messages.size() > 7:
		messages.pop_front()


func flash(text: String) -> void:
	banner = text
	banner_t = 3.0


func _process(dt: float) -> void:
	for m: Dictionary in messages:
		m["t"] += dt
	messages = messages.filter(func(m): return m["t"] < 16.0)
	banner_t = maxf(banner_t - dt, 0.0)
	queue_redraw()


func _draw() -> void:
	if fleet == null:
		return
	var b = fleet.boats[fleet.player]
	var race = fleet.race
	var e = race.entrants[fleet.player] if race != null else null
	_draw_race(b, race, e)
	_draw_instruments(b, race, e)
	_draw_trim(b)
	if show_tune:
		_draw_tune(b)
	_draw_messages()
	if banner_t > 0.0:
		var a := clampf(banner_t, 0.0, 1.0)
		var w := size.x
		_text(Vector2(0, size.y * 0.3), banner, 46, Color(1, 1, 1, a), w, HORIZONTAL_ALIGNMENT_CENTER, true)
	if show_board and race != null:
		_draw_standings(race)
	if show_help:
		_draw_help()


func _panel(r: Rect2) -> void:
	draw_rect(r, PANEL)


func _text(p: Vector2, s: String, sz: int, c := Color.WHITE, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT, bold := false) -> void:
	draw_string(_bold if bold else _font, p, s, align, w, sz, c)


# --- Race panel (top left) and flags (top centre) --------------------------------------

func _draw_race(b, race, e) -> void:
	var r := Rect2(16, 16, 540, 132)
	_panel(r)
	var x := r.position.x + 14
	var y := r.position.y + 34
	if race == null:
		_text(Vector2(x, y), "FREE SAIL", 26, ACCENT, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
		_text(Vector2(x, y + 28), "Union Reservoir, Longmont, Colorado", 15, DIM)
		_text(Vector2(x, y + 50), "Marks 1-9 are out. Esc for the menu.", 15, DIM)
		return
	var clock: float = race.clock
	var head := ""
	var col := Color.WHITE
	match race.phase:
		Race.Phase.CHECKIN:
			head = "CHECK-IN   start in %s" % Race.fmt_clock(-clock)
			col = WARN
		Race.Phase.SEQUENCE:
			head = "START IN  %s" % Race.fmt_clock(-clock)
			col = ACCENT
		Race.Phase.RACING, Race.Phase.DONE:
			if e.finished:
				head = "FINISHED   %s" % Race.fmt_clock(e.finish_time)
				col = GOOD
			elif e.status != "":
				head = e.status
				col = BAD
			elif not e.started:
				head = ("OCS: RETURN BELOW THE LINE  " if e.ocs and not e.cleared else "START NOW  ") + Race.fmt_clock(clock)
				col = BAD if e.ocs and not e.cleared else WARN
			else:
				head = "RACING   %s" % Race.fmt_clock(clock)
	_text(Vector2(x, y), head, 26, col, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
	# Next target.
	var line2 := ""
	if race.phase == Race.Phase.CHECKIN and not e.checked_in:
		line2 = "Flag L up: pass the RC boat's transom on starboard to check in"
	elif race.phase == Race.Phase.CHECKIN:
		line2 = "Checked in. Course goes up at the Attention signal (3:00)."
	elif race.course.size() > 0 and not e.finished and e.status == "":
		var i: int = e.leg if e.started else -1
		var target: Vector2 = race.line_center() if i < 0 else race.point_of(i)
		var name: String = "the start line" if i < 0 else ("mark " + race.course[i] if race.is_mark(i) else ("the gate" if race.course[i] == "G" else "the finish"))
		var d: Vector2 = target - b.pos
		var brg := fposmod(rad_to_deg(atan2(d.x, d.y)), 360.0)
		line2 = ("Next: %s   %03d°   %d m" % [name, int(brg), int(d.length())]) if (not sim or coach) else "Next: %s" % name
		if e.started:
			line2 += "   leg %d/%d" % [e.leg + 1, race.course.size()]
	_text(Vector2(x, y + 28), line2, 16, Color.WHITE)
	var line3 := ""
	if (race.phase >= Race.Phase.RACING or race.phase == Race.Phase.SEQUENCE) and (not sim or coach or e.finished):
		line3 = "Position %d / %d" % [race.place_of(e), race.entrants.size()]
	if e.penalty_turns > 0:
		var done := absf(e.pen_accum) / TAU
		line3 += "    PENALTY: %d turn%s (%.1f done, tacks %d gybes %d)" % [e.penalty_turns, "s" if e.penalty_turns > 1 else "", done, e.pen_tacks, e.pen_gybes]
	_text(Vector2(x, y + 50), line3, 16, BAD if e.penalty_turns > 0 else Color.WHITE)
	var line4 := "Course: %s  (marks to port)" % race.course_text if race.course_text != "" else "Course: posted at the Attention signal"
	_text(Vector2(x, y + 72), line4, 14, DIM)
	if not e.checked_in and race.phase != Race.Phase.CHECKIN:
		_text(Vector2(x + 300, y + 72), "not checked in", 13, WARN)

	# RC flags, top centre.
	var fl: Array = race.flags.keys()
	var fw := 64.0
	var total := maxf(fl.size(), 1) * (fw + 10.0) + 150.0
	var fr := Rect2(size.x * 0.5 - total * 0.5, 16, total, 58)
	_panel(fr)
	_text(fr.position + Vector2(12, 24), "RC flags", 14, DIM)
	_text(fr.position + Vector2(12, 44), "board: " + (race.course_text if race.course_text != "" else "-"), 13, DIM)
	var fx := fr.position.x + 140.0
	if fl.is_empty():
		_text(Vector2(fx, fr.position.y + 36), "none", 16, DIM)
	for f: String in fl:
		_flag(Rect2(fx, fr.position.y + 10, fw, 38), f)
		fx += fw + 10.0


func _flag(r: Rect2, f: String) -> void:
	match f:
		"L":
			var h := r.size * 0.5
			draw_rect(Rect2(r.position, h), Color(1, 0.85, 0))
			draw_rect(Rect2(r.position + Vector2(h.x, 0), h), Color(0.05, 0.05, 0.05))
			draw_rect(Rect2(r.position + Vector2(0, h.y), h), Color(0.05, 0.05, 0.05))
			draw_rect(Rect2(r.position + h, h), Color(1, 0.85, 0))
		"X":
			draw_rect(r, Color(1, 1, 1))
			draw_rect(Rect2(r.position + Vector2(r.size.x * 0.4, 0), Vector2(r.size.x * 0.2, r.size.y)), Color(0.1, 0.25, 0.8))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.4), Vector2(r.size.x, r.size.y * 0.2)), Color(0.1, 0.25, 0.8))
		"PORTSMOUTH":
			draw_rect(r, Color(1, 0.88, 0.1))
		"LMS":
			draw_rect(r, Color(0.1, 0.65, 0.25))
		_:
			draw_rect(r, Color(0.8, 0.8, 0.8))
	draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
	var label: String = {"PORTSMOUTH": "class", "LMS": "class"}.get(f, f)

	if f == "PORTSMOUTH" or f == "LMS":
		_text(r.position + Vector2(4, r.size.y - 6), label, 11, Color(0, 0, 0, 0.7))


# --- Instruments (bottom left) --------------------------------------------------------

## Simulator: a tactical compass with boat speed (as a GPS unit shows them) and a feel for the
## heel. Coach mode (or Assisted) adds wind and VMG numbers.
func _draw_instruments(b, race, e) -> void:
	var full := not sim or coach
	var r := Rect2(16, size.y - 196, 420, 180)
	_panel(r)
	var p := r.position
	var hdg := fposmod(rad_to_deg(b.heading), 360.0)
	var tack := "starboard" if b.tack() > 0 else "port"
	if full:
		_text(p + Vector2(14, 58), "%.1f" % (b.speed() / KN), 52, Color.WHITE, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
		_text(p + Vector2(16, 80), "knots" + (" (coach)" if sim else ""), 14, DIM)
		_text(p + Vector2(150, 34), "HDG  %03d°" % int(hdg), 18, Color.WHITE)
		_text(p + Vector2(150, 58), "TWS  %.1f kn   TWA %d°" % [b.tws / KN, int(absf(rad_to_deg(b.twa)))], 16, Color.WHITE)
		_text(p + Vector2(150, 80), "AWA  %d°   %s tack" % [int(absf(rad_to_deg(b.awa))), tack], 16, Color.WHITE)
		if race != null and e != null and e.started and not e.finished:
			var target: Vector2 = race.point_of(e.leg)
			var to: Vector2 = (target - b.pos).normalized()
			var vmg: float = b.velocity().dot(to) / KN
			_text(p + Vector2(150, 102), "VMG to next  %.1f kn" % vmg, 16, GOOD if vmg > 0.0 else BAD)
		else:
			var wf := deg_to_rad(b.tw_from)
			var vmg_w: float = b.velocity().dot(Vector2(sin(wf), cos(wf))) / KN
			_text(p + Vector2(150, 102), "VMG upwind  %.1f kn" % vmg_w, 16, DIM)
	else:
		# Tactical compass: big heading digits, the way a Velocitek or Tacktick shows it.
		# From the helm the heading is read off the compass by the splash guard; in the other views it is here.
		if helm_view:
			_text(p + Vector2(14, 64), "%.1f" % (b.speed() / KN), 52, Color.WHITE, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
			_text(p + Vector2(16, 86), "knots", 14, DIM)
		else:
			_text(p + Vector2(14, 64), "%03d" % int(hdg), 58, Color.WHITE, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
			_text(p + Vector2(16, 86), "compass", 14, DIM)
			_text(p + Vector2(120, 64), "%.1f" % (b.speed() / KN), 34, Color.WHITE, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
			_text(p + Vector2(122, 86), "kn", 14, DIM)
		_text(p + Vector2(190, 40), "%s tack" % tack, 18, Color.WHITE)
		_text(p + Vector2(190, 64), "Trim by the telltales and yarns;", 14, DIM)
		_text(p + Vector2(190, 84), "puffs show as dark water.", 14, DIM)
		_text(p + Vector2(190, 104), _k("I: coach numbers", "Touchpad: coach numbers"), 14, Color(1, 1, 1, 0.4))
	# Heel: on the water you feel it; here it gets a gauge.
	var c := p + Vector2(70, 150)
	var rad := 46.0
	draw_arc(c, rad, PI + 0.2, TAU - 0.2, 32, Color(1, 1, 1, 0.25), 3.0)
	for deg in [-30, -15, 0, 15, 30]:
		var a := -PI * 0.5 + deg_to_rad(deg) * 1.5
		draw_line(c + Vector2(cos(a), sin(a)) * (rad - 6), c + Vector2(cos(a), sin(a)) * rad, Color(1, 1, 1, 0.5), 1.5)
	var heel: float = b.heel
	var ha := -PI * 0.5 + clampf(heel, -1.0, 1.0) * 1.5
	var hc := GOOD if absf(heel) < 0.2 else (WARN if absf(heel) < 0.4 else BAD)
	draw_line(c, c + Vector2(cos(ha), sin(ha)) * (rad - 4), hc, 3.0)
	_text(c + Vector2(-40, 22), "heel %d°" % int(absf(rad_to_deg(heel))), 13, DIM, 80, HORIZONTAL_ALIGNMENT_CENTER)
	var flags := []
	if b.capsized:
		flags.append(_k("CAPSIZED (R: crew rights her)", "CAPSIZED (Triangle: crew rights her)") if b.capsize_t >= b.RIGHT_MIN else "CAPSIZED, crew swimming to the board")
	elif b.water_in > 0.05:
		flags.append("bailing %d%%" % int(b.water_in * 100.0))
	if b.aground:
		flags.append("AGROUND")
	if warp > 1:
		flags.append("TIME x%d" % warp)
	flags.append("cam: " + cam_name)
	_text(p + Vector2(150, 140), "   ".join(flags), 14, WARN if b.capsized or b.aground else DIM)
	_text(p + Vector2(150, 162), _k("F1 help   Y rig   M chart   Tab results   C cam", "Create help   R3 chart   Cross cam"), 13, Color(1, 1, 1, 0.4))


# --- Trim (bottom centre) --------------------------------------------------------------

func _draw_trim(b) -> void:
	var full := not sim or coach
	var w := 690.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 176, w, 160)
	_panel(r)
	var p := r.position + Vector2(14, 26)
	var assist: Dictionary = fleet.assist
	_bar(p, "MAIN", b.main_sheet, b.main_alpha, b.awa, ideal.x if full else -1.0, assist["main"], _k("W/S", "R2/L2"), full)
	_bar(p + Vector2(0, 30), "JIB", b.jib_sheet, b.jib_alpha, b.awa, ideal.y if full else -1.0, assist["jib"], _k("Q/E", "L1/R1"), full, "crew")
	_setting(p + Vector2(0, 60), "VANG", b.vang, _k("Z/X", "D-pad left/right"), _crew_has("vang"), _vang_text(b.vang))
	_setting(p + Vector2(0, 86), "OUTHAUL", b.outhaul / b.OUTHAUL_MAX, _k("F/V", "keys F/V"), _crew_has("outhaul"), _outhaul_text(b.outhaul))
	# Crew position.
	var cy: float = b.crew_y
	var q := p + Vector2(0, 116)
	_text(q + Vector2(0, 4), "CREW", 13, DIM)
	var bar := Rect2(q + Vector2(76, -6), Vector2(204, 12))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_line(bar.position + Vector2(bar.size.x * 0.5, -3), bar.position + Vector2(bar.size.x * 0.5, 15), Color(1, 1, 1, 0.4), 1.0)
	var cx := bar.position.x + bar.size.x * 0.5 + clampf(cy / 1.05, -1.0, 1.0) * bar.size.x * 0.5
	# Fore and aft as in a plan view: forward is up.
	draw_circle(Vector2(cx, bar.position.y + 6 - clampf(float(b.crew_x) / b.CREW_X_FWD, -1.0, 1.0) * 6.0), 7, Color(1, 0.8, 0.3))
	var hk := "crew" if assist["hike"] else _k("Shift/Ctrl", "Circle/Square")
	_text(q + Vector2(292, 4), "hike: %s" % hk, 13, DIM)
	_text(q + Vector2(372, 4), "board %s (%s)" % [_board_text(b.board), _k("B", "D-pad up/down")], 13, DIM)
	if b.pole_state != b.POLE_STOWED:
		_text(p + Vector2(430, 64), "pole: " + _pole_text(b), 13, WARN if b.pole_busy() or b.pole_wrong_side() else DIM)
	# Tiller.
	var tr := Rect2(r.position + Vector2(w - 150, 118), Vector2(130, 10))
	draw_rect(tr, Color(1, 1, 1, 0.12))
	draw_line(tr.position + Vector2(tr.size.x * 0.5, -3), tr.position + Vector2(tr.size.x * 0.5, 13), Color(1, 1, 1, 0.4), 1.0)
	var handle: float = -b.tiller if tiller_mode else b.tiller
	var tx: float = tr.position.x + tr.size.x * 0.5 + handle * tr.size.x * 0.5
	draw_rect(Rect2(tx - 3, tr.position.y - 3, 6, 16), Color(1, 1, 1))
	_text(tr.position + Vector2(0, -8), ("TILLER  port | stbd" if tiller_mode else "HELM") + _k("   (Space centres)", "   (left stick)"), 11, DIM)


## One sheet bar: position (0 in, 1 eased). With `full` it also says how the sail is working.
func _bar(p: Vector2, label: String, sheet: float, alpha: float, awa: float, ideal_v: float, auto: bool, keys: String, full: bool, who := "auto") -> void:
	_text(p + Vector2(0, 4), label, 13, DIM)
	var bar := Rect2(p + Vector2(76, -6), Vector2(204, 12))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var fill := Rect2(bar.position, Vector2(bar.size.x * (1.0 - sheet), bar.size.y))
	var a := absf(rad_to_deg(alpha))
	var running := absf(rad_to_deg(awa)) > 125.0
	var state := ""
	var col := GOOD
	if a < 5.0:
		state = "luffing: sheet in / bear away"
		col = BAD
	elif a < 9.0 and not running:
		state = "windward telltale lifting"
		col = WARN
	elif a > 28.0 and not running:
		state = "stalled: ease / head up"
		col = BAD
	elif a > 22.0 and not running:
		state = "leeward telltale drooping"
		col = WARN
	else:
		state = "running" if running else "telltales streaming"
	# The coach judges the trim against the best sheet for the moment, not fixed angles: on a
	# reach the fastest trim can have the leeward telltale drooping.
	var hint := ""
	if ideal_v >= 0.0:
		var off := sheet - ideal_v
		col = GOOD if absf(off) < 0.07 else (WARN if absf(off) < 0.18 else BAD)
		if off < -0.07:
			hint = "  (ease)"
		elif off > 0.07:
			hint = "  (sheet in)"
	draw_rect(fill, (col if full else Color(0.85, 0.85, 0.85)) * Color(1, 1, 1, 0.85))
	if ideal_v >= 0.0:
		var ix := bar.position.x + bar.size.x * (1.0 - ideal_v)
		draw_line(Vector2(ix, bar.position.y - 4), Vector2(ix, bar.end.y + 4), Color(1, 1, 1, 0.9), 2.0)
	var right := who if auto else keys
	if full:
		right += "   " + state + hint
	_text(p + Vector2(292, 4), right, 13, col if full else DIM)


## A rig control: a 0..1 bar and its setting in words.
func _setting(p: Vector2, label: String, v: float, keys: String, auto: bool, value: String) -> void:
	_text(p + Vector2(0, 4), label, 13, DIM)
	var bar := Rect2(p + Vector2(76, -4), Vector2(204, 8))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v, 0.0, 1.0), bar.size.y)), Color(0.7, 0.8, 0.95, 0.8))
	_text(p + Vector2(292, 4), value + "   " + ("crew" if auto else keys), 13, DIM)


# --- Rig tune panel (Y) ----------------------------------------------------------------

## True when the crew is setting this rig control (the rig assist is on and you haven't taken
## it over); "pole" goes with the jib.
func _crew_has(field: String) -> bool:
	if field == "pole":
		return fleet.assist.get("jib", false) and not fleet.rig_manual.has("pole")
	return fleet.assist.get("rig", false) and not fleet.rig_manual.has(field)


## Inches to the nearest eighth, the way they're marked on a Snipe: "2 1/2 in", "3/8 in".
static func inch(x: float) -> String:
	var e := int(round(absf(x) * 8.0))
	var whole := e / 8
	var frac := e % 8
	var fs := ""
	if frac != 0:
		var num := frac
		var den := 8
		while num % 2 == 0:
			num /= 2
			den /= 2
		fs = "%d/%d" % [num, den]
	if whole == 0 and fs == "":
		return "0 in"
	if whole == 0:
		return fs + " in"
	return ("%d %s in" % [whole, fs]) if fs != "" else "%d in" % whole


static func _outhaul_text(v: float) -> String:
	return "at the band" if v < 0.07 else "eased " + inch(v)


static func _cunningham_text(v: float) -> String:
	return "loose" if v < 0.07 else inch(v) + " on"


static func _vang_text(v: float) -> String:
	return "slack" if v < 0.035 else "on %d/10" % int(round(v * 10.0))


static func _traveler_text(v: float) -> String:
	return "centred" if v < 0.07 else "down " + inch(v)


static func _puller_text(v: float) -> String:
	if absf(v) < 0.07:
		return "neutral"
	var txt := inch(v) + (" forward" if v > 0.0 else " aft")
	for m: float in [-0.375, 0.375, 0.75, 1.0]:
		if absf(v - m) < 0.03:
			txt += " (mark)"
	return txt


static func _halyard_text(v: float) -> String:
	return "full tension" if v < 0.07 else "eased %s of %d" % [inch(v), int(BoatSimRef.HALYARD_THROW)]


static func _lead_text(v: float) -> String:
	return "neutral" if absf(v) < 0.07 else inch(v) + (" forward" if v > 0.0 else " aft")


static func _board_text(v: float) -> String:
	if v > 0.98:
		return "down"
	if absf(v - 0.36) < 0.03:
		return "raised"
	return "moving"


func _pole_text(b) -> String:
	var side := "starboard" if b.pole_side > 0.0 else "port"
	var st: int = b.pole_state
	if st == BoatSimRef.POLE_SETTING:
		return "crew setting it to %s" % side
	if st == BoatSimRef.POLE_SET:
		return ("on the wrong side after the gybe: %s to swap" % _k("G", "Triangle")) if b.pole_wrong_side() else "set to %s" % side
	if st == BoatSimRef.POLE_STOWING:
		return "crew stowing it"
	if st == BoatSimRef.POLE_SWAPPING:
		return "crew swapping it to %s" % side
	return "stowed"


## Every rig control with its setting in the guide's units, its keys and who has it; then what
## you'd see looking up (mast bend, forestay sag, the sails' shape, the jib telltales, the
## helm); in coach mode the crew's setting for this wind beside each control.
func _draw_tune(b) -> void:
	var full := not sim or coach
	_guide_t -= get_process_delta_time()
	if full and _guide_t <= 0.0:
		_guide_t = 0.5
		_guide = _crew_settings(b)
	var weather := -float(b.tiller) * signf(b.awa if absf(b.awa) > 0.01 else 1.0) * rad_to_deg(b.MAX_RUDDER)
	_helm_avg = lerpf(_helm_avg, weather, clampf(get_process_delta_time() * 0.7, 0.0, 1.0))
	var rows := [
		["Outhaul", _outhaul_text(b.outhaul), _k("V / F", "keys V / F"), "outhaul", _outhaul_text(_guide.get("outhaul", 0.0))],
		["Cunningham", _cunningham_text(b.cunningham), "L / O", "cunningham", _cunningham_text(_guide.get("cunningham", 0.0))],
		["Vang", _vang_text(b.vang), _k("Z / X", "D-pad left / right"), "vang", _vang_text(_guide.get("vang", 0.0))],
		["Traveler", _traveler_text(b.traveler), "[ / ]", "traveler", _traveler_text(_guide.get("traveler", 0.0))],
		["Mast at deck", _puller_text(b.puller), ", / .", "puller", _puller_text(_guide.get("puller", 0.0))],
		["Jib halyard", _halyard_text(b.halyard), "- / =", "halyard", _halyard_text(_guide.get("halyard", 0.0))],
		["Jib lead", _lead_text(b.jib_lead), "; / '", "jib_lead", _lead_text(_guide.get("jib_lead", 0.0))],
		["Centreboard", _board_text(b.board), _k("B, U / N", "D-pad up / down"), "board", _board_text(_guide.get("board", 1.0))],
		["Whisker pole", _pole_text(b), _k("G", "Triangle"), "pole", ""],
	]
	var r := Rect2(16, 158, 600, 26 + rows.size() * 21 + 8 * 19 + 18)
	draw_rect(r, Color(0.02, 0.04, 0.06, 0.82))
	var x := r.position.x + 12
	var y := r.position.y + 22
	_text(Vector2(x, y), "RIG", 16, ACCENT, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
	_text(Vector2(x + 44, y), "Y hides", 11, Color(1, 1, 1, 0.4))
	_text(Vector2(x + 140, y), "setting", 12, DIM)
	_text(Vector2(x + 330, y), "keys" if not pad else "keys (pad)", 12, DIM)
	if full:
		_text(Vector2(x + 440, y), "crew would set", 12, DIM)
	y += 21
	for row: Array in rows:
		var crew := _crew_has(row[3])
		_text(Vector2(x, y), row[0], 14, DIM)
		_text(Vector2(x + 140, y), row[1], 14, Color.WHITE)
		_text(Vector2(x + 330, y), "crew" if crew else row[2], 13, GOOD if crew else Color(1, 0.85, 0.5))
		if full and row[4] != "":
			_text(Vector2(x + 440, y), row[4], 13, DIM)
		y += 21
	# What you'd see looking up.
	y += 6
	var a := absf(rad_to_deg(b.jib_alphas[0])) - absf(rad_to_deg(b.jib_alphas[2]))
	var tt := "luff telltales break evenly"
	if b.pole_state == b.POLE_SET:
		tt = "on the pole"
	elif a > 1.5:
		tt = "top telltales break first: lead forward"
	elif a < -1.5:
		tt = "bottom telltales break first: lead aft"
	var batten := rad_to_deg(b.main_twist) * 0.8
	var bt := "top batten parallel to the boom" if batten < 2.0 else "top batten open %d°" % int(round(batten))
	var side := ""
	if absf(b.mast_side) > 0.12:
		side = ", middle %s to %s" % [inch(b.mast_side), "leeward" if b.mast_side > 0.0 else "windward"]
	var helm := "neutral helm"
	if _helm_avg > 4.0:
		helm = "heavy weather helm"
	elif _helm_avg > 1.0:
		helm = "light weather helm"
	elif _helm_avg < -1.0:
		helm = "lee helm"
	if full:
		helm += " (%+.1f° of rudder)" % _helm_avg
	for line: String in [
		"Mast bend %s at mid-height%s. Forestay sag %s." % [inch(b.mast_bend), side, inch(b.stay_sag)],
		"Main depth %d%% (foot %d%%, head %d%%), draft %d%% aft, %s." % [int(round(b.main_depth[1] * 100.0)), int(round(b.main_depth[0] * 100.0)), int(round(b.main_depth[2] * 100.0)), int(round(b.main_draft * 100.0)), bt],
		"Jib depth %d%%, twist %d°, %s." % [int(round(b.jib_depth[1] * 100.0)), int(round(rad_to_deg(b.jib_twist))), tt],
		"Helm: %s." % helm,
		"Ashore (start menu): %s mast; spreaders %s, %s tip to tip;" % [b.MAST_NAMES[clampi(b.mast, 0, 2)], inch(b.spreader_len), inch(b.spreader_tips)],
		"   shrouds %s aft of the stem; rake %s." % [inch(b.shroud_pos), "at the base" if absf(b.rake) < 0.07 else inch(b.rake) + (" aft" if b.rake > 0.0 else " forward") + " of the base"],
	]:
		_text(Vector2(x, y), line, 13, Color(1, 1, 1, 0.8))
		y += 19
	if pad:
		_text(Vector2(x, y + 2), "Cunningham, traveler, mast, halyard and lead are on the keyboard.", 12, DIM)


## The settings the crew would use right now (auto_rig on a copy of the boat).
func _crew_settings(b) -> Dictionary:
	var c = BoatSimRef.new()
	for k: String in ["tws", "twa", "aws", "awa", "u", "v", "heel", "jib", "jib_sheet", "main_sheet", "mast", "pole_state", "jib_lead", "halyard", "main_load", "jib_load"]:
		c.set(k, b.get(k))
	c.auto_rig()
	var out := {}
	for k: String in ["outhaul", "cunningham", "vang", "traveler", "puller", "halyard", "jib_lead", "board"]:
		out[k] = c.get(k)
	return out


# --- Messages, standings, help ---------------------------------------------------------

func _draw_messages() -> void:
	if show_help:
		return
	var y := size.y - 250.0
	var x := size.x - 560.0
	for i in range(messages.size() - 1, -1, -1):
		var m: Dictionary = messages[i]
		var a := clampf((16.0 - m["t"]) / 3.0, 0.0, 1.0)
		var col := Color(1, 0.9, 0.6, a) if m["player"] else Color(1, 1, 1, a * 0.85)
		var lines := _wrap(m["text"], 14, 530.0)
		for k in range(lines.size() - 1, -1, -1):
			draw_rect(Rect2(x - 8, y - 18, 552, 22), Color(0, 0, 0, 0.35 * a))
			_text(Vector2(x + (0.0 if k == 0 else 12.0), y), lines[k], 14, col)
			y -= 22.0
		y -= 4.0
		if y < size.y * 0.35:
			break


## Split text into lines that fit `width` pixels at font size `sz`.
func _wrap(text: String, sz: int, width: float) -> Array:
	var out := []
	var line := ""
	for word in text.split(" "):
		var trial := word if line == "" else line + " " + word
		if line != "" and _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width:
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


## In the simulator you only know the order once boats have finished; before that you have
## your own eyes. Assisted (or coach) shows the live order with distances.
func _draw_standings(race) -> void:
	var live := not sim or coach
	var list: Array = race.standings()
	var r := Rect2(size.x * 0.5 - 300, 110, 600, 60 + list.size() * 26)
	draw_rect(r, Color(0.02, 0.04, 0.06, 0.85))
	_text(r.position + Vector2(16, 30), ("Standings   %s" if live else "Finishers   %s") % race.course_text, 20, ACCENT, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
	var y := r.position.y + 58
	var i := 1
	for e in list:
		var status: String = e.status
		var info := ""
		if e.finished:
			info = Race.fmt_clock(e.finish_time)
		elif status == "" and e.started:
			info = ("leg %d/%d  %d m to go" % [e.leg + 1, race.course.size(), int(race.remaining(e))]) if live else "racing"
		elif status == "":
			info = "not started"
		var col := Color(0.4, 0.95, 1.0) if e.is_player else Color.WHITE
		var shown: bool = live or e.finished or status != ""
		_text(Vector2(r.position.x + 16, y), ("%d" % i) if shown else "-", 16, col)
		_text(Vector2(r.position.x + 50, y), "%s  %s" % [e.sail, e.name], 16, col)
		_text(Vector2(r.position.x + 300, y), status if status != "" else info, 16, BAD if status != "" else col)
		if e.penalty_turns > 0 and (live or e.is_player):
			_text(Vector2(r.position.x + 500, y), "penalty", 14, BAD)
		y += 26
		i += 1


const HELP := [
	["A / D  or  ← / →", "tiller to port / starboard: the bow swings the other way (Alt: fine)"],
	["Left mouse drag", "sideways moves the tiller; draw back to pull the main in, push to ease"],
	["W / S  or  ↑ / ↓", "pull the main in (slower as the load builds) / let it run out"],
	["Space", "tiller back to the centreline (it stays wherever you leave it)"],
	["Q / E", "ease / sheet the jib yourself, and handle the pole (J gives them back)"],
	["Shift / Ctrl", "hike out / move in yourself (H gives it back to the crew)"],
	["Z / X", "vang: ease / on (slack until hiking hard, then take the slack out)"],
	["V / F", "outhaul: ease / tighten (tight upwind, eased 2-3 in downwind)"],
	["L / O", "cunningham: ease / pull on (loose until overpowered; draft forward)"],
	["[ / ]", "traveler: drop to leeward / back to the centre"],
	[",  /  .", "mast at the deck: pull aft / push forward (marks 3/8 aft, 3/8, 3/4, 1 in fwd)"],
	["-  /  =", "jib halyard: ease / tighten (rig tension; right off dead downwind)"],
	[";  /  '", "jib lead: aft / forward (top telltales break first: forward)"],
	["B,  U / N", "centreboard down / half / up;  raise / lower it a little"],
	["G", "whisker pole: set (running), stow, or swap it after a gybe"],
	["Y", "rig panel: every control, its setting, its keys, the sail shape"],
	["R", "crew rights the boat after a capsize"],
	["C", "camera: helm, chase, start line, overhead (right-drag to look, wheel)"],
	["M  /  I", "chart  /  coach numbers (speed, wind, VMG, trim hints, the crew's rig)"],
	["Tab", "finishers (live standings in coach or assisted mode)"],
	["T  /  Esc", "time warp x1-x8  /  pause menu (hands controls back to the crew)"],
]


## Keys or pad, whichever was used last.
func _k(keys: String, pad_text: String) -> String:
	return pad_text if pad else keys


const HELP_PAD := [
	["Left stick", "tiller handle: push to port and the bow goes to starboard; let go to centre"],
	["R2 / L2", "pull the main in / ease it, as hard as you squeeze; harder near the centreline"],
	["L1 / R1", "ease / sheet the jib yourself (pause menu gives it back to the crew)"],
	["Circle / Square", "hike out / move in yourself"],
	["D-pad up / down", "centreboard up / down"],
	["D-pad left / right", "vang: ease / on (slack until hiking hard)"],
	["Right stick", "look the way you push it, right round to the stern, up or down; let go to look ahead"],
	["Cross", "camera"],
	["Triangle", "whisker pole: set, stow, swap after a gybe; capsized: crew rights her; finished: results"],
	["R3 / L3", "chart / time warp x1-x8"],
	["Touchpad / Create", "coach numbers / this help"],
	["Options", "pause menu"],
	["Keyboard", "the rest of the rig: outhaul V/F, cunningham L/O, traveler [ ], mast , . halyard - =, lead ; '"],
	["", "Y shows the rig panel; the crew sets these if the pause menu says so; Tab the finishers"],
	["Rumble", "helm load; the main luffing; R2 stiffening as the boom nears the centreline; a knock"],
]


func _draw_help() -> void:
	var r := Rect2(size.x * 0.5 - 450, 30, 900, minf(size.y - 50, 840))
	draw_rect(r, Color(0.02, 0.04, 0.06, 0.92))
	var p := r.position + Vector2(24, 36)
	_text(p, "Controls (PS5 controller)" if pad else "Controls", 24, ACCENT, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
	p.y += 32
	for row: Array in (HELP_PAD if pad else HELP):
		_text(p, row[0], 15, Color(1, 0.85, 0.5))
		_text(p + Vector2(200, 0), row[1], 15, Color.WHITE)
		p.y += 23
	p.y += 12
	_text(p, "Racing (Union Sailing Club 2026 SIs)", 18, ACCENT, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
	p.y += 26
	for line in [
		"Check in: while flag L flies, sail past the RC boat's transom on starboard tack.",
		"Appendix U start: 3 long = 3 min, 2 long = 2 min, 1 long + 3 short = 1:30, 1 long = 1 min,",
		"   3 short = 30 s, 2 short = 20 s, 1 short = 10 s, then 5-4-3-2-1 and a long horn to start.",
		"Start between the RC boat (moored at mark 1) and the orange pin. Over early: flag X, go back.",
		"Round every mark to port. G = sail through the start/finish line. F = finish there.",
		"Touch a mark: one turn. Foul a boat (port/starboard, windward, clear astern, tacking): two turns.",
		"Finishers more than 20 minutes behind the first boat are scored TLE.",
	]:
		_text(p, line, 14, Color(1, 1, 1, 0.85))
		p.y += 21
