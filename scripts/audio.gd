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
	wind.stream = _ambient(29.0, 0, 7)
	water.stream = _ambient(19.0, 1, 11)
	flap.stream = _ambient(5.0, 2, 13)
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


var _wind_v := 0.0
var _water_v := 0.0


## Called every frame with the player's boat: apparent wind (m/s), speed (m/s), luffing 0..1.
## Wind in the ears is quiet in a drifter and builds with the apparent wind; the water along
## the hull builds with boat speed. Levels ease toward their targets, so nothing switches on.
func ambience(aws: float, speed: float, luff: float) -> void:
	_wind_v = lerpf(_wind_v, pow(clampf((aws - 1.0) / 11.0, 0.0, 1.0), 1.3) * 0.5, 0.04)
	wind.volume_db = _db(_wind_v * master)
	wind.pitch_scale = 0.9 + clampf(aws / 14.0, 0.0, 0.35)
	_water_v = lerpf(_water_v, pow(clampf(speed / 4.5, 0.0, 1.0), 1.2) * 0.5, 0.04)
	water.volume_db = _db(_water_v * master)
	water.pitch_scale = 0.9 + clampf(speed / 7.0, 0.0, 0.3)
	flap.volume_db = _db(clampf(luff, 0.0, 1.0) * clampf(aws / 8.0, 0.0, 1.0) * 0.45 * master)


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


const AMB_RATE := 11025

## Looping ambience that doesn't sound like a loop: `seconds` long, its tail cross-faded into
## its head so there is no gap or click at the join, with slow uneven swells all through it.
## kind 0: wind, a low roar with a little air over it. 1: water along the hull, lapping.
## 2: a sail flogging, in uneven flaps.
static func _ambient(seconds: float, kind: int, seed_v: int) -> AudioStreamWAV:
	var n := int(seconds * AMB_RATE)
	var xf := int(1.5 * AMB_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n + xf)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# Low-pass and high-pass coefficients, gains for the low and middle bands, and the swell:
	# how long each level holds (s), how low it dips, how fast it moves.
	var a1: float = [0.12, 0.7, 0.6][kind]
	var a2: float = [0.002, 0.14, 0.05][kind]
	var g_lo: float = [2.2, 0.9, 1.1][kind]
	var g_mid: float = [0.45, 0.0, 0.0][kind]
	var hold_min: float = [0.5, 0.25, 0.07][kind]
	var hold_max: float = [1.6, 0.9, 0.16][kind]
	var e_min: float = [0.45, 0.15, 0.0][kind]
	var e_k: float = [0.0004, 0.002, 0.01][kind]
	var lo := 0.0
	var lo2 := 0.0
	var hp := 0.0
	var env := 0.7
	var target := 0.7
	var left := 0
	for i in n + xf:
		var w := rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * a1
		lo2 += (lo - lo2) * a1
		hp += (lo2 - hp) * a2
		if left <= 0:
			left = int(rng.randf_range(hold_min, hold_max) * AMB_RATE)
			target = rng.randf_range(e_min, 1.0)
		left -= 1
		env += (target - env) * e_k
		buf[i] = ((lo2 - hp) * g_lo + (lo - lo2) * g_mid) * env
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := buf[i]
		if i < xf:
			var f := float(i) / xf
			v = v * sin(f * PI * 0.5) + buf[n + i] * cos(f * PI * 0.5)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 20000.0))
	var out := AudioStreamWAV.new()
	out.format = AudioStreamWAV.FORMAT_16_BITS
	out.mix_rate = AMB_RATE
	out.data = data
	out.loop_mode = AudioStreamWAV.LOOP_FORWARD
	out.loop_end = n
	return out
