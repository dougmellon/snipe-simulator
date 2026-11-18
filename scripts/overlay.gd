extends Control
## Pause menu, results sheet and the after-race debrief.

signal resume
signal restart
signal retire
signal next_race
signal to_menu
signal quit_game
signal debrief
signal watch(t: float)
signal results_back

const Race := preload("res://scripts/race.gd")
const Menu := preload("res://scripts/menu.gd")
const Analysis := preload("res://scripts/analysis.gd")
const SECTOR_NAMES := {"upwind": "Upwind", "reach": "Reaching", "downwind": "Downwind"}
const DIM := Color(1, 1, 1, 0.55)
const HEAD := Color(1.0, 0.8, 0.4)

var _box: VBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.09, 0.94)
	sb.set_corner_radius_all(10)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 26)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	hide()


func _clear() -> void:
	for c in _box.get_children():
		c.queue_free()


func _center() -> void:
	await get_tree().process_frame
	_panel.position = (size - _panel.size) * 0.5


func _title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(1.0, 0.62, 0.2))
	_box.add_child(l)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 38)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


func show_pause(racing: bool, fleet) -> void:
	_clear()
	_title("Paused")
	_button("Resume", func(): resume.emit()).grab_focus.call_deferred()
	if racing:
		_button("Restart this race", func(): restart.emit())
		_button("Retire (RET)", func(): retire.emit())
	for key: String in ["jib", "hike", "rig", "main"]:
		var c := CheckBox.new()
		c.text = {"jib": "Crew trims the jib and handles the pole", "hike": "Crew hikes",
			"rig": "Crew sets the rig (outhaul, cunningham, vang, mast, halyard, lead, board)", "main": "Auto main"}[key]
		# Shown unticked while you hold any of its controls, so ticking it hands them back.
		var held := false
		for k: String in fleet.rig_manual:
			held = held or (k == "pole" if key == "jib" else (k != "pole" and key == "rig"))
		c.button_pressed = fleet.assist.get(key, false) and not held
		Menu.style_check(c)
		# Ticking it hands back every control of that kind the player had taken over.
		c.toggled.connect(func(on: bool): fleet.set_assist(key, on))
		_box.add_child(c)
	_button("Main menu", func(): to_menu.emit())
	_button("Quit to desktop", func(): quit_game.emit())
	show()
	_center()


