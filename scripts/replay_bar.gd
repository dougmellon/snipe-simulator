extends Control
## The replay controls along the bottom of the screen: back to the debrief, play/pause, speed,
## a timeline to drag, the race clock, and a line saying who you're following and what move
## they're in.

signal seek(t: float)
signal toggle_play
signal cycle_speed
signal back

var _slider: HSlider
var _play: Button
var _speed: Button
var _clock: Label
var _info: Label
var gun_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -96.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.09, 0.82)
	sb.set_corner_radius_all(8)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = -12.0
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(_btn("Debrief", func(): back.emit()))
	_play = _btn("Pause", func(): toggle_play.emit())
	_play.custom_minimum_size.x = 80
	row.add_child(_play)
	_speed = _btn("x1", func(): cycle_speed.emit())
	_speed.custom_minimum_size.x = 50
	row.add_child(_speed)
	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.step = 0.1
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(func(v: float): seek.emit(v))
	row.add_child(_slider)
	_clock = Label.new()
	_clock.custom_minimum_size.x = 120
	_clock.add_theme_font_size_override("font_size", 18)
	row.add_child(_clock)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	col.add_child(_info)


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b


func setup(t0: float, t1: float, gun: float) -> void:
	gun_t = gun
	# Changing the range can clamp the value, which would otherwise fire a seek to the start.
	_slider.set_block_signals(true)
	_slider.min_value = t0
	_slider.max_value = t1
	_slider.set_block_signals(false)


func update_view(t: float, playing: bool, speed: int, info: String) -> void:
	_slider.set_value_no_signal(t)
	_play.text = "Pause" if playing else "Play"
	_speed.text = "x%d" % speed
	var c := t - gun_t
	var s := int(absf(c))
	_clock.text = "%s%d:%02d" % ["-" if c < 0.0 else "", s / 60, s % 60]
	_info.text = info
