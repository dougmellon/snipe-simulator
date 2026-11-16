extends SceneTree
## Writes the RC horn blasts to WAV files for listening, and prints their pitch and levels.
## Run: godot --headless --path . --script res://tests/horn_export.gd -- out=C:/tmp
const Audio := preload("res://scripts/audio.gd")


func _init() -> void:
	var out := OS.get_user_data_dir()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	for spec: Array in [["long", Audio.LONG_S], ["short", Audio.SHORT_S]]:
		var t0 := Time.get_ticks_msec()
		var w: AudioStreamWAV = Audio.air_horn(spec[1])
		var ms := Time.get_ticks_msec() - t0
		var path: String = out.path_join("rc_horn_%s.wav" % spec[0])
		w.save_to_wav(path)
		var n := w.data.size() / 2
		var peak := 0.0
		var sum := 0.0
		var mid := PackedFloat32Array()
		for i in n:
			var v := w.data.decode_s16(i * 2) / 32768.0
			peak = maxf(peak, absf(v))
			sum += v * v
			if i > n * 0.15 and i < n * 0.15 + 8192:
				mid.append(v)
		# Fundamental from the autocorrelation peak between 200 and 800 Hz.
		var best := 0
		var best_r := -INF
		for lag in range(Audio.HORN_RATE / 800, Audio.HORN_RATE / 200):
			var r := 0.0
			for i in range(0, mid.size() - lag, 2):
				r += mid[i] * mid[i + lag]
			if r > best_r:
				best_r = r
				best = lag
		print("%s: %.2f s, built in %d ms, peak %.2f, rms %.2f, fundamental %.0f Hz -> %s" % [spec[0], float(n) / Audio.HORN_RATE, ms, peak, sqrt(sum / n), float(Audio.HORN_RATE) / best, path])
	quit()
