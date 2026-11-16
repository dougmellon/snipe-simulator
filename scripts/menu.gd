extends Control
## Start menu: conditions, fleet, course, starting time, series flag and assists.
## Remembers the last settings in user://settings.cfg.

signal start_requested(cfg: Dictionary)
signal quit_requested

const Course := preload("res://scripts/course.gd")
const DIRS := ["Random", "N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const SPEEDS := [["Light (6 kn)", 6.0], ["Medium (10 kn)", 10.0], ["Fresh (14 kn)", 14.0], ["Strong (18 kn)", 18.0], ["Random", -1.0]]
const GUSTS := [["Steady", 0.15], ["Shifty", 0.5], ["Puffy", 0.9]]
const SKILLS := [["Novice", 0.55], ["Club racer", 0.78], ["Sharp", 0.95]]
const STARTS := [["Check-in, 5:00 to go", -300.0], ["Attention signal, 3:00", -181.0], ["1 minute to go", -65.0]]

var controls := {}
var cfg_file := ConfigFile.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cfg_file.load("user://settings.cfg")
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.08, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.09, 0.88)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(48, 40)
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var title := Label.new()
	title.text = "SNIPE"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.2))
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Union Reservoir  ·  Longmont, Colorado\nUnion Sailing Club series racing, 2026 sailing instructions"
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	v.add_child(sub)
	v.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	_option(grid, "realism", "Realism", ["Simulator", "Assisted (learning)"], 0)
	_option(grid, "steer", "Steering", ["Tiller: push it, the bow goes the other way", "Point the bow (arcade)"], 0)
	_option(grid, "mode", "Mode", ["Race", "Free sail"], 0)
	_option(grid, "dir", "Wind from", DIRS, 0)
	_option(grid, "speed", "Wind strength", SPEEDS.map(func(s): return s[0]), 1)
	_option(grid, "gust", "Wind character", GUSTS.map(func(s): return s[0]), 1)
	_spin(grid, "ai", "Other Snipes (fleet of 10 max)", 0, 9, 7)
	_option(grid, "skill", "Their skill", SKILLS.map(func(s): return s[0]), 1)
	_option(grid, "course", "Course", ["RC's choice"] + Course.TYPES, 0)
	_option(grid, "start", "Start at", STARTS.map(func(s): return s[0]), 0)
	_option(grid, "fleet", "Series", ["Summer / Fall (Portsmouth start)", "Spring (LMS fleet flag)"], 0)
	_line(grid, "sail", "Your sail number", "31415")
	v.add_child(HSeparator.new())
	var assists := HBoxContainer.new()
	assists.add_theme_constant_override("separation", 18)
	v.add_child(assists)
	_check(assists, "auto_jib", "Crew trims the jib", true)
	_check(assists, "auto_hike", "Crew hikes", true)
	_check(assists, "auto_rig", "Crew sets vang / outhaul", false)
	_check(assists, "auto_main", "Auto main", false)
	var note := Label.new()
	note.text = "Simulator: you helm and trim the main, and read the telltales, the windex and the water.
No speedo or wind instruments (Snipe class rules allow a compass and a watch); I shows coach data.
Assisted: everything automatic except helm and main, full instruments and map aids."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	v.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	var go := Button.new()
	go.text = "  Go sailing  "
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(_on_go)
	buttons.add_child(go)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): quit_requested.emit())
	buttons.add_child(quit)
	go.grab_focus.call_deferred()

	var credit := Label.new()
	credit.text = "Shoreline © OpenStreetMap contributors (ODbL). Mark positions approximate, from the club's reference map."
	credit.add_theme_font_size_override("font_size", 12)
	credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_left = 50.0
	credit.offset_top = -34.0
	add_child(credit)


func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	parent.add_child(l)


func _option(parent: Control, key: String, text: String, items: Array, default: int) -> void:
	_label(parent, text)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(cfg_file.get_value("menu", key, default), 0, items.size() - 1)
	o.custom_minimum_size = Vector2(290, 0)
	parent.add_child(o)
	controls[key] = o


func _spin(parent: Control, key: String, text: String, lo: int, hi: int, default: int) -> void:
	_label(parent, text)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = cfg_file.get_value("menu", key, default)
	parent.add_child(s)
	controls[key] = s


func _line(parent: Control, key: String, text: String, default: String) -> void:
	_label(parent, text)
	var e := LineEdit.new()
	e.text = cfg_file.get_value("menu", key, default)
	e.max_length = 6
	parent.add_child(e)
	controls[key] = e


func _check(parent: Control, key: String, text: String, default: bool) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = cfg_file.get_value("menu", key, default)
	style_check(c)
	parent.add_child(c)
	controls[key] = c


func _on_go() -> void:
	for k: String in controls:
		var c: Control = controls[k]
		if c is OptionButton:
			cfg_file.set_value("menu", k, (c as OptionButton).selected)
		elif c is SpinBox:
			cfg_file.set_value("menu", k, int((c as SpinBox).value))
		elif c is LineEdit:
			cfg_file.set_value("menu", k, (c as LineEdit).text)
		elif c is CheckBox:
			cfg_file.set_value("menu", k, (c as CheckBox).button_pressed)
	cfg_file.save("user://settings.cfg")
	start_requested.emit(build_cfg())


func build_cfg() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var dir_i: int = controls["dir"].selected
	var wind_from := rng.randf_range(0.0, 360.0) if dir_i == 0 else (dir_i - 1) * 45.0 + rng.randf_range(-8.0, 8.0)
	var sp: float = SPEEDS[controls["speed"].selected][1]
	if sp < 0.0:
		sp = rng.randf_range(5.0, 17.0)
	var course_i: int = controls["course"].selected
	var sail: String = controls["sail"].text.strip_edges()
	if sail == "":
		sail = "31415"
	var sim: bool = controls["realism"].selected == 0
	var assist := {"jib": controls["auto_jib"].button_pressed, "hike": controls["auto_hike"].button_pressed,
		"main": controls["auto_main"].button_pressed, "rig": controls["auto_rig"].button_pressed}
	if not sim:
		assist["jib"] = true
		assist["hike"] = true
		assist["rig"] = true
	return {
		"sim": sim,
		"tiller": controls["steer"].selected == 0,
		"race": controls["mode"].selected == 0,
		"wind_from": fposmod(wind_from, 360.0),
		"wind_kn": sp,
		"gust": GUSTS[controls["gust"].selected][1],
		"ai": int(controls["ai"].value) if controls["mode"].selected == 0 else 0,
		"skill": SKILLS[controls["skill"].selected][1],
		"course": Course.rc_choice(sp) if course_i == 0 else course_i - 1,
		"start": STARTS[controls["start"].selected][1],
		"fleet": "PORTSMOUTH" if controls["fleet"].selected == 0 else "LMS",
		"player": true,
		"player_sail": sail,
		"assist": assist,
		"seed": rng.randi(),
	}


## The default theme's unticked box is dark-on-dark; draw clear ones for our dark panels.
static func style_check(c: CheckBox) -> void:
	c.add_theme_icon_override("unchecked", _box_icon(false))
	c.add_theme_icon_override("checked", _box_icon(true))


static func _box_icon(ticked: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		for j in n:
			var edge := i < 2 or j < 2 or i >= n - 2 or j >= n - 2
			if edge:
				img.set_pixel(i, j, Color(0.85, 0.88, 0.9))
			elif ticked and i >= 5 and j >= 5 and i < n - 5 and j < n - 5:
				img.set_pixel(i, j, Color(1.0, 0.62, 0.2))
	return ImageTexture.create_from_image(img)
