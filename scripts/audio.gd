extends Node
## Procedural sound: the RC's air horn (Appendix U long and short sounds), wind in the rig,
## water past the hull and a flogging sail.

const RATE := 22050
const HORN_RATE := 44100
const LONG_S := 1.5
const SHORT_S := 0.45
const GAP_S := 0.4
const SOUND_SPEED := 343.0

var horn_long: AudioStreamWAV
var horn_short: AudioStreamWAV
## The horn sounds from the committee boat: quieter and duller with distance, and late by the
## time sound takes to cross the water (1.3 s from the windward mark).
var horn := AudioStreamPlayer3D.new()
var wind := AudioStreamPlayer.new()
var water := AudioStreamPlayer.new()
var flap := AudioStreamPlayer.new()
var queue: Array = []  # [time, "L" or "S"]
var clock := 0.0
var free_at := 0.0
var master := 1.0


func _ready() -> void:
	horn_long = air_horn(LONG_S)
	horn_short = air_horn(SHORT_S)
	for p in [horn, wind, water, flap]:
		add_child(p)
	horn.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	horn.unit_size = 25.0
	horn.max_db = 6.0
	horn.max_distance = 4000.0
	horn.max_polyphony = 3
	horn.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	wind.stream = _noise(3.0, 0.08, 0.0)
	water.stream = _noise(2.5, 0.25, 0.0)
	flap.stream = _noise(1.0, 0.6, 9.0)
	for p in [wind, water, flap]:
		p.volume_db = -60.0
		p.play()


func set_horn_position(p: Vector3) -> void:
	horn.position = p


## "LLL", "LSSS", "S" ... blasts with a short pause between them, starting after `delay`
## seconds (the sound's travel time) and never overlapping a sequence already sounding.
func signal_pattern(pattern: String, delay := 0.0) -> void:
	var t := maxf(clock + delay, free_at)
	for c in pattern:
		queue.append([t, c])
		t += (LONG_S if c == "L" else SHORT_S) + GAP_S
	free_at = t


func _process(dt: float) -> void:
	clock += dt
	horn.volume_db = 4.0 + linear_to_db(maxf(master, 0.001))
	while not queue.is_empty() and queue[0][0] <= clock:
		var c: String = queue.pop_front()[1]
		horn.stream = horn_long if c == "L" else horn_short
		horn.play()


## Called every frame with the player's boat: apparent wind (m/s), speed (m/s), luffing 0..1.
func ambience(aws: float, speed: float, luff: float) -> void:
	wind.volume_db = _db(clampf((aws - 1.0) / 10.0, 0.0, 1.0) * 0.55 * master)
	wind.pitch_scale = 0.8 + clampf(aws / 12.0, 0.0, 0.6)
	water.volume_db = _db(clampf(speed / 4.0, 0.0, 1.0) * 0.6 * master)
	water.pitch_scale = 0.8 + clampf(speed / 6.0, 0.0, 0.5)
	flap.volume_db = _db(clampf(luff, 0.0, 1.0) * clampf(aws / 8.0, 0.0, 1.0) * 0.5 * master)


static func _db(x: float) -> float:
	return linear_to_db(maxf(x, 0.0005))


## A race committee air horn (the canned-air kind): a metal reed buzzing into a short flared
## trumpet. The reed makes a rich, nearly sawtooth tone around 415 Hz; the flare lifts the
## harmonics near 1.7 and 3.3 kHz, which is where the blare comes from. A second reed a hair
## sharp gives the rasp, the note starts flat and "blats" up to pitch as the reed catches,
## sags as the valve closes, carries a little air hiss, and is slightly overdriven. The tail
## has the slap back off the water and the far shore.
static func air_horn(blast: float) -> AudioStreamWAV:
	var f0 := 415.0
	# One period of the reed's waveform as seen through the flare, band-limited under 9 kHz.
	var tn := 2048
	var table := PackedFloat32Array()
	table.resize(tn)
	var h := 1
	while h * f0 < 9000.0:
		var f := h * f0
		var flare := 0.15 + 1.5 * exp(-pow((f - 1700.0) / 900.0, 2.0)) + 0.9 * exp(-pow((f - 3300.0) / 800.0, 2.0))
		var amp := pow(float(h), -0.55) * flare
		var ph := float(h * h) * 0.61
		for i in tn:
			table[i] += amp * sin(TAU * h * i / tn + ph)
		h += 1
	var peak := 0.0
	for v in table:
		peak = maxf(peak, absf(v))
	for i in tn:
		table[i] /= peak

	var rng := RandomNumberGenerator.new()
	rng.seed = int(blast * 1000.0)
	var n_blast := int(blast * HORN_RATE)
	var tail := int(0.75 * HORN_RATE)
	var dry := PackedFloat32Array()
	dry.resize(n_blast + tail)
	var p1 := 0.0
	var p2 := 0.37
	var wander := 0.0
	var hiss_lp := 0.0
	var drive := tanh(1.8)
	for i in n_blast:
		var t := float(i) / HORN_RATE
		var left := blast - t
		var env := smoothstep(0.0, 0.018, t) * (1.0 + 0.18 * exp(-pow((t - 0.035) / 0.02, 2.0))) * smoothstep(0.0, 0.06, left)
		var pitch := 1.0 - 0.07 * (1.0 - smoothstep(0.0, 0.06, t)) - 0.04 * (1.0 - smoothstep(0.0, 0.06, left))
		wander = lerpf(wander, rng.randf_range(-1.0, 1.0), 0.002)
		var f := f0 * pitch * (1.0 + 0.004 * wander)
		p1 = fposmod(p1 + f / HORN_RATE, 1.0)
		p2 = fposmod(p2 + f * 1.0065 / HORN_RATE, 1.0)
		var s := (_read(table, p1) + 0.55 * _read(table, p2)) / 1.55
		var w := rng.randf_range(-1.0, 1.0)
		hiss_lp += (w - hiss_lp) * 0.35
		s = (s + (w - hiss_lp) * 0.07) * env * (1.0 + 0.025 * wander)
		dry[i] = tanh(1.8 * s) / drive
	# Slap back off the water and a fainter, duller echo from the far shore.
	var out := dry.duplicate()
	var e1 := int(0.19 * HORN_RATE)
	var e2 := int(0.46 * HORN_RATE)
	var lp := 0.0
	for i in out.size():
		lp += ((dry[i - e2] if i >= e2 else 0.0) - lp) * 0.25
		out[i] += (0.24 * dry[i - e1] if i >= e1 else 0.0) + 0.14 * lp
	peak = 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(out.size() * 2)
	for i in out.size():
		data.encode_s16(i * 2, int(out[i] / peak * 0.89 * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = HORN_RATE
	wav.data = data
	return wav


static func _read(table: PackedFloat32Array, phase: float) -> float:
	var x := phase * table.size()
	var i := int(x)
	var fr := x - i
	return lerpf(table[i % table.size()], table[(i + 1) % table.size()], fr)


## Looping filtered noise. `bright` 0..1 sets the low-pass; `flutter_hz` > 0 amplitude-modulates.
static func _noise(seconds: float, bright: float, flutter_hz: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * bright
		y2 += (y - y2) * bright
		var s := y2 * 2.2
		if flutter_hz > 0.0:
			s *= 0.5 + 0.5 * sin(TAU * flutter_hz * t + 1.3 * sin(TAU * 1.7 * t))
		# Fade the ends so the loop has no click.
		var edge := minf(minf(t, seconds - t) / 0.05, 1.0)
		data.encode_s16(i * 2, int(clampf(s * edge, -1.0, 1.0) * 20000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w
