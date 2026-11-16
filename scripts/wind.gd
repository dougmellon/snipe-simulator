extends RefCounted
## Wind over the reservoir: a base direction and speed, a slow oscillating shift, a gentle
## left-to-right bend across the lake, and puffs and lulls that drift downwind.
## Directions are compass degrees the wind blows FROM. Vectors are Vector2(east, north) air
## velocity in m/s (the direction the air moves).

const KN := 0.514444

var base_from := 270.0
var base_speed := 5.0
var gustiness := 0.5
var time := 0.0

var rng := RandomNumberGenerator.new()
var osc_amp := 6.0
var osc_period := 240.0
var osc_phase := 0.0
var drift := 0.0  # slow persistent shift, degrees
var drift_rate := 0.0
var bend_phase := 0.0

## Each puff: {pos: Vector2, radius: float, strength: float, shift: float, age: float, life: float}
var puffs: Array = []
var lake  # optional, for spawning puffs over the water and shore shadow
const MAX_PUFFS := 16


func setup(from_deg: float, speed_kn: float, gust: float, seed: int, lake_ref = null) -> void:
	base_from = from_deg
	base_speed = speed_kn * KN
	gustiness = clampf(gust, 0.0, 1.0)
	lake = lake_ref
	rng.seed = seed
	osc_amp = 3.0 + 9.0 * gustiness
	osc_period = rng.randf_range(180.0, 360.0)
	osc_phase = rng.randf() * TAU
	bend_phase = rng.randf() * TAU
	drift = 0.0
	drift_rate = 0.0
	time = 0.0
	puffs.clear()
	# Start with the lake already dotted with puffs.
	for i in int(6 + 8 * gustiness):
		_spawn_puff(true)


func update(dt: float) -> void:
	time += dt
	drift_rate += rng.randfn(0.0, 0.004 * (0.3 + gustiness)) * dt * 60.0
	drift_rate *= 0.995
	drift = clampf(drift + drift_rate * dt, -12.0, 12.0)
	var move := mean_vector() * 0.85
	for p: Dictionary in puffs:
		p["age"] += dt
		p["pos"] += move * dt
	puffs = puffs.filter(func(p): return p["age"] < p["life"])
	var want := int(6 + 8 * gustiness)
	if puffs.size() < mini(want, MAX_PUFFS) and rng.randf() < dt * 0.25:
		_spawn_puff(false)


func mean_from() -> float:
	return fposmod(base_from + drift + osc_amp * sin(TAU * time / osc_period + osc_phase), 360.0)


func mean_vector() -> Vector2:
	return from_to_vector(mean_from(), base_speed)


## Wind direction (from) and speed at a point.
func sample(p: Vector2) -> Vector2:
	var from := mean_from()
	# The wind bends a few degrees across the reservoir, so one side of the course is favoured.
	var up := _dir(from)
	var across := Vector2(up.y, -up.x)
	from += (2.0 + 3.0 * gustiness) * sin(p.dot(across) / 900.0 + bend_phase + time / 600.0)
	var speed := base_speed
	var factor := 1.0
	for q: Dictionary in puffs:
		var d2: float = p.distance_squared_to(q["pos"])
		var r: float = q["radius"]
		if d2 > 9.0 * r * r:
			continue
		var env := _envelope(q)
		var w := exp(-d2 / (r * r)) * env
		factor += q["strength"] * w
		from += q["shift"] * w
	# Lighter air just off a windward shore.
	if lake != null:
		var upwind := _dir(from)
		var land := 0.0
		for dist in [30.0, 70.0]:
			if lake.shore_distance(p + upwind * dist) > 0.0:
				land += 0.5
		factor *= 1.0 - 0.18 * land
	return Vector2(fposmod(from, 360.0), maxf(speed * factor, 0.2))


func vector_at(p: Vector2) -> Vector2:
	var s := sample(p)
	return from_to_vector(s.x, s.y)


## Puffs for the water shader: (east, north, radius, strength * envelope).
func shader_puffs() -> PackedVector4Array:
	var out := PackedVector4Array()
	for q: Dictionary in puffs:
		out.append(Vector4(q["pos"].x, q["pos"].y, q["radius"], q["strength"] * _envelope(q)))
	while out.size() < MAX_PUFFS:
		out.append(Vector4(0, 0, 1, 0))
	return out


func _envelope(q: Dictionary) -> float:
	var a: float = q["age"]
	var l: float = q["life"]
	return clampf(a / 20.0, 0.0, 1.0) * clampf((l - a) / 20.0, 0.0, 1.0)


func _spawn_puff(anywhere: bool) -> void:
	var up := _dir(mean_from())
	var pos: Vector2
	var tries := 0
	while true:
		tries += 1
		if anywhere or lake == null:
			pos = Vector2(rng.randf_range(-900, 900), rng.randf_range(-1100, 1100))
		else:
			# Upwind edge of the lake so it drifts across the water.
			var across := Vector2(up.y, -up.x)
			pos = up * rng.randf_range(900, 1300) + across * rng.randf_range(-1000, 1000)
		if lake == null or lake.shore_distance(pos) < 200.0 or tries > 20:
			break
	var lull := rng.randf() < 0.3
	var strength := rng.randf_range(0.12, 0.2 + 0.3 * gustiness)
	puffs.append({
		"pos": pos,
		"radius": rng.randf_range(70.0, 170.0),
		"strength": -strength * 0.7 if lull else strength,
		"shift": rng.randf_range(-6.0, 6.0) * (0.5 + gustiness),
		"age": rng.randf_range(0.0, 60.0) if anywhere else 0.0,
		"life": rng.randf_range(120.0, 260.0),
	})


static func _dir(from_deg: float) -> Vector2:
	var a := deg_to_rad(from_deg)
	return Vector2(sin(a), cos(a))


## Air velocity for a wind blowing from `from_deg` at `speed`.
static func from_to_vector(from_deg: float, speed: float) -> Vector2:
	return -_dir(from_deg) * speed
