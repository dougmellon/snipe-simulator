extends SceneTree
## Checks the GPU wave simulation (scripts/waves.gd). Needs a GPU, so run it windowed:
##   godot --path . --script res://tests/waves_check.gd
## 1. One unit wave, run through the whole pipeline (spectrum, FFTs, unpack), matches the
##    analytic height, displacement and Jacobian everywhere, and runs downwind at the right speed.
## 2. With the real spectrum, each tile's height variance matches the spectrum it was drawn from,
##    and the significant wave height matches the JONSWAP fetch-limited formula.
## 3. Reports slope, Jacobian and foam statistics for a light and a fresh breeze.

const Waves := preload("res://scripts/waves.gd")
const G := 9.81
const SIGMA_RHO := 7.28e-5

var waves
var failures := 0
var _got := {}


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _read(c: int) -> Dictionary:
	_got = {}
	RenderingServer.call_on_render_thread(func(): _got = waves.read_back(c))
	await _frames(2)
	return _got


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	waves = Waves.new()
	await _frames(3)
	if not waves.available:
		print("FAIL  no GPU waves (run this windowed, not headless)")
		quit(1)
		return
	await _single_wave_test()
	await _statistics_test()
	waves.free_gpu()
	await _frames(2)
	print("waves_check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures > 0 else 0)


func _single_wave_test() -> void:
	var n: int = Waves.N
	for spec in [[0, 5, 3], [1, -7, 2], [2, 3, -9]]:
		var c: int = spec[0]
		var m := Vector2(spec[1], spec[2])
		var L: float = Waves.PATCH[c]
		var k := m * TAU / L
		var kl := k.length()
		var t := 12.3
		var w := sqrt(G * kl + SIGMA_RHO * kl * kl * kl)
		var w0 := TAU / Waves.LOOP
		w = roundf(w / w0) * w0
		waves.debug_wave = Vector4i(n / 2 + int(m.x), n / 2 + int(m.y), c, 1)
		waves.update(t, 5.0, Vector2(1, 0), 1200.0)
		await _frames(2)
		var got: Dictionary = await _read(c)
		var disp: Array = got["disp"]
		var slope: Array = got["slope"]
		var worst := 0.0
		var worst_j := 0.0
		var worst_s := 0.0
		for y in range(0, n, 7):
			for x in range(0, n, 5):
				var p := Vector2(x, y) * L / n
				var ph := k.dot(p) - w * t
				var h := 2.0 * cos(ph)
				var dx := -2.0 * k.x / kl * sin(ph) * Waves.CHOPPY
				var dy := -2.0 * k.y / kl * sin(ph) * Waves.CHOPPY
				var dxx := -2.0 * k.x * k.x / kl * cos(ph) * Waves.CHOPPY
				var dyy := -2.0 * k.y * k.y / kl * cos(ph) * Waves.CHOPPY
				var dxy := -2.0 * k.x * k.y / kl * cos(ph) * Waves.CHOPPY
				var jac := (1.0 + dxx) * (1.0 + dyy) - dxy * dxy
				var v: Vector4 = disp[y * n + x]
				worst = maxf(worst, maxf(absf(v.y - h), maxf(absf(v.x - dx), absf(v.z - dy))))
				worst_j = maxf(worst_j, absf(v.w - jac) / maxf(1.0, absf(jac)))
				if jac > 0.3:
					var hx := -2.0 * k.x * sin(ph)
					var hy := -2.0 * k.y * sin(ph)
					var sx := (hx * (1.0 + dyy) - dxy * hy) / jac
					var sy := ((1.0 + dxx) * hy - dxy * hx) / jac
					var s := Vector2(sx, sy)
					if s.length() < 1.1:
						var sv: Vector4 = slope[y * n + x]
						worst_s = maxf(worst_s, (Vector2(sv.x, sv.y) - s).length())
		_check(worst < 0.01 and worst_j < 0.02 and worst_s < 0.01,
			"single wave c%d k=(%d,%d): height/displacement err %.4f, Jacobian err %.4f, slope err %.4f" % [c, m.x, m.y, worst, worst_j, worst_s])
	waves.debug_wave = Vector4i.ZERO


## Height variance the spectrum puts in cascade c (sum of S(k) dk^2 over its band).
func _expected_var(c: int, u: float, f: float, wind_ang: float) -> float:
	var n: int = Waves.N
	var L: float = Waves.PATCH[c]
	var dk := TAU / L
	var wp := 22.0 * pow(G * G / (u * f), 1.0 / 3.0)
	var alpha := 0.076 * pow(u * u / (f * G), 0.22)
	var total := 0.0
	for j in n:
		for i in n:
			var k := Vector2(i - n / 2, j - n / 2) * dk
			var kl := k.length()
			if kl < maxf(waves.k_lo[c], 1e-4) or kl >= waves.k_hi[c]:
				continue
			var w := sqrt(G * kl + SIGMA_RHO * kl * kl * kl)
			var sig := 0.07 if w <= wp else 0.09
			var r := exp(-(w - wp) * (w - wp) / (2.0 * sig * sig * wp * wp))
			var x := wp / w
			var s := alpha * G * G / pow(w, 5.0) * exp(-1.25 * pow(x, 4.0)) * pow(3.3, r)
			var q := w / wp
			var beta: float
			if q < 0.95:
				beta = 2.61 * pow(q, 1.3)
			elif q < 1.6:
				beta = 2.28 * pow(q, -1.3)
			else:
				beta = pow(10.0, -0.4 + 0.8393 * exp(-0.567 * log(q * q)))
			var th := wrapf(atan2(k.y, k.x) - (wind_ang - Waves.ROT[c]), -PI, PI)
			var ch := cosh(beta * th)
			var d := beta / (2.0 * tanh(beta * PI)) / (ch * ch)
			var dwdk := (G + 3.0 * SIGMA_RHO * kl * kl) / (2.0 * w)
			total += s * d * dwdk / kl * dk * dk
	return total


func _statistics_test() -> void:
	var n: int = Waves.N
	for kn in [6.0, 11.0, 14.0, 18.0, 22.0]:
		var u: float = kn * 0.514444
		var f := 1200.0
		var dir := Vector2(0.6, -0.8)
		var wang := atan2(dir.y, dir.x)
		# Run a few seconds so the foam reaches a steady state.
		for i in 180:
			waves.update(100.0 + i / 60.0, u, dir, f)
			await process_frame
		var total := 0.0
		print("--- %d kn (%.2f m/s), fetch %d m ---" % [kn, u, f])
		for c in Waves.CASCADES:
			var got: Dictionary = await _read(c)
			var disp: Array = got["disp"]
			var slope: Array = got["slope"]
			var mean := 0.0
			var sq := 0.0
			var ss := 0.0
			var jmin := INF
			var foam := 0
			var jlow := 0
			for i in n * n:
				var v: Vector4 = disp[i]
				mean += v.y
				sq += v.y * v.y
				var sv: Vector4 = slope[i]
				ss += sv.z
				jmin = minf(jmin, v.w)
				if v.w < 0.5:
					jlow += 1
				if sv.w > 0.3:
					foam += 1
			mean /= n * n
			var var_h := sq / (n * n) - mean * mean
			var want := _expected_var(c, u, f, wang)
			total += var_h
			print("  c%d  L=%.1f m  band %.2f..%.2f rad/m  var %.6f (spectrum %.6f)  rms slope %.3f  J min %.2f  J<0.5 %.2f%%  foam %.2f%%" % [
				c, Waves.PATCH[c], waves.k_lo[c], waves.k_hi[c], var_h, want, sqrt(ss / (n * n)), jmin, 100.0 * jlow / (n * n), 100.0 * foam / (n * n)])
			_check(want > 0.0 and var_h / want > 0.6 and var_h / want < 1.6, "c%d height variance within 40%% of its spectrum" % c)
			if c < 2:
				var line := "      share of J below"
				for thr in [0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]:
					var below := 0
					for i in n * n:
						if (disp[i] as Vector4).w < thr:
							below += 1
					line += "  %.2f: %.3f%%" % [thr, 100.0 * below / (n * n)]
				print(line)
		var hs := 4.0 * sqrt(total)
		var hs_formula := 0.0016 * sqrt(G * f / (u * u)) * u * u / G
		print("  Hs %.3f m (JONSWAP fetch-limited formula %.3f m), peak wavelength %.2f m" % [
			hs, hs_formula, TAU * G / pow(22.0 * pow(G * G / (u * f), 1.0 / 3.0), 2.0)])
		_check(absf(hs / hs_formula - 1.0) < 0.35, "Hs within 35 percent of the fetch-limited formula")
