extends Node3D
## Everything static around the racing: sky and sun, the reservoir water, the farmland with its
## bank and shore, the Front Range on the western horizon, the Union Sailing Club, farms and
## trees, the course marks, and (per race) the committee boat, pin and signal flags.
## World is Vector2(east, north) metres; 3D is +X east, +Y up, -Z north (Lake.to_3d).
##
## Cameras looking at this need camera.far >= 25000 for the mountains and the far horizon.

const Lake := preload("res://scripts/lake.gd")
const Waves := preload("res://scripts/waves.gd")
const BoatView := preload("res://scripts/boat_view.gd")
const Kit := BoatView.Kit

const LAND_H := 1.2
const BANK_W := 8.0
const LAND_EXTENT := 30000.0
const SUN_AZIMUTH := 235.0
const SUN_ELEVATION := 44.0
const HAZE := Color(0.7, 0.78, 0.88)
const FLAG_ORDER := ["AP", "PORTSMOUTH", "LMS", "L", "X", "C", "S"]

var lake
var race
var env: Environment
var sun: DirectionalLight3D
var water_mat: ShaderMaterial
var land_mat: ShaderMaterial
var marks := {}          # id -> Node3D (the buoy, bobbing)
var mark_labels := {}    # id -> Label3D
var rc_boat: Node3D
var rc_flag_root: Node3D
var rc_boards: Array[Label3D] = []
var pin_node: Node3D
var line_mi: MeshInstance3D
var highlight: Node3D
var highlight_label: Label3D
var highlight_id := ""
var wind_flags: Array[Node3D] = []   # flag roots that turn to stream downwind
var flag_mats: Array[ShaderMaterial] = []
var farm_positions: Array[Vector2] = []
var _t := 0.0
var _wind_from := 270.0
var _wind_speed := 5.0
var _line_on := false
var _mark_labels_on := true
var _flag_mesh_cache := {}
var _flag_tex_cache := {}
var _dock_dir := Vector2.UP
var _club_flag: Node3D


func build(lake_ref) -> void:
	lake = lake_ref
	for c in get_children():
		c.queue_free()
	marks.clear()
	mark_labels.clear()
	wind_flags.clear()
	flag_mats.clear()
	_make_environment()
	_make_water()
	_plan_farms()
	_make_land()
	_make_mountains()
	_make_club()
	_make_farms_and_trees()
	_make_marks()
	_make_highlight()
	update_water(0.0, 270.0, 5.0, PackedVector4Array())


# --- Sky, sun, fog ----------------------------------------------------------------------------

func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.23, 0.42, 0.72)
	sm.sky_horizon_color = HAZE
	sm.sky_curve = 0.09
	sm.ground_bottom_color = Color(0.36, 0.37, 0.32)
	sm.ground_horizon_color = HAZE
	sm.ground_curve = 0.05
	sm.sun_angle_max = 9.0
	sm.sun_curve = 0.06
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = HAZE
	env.fog_light_energy = 1.0
	env.fog_density = 0.00009
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.08
	# Ambient occlusion at boat scale: contact shadow in the cockpits, under rubrails and round
	# the fittings, so the boats don't look flat-lit.
	env.ssao_enabled = true
	env.ssao_radius = 0.45
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	# Screen-space reflections put the boats, sails and committee boat in the water.
	env.ssr_enabled = true
	env.ssr_max_steps = 72
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.3
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var az := deg_to_rad(SUN_AZIMUTH)
	var el := deg_to_rad(SUN_ELEVATION)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.25
	sun.light_angular_distance = 0.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	add_child(sun)


# --- Water ------------------------------------------------------------------------------------

func _sdf_params(mat: ShaderMaterial, tex: Texture2D) -> void:
	mat.set_shader_parameter("sdf_tex", tex)
	mat.set_shader_parameter("sdf_origin", lake.sdf_origin)
	mat.set_shader_parameter("sdf_dim", Vector2(lake.sdf_w, lake.sdf_h))
	mat.set_shader_parameter("sdf_cell", lake.sdf_cell)


var _sdf_tex: Texture2D
var waves  # Waves: the GPU wave simulation the water samples
var _wave_t := -1.0
var _wave_wind := 5.0
var _wave_to := Vector2.RIGHT
const WAVE_FETCH := 1200.0  # the fetch the wave spectrum is made for; the shader scales it locally