## `day` is {sail: [points...]} across the races sailed today, `race_no` 1-based.
func show_results(race, race_no: int, day: Dictionary, names: Dictionary, has_debrief := false) -> void:
	_clear()
	_title("Race %d results   ·   %s" % [race_no, race.course_text])
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	_box.add_child(grid)
	for h in ["Place", "Sail", "Boat", "Started", "Elapsed", "Status"]:
		_cell(grid, h, Color(1, 1, 1, 0.55))
	var place := 1
	for e in race.standings():
		var col := Color(0.4, 0.95, 1.0) if e.is_player else Color.WHITE
		var ok: bool = e.finished and e.status == ""
		_cell(grid, str(place) if ok else "-", col)
		_cell(grid, e.sail, col)
		_cell(grid, e.name, col)
		_cell(grid, Race.fmt_clock(e.start_time) if e.started else "-", col)
		_cell(grid, Race.fmt_clock(e.finish_time) if e.finished else "-", col)
		_cell(grid, e.status if e.status != "" else "finished", Color(1.0, 0.45, 0.4) if e.status != "" else col)
		if ok:
			place += 1
	if race_no > 1 or day.size() > 0:
		var l := Label.new()
		l.text = "\nToday so far (simple low-point; the club scores its series with CHIP3):"
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		_box.add_child(l)
		var rows := []
		for sail: String in day:
			var pts: Array = day[sail]
			rows.append([sail, pts.reduce(func(a, b): return a + b, 0), pts])
		rows.sort_custom(func(a, b): return a[1] < b[1])
		var g2 := GridContainer.new()
		g2.columns = 3
		g2.add_theme_constant_override("h_separation", 22)
		_box.add_child(g2)
		for r: Array in rows:
			_cell(g2, "%s %s" % [r[0], names.get(r[0], "")], Color.WHITE)
			_cell(g2, " + ".join(r[2].map(func(x): return str(x))), Color(1, 1, 1, 0.6))
			_cell(g2, "= %d" % r[1], Color(1.0, 0.8, 0.4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_box.add_child(h)
	if has_debrief:
		var db := Button.new()
		db.text = "  Debrief and replay  "
		db.add_theme_font_size_override("font_size", 18)
		db.pressed.connect(func(): debrief.emit())
		h.add_child(db)
	var nb := Button.new()
	nb.text = "  Next race  " if race_no < 3 else "  Another race  "
	nb.add_theme_font_size_override("font_size", 18)
	nb.pressed.connect(func(): next_race.emit())
	h.add_child(nb)
	nb.grab_focus.call_deferred()
	var mb := Button.new()
	mb.text = "Main menu"
	mb.pressed.connect(func(): to_menu.emit())
	h.add_child(mb)
	show()
	_center()


## The debrief for one boat: the start, steady sailing by wind and sector, and every move with
## what it cost. `a` is from Analysis.run, `fleet_cmp` from Analysis.fleet_compare.
func show_debrief(a: Dictionary, fleet_cmp: Dictionary, race_no: int, meta: Dictionary) -> void:
	_clear()
	_title("Race %d debrief   ·   %s" % [race_no, a["name"]])
	var cfg: Dictionary = meta.get("cfg", {})
	_note("Course %s. Wind %03d° at %.0f kn. Losses are distance behind a boat that kept sailing at the steady speed you had just before (tacks, gybes) or your steady speed for that leg (roundings, start)." % [
		meta.get("course_text", ""), int(cfg.get("wind_from", 0)), float(cfg.get("wind_kn", 0))])

	_section("Start")
	var st: Dictionary = a["start"]
	if st.get("complete", false):
		var late: Variant = st["late_s"]
		var txt := "At the gun your bow was %s at %.1f kn, %.0f%% of your steady upwind speed. " % [
			("%.0f m behind the line" % st["behind_m"]) if st["behind_m"] >= 0.0 else ("%.0f m over the line" % -st["behind_m"]),
			st["speed_kn"], 100.0 * st["speed_ratio"]]
		txt += ("You crossed %.0f s after the gun. " % late) if late != null else "You never started. "
		txt += "30 s in you were %.0f m (%.1f lengths) behind a boat that crossed at the gun at your steady upwind VMG." % [st["loss_m"], st["lengths"]]
		if st["ocs"]:
			txt += " You were over early."
		_note(txt, Color.WHITE)
		var parts := []
		for b: Dictionary in st["bins"]:
			parts.append("%+d to %+d s: %.1f kn" % [int(b["from"]), int(b["to"]), b["speed_kn"]])
		_note("Speed around the gun: " + ",  ".join(parts))
	else:
		_note("No start to score in this recording.")

	_section("Steady sailing (leaving out 10 s before to 20 s after each move)")
	if a["wind"].is_empty():
		_note("Not enough steady sailing to show.")
	else:
		var g := _grid(7)
		for h in ["Wind", "Sector", "Time", "Speed", "VMG", "Angle", "Fleet VMG"]:
			_cell(g, h, DIM)
		for row: Dictionary in a["wind"]:
			var key: String = row["bin"] + "|" + row["sector"]
			_cell(g, str(row["bin"]).capitalize(), Color.WHITE)
			_cell(g, SECTOR_NAMES.get(row["sector"], row["sector"]), Color.WHITE)
			_cell(g, "%d:%02d" % [int(row["time_s"]) / 60, int(row["time_s"]) % 60], Color.WHITE)
			_cell(g, "%.2f kn" % row["speed_kn"], Color.WHITE)
			_cell(g, "%.2f kn" % row["vmg_kn"] if row["sector"] != "reach" else "-", Color.WHITE)
			_cell(g, "%.0f°" % row["twa_deg"], _check_col(row["checks"]))
			_cell(g, ("%.2f kn" % fleet_cmp["vmg"][key]) if fleet_cmp["vmg"].has(key) and row["sector"] != "reach" else "-", DIM)

	_section("Moves")
	var sm: Dictionary = a["summary"]
	var lines := []
	for kind: String in ["tack", "gybe", "rounding"]:
		var k: Dictionary = sm[kind]
		var label: String = {"tack": "Tacks", "gybe": "Gybes", "rounding": "Roundings"}[kind]
		if k["n"] == 0:
			lines.append("%s: none clean" % label)
			continue
		var f: Variant = fleet_cmp["kinds"].get(kind)
		lines.append("%s: %d clean, %.1f lengths each%s" % [label, k["n"], k["mean_lengths"], (" (fleet %.1f)" % f) if f != null else ""])
	if sm["penalty_m"] > 0.0:
		lines.append("penalty turns cost %.0f m" % sm["penalty_m"])
	_note(".   ".join(lines) + ".", Color.WHITE)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var mg := GridContainer.new()
	mg.columns = 6
	mg.add_theme_constant_override("h_separation", 22)
	mg.add_theme_constant_override("v_separation", 4)
	scroll.add_child(mg)
	for h in ["Clock", "Move", "Lost", "Lengths", "Where it went", ""]:
		_cell(mg, h, DIM)
	for r: Dictionary in a["moves"]:
		var col := Color.WHITE if r["clean"] else DIM
		_cell(mg, Race.fmt_clock(r["clock"]), col)
		_cell(mg, Analysis.move_name(r) + (" (penalty)" if r["penalty"] else ""), col)
		if r["clean"]:
			_cell(mg, "%.1f m" % r["loss_m"], col)
			_cell(mg, "%.1f" % r["lengths"], _check_col([r["check"]]) if not r["check"].is_empty() else col)
			var worst: Dictionary = {}
			for b: Dictionary in r["bins"]:
				if worst.is_empty() or b["loss_m"] > worst["loss_m"]:
					worst = b
			_cell(mg, ("%+d to %+d s: %.1f m" % [int(worst["from"]), int(worst["to"]), worst["loss_m"]]) if not worst.is_empty() else "", col)
		else:
			_cell(mg, "-", col)
			_cell(mg, "-", col)
			_cell(mg, "penalty turn" if r["penalty"] else "too close to another move to score", col)
		var w := Button.new()
		w.text = "Watch"
		w.add_theme_font_size_override("font_size", 14)
		var t: float = r["t"]
		w.pressed.connect(func(): watch.emit(t - 12.0))
		mg.add_child(w)
	_note("Targets: a tack should cost 0.5 to 2.5 lengths (an estimate for dinghies, not Snipe data). Other targets wait for real-boat data. Grey rows can't be scored.")

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_box.add_child(h)
	var wb := Button.new()
	wb.text = "  Watch the whole race  "
	wb.add_theme_font_size_override("font_size", 18)
	var t_from := float(meta.get("gun_t", 0.0)) - 30.0 if meta.get("gun_t") != null else 0.0
	wb.pressed.connect(func(): watch.emit(t_from))
	h.add_child(wb)
	wb.grab_focus.call_deferred()
	var bb := Button.new()
	bb.text = "Back to results"
	bb.add_theme_font_size_override("font_size", 18)
	bb.pressed.connect(func(): results_back.emit())
	h.add_child(bb)
	show()
	_center()


func show_message(title: String, text: String) -> void:
	_clear()
	_title(title)
	_note(text, Color.WHITE)
	_button("Back to results", func(): results_back.emit())
	show()
	_center()


func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", HEAD)
	_box.add_child(l)


func _note(text: String, col := DIM) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 880
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	_box.add_child(l)


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 4)
	_box.add_child(g)
	return g


## Colour for a value with target checks: amber when outside an estimate, red when outside a
## measured target, white otherwise.
func _check_col(checks: Array) -> Color:
	var col := Color.WHITE
	for c: Dictionary in checks:
		if c.get("status") == "fail":
			return Color(1.0, 0.45, 0.4)
		if c.get("status") == "warn":
			col = Color(1.0, 0.75, 0.35)
	return col


func _cell(grid: GridContainer, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 16)
	grid.add_child(l)
