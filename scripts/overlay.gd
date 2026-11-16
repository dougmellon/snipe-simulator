extends Control
## Pause menu and results sheet.

signal resume
signal restart
signal retire
signal next_race
signal to_menu
signal quit_game

const Race := preload("res://scripts/race.gd")
const Menu := preload("res://scripts/menu.gd")

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
		c.text = {"jib": "Crew trims the jib", "hike": "Crew hikes", "rig": "Crew sets vang / outhaul", "main": "Auto main"}[key]
		c.button_pressed = fleet.assist.get(key, false)
		Menu.style_check(c)
		c.toggled.connect(func(on: bool): fleet.assist[key] = on)
		_box.add_child(c)
	_button("Main menu", func(): to_menu.emit())
	_button("Quit to desktop", func(): quit_game.emit())
	show()
	_center()


## `day` is {sail: [points...]} across the races sailed today, `race_no` 1-based.
func show_results(race, race_no: int, day: Dictionary, names: Dictionary) -> void:
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


func _cell(grid: GridContainer, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 16)
	grid.add_child(l)