func _make_water() -> void:
	_sdf_tex = lake.sdf_texture()
	if waves != null:
		waves.free_gpu()
	waves = Waves.new()
	water_mat = ShaderMaterial.new()
	water_mat.shader = preload("res://shaders/water.gdshader")
	_sdf_params(water_mat, _sdf_tex)
	water_mat.set_shader_parameter("foam_noise", _gray_noise(47, 0.02, 4))
	water_mat.set_shader_parameter("fetch_ref", WAVE_FETCH)
	for c in Waves.CASCADES:
		if c < 2:
			water_mat.set_shader_parameter("disp%d" % c, waves.disp_tex[c])
		water_mat.set_shader_parameter("slope%d" % c, waves.slope_tex[c])
	water_mat.set_shader_parameter("tile_len", Vector3(Waves.PATCH[0], Waves.PATCH[1], Waves.PATCH[2]))
	water_mat.set_shader_parameter("tile_rot", Vector3(Waves.ROT[0], Waves.ROT[1], Waves.ROT[2]))
	# A unit grid the shader spreads out around the camera (fine underfoot, coarse far off).
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	pm.subdivide_width = 1023
	pm.subdivide_depth = 1023
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = water_mat
	mi.custom_aabb = AABB(Vector3(-20000.0, -2.0, -20000.0), Vector3(40000.0, 4.0, 40000.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and waves != null:
		waves.free_gpu()


## The water for a moment of the race: `wind_from_deg` and `wind_speed_ms` are the mean wind over
## the lake; the puffs roughen it locally.
func update_water(time: float, wind_from_deg: float, wind_speed_ms: float, puffs: PackedVector4Array) -> void:
	_wind_from = wind_from_deg
	_wind_speed = wind_speed_ms
	var a := deg_to_rad(wind_from_deg)
	var to := -Vector2(sin(a), cos(a))
	# The sea takes a while to build or turn with the wind.
	var dt := time - _wave_t
	if _wave_t < 0.0 or dt < 0.0 or dt > 30.0:
		_wave_wind = wind_speed_ms
		_wave_to = to
	else:
		var k := 1.0 - exp(-dt / 25.0)
		_wave_wind = lerpf(_wave_wind, wind_speed_ms, k)
		_wave_to = _wave_to.slerp(to, k).normalized()
	_wave_t = time
	waves.update(time, clampf(_wave_wind, 0.3, 16.0), _wave_to, WAVE_FETCH)
	water_mat.set_shader_parameter("wave_time", time)
	water_mat.set_shader_parameter("wind_dir", _wave_to)
	water_mat.set_shader_parameter("wind_speed", clampf(_wave_wind, 0.3, 16.0))
	var pa := PackedVector4Array()
	for i in 16:
		pa.append(puffs[i] if i < puffs.size() else Vector4(0.0, 0.0, 1.0, 0.0))
	water_mat.set_shader_parameter("puffs", pa)
	for f in wind_flags:
		if is_instance_valid(f):
			f.rotation = Vector3(0.0, -a - _parent_yaw(f), 0.0)
	for m in flag_mats:
		m.set_shader_parameter("wind", wind_speed_ms)


## Sum of the yaw of a node's ancestors up to this view (they only ever turn about +Y).
func _parent_yaw(n: Node3D) -> float:
	var y := 0.0
	var p := n.get_parent()
	while p != null and p != self:
		if p is Node3D:
			y += (p as Node3D).rotation.y
		p = p.get_parent()
	return y


# --- Land -------------------------------------------------------------------------------------

## Ground height for a signed shore distance: a short bank rising from the water to the fields.
static func land_height(d: float) -> float:
	if d <= 0.0:
		return maxf(d * 0.3, -3.0)
	if d >= BANK_W:
		return LAND_H
	var t := d / BANK_W
	return LAND_H * (1.0 - (1.0 - t) * (1.0 - t))


## Ground height at a world point (on land well away from the lake it is LAND_H).
func ground_at(p: Vector2) -> float:
	return land_height(lake.shore_distance(p))


func _make_land() -> void:
	land_mat = ShaderMaterial.new()
	land_mat.shader = preload("res://shaders/land.gdshader")
	_sdf_params(land_mat, _sdf_tex)
	var w: int = lake.sdf_w
	var h: int = lake.sdf_h
	var cell: float = lake.sdf_cell
	var org: Vector2 = lake.sdf_origin
	var sdf: PackedFloat32Array = lake.sdf
	var hts := PackedFloat32Array()
	hts.resize(w * h)
	for i in w * h:
		hts[i] = land_height(sdf[i])

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var blk := 8
	for bj in range(0, h - 1, blk):
		for bi in range(0, w - 1, blk):
			var i1 := mini(bi + blk, w - 1)
			var j1 := mini(bj + blk, h - 1)
			var dmin := INF
			var dmax := -INF
			for j in range(bj, j1 + 1):
				for i in range(bi, i1 + 1):
					var d := sdf[j * w + i]
					dmin = minf(dmin, d)
					dmax = maxf(dmax, d)
			if dmax < -6.0:
				continue
			if dmin > BANK_W + 0.5:
				var e0 := org.x + bi * cell
				var e1 := org.x + i1 * cell
				var n0 := org.y + bj * cell
				var n1 := org.y + j1 * cell
				_land_quad(verts, norms, Vector3(e0, LAND_H, -n0), Vector3(e1, LAND_H, -n0),
					Vector3(e0, LAND_H, -n1), Vector3(e1, LAND_H, -n1), Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP)
				continue
			for j in range(bj, j1):
				for i in range(bi, i1):
					var k := j * w + i
					if sdf[k] < -5.0 and sdf[k + 1] < -5.0 and sdf[k + w] < -5.0 and sdf[k + w + 1] < -5.0:
						continue
					var e := org.x + i * cell
					var n := org.y + j * cell
					_land_quad(verts, norms,
						Vector3(e, hts[k], -n), Vector3(e + cell, hts[k + 1], -n),
						Vector3(e, hts[k + w], -n - cell), Vector3(e + cell, hts[k + w + 1], -n - cell),
						_grid_normal(hts, w, h, i, j, cell), _grid_normal(hts, w, h, i + 1, j, cell),
						_grid_normal(hts, w, h, i, j + 1, cell), _grid_normal(hts, w, h, i + 1, j + 1, cell))
	# Flat farmland out to the horizon around the distance-field rectangle.
	var fe0 := org.x
	var fe1 := org.x + (w - 1) * cell
	var fn0 := org.y
	var fn1 := org.y + (h - 1) * cell
	var X := LAND_EXTENT
	for r: Rect2 in [Rect2(-X, -X, 2.0 * X, fn0 + X), Rect2(-X, fn1, 2.0 * X, X - fn1),
			Rect2(-X, fn0, fe0 + X, fn1 - fn0), Rect2(fe1, fn0, X - fe1, fn1 - fn0)]:
		_land_quad(verts, norms, Vector3(r.position.x, LAND_H, -r.position.y), Vector3(r.end.x, LAND_H, -r.position.y),
			Vector3(r.position.x, LAND_H, -r.end.y), Vector3(r.end.x, LAND_H, -r.end.y),
			Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Land"
	mi.mesh = mesh
	mi.material_override = land_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Quad from its south-west, south-east, north-west and north-east corners, facing up.
static func _land_quad(verts: PackedVector3Array, norms: PackedVector3Array, sw: Vector3, se: Vector3, nw: Vector3, ne: Vector3,
		n_sw: Vector3, n_se: Vector3, n_nw: Vector3, n_ne: Vector3) -> void:
	verts.append_array([sw, nw, se, se, nw, ne])
	norms.append_array([n_sw, n_nw, n_se, n_se, n_nw, n_ne])


static func _grid_normal(hts: PackedFloat32Array, w: int, h: int, i: int, j: int, cell: float) -> Vector3:
	var il := maxi(i - 1, 0)
	var ir := mini(i + 1, w - 1)
	var jd := maxi(j - 1, 0)
	var ju := mini(j + 1, h - 1)
	var dhe := (hts[j * w + ir] - hts[j * w + il]) / ((ir - il) * cell)
	var dhn := (hts[ju * w + i] - hts[jd * w + i]) / ((ju - jd) * cell)
	return Vector3(-dhe, 1.0, dhn).normalized()


# --- Mountains --------------------------------------------------------------------------------

## Skyline layers of the Front Range as seen from the reservoir, in angular height (degrees
## above the horizon) against compass bearing: rolling foothills, the main range, and the
## Continental Divide with Longs Peak and Mount Meeker to the WNW and the Indian Peaks to the W.
## Each layer is the upper envelope of many overlapping summits plus a little ridged noise.
const MOUNTAIN_LAYERS := [
	{"r": 11000.0, "haze": 0.2, "from": 196.0, "to": 350.0, "base": 0.3, "h": [0.35, 1.0], "w": [3.0, 8.0], "gap": 2.6, "p": 0.0},
	{"r": 14000.0, "haze": 0.33, "from": 200.0, "to": 338.0, "base": 0.7, "h": [0.9, 1.9], "w": [3.0, 7.5], "gap": 1.8, "p": 1.25},
	{"r": 17500.0, "haze": 0.45, "from": 204.0, "to": 330.0, "base": 1.2, "h": [1.6, 2.6], "w": [2.4, 6.0], "gap": 1.6, "p": 1.3},
]
const NAMED_PEAKS := [
	[284.0, 3.4, 2.2, 0.1],     # Longs Peak (flat-topped)
	[281.2, 3.15, 2.0, 0.0],    # Mount Meeker
	[262.6, 2.95, 2.4, 0.0],    # Mount Audubon
	[257.5, 3.0, 2.2, 0.1],     # Arapaho Peaks
	[259.8, 2.8, 1.6, 0.0],     # Navajo and Apache
	[296.0, 2.6, 2.8, 0.0],     # Mummy Range
	[240.0, 2.55, 2.5, 0.0],    # James Peak area
]


## Summit profile over x in -1..1: a rounded hill when p is 0, otherwise a rocky point whose
## flanks steepen with p; `flat` widens the top into a plateau.
static func _peak_shape(x: float, p: float, flat: float) -> float:
	var a := absf(x)
	if a >= 1.0:
		return 0.0
	a = maxf(a - flat, 0.0) / (1.0 - flat)
	if p <= 0.0:
		return 0.5 + 0.5 * cos(PI * a)
	return pow(1.0 - a, p)


func _make_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1873
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/mountains.gdshader")
	mat.set_shader_parameter("haze_color", HAZE)
	mat.set_shader_parameter("snowline", 2.75)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for li in MOUNTAIN_LAYERS.size():
		var L: Dictionary = MOUNTAIN_LAYERS[li]
		var b0: float = L["from"]
		var b1: float = L["to"]
		# Summits: [bearing, height deg, half width deg, flat top fraction].
		var peaks := []
		var b := b0 - 3.0
		while b < b1 + 3.0:
			peaks.append([b, rng.randf_range(L["h"][0], L["h"][1]), rng.randf_range(L["w"][0], L["w"][1]), 0.0])
			b += L["gap"] * rng.randf_range(0.6, 1.4)
		if li == 2:
			peaks.append_array(NAMED_PEAKS)
		if li == 0:
			peaks.append([214.0, 1.35, 3.5, 0.0])   # Boulder foothills behind the Flatirons
		var jag := []
		for _k in 400:
			jag.append(rng.randf())
		var r: float = L["r"]
		var step := 0.06
		var n := int((b1 - b0) / step)
		var smooth := PackedFloat32Array()
		var angs := PackedFloat32Array()
		for i in n + 1:
			var bb := b0 + i * step
			var env_w := smoothstep(b0, b0 + 16.0, bb) * (1.0 - smoothstep(b1 - 22.0, b1, bb))
			var ang: float = L["base"]
			for pk: Array in peaks:
				var w: float = pk[2]
				if absf(bb - pk[0]) < w:
					ang = maxf(ang, pk[1] * _peak_shape((bb - pk[0]) / w, L["p"], pk[3]))
			smooth.append(ang * env_w)
			var rough := 1.0 - absf(2.0 * _fbm1(bb / 0.35 + li * 50.0, jag) - 1.0)
			angs.append(ang * env_w * (0.94 + 0.12 * rough))
		var base := verts.size()
		for i in n + 1:
			var bb := b0 + i * step
			var ang := angs[i]
			var hgt := r * tan(deg_to_rad(ang))
			var br := deg_to_rad(bb)
			var dir := Vector3(sin(br), 0.0, -cos(br))
			# Flanks climbing toward the north face the south-west sun a little.
			var slope := (smooth[mini(i + 4, n)] - smooth[maxi(i - 4, 0)]) / (8.0 * step)
			var lit := clampf(0.5 + slope * 1.5, 0.0, 1.0)
			var snow_ok := 1.0 if li == 2 else 0.0
			verts.append(dir * r + Vector3(0.0, -400.0, 0.0))
			verts.append(dir * r + Vector3(0.0, hgt, 0.0))
			cols.append(Color(0.0, L["haze"], lit, snow_ok))
			cols.append(Color(1.0, L["haze"], lit, snow_ok))
			uvs.append(Vector2(bb, -2.0))
			uvs.append(Vector2(bb, ang))
			if i > 0:
				var k := base + (i - 1) * 2
				idx.append_array([k, k + 1, k + 2, k + 2, k + 1, k + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "FrontRange"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2000.0
	add_child(mi)


static func _fbm1(x: float, noise: Array) -> float:
	var s := 0.0
	var amp := 0.5
	var f := 1.0
	for o in 4:
		var xf := x * f + o * 17.0
		var i := int(floorf(xf))
		var t := xf - floorf(xf)
		t = t * t * (3.0 - 2.0 * t)
		var a: float = noise[posmod(i, noise.size())]
		var c: float = noise[posmod(i + 1, noise.size())]
		s += amp * lerpf(a, c, t)
		amp *= 0.5
		f *= 2.1
	return s / 0.9375


# --- Farms, trees, the club -------------------------------------------------------------------

func _plan_farms() -> void:
	farm_positions.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var grid := 804.67
	var tries := 0
	while farm_positions.size() < 22 and tries < 500:
		tries += 1
		var i := rng.randi_range(-8, 8)
		var j := rng.randi_range(-8, 8)
		var along := rng.randf_range(-300.0, 300.0)
		var side := 70.0 if rng.randf() < 0.5 else -70.0
		var p := Vector2(i * grid + side, j * grid + along) if rng.randf() < 0.5 else Vector2(i * grid + along, j * grid + side)
		if p.length() < 1500.0 or p.length() > 7200.0 or lake.shore_distance(p) < 350.0:
			continue
		var ok := true
		for q in farm_positions:
			if q.distance_to(p) < 700.0:
				ok = false
				break
		if ok:
			farm_positions.append(p)


## A gabled building on flat ground at `c` (east, north), `size` = (east-west, north-south).
static func _building(k: Kit, c: Vector2, size: Vector2, wall_h: float, roof_h: float, ridge_ew: bool,
		wall: Color, roof: Color, y0 := LAND_H) -> void:
	var o := Vector3(c.x, y0, -c.y)
	k.box(o + Vector3(0, wall_h * 0.5, 0), Vector3(size.x, wall_h, size.y), wall)
	var ov := 0.4
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var top := wall_h + roof_h
	if ridge_ew:
		var r0 := o + Vector3(-hx - ov, top, 0)
		var r1 := o + Vector3(hx + ov, top, 0)
		for s: float in [-1.0, 1.0]:
			var e0 := o + Vector3(-hx - ov, wall_h - 0.15, s * (hz + ov))
			var e1 := o + Vector3(hx + ov, wall_h - 0.15, s * (hz + ov))
			k.quad(r0, r1, e1, e0, roof, Vector3(0, 1, s))
			k.tri(o + Vector3(s * hx, wall_h, -hz), o + Vector3(s * hx, wall_h, hz), o + Vector3(s * hx, top, 0), wall, Vector3(s, 0, 0))
	else:
		var r0 := o + Vector3(0, top, -hz - ov)
		var r1 := o + Vector3(0, top, hz + ov)
		for s: float in [-1.0, 1.0]:
			var e0 := o + Vector3(s * (hx + ov), wall_h - 0.15, -hz - ov)
			var e1 := o + Vector3(s * (hx + ov), wall_h - 0.15, hz + ov)
			k.quad(r0, r1, e1, e0, roof, Vector3(s, 1, 0))
			k.tri(o + Vector3(-hx, wall_h, s * hz), o + Vector3(hx, wall_h, s * hz), o + Vector3(0, top, s * hz), wall, Vector3(0, 0, s))


static func _tree_mesh() -> ArrayMesh:
	var k := Kit.new()
	k.cyl(Vector3(0, -0.3, 0), Vector3(0, 3.4, 0), 0.38, Color(0.36, 0.29, 0.22), 6, 0.2)
	var leaf := Color(0.36, 0.47, 0.22)
	var lumps := [[Vector3(0, 6.0, 0), 3.2], [Vector3(1.4, 5.1, 0.7), 2.3], [Vector3(-1.2, 5.4, -0.9), 2.4],
		[Vector3(0.3, 7.7, 0.2), 2.1], [Vector3(-0.6, 4.6, 1.3), 1.9]]
	for l: Array in lumps:
		var sm := SphereMesh.new()
		var r: float = l[1]
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 7
		sm.rings = 4
		k.prim(sm, Transform3D(Basis.IDENTITY, l[0]), leaf)
	var mat := BoatView.vcol_material(0.92)
	return k.commit(mat)


func _make_farms_and_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var k := Kit.new()
	var trees: Array[Transform3D] = []
	var tcols: Array[Color] = []
	var walls := [Color(0.93, 0.91, 0.86), Color(0.9, 0.84, 0.7), Color(0.62, 0.67, 0.72), Color(0.86, 0.8, 0.55)]
	var roofs := [Color(0.27, 0.24, 0.22), Color(0.42, 0.26, 0.2), Color(0.35, 0.38, 0.42)]
	var add_tree := func(p: Vector2, sc: float) -> void:
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * rng.randf_range(0.85, 1.15), sc, sc * rng.randf_range(0.85, 1.15)))
		trees.append(Transform3D(b, Vector3(p.x, ground_at(p), -p.y)))
		var g := rng.randf_range(0.8, 1.15)
		tcols.append(Color(g * rng.randf_range(0.9, 1.1), g, g * rng.randf_range(0.85, 1.05)))
	for f in farm_positions:
		_building(k, f + Vector2(-25, 18), Vector2(13, 9), 3.0, 2.0, true, walls[rng.randi() % walls.size()], roofs[rng.randi() % roofs.size()])
		if rng.randf() < 0.8:
			_building(k, f + Vector2(18, 22), Vector2(13, 20), 5.5, 3.5, false, Color(0.58, 0.14, 0.1), Color(0.55, 0.57, 0.6))
		if rng.randf() < 0.7:
			_building(k, f + Vector2(22, -22), Vector2(26, 13), 5.0, 1.3, true, Color(0.63, 0.65, 0.67), Color(0.72, 0.74, 0.76))
		for b in rng.randi_range(0, 4):
			var bp := f + Vector2(-28 + b * 9.5, -26)
			var o := Vector3(bp.x, LAND_H, -bp.y)
			k.cyl(o, o + Vector3(0, 6.5, 0), 3.6, Color(0.76, 0.78, 0.8), 14)
			k.cyl(o + Vector3(0, 6.5, 0), o + Vector3(0, 8.6, 0), 3.8, Color(0.7, 0.72, 0.75), 14, 0.3)
		# Windbreak rows on the north and west sides, a few shade trees by the house.
		for t in 15:
			add_tree.call(f + Vector2(-52 + t * 7.2, 58 + rng.randf_range(-1.5, 1.5)), rng.randf_range(0.65, 0.9))
		if rng.randf() < 0.7:
			for t in 12:
				add_tree.call(f + Vector2(-60 + rng.randf_range(-1.5, 1.5), -40 + t * 8.0), rng.randf_range(0.65, 0.9))
		for _k in rng.randi_range(2, 5):
			add_tree.call(f + Vector2(rng.randf_range(-45, -5), rng.randf_range(0, 40)), rng.randf_range(0.9, 1.4))
	# Cottonwood groves along parts of the shore.
	var shore: PackedVector2Array = lake.shore
	var club := lake.dock as Vector2
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.004
	for i in shore.size():
		var a := shore[i]
		var b := shore[(i + 1) % shore.size()]
		var seg := a.distance_to(b)
		var steps := int(seg / 14.0)
		for s in steps:
			var p := a.lerp(b, (s + 0.5) / maxf(steps, 1))
			if noise.get_noise_2dv(p) < 0.12 or p.distance_to(club) < 110.0:
				continue
			var n := _shore_normal(p)
			for _k in rng.randi_range(1, 3):
				var q := p + n * rng.randf_range(16.0, 55.0) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
				var d: float = lake.shore_distance(q)
				if d > 12.0 and d < 70.0:
					add_tree.call(q, rng.randf_range(1.0, 1.6))
	# A few tree lines along county roads.
	for _k in 10:
		var gi := rng.randi_range(-6, 6)
		var gj := rng.randi_range(-6, 6)
		var ew := rng.randf() < 0.5
		var start := Vector2(gi * 804.67, gj * 804.67)
		for t in 30:
			var off := t * 13.0 + rng.randf_range(-2, 2)
			var p := start + (Vector2(off, 13.0) if ew else Vector2(13.0, off))
			if lake.shore_distance(p) > 80.0 and p.length() < 7500.0:
				add_tree.call(p, rng.randf_range(0.8, 1.3))
	# Shade trees round the clubhouse.
	for _k in 7:
		var p: Vector2 = _club_point(Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-60, -30)))
		if lake.shore_distance(p) > 15.0:
			add_tree.call(p, rng.randf_range(1.0, 1.4))

	var mi := MeshInstance3D.new()
	mi.name = "Farms"
	mi.mesh = k.commit(BoatView.vcol_material(0.8))
	add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tree_mesh()
	mm.instance_count = trees.size()
	for i in trees.size():
		mm.set_instance_transform(i, trees[i])
		mm.set_instance_color(i, tcols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.multimesh = mm
	add_child(mmi)
	land_mat.set_shader_parameter("farm_pos", PackedVector2Array(farm_positions))
	land_mat.set_shader_parameter("farm_count", farm_positions.size())


## Unit vector pointing inland (up the distance field) at a point near the shore.
func _shore_normal(p: Vector2) -> Vector2:
	var e := 3.0
	var g := Vector2(lake.shore_distance(p + Vector2(e, 0)) - lake.shore_distance(p - Vector2(e, 0)),
		lake.shore_distance(p + Vector2(0, e)) - lake.shore_distance(p - Vector2(0, e)))
	return g.normalized() if g.length() > 1e-6 else Vector2.UP


## World (east, north) of a point in the club's local frame (-Z inland, +Z out over the water).
func _club_point(local: Vector3) -> Vector2:
	var inland := _dock_dir
	var right := Vector2(inland.y, -inland.x)
	return (lake.dock as Vector2) + right * local.x - inland * local.z


func _make_club() -> void:
	_dock_dir = _shore_normal(lake.dock)
	var club := Node3D.new()
	club.name = "SailingClub"
	club.position = Lake.to_3d(lake.dock)
	club.rotation.y = -atan2(_dock_dir.x, _dock_dir.y)
	add_child(club)
	var k := Kit.new()
	var wood := Color(0.55, 0.42, 0.3)
	var grey_wood := Color(0.62, 0.58, 0.52)
	# Gangway down the bank to a floating dock with a T-head.
	var gy0 := LAND_H + 0.1
	k.quad(Vector3(-0.8, gy0, -10), Vector3(0.8, gy0, -10), Vector3(0.8, 0.42, 3), Vector3(-0.8, 0.42, 3), grey_wood, Vector3.UP)
	k.box(Vector3(0, 0.3, 18), Vector3(2.4, 0.2, 30), grey_wood)
	k.box(Vector3(0, 0.3, 34.2), Vector3(14, 0.2, 2.4), grey_wood)
	k.box(Vector3(0, 0.08, 18), Vector3(2.0, 0.3, 29.5), Color(0.12, 0.12, 0.13))
	k.box(Vector3(0, 0.08, 34.2), Vector3(13.6, 0.3, 2.0), Color(0.12, 0.12, 0.13))
	for z: float in [4.0, 12.0, 20.0, 28.0]:
		for s: float in [-1.0, 1.0]:
			k.cyl(Vector3(s * 1.35, -1.0, z), Vector3(s * 1.35, 1.3, z), 0.12, wood, 7, -1.0, true)
	for s: float in [-1.0, 1.0]:
		k.cyl(Vector3(s * 7.2, -1.0, 34.2), Vector3(s * 7.2, 1.3, 34.2), 0.12, wood, 7, -1.0, true)
	# Clubhouse with a lake-side deck.
	var y := LAND_H
	var bz := -45.0
	k.box(Vector3(8, y + 1.6, bz), Vector3(14, 3.2, 9), Color(0.8, 0.76, 0.66))
	for s: float in [-1.0, 1.0]:
		k.quad(Vector3(-0.4, y + 3.05, bz + s * 4.9), Vector3(16.4, y + 3.05, bz + s * 4.9),
			Vector3(16.4, y + 4.8, bz), Vector3(-0.4, y + 4.8, bz), Color(0.22, 0.33, 0.28), Vector3(0, 1, s))
		k.tri(Vector3(8 + s * 7, y + 3.2, bz - 4.5), Vector3(8 + s * 7, y + 3.2, bz + 4.5), Vector3(8 + s * 7, y + 4.8, bz),
			Color(0.8, 0.76, 0.66), Vector3(s, 0, 0))
	for wx: float in [2.5, 5.5, 10.5, 13.5]:
		k.box(Vector3(wx, y + 1.7, bz + 4.52), Vector3(1.5, 1.1, 0.06), Color(0.15, 0.2, 0.25))
	k.box(Vector3(8, y + 1.05, bz + 4.52), Vector3(1.0, 2.1, 0.06), Color(0.35, 0.2, 0.12))
	k.box(Vector3(8, y + 0.35, bz + 6.2), Vector3(14, 0.2, 3.4), wood)
	for px: float in [1.2, 4.6, 8.0, 11.4, 14.8]:
		k.box(Vector3(px, y + 0.95, bz + 7.8), Vector3(0.1, 1.0, 0.1), wood)
	k.box(Vector3(8, y + 1.42, bz + 7.8), Vector3(13.8, 0.08, 0.08), wood)
	# Boat shed and a rack of dinghies on dollies.
	k.box(Vector3(-16, y + 1.5, -40), Vector3(8, 3.0, 6), Color(0.72, 0.7, 0.66))
	k.box(Vector3(-16, y + 3.1, -40), Vector3(8.6, 0.2, 6.6), Color(0.35, 0.37, 0.4))
	for b in 6:
		var bx := -10.0 + b * 2.2
		var hc: Color = [Color(0.85, 0.85, 0.82), Color(0.2, 0.35, 0.7), Color(0.75, 0.15, 0.12), Color(0.9, 0.9, 0.88)][b % 4]
		k.box(Vector3(bx, y + 0.75, -58), Vector3(1.4, 0.5, 4.6), hc)
		k.box(Vector3(bx, y + 1.02, -58), Vector3(1.3, 0.05, 4.4), Color(0.93, 0.93, 0.9))
		k.box(Vector3(bx, y + 0.3, -58), Vector3(1.0, 0.4, 3.0), Color(0.25, 0.25, 0.25))
	# Cars on the gravel lot.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for c in 7:
		var cx := -26.0 + c * 5.5
		var col: Color = [Color(0.8, 0.8, 0.82), Color(0.15, 0.15, 0.17), Color(0.55, 0.1, 0.1), Color(0.2, 0.3, 0.5), Color(0.9, 0.9, 0.9)][rng.randi() % 5]
		var cz := -78.0 + rng.randf_range(-0.5, 0.5)
		k.box(Vector3(cx, y + 0.65, cz), Vector3(1.85, 0.75, 4.6), col)
		k.box(Vector3(cx, y + 1.3, cz + 0.2), Vector3(1.65, 0.6, 2.5), Color(0.18, 0.22, 0.27))
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(BoatView.vcol_material(0.75))
	club.add_child(mi)
	var club_sign := Label3D.new()
	club_sign.text = "UNION SAILING CLUB"
	club_sign.font_size = 64
	club_sign.pixel_size = 0.006
	club_sign.modulate = Color(0.1, 0.18, 0.3)
	club_sign.position = Vector3(8, y + 2.75, bz + 4.56)
	club_sign.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	club.add_child(club_sign)
	# Flagpole with the Stars and Stripes, streaming downwind.
	var pole := MeshInstance3D.new()
	var pk := Kit.new()
	pk.cyl(Vector3(-4, y, -26), Vector3(-4, y + 9.0, -26), 0.07, Color(0.85, 0.86, 0.88), 8, 0.04, true)
	pole.mesh = pk.commit(BoatView.vcol_material(0.4))
	club.add_child(pole)
	_club_flag = _make_flag("USA", 1.5, 0.95)
	_club_flag.position = Vector3(-4, y + 8.9, -26)
	club.add_child(_club_flag)
	wind_flags.append(_club_flag)
	# Gravel lot and lawn in the land shader.
	var right := Vector2(_dock_dir.y, -_dock_dir.x)
	land_mat.set_shader_parameter("lot_angle", atan2(right.y, right.x))
	var lot_c := _club_point(Vector3(-8, 0, -76))
	land_mat.set_shader_parameter("lot_rect", Vector4(lot_c.x, lot_c.y, 30.0, 14.0))
	var lawn_c := _club_point(Vector3(4, 0, -36))
	land_mat.set_shader_parameter("lawn_rect", Vector4(lawn_c.x, lawn_c.y, 30.0, 26.0))


# --- Marks ------------------------------------------------------------------------------------

func _make_marks() -> void:
	var k := Kit.new()
	var white := Color(0.95, 0.95, 0.93)
	var orange := Color(1.0, 0.4, 0.08)
	var bands := [[-0.4, 0.12, white], [0.12, 0.3, orange], [0.3, 0.5, white], [0.5, 0.68, orange], [0.68, 0.85, white]]
	for b: Array in bands:
		k.cyl(Vector3(0, b[0], 0), Vector3(0, b[1], 0), 0.45, b[2], 18)
	var dome := SphereMesh.new()
	dome.radius = 0.45
	dome.height = 0.9
	dome.radial_segments = 18
	dome.rings = 8
	dome.is_hemisphere = true
	k.prim(dome, Transform3D(Basis.from_scale(Vector3(1, 0.38, 1)), Vector3(0, 0.85, 0)), white)
	k.cyl(Vector3(0, 0.99, 0), Vector3(0, 1.12, 0), 0.03, Color(0.3, 0.3, 0.3), 6)
	var mesh := k.commit(BoatView.vcol_material(0.35))
	for id: String in lake.marks:
		var m := MeshInstance3D.new()
		m.name = "Mark" + id
		m.mesh = mesh
		m.position = Lake.to_3d(lake.marks[id])
		add_child(m)
		marks[id] = m
		var l := Label3D.new()
		l.text = id
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.0008
		l.font_size = 26
		l.outline_size = 8
		l.modulate = Color(1.0, 0.75, 0.45, 0.85)
		l.outline_modulate = Color(0, 0, 0, 0.55)
		l.no_depth_test = true
		l.position = Vector3(0, 2.4, 0)
		m.add_child(l)
		mark_labels[id] = l


func set_mark_labels_visible(on: bool) -> void:
	_mark_labels_on = on
	for id in mark_labels:
		mark_labels[id].visible = on and id != highlight_id


func _make_highlight() -> void:
	highlight = Node3D.new()
	highlight.name = "Highlight"
	highlight.visible = false
	add_child(highlight)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.15, 0.75)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cone := CylinderMesh.new()
	cone.top_radius = 0.9
	cone.bottom_radius = 0.0
	cone.height = 1.5
	cone.radial_segments = 4
	cone.material = mat
	var ci := MeshInstance3D.new()
	ci.mesh = cone
	ci.position = Vector3(0, 4.6, 0)
	ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.add_child(ci)
	highlight_label = Label3D.new()
	highlight_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	highlight_label.fixed_size = true
	highlight_label.pixel_size = 0.0009
	highlight_label.font_size = 34
	highlight_label.outline_size = 10
	highlight_label.modulate = Color(1.0, 0.9, 0.3)
	highlight_label.outline_modulate = Color(0, 0, 0, 0.7)
	highlight_label.no_depth_test = true
	highlight_label.position = Vector3(0, 6.2, 0)
	highlight.add_child(highlight_label)


# --- Flags ------------------------------------------------------------------------------------

@warning_ignore("integer_division")
func _flag_texture(key: String) -> ImageTexture:
	if _flag_tex_cache.has(key):
		return _flag_tex_cache[key]
	var w := 96
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var white := Color(0.97, 0.97, 0.95)
	var blue := Color(0.02, 0.2, 0.6)
	var red := Color(0.82, 0.06, 0.1)
	var yellow := Color(1.0, 0.84, 0.05)
	var black := Color(0.04, 0.04, 0.04)
	match key:
		"L":
			img.fill(black)
			img.fill_rect(Rect2i(0, 0, w / 2, h / 2), yellow)
			img.fill_rect(Rect2i(w / 2, h / 2, w / 2, h / 2), yellow)
		"X":
			img.fill(white)
			img.fill_rect(Rect2i(w / 2 - 7, 0, 14, h), blue)
			img.fill_rect(Rect2i(0, h / 2 - 7, w, 14), blue)
		"S":
			img.fill(white)
			img.fill_rect(Rect2i(w / 2 - 16, h / 2 - 16, 32, 32), blue)
		"C":
			var bands := [blue, white, red, white, blue]
			for i in 5:
				img.fill_rect(Rect2i(0, i * h / 5, w, h / 5 + 1), bands[i])
		"AP":
			img.fill(Color(0, 0, 0, 0))
			for x in w:
				var stripe: Color = red if (x * 5 / w) % 2 == 0 else white
				var half := (h * 0.5) * (1.0 - 0.72 * float(x) / w)
				for y in h:
					if absf(y + 0.5 - h * 0.5) <= half:
						img.set_pixel(x, y, stripe)
		"PORTSMOUTH":
			img.fill(yellow)
		"LMS":
			img.fill(Color(0.08, 0.55, 0.2))
		"ORANGE":
			img.fill(Color(1.0, 0.42, 0.04))
		"USA":
			for i in 13:
				img.fill_rect(Rect2i(0, i * h / 13, w, h / 13 + 1), red if i % 2 == 0 else white)
			img.fill_rect(Rect2i(0, 0, 40, 35), blue)
			for sy in 5:
				for sx in 6:
					img.fill_rect(Rect2i(3 + sx * 6 + (sy % 2) * 3, 3 + sy * 6, 2, 2), white)
		_:
			img.fill(white)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_flag_tex_cache[key] = tex
	return tex


func _flag_mesh(w: float, h: float) -> ArrayMesh:
	var key := "%.2fx%.2f" % [w, h]
	if _flag_mesh_cache.has(key):
		return _flag_mesh_cache[key]
	var nu := 12
	var nv := 4
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in nv + 1:
		for i in nu + 1:
			var uv := Vector2(float(i) / nu, float(j) / nv)
			verts.append(Vector3(0.0, -uv.y * h, uv.x * w))
			uvs.append(uv)
			norms.append(Vector3.RIGHT)
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			idx.append_array([a, a + 1, a + nu + 1, a + 1, a + nu + 2, a + nu + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_flag_mesh_cache[key] = m
	return m


## A waving flag: origin at the top of the hoist, flying toward local +Z.
func _make_flag(key: String, w: float, h: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Flag_" + key
	var mi := MeshInstance3D.new()
	mi.mesh = _flag_mesh(w, h)
	mi.custom_aabb = AABB(Vector3(-w, -h * 1.5, -w * 0.5), Vector3(w * 2.0, h * 2.0, w * 2.0))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flag.gdshader")
	mat.set_shader_parameter("tex", _flag_texture(key))
	mat.set_shader_parameter("fly_len", w)
	mat.set_shader_parameter("phase", randf() * TAU)
	mat.set_shader_parameter("wind", _wind_speed)
	mi.material_override = mat
	flag_mats.append(mat)
	root.add_child(mi)
	return root


var _rc_flag_nodes: Array[Node3D] = []


func update_flags(flags: Dictionary, course_text: String) -> void:
	if rc_flag_root == null or not is_instance_valid(rc_flag_root):
		return
	for n in _rc_flag_nodes:
		var mi := n.get_child(0) as MeshInstance3D
		flag_mats.erase(mi.material_override)
		n.queue_free()
	_rc_flag_nodes.clear()
	var keys: Array = []
	for k: String in FLAG_ORDER:
		if flags.get(k, false):
			keys.append(k)
	for k in flags:
		if flags[k] and not keys.has(k):
			keys.append(k)
	var fw := 0.75
	var fh := 0.5
	for i in keys.size():
		var f := _make_flag(str(keys[i]), fw, fh)
		f.position = Vector3(0.0, -i * (fh + 0.14), 0.05)
		rc_flag_root.add_child(f)
		_rc_flag_nodes.append(f)
	var txt := "  ".join(course_text.split(" ", false))
	for b in rc_boards:
		b.text = txt
		# Fit the widest text that stays on the 2.3 m board, capped at ~0.3 m tall digits.
		var font: Font = b.font if b.font != null else ThemeDB.fallback_font
		var wpx := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, b.font_size).x
		b.pixel_size = minf(0.0034, 2.1 / maxf(wpx, 1.0))


# --- Race committee boat, pin and line ---------------------------------------------------------

func set_race(race_ref) -> void:
	for n: Node3D in [rc_boat, pin_node, line_mi]:
		if n != null and is_instance_valid(n):
			wind_flags = wind_flags.filter(func(f): return is_instance_valid(f) and not n.is_ancestor_of(f))
			n.queue_free()
	rc_boat = null
	pin_node = null
	line_mi = null
	rc_flag_root = null
	rc_boards.clear()
	_rc_flag_nodes.clear()
	race = race_ref
	if race == null:
		if highlight_id in ["PIN", "G", "F", "LINE"]:
			highlight_mark("")
		return
	_make_rc_boat()
	_make_pin()
	_make_line()
	update_flags(race.flags, race.course_text)
	var a := deg_to_rad(_wind_from)
	for f in wind_flags:
		f.rotation = Vector3(0.0, -a - _parent_yaw(f), 0.0)
	if highlight_id != "":
		highlight_mark(highlight_id)


func _make_rc_boat() -> void:
	rc_boat = Node3D.new()
	rc_boat.name = "RCBoat"
	add_child(rc_boat)
	rc_boat.position = Lake.to_3d(race.rc_pos)
	rc_boat.rotation.y = -float(race.rc_heading)
	var k := Kit.new()
	var alu := Color(0.8, 0.82, 0.85)
	var white := Color(0.94, 0.94, 0.92)
	var navy := Color(0.14, 0.18, 0.32)
	var half_l: float = race.RC_LENGTH * 0.5
	for s: float in [-1.0, 1.0]:
		var x := s * 0.9
		k.cyl(Vector3(x, 0.05, half_l - 0.25), Vector3(x, 0.05, -half_l + 0.9), 0.32, alu, 14, -1.0, true)
		k.cyl(Vector3(x, 0.05, -half_l + 0.9), Vector3(x, 0.24, -half_l + 0.05), 0.32, alu, 14, 0.07)
		k.box(Vector3(x, 0.33, 0.1), Vector3(0.14, 0.2, 6.2), Color(0.3, 0.3, 0.32))
	k.box(Vector3(0, 0.44, 0.15), Vector3(2.5, 0.24, 6.6), white)
	k.box(Vector3(0, 0.575, 0.15), Vector3(2.4, 0.03, 6.45), Color(0.42, 0.45, 0.48))
	var deck := 0.59
	var fence_h := 0.75
	var fy := deck + fence_h * 0.5
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 1.2, fy, 0.05), Vector3(0.04, fence_h, 6.0), white)
		k.box(Vector3(s * 1.225, deck + 0.2, 0.05), Vector3(0.012, 0.14, 6.0), navy)
		k.cyl(Vector3(s * 1.2, deck + fence_h, -2.95), Vector3(s * 1.2, deck + fence_h, 3.05), 0.025, alu, 6)
		k.box(Vector3(s * 0.83, fy, -2.95), Vector3(0.74, fence_h, 0.04), white)
	k.box(Vector3(-0.45, fy, 3.05), Vector3(1.5, fence_h, 0.04), white)
	k.box(Vector3(-0.45, deck + 0.2, 3.075), Vector3(1.5, 0.14, 0.012), navy)
	# Console, windshield, seats, bimini and outboard.
	k.box(Vector3(0.55, deck + 0.5, -1.3), Vector3(0.8, 1.0, 0.6), white)
	k.box(Vector3(0.55, deck + 1.18, -1.52), Vector3(0.8, 0.36, 0.04), Color(0.16, 0.2, 0.25), Basis(Vector3.RIGHT, -0.4))
	k.box(Vector3(-0.85, deck + 0.22, 0.6), Vector3(0.5, 0.45, 2.2), navy)
	k.box(Vector3(0.0, deck + 0.22, 2.65), Vector3(2.2, 0.45, 0.55), navy)
	for px: float in [-1.0, 1.0]:
		for pz: float in [-1.6, 0.4]:
			k.cyl(Vector3(px * 1.05, deck, pz), Vector3(px * 0.98, 2.3, pz), 0.02, alu, 5)
	k.box(Vector3(0, 2.32, -0.6), Vector3(2.1, 0.06, 2.3), navy)
	k.box(Vector3(0, 0.05, half_l + 0.3), Vector3(0.12, 0.9, 0.26), Color(0.16, 0.16, 0.17))
	k.box(Vector3(0, -0.22, half_l + 0.32), Vector3(0.3, 0.025, 0.4), Color(0.16, 0.16, 0.17))
	k.box(Vector3(0, 0.78, half_l + 0.33), Vector3(0.42, 0.55, 0.62), Color(0.09, 0.09, 0.1))
	k.box(Vector3(0, 0.66, half_l + 0.33), Vector3(0.43, 0.05, 0.63), Color(0.85, 0.85, 0.85))
	# Signal mast with a yardarm; line flag pole on the port side where the line runs.
	var mast := Vector3(0.0, deck, 1.9)
	k.cyl(mast, mast + Vector3(0, 5.2, 0), 0.045, alu, 8, 0.03, true)
	k.cyl(mast + Vector3(-0.8, 4.75, 0), mast + Vector3(0.8, 4.75, 0), 0.025, alu, 6)
	var pole := Vector3(-1.24, deck, 1.0)
	k.cyl(pole, pole + Vector3(0, 3.4, 0), 0.03, white, 6, -1.0, true)
	# Course boards: one over the transom, one on each side.
	var bh := 1.95
	k.box(Vector3(0, bh, half_l - 0.4), Vector3(2.3, 0.85, 0.04), white)
	k.box(Vector3(0, bh, half_l - 0.44), Vector3(2.36, 0.91, 0.02), Color(0.15, 0.15, 0.15))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 1.08, bh + 0.35, -0.6), Vector3(0.04, 0.85, 2.1), white)
		k.box(Vector3(s * 1.06, bh + 0.35, -0.6), Vector3(0.02, 0.91, 2.16), Color(0.15, 0.15, 0.15))
	# Two race officers.
	for pz: Array in [[Vector3(0.5, deck, -0.75), Color(0.95, 0.45, 0.1)], [Vector3(-0.5, deck, 1.55), Color(0.9, 0.15, 0.12)]]:
		var o: Vector3 = pz[0]
		k.cyl(o + Vector3(-0.1, 0, 0), o + Vector3(-0.1, 0.85, 0), 0.07, navy, 6)
		k.cyl(o + Vector3(0.1, 0, 0), o + Vector3(0.1, 0.85, 0), 0.07, navy, 6)
		var cap := CapsuleMesh.new()
		cap.radius = 0.17
		cap.height = 0.7
		k.prim(cap, Transform3D(Basis.from_scale(Vector3(1.2, 1.0, 0.8)), o + Vector3(0, 1.15, 0)), pz[1])
		var hs := SphereMesh.new()
		hs.radius = 0.11
		hs.height = 0.22
		k.prim(hs, Transform3D(Basis.IDENTITY, o + Vector3(0, 1.6, 0)), Color(0.9, 0.72, 0.58))
		k.cyl(o + Vector3(0, 1.66, 0), o + Vector3(0, 1.69, 0), 0.2, Color(0.9, 0.88, 0.8), 10, -1.0, true)
		k.cyl(o + Vector3(0, 1.69, 0), o + Vector3(0, 1.78, 0), 0.11, Color(0.9, 0.88, 0.8), 10, -1.0, true)
	# Mooring line from the bow cleat to mark 1.
	var bow := Vector3(0, deck - 0.02, -half_l + 0.1)
	var m1: Vector3 = rc_boat.transform.affine_inverse() * (Lake.to_3d(lake.marks["1"]) + Vector3(0, 0.3, 0))
	var prev := bow
	for i in range(1, 13):
		var t := i / 12.0
		var p := bow.lerp(m1, t) - Vector3(0, 0.55 * 4.0 * t * (1.0 - t), 0)
		k.cyl(prev, p, 0.014, Color(0.95, 0.8, 0.2), 5)
		prev = p
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(BoatView.vcol_material(0.5))
	rc_boat.add_child(mi)

	rc_flag_root = Node3D.new()
	rc_flag_root.name = "SignalFlags"
	rc_flag_root.position = mast + Vector3(0, 4.6, 0)
	rc_boat.add_child(rc_flag_root)
	wind_flags.append(rc_flag_root)
	var lf := _make_flag("ORANGE", 0.9, 0.6)
	lf.position = pole + Vector3(0, 3.35, 0)
	rc_boat.add_child(lf)
	wind_flags.append(lf)

	for spec: Array in [[Vector3(0, bh, half_l - 0.37), 0.0], [Vector3(1.11, bh + 0.35, -0.6), PI * 0.5],
			[Vector3(-1.11, bh + 0.35, -0.6), -PI * 0.5]]:
		var l := Label3D.new()
		l.font_size = 128
		l.pixel_size = 0.0034
		l.modulate = Color(0.02, 0.02, 0.02)
		l.outline_size = 0
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		l.position = spec[0]
		l.rotation.y = spec[1]
		rc_boat.add_child(l)
		rc_boards.append(l)


