extends Control
## Heads-up display: race status, the RC's flags and course board, instruments, sail trim with
## telltales, messages, big banners, the leaderboard and the help card.

const Race := preload("res://scripts/race.gd")
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
var coach := false # show the coach numbers anyway
var tiller_mode := true  # the helm gauge shows where the tiller handle is
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

## Simulator: what a Snipe sailor actually has, a tactical compass and a feel for the heel.
## Coach mode (or Assisted) adds the speedo, wind and VMG numbers.
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
		_text(p + Vector2(14, 64), "%03d" % int(hdg), 58, Color.WHITE, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
		_text(p + Vector2(16, 86), "compass", 14, DIM)
		_text(p + Vector2(190, 40), "%s tack" % tack, 18, Color.WHITE)
		_text(p + Vector2(190, 64), "Trim by the telltales and windex;", 14, DIM)
		_text(p + Vector2(190, 84), "puffs show as dark water.", 14, DIM)
		_text(p + Vector2(190, 104), "I: coach numbers", 14, Color(1, 1, 1, 0.4))
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
		flags.append("CAPSIZED (R: crew rights her)" if b.capsize_t >= b.RIGHT_MIN else "CAPSIZED, crew swimming to the board")
	elif b.water_in > 0.05:
		flags.append("bailing %d%%" % int(b.water_in * 100.0))
	if b.aground:
		flags.append("AGROUND")
	if warp > 1:
		flags.append("TIME x%d" % warp)
	flags.append("cam: " + cam_name)
	_text(p + Vector2(150, 140), "   ".join(flags), 14, WARN if b.capsized or b.aground else DIM)
	_text(p + Vector2(150, 162), "F1 help   M chart   Tab results   C camera", 13, Color(1, 1, 1, 0.4))


# --- Trim (bottom centre) --------------------------------------------------------------

func _draw_trim(b) -> void:
	var full := not sim or coach
	var w := 690.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 176, w, 160)
	_panel(r)
	var p := r.position + Vector2(14, 26)
	var assist: Dictionary = fleet.assist
	_bar(p, "MAIN", b.main_sheet, b.main_alpha, b.awa, ideal.x if full else -1.0, assist["main"], "W/S", full)
	_bar(p + Vector2(0, 30), "JIB", b.jib_sheet, b.jib_alpha, b.awa, ideal.y if full else -1.0, assist["jib"], "Q/E", full, "crew")
	_setting(p + Vector2(0, 60), "VANG", b.vang, "Z/X", assist.get("rig", false), "slack", "hard on")
	_setting(p + Vector2(0, 86), "OUTHAUL", b.flatten, "V/F", assist.get("rig", false), "full", "flat")
	# Crew position.
	var cy: float = b.crew_y
	var q := p + Vector2(0, 116)
	_text(q + Vector2(0, 4), "CREW", 13, DIM)
	var bar := Rect2(q + Vector2(76, -6), Vector2(204, 12))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_line(bar.position + Vector2(bar.size.x * 0.5, -3), bar.position + Vector2(bar.size.x * 0.5, 15), Color(1, 1, 1, 0.4), 1.0)
	var cx := bar.position.x + bar.size.x * 0.5 + clampf(cy / 1.05, -1.0, 1.0) * bar.size.x * 0.5
	draw_circle(Vector2(cx, bar.position.y + 6), 7, Color(1, 0.8, 0.3))
	var hk := "crew" if assist["hike"] else "Shift/Ctrl"
	_text(q + Vector2(292, 4), "hike: %s" % hk, 13, DIM)
	var board := "down" if b.board > 0.75 else ("half" if b.board > 0.25 else "up")
	_text(q + Vector2(380, 4), "board %s (B)" % board, 13, DIM)
	# Tiller.
	var tr := Rect2(r.position + Vector2(w - 150, 118), Vector2(130, 10))
	draw_rect(tr, Color(1, 1, 1, 0.12))
	draw_line(tr.position + Vector2(tr.size.x * 0.5, -3), tr.position + Vector2(tr.size.x * 0.5, 13), Color(1, 1, 1, 0.4), 1.0)
	var handle: float = -b.tiller if tiller_mode else b.tiller
	var tx: float = tr.position.x + tr.size.x * 0.5 + handle * tr.size.x * 0.5
	draw_rect(Rect2(tx - 3, tr.position.y - 3, 6, 16), Color(1, 1, 1))
	_text(tr.position + Vector2(0, -8), ("TILLER  port | stbd" if tiller_mode else "HELM") + "   (Space centres)", 11, DIM)


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


## A rig control: 0..1 with labels at each end.
func _setting(p: Vector2, label: String, v: float, keys: String, auto: bool, lo: String, hi: String) -> void:
	_text(p + Vector2(0, 4), label, 13, DIM)
	var bar := Rect2(p + Vector2(76, -4), Vector2(204, 8))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v, 0.0, 1.0), bar.size.y)), Color(0.7, 0.8, 0.95, 0.8))
	_text(p + Vector2(292, 4), ("crew" if auto else keys) + "   %s .. %s" % [lo, hi], 13, DIM)


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
	["Q / E", "ease / sheet the jib yourself (J gives it back to the crew)"],
	["Shift / Ctrl", "hike out / move in yourself (H gives it back to the crew)"],
	["Z / X", "vang: ease / tension (a loose vang twists the leech open)"],
	["V / F", "outhaul + cunningham: ease for power / flatten to depower"],
	["B", "centreboard down / half / up"],
	["R", "crew rights the boat after a capsize"],
	["C", "camera: helm, chase, start line, overhead (right-drag to look, wheel)"],
	["M  /  I", "chart  /  coach numbers (speed, wind, VMG, trim hints)"],
	["Tab", "finishers (live standings in coach or assisted mode)"],
	["T  /  Esc", "time warp x1-x8  /  pause menu"],
]


func _draw_help() -> void:
	var r := Rect2(size.x * 0.5 - 420, 60, 840, 700)
	draw_rect(r, Color(0.02, 0.04, 0.06, 0.92))
	var p := r.position + Vector2(24, 40)
	_text(p, "Controls", 24, ACCENT, -1, HORIZONTAL_ALIGNMENT_LEFT, true)
	p.y += 36
	for row: Array in HELP:
		_text(p, row[0], 16, Color(1, 0.85, 0.5))
		_text(p + Vector2(200, 0), row[1], 16, Color.WHITE)
		p.y += 26
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