## World position of the committee boat end of the line (its orange flag pole).
func rc_line_end() -> Vector3:
	if rc_boat == null:
		return Vector3.ZERO
	return rc_boat.transform * Vector3(-1.24, 0.0, 1.0)


func _make_pin() -> void:
	pin_node = Node3D.new()
	pin_node.name = "Pin"
	add_child(pin_node)
	pin_node.position = Lake.to_3d(race.pin)
	var k := Kit.new()
	var orange := Color(1.0, 0.42, 0.05)
	k.cyl(Vector3(0, -0.35, 0), Vector3(0, 0.95, 0), 0.55, orange, 18)
	var dome := SphereMesh.new()
	dome.radius = 0.55
	dome.height = 1.1
	dome.is_hemisphere = true
	dome.radial_segments = 18
	dome.rings = 8
	k.prim(dome, Transform3D(Basis.from_scale(Vector3(1, 0.45, 1)), Vector3(0, 0.95, 0)), orange)
	k.cyl(Vector3(0, 0.25, 0), Vector3(0, 0.4, 0), 0.56, Color(0.1, 0.1, 0.1), 18)
	k.cyl(Vector3(0, 1.1, 0), Vector3(0, 2.7, 0), 0.025, Color(0.2, 0.2, 0.2), 5, -1.0, true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(BoatView.vcol_material(0.45))
	pin_node.add_child(mi)
	var f := _make_flag("ORANGE", 0.6, 0.42)
	f.position = Vector3(0, 2.68, 0)
	pin_node.add_child(f)
	wind_flags.append(f)


func _make_line() -> void:
	var a := rc_line_end()
	var b := Lake.to_3d(race.pin)
	var d := b - a
	d.y = 0.0
	var line_len := d.length()
	var side := Vector3(-d.z, 0, d.x).normalized() * 0.12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := Vector3(0, 0.07, 0)
	var pts := [a + y - side, a + y + side, b + y + side, b + y - side]
	var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(line_len / 3.0, 1), Vector2(line_len / 3.0, 0)]
	for i: int in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
		st.set_uv(uvs[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[i])
	var img := Image.create(32, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	img.fill_rect(Rect2i(0, 0, 18, 2), Color(1.0, 1.0, 1.0, 0.75))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.albedo_color = Color(1.0, 0.95, 0.7, 0.8)
	mat.texture_repeat = true
	mat.no_depth_test = false
	line_mi = MeshInstance3D.new()
	line_mi.name = "StartLine"
	line_mi.mesh = st.commit()
	line_mi.material_override = mat
	line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line_mi.visible = _line_on
	add_child(line_mi)


func set_line_visible(on: bool) -> void:
	_line_on = on
	if line_mi != null and is_instance_valid(line_mi):
		line_mi.visible = on


func highlight_mark(id: String) -> void:
	highlight_id = id
	for k in mark_labels:
		mark_labels[k].visible = _mark_labels_on and k != id
	if id == "" or highlight == null:
		if highlight != null:
			highlight.visible = false
		return
	var p: Vector2
	var text := ""
	if lake.marks.has(id):
		p = lake.marks[id]
		text = "Mark " + id
	elif race != null and id == "PIN":
		p = race.pin
		text = "Pin"
	elif race != null and id in ["G", "F", "LINE"]:
		p = race.line_center()
		text = "Finish" if id == "F" else ("Gate" if id == "G" else "Line")
	else:
		highlight.visible = false
		return
	highlight.position = Lake.to_3d(p)
	highlight_label.text = text
	highlight.visible = true


# --- Per frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var i := 0
	for id: String in marks:
		var m: Node3D = marks[id]
		i += 1
		m.position.y = 0.05 * sin(_t * 1.35 + i * 1.7)
		m.rotation = Vector3(0.05 * sin(_t * 1.1 + i), 0.0, 0.05 * sin(_t * 0.9 + i * 2.3))
	if pin_node != null and is_instance_valid(pin_node):
		pin_node.position.y = 0.06 * sin(_t * 1.2 + 0.4)
		pin_node.rotation = Vector3(0.06 * sin(_t * 0.95), 0.0, 0.06 * sin(_t * 1.15 + 1.0))
	if rc_boat != null and is_instance_valid(rc_boat):
		rc_boat.position.y = 0.03 * sin(_t * 0.8)
		rc_boat.rotation.x = 0.012 * sin(_t * 0.7 + 0.5)
		rc_boat.rotation.z = 0.015 * sin(_t * 0.6)
	if highlight != null and highlight.visible:
		var cone := highlight.get_child(0) as Node3D
		cone.position.y = 4.6 + 0.35 * sin(_t * 2.2)
		cone.rotation.y = _t * 1.2


## Cut the Snipes out of the water surface: one Vector4(east, north, heading, heel) per boat
## (up to 10), so the water doesn't show inside their cockpits.
func update_hulls(hulls: PackedVector4Array) -> void:
	var arr := PackedVector4Array()
	for i in 10:
		arr.append(hulls[i] if i < hulls.size() else Vector4.ZERO)
	water_mat.set_shader_parameter("hulls", arr)
	water_mat.set_shader_parameter("hull_count", mini(hulls.size(), 10))


## Seamless grey noise for foam breakup, wind lanes and the ragged edges of puffs.
static func _gray_noise(seed: int, freq: float, octaves: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


## Speeds (m/s) for the boats passed to update_hulls, in the same order: they drive the bow waves.
func update_hull_speeds(speeds: PackedFloat32Array) -> void:
	var arr := PackedFloat32Array()
	for i in 10:
		arr.append(speeds[i] if i < speeds.size() else 0.0)
	water_mat.set_shader_parameter("hull_u", arr)


## Wake tracks, one per boat (up to 10): an Array of Vector4(east, north, age s, speed m/s),
## newest first, up to 20 points each.
func update_wakes(tracks: Array) -> void:
	var pts := PackedVector4Array()
	var boxes := PackedVector4Array()
	var n := mini(tracks.size(), 10)
	for b in 10:
		var tr: Array = tracks[b] if b < n else []
		var box := Rect2()
		var reach := 2.0
		for i in 20:
			if i < tr.size():
				var q: Vector4 = tr[i]
				pts.append(q)
				box = Rect2(q.x, q.y, 0, 0) if i == 0 else box.expand(Vector2(q.x, q.y))
				# The V spreads about a third of the distance run; the slick widens with age.
				reach = maxf(reach, 0.36 * (q.z * maxf(q.w, 0.3) + 2.4) + 1.5)
			else:
				pts.append(Vector4(0, 0, 0, -1))
		box = box.grow(reach)
		boxes.append(Vector4(box.position.x, box.position.y, box.end.x, box.end.y) if b < n else Vector4(1, 1, -1, -1))
	water_mat.set_shader_parameter("wake_pts", pts)
	water_mat.set_shader_parameter("wake_box", boxes)
	water_mat.set_shader_parameter("wake_boats", n)
