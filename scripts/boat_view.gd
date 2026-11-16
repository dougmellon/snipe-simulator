extends Node3D
## A Snipe dinghy posed each frame from a BoatSim: hard-chine hull, rig, sails, foils and crew.
## Local frame: forward -Z, starboard +X, up +Y, origin at the centre of gravity on the
## waterline. A sim body point (bx forward, by starboard) at height h is Vector3(by, h, -bx).

const Lake := preload("res://scripts/lake.gd")
const BoatSim := preload("res://scripts/boat_sim.gd")
const SailShader := preload("res://shaders/sail.gdshader")

const BOOM_H := 1.17
const MAST_TOP := 6.68
const HOUNDS := 5.25
const SPREADER_H := 3.5
const JIB_TACK_H := 0.5
const JIB_LUFF := 4.8
const COCKPIT_FWD := 0.45
const COCKPIT_AFT := -1.95
const SIDE_DECK := 0.2
const FLOOR_H := 0.02
const CROWN := 0.03
const SKIPPER_X := -1.4
const CREW_X := -0.5
const SAIL_AABB := AABB(Vector3(-4.0, -1.0, -4.5), Vector3(8.0, 9.0, 9.0))


## Accumulates coloured triangles into one mesh surface. Faces are oriented by the normals
## given, so callers never have to think about winding.
class Kit:
	var st := SurfaceTool.new()
	var count := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
		var g := (b - a).cross(c - a)
		if g.dot(na + nb + nc) < 0.0:
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		# Godot's front faces wind clockwise: emit a, c, b.
		st.set_color(col)
		st.set_normal(na)
		st.add_vertex(a)
		st.set_normal(nc)
		st.add_vertex(c)
		st.set_normal(nb)
		st.add_vertex(b)
		count += 3

	## Flat triangle facing `out` (only its side matters).
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out := Vector3.ZERO) -> void:
		var n := (b - a).cross(c - a).normalized()
		if out != Vector3.ZERO and n.dot(out) < 0.0:
			n = -n
		tri_n(a, b, c, n, n, n, col)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out := Vector3.ZERO) -> void:
		var n := (b - a).cross(c - a) + (c - a).cross(d - a)
		n = n.normalized()
		if out != Vector3.ZERO and n.dot(out) < 0.0:
			n = -n
		tri_n(a, b, c, n, n, n, col)
		tri_n(a, c, d, n, n, n, col)

	func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color) -> void:
		tri_n(a, b, c, na, nb, nc, col)
		tri_n(a, c, d, na, nc, nd, col)

	## Any primitive mesh, transformed and flat-coloured.
	func prim(mesh: Mesh, xf: Transform3D, col: Color) -> void:
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var c := idx[i + 2]
			# Primitive meshes are already wound for Godot; keep their order.
			for k: int in [a, b, c]:
				st.set_color(col)
				st.set_normal((nb * norms[k]).normalized())
				st.add_vertex(xf * verts[k])
		count += idx.size()

	func box(center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
		var bm := BoxMesh.new()
		bm.size = size
		prim(bm, Transform3D(basis, center), col)

	## Smooth-sided tube from a to b (radius r at a, r2 at b), optionally capped.
	func cyl(a: Vector3, b: Vector3, r: float, col: Color, seg := 8, r2 := -1.0, caps := false) -> void:
		var ax := b - a
		if ax.length() < 1e-5:
			return
		var axn := ax.normalized()
		var ref := Vector3.UP if absf(axn.y) < 0.9 else Vector3.RIGHT
		var u := axn.cross(ref).normalized()
		var w := axn.cross(u).normalized()
		var rb := r if r2 < 0.0 else r2
		var slope := (r - rb) / ax.length()
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var d0 := u * cos(a0) + w * sin(a0)
			var d1 := u * cos(a1) + w * sin(a1)
			var n0 := (d0 + axn * slope).normalized()
			var n1 := (d1 + axn * slope).normalized()
			quad_n(a + d0 * r, a + d1 * r, b + d1 * rb, b + d0 * rb, n0, n1, n1, n0, col)
			if caps:
				tri(a, a + d0 * r, a + d1 * r, col, -axn)
				if rb > 0.0:
					tri(b, b + d0 * rb, b + d1 * rb, col, axn)

	func commit(mat: Material) -> ArrayMesh:
		var m := st.commit()
		if m.get_surface_count() > 0:
			m.surface_set_material(0, mat)
		return m


static func vcol_material(rough := 0.45, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	return m


## A unit tube along +Y from 0 to 1, used for lines that are re-aimed every frame.
static func unit_tube(r: float, col: Color) -> ArrayMesh:
	var k := Kit.new()
	k.cyl(Vector3.ZERO, Vector3.UP, r, col, 5)
	return k.commit(vcol_material(0.7))


## Aim a unit tube (see unit_tube) from a to b.
static func aim_tube(node: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		node.visible = false
		return
	node.visible = true
	var y := d / l
	var ref := Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	node.transform = Transform3D(Basis(x, d, z), a)


# --- Hull lines (sim x forward, metres) -------------------------------------------------------

static func sheer_hb(x: float) -> float:
	if x <= 0.35:
		return 0.76 - 0.028 * (0.35 - x) * (0.35 - x)
	var t := clampf((x - 0.35) / (BoatSim.BOW_X - 0.35), 0.0, 1.0)
	return 0.76 * (1.0 - pow(t, 1.6))


static func chine_hb(x: float) -> float:
	if x <= 0.3:
		return sheer_hb(x) * 0.81
	var t := clampf((x - 0.3) / (BoatSim.BOW_X - 0.3), 0.0, 1.0)
	return sheer_hb(0.3) * 0.81 * (1.0 - pow(t, 1.35))


static func sheer_h(x: float) -> float:
	return 0.34 + 0.02 * x * x * (1.0 if x > 0.0 else 0.35)


static func chine_h(x: float) -> float:
	var h := -0.05
	if x > 0.6:
		h += 0.075 * (x - 0.6) * (x - 0.6)
	if x < -1.2:
		h += 0.015 * (-1.2 - x)
	return h


static func keel_h(x: float) -> float:
	var h := -0.18
	if x > 0.3:
		h += 0.095 * (x - 0.3) * (x - 0.3)
	if x < -0.4:
		h += 0.03 * pow(-0.4 - x, 1.5)
	return minf(h, chine_h(x) - 0.03)


static func hp(x: float, y: float, h: float) -> Vector3:
	return Vector3(y, h, -x)


# --- Scene parts ------------------------------------------------------------------------------

static var _sail_grid: ArrayMesh
static var _shared_vcol: StandardMaterial3D

var sail_number := ""
var is_player := false
var hull_color := Color(0.1, 0.25, 0.6)
var pivot: Node3D
var hull_mi: MeshInstance3D
var boom_node: Node3D
var main_mi: MeshInstance3D
var jib_mi: MeshInstance3D
var main_mat: ShaderMaterial
var jib_mat: ShaderMaterial
var rudder_node: Node3D
var board_node: Node3D
var sheet_mi: MeshInstance3D
var ext_mi: MeshInstance3D
var figs: Array[Node3D] = []
var uppers: Array[Node3D] = []
var legs: Array[Node3D] = []
var label: Label3D
var wake_mi: MeshInstance3D
var _phase := 0.0
var _decal_vp: SubViewport
var _decal_wait := 0


func setup(color: Color, number: String, player: bool) -> void:
	hull_color = color
	sail_number = number
	is_player = player
	_phase = float(hash(number) % 1000) * 0.01
	for c in get_children():
		c.queue_free()
	figs.clear()
	uppers.clear()
	legs.clear()
	if _shared_vcol == null:
		_shared_vcol = vcol_material(0.42)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)

	hull_mi = MeshInstance3D.new()
	hull_mi.name = "Hull"
	hull_mi.mesh = _build_hull()
	pivot.add_child(hull_mi)

	boom_node = Node3D.new()
	boom_node.name = "Boom"
	boom_node.position = hp(BoatSim.MAST_X, 0.0, BOOM_H)
	pivot.add_child(boom_node)
	var bmi := MeshInstance3D.new()
	bmi.mesh = _build_boom()
	boom_node.add_child(bmi)

	rudder_node = Node3D.new()
	rudder_node.name = "Rudder"
	rudder_node.position = hp(BoatSim.STERN_X - 0.06, 0.0, 0.25)
	pivot.add_child(rudder_node)
	var rmi := MeshInstance3D.new()
	rmi.mesh = _build_rudder()
	rudder_node.add_child(rmi)

	board_node = Node3D.new()
	board_node.name = "Board"
	board_node.position = hp(0.55, 0.0, -0.09)
	pivot.add_child(board_node)
	var cbi := MeshInstance3D.new()
	var k := Kit.new()
	k.box(Vector3(0.0, -0.5, 0.17), Vector3(0.022, 1.0, 0.38), Color(0.85, 0.85, 0.82))
	cbi.mesh = k.commit(_shared_vcol)
	board_node.add_child(cbi)

	sheet_mi = MeshInstance3D.new()
	sheet_mi.mesh = unit_tube(0.006, Color(0.15, 0.2, 0.35))
	sheet_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(sheet_mi)
	ext_mi = MeshInstance3D.new()
	ext_mi.mesh = unit_tube(0.011, Color(0.08, 0.08, 0.08))
	ext_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(ext_mi)

	_build_sails()
	_build_crew()
	_build_details()

	label = Label3D.new()
	label.name = "SailLabel"
	label.text = number
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0008
	label.font_size = 30
	label.outline_size = 8
	label.no_depth_test = true
	label.modulate = Color(1.0, 0.86, 0.2, 0.95) if player else Color(1.0, 1.0, 1.0, 0.85)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.6)
	label.position = Vector3(0.0, 8.0, 0.0)
	add_child(label)

	_build_wake()


func set_label_visible(on: bool) -> void:
	if label != null:
		label.visible = on


func _build_hull() -> ArrayMesh:
	var k := Kit.new()
	var topside := hull_color
	var bottom := hull_color.darkened(0.3)
	var deck := Color(0.93, 0.93, 0.9)
	var floor_c := Color(0.8, 0.81, 0.8)
	var wood := Color(0.6, 0.38, 0.19)
	var alu := Color(0.78, 0.8, 0.83)
	var wire := Color(0.3, 0.3, 0.32)

	var xs: Array[float] = []
	var n := 30
	for i in n + 1:
		var t := float(i) / n
		xs.append(BoatSim.STERN_X + (BoatSim.BOW_X - BoatSim.STERN_X) * (1.0 - pow(1.0 - t, 1.35)))
	for extra: float in [COCKPIT_FWD, COCKPIT_AFT]:
		var keep: Array[float] = []
		for x in xs:
			if absf(x - extra) > 0.04:
				keep.append(x)
		keep.append(extra)
		xs = keep
	xs.sort()

	for s: float in [-1.0, 1.0]:
		var kl: Array[Vector3] = []
		var cl: Array[Vector3] = []
		var sl: Array[Vector3] = []
		var rl: Array[Vector3] = []
		for x in xs:
			kl.append(hp(x, 0.0, keel_h(x)))
			cl.append(hp(x, s * chine_hb(x), chine_h(x)))
			sl.append(hp(x, s * sheer_hb(x), sheer_h(x) - 0.045))
			rl.append(hp(x, s * sheer_hb(x), sheer_h(x)))
		_strip(k, kl, cl, Vector3(s * 0.4, -1.0, 0.0), bottom)
		_strip(k, cl, sl, Vector3(s, 0.15, 0.0), topside)
		_strip(k, sl, rl, Vector3(s, 0.3, 0.0), wood)

	# Transom.
	var xt := xs[0]
	var q := hp(xt, 0.0, (keel_h(xt) + sheer_h(xt)) * 0.5)
	var ring := [hp(xt, -sheer_hb(xt), sheer_h(xt)), hp(xt, -chine_hb(xt), chine_h(xt)), hp(xt, 0.0, keel_h(xt)),
		hp(xt, chine_hb(xt), chine_h(xt)), hp(xt, sheer_hb(xt), sheer_h(xt)), hp(xt, 0.0, sheer_h(xt) + CROWN)]
	for i in ring.size():
		k.tri(q, ring[i], ring[(i + 1) % ring.size()], topside, Vector3(0, 0, 1))

	# Deck: side decks along the cockpit, full width fore and aft of it.
	for i in xs.size() - 1:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var open := x0 >= COCKPIT_AFT - 0.001 and x1 <= COCKPIT_FWD + 0.001
		for s: float in [-1.0, 1.0]:
			var e0 := hp(x0, s * sheer_hb(x0), sheer_h(x0))
			var e1 := hp(x1, s * sheer_hb(x1), sheer_h(x1))
			var i0 := _deck_inner(x0, s, open)
			var i1 := _deck_inner(x1, s, open)
			k.quad(e0, e1, i1, i0, deck, Vector3.UP)
			if not open:
				var m0 := hp(x0, 0.0, sheer_h(x0) + CROWN)
				var m1 := hp(x1, 0.0, sheer_h(x1) + CROWN)
				k.quad(i0, i1, m1, m0, deck, Vector3.UP)
			else:
				var f0 := hp(x0, s * _floor_hb(x0), FLOOR_H)
				var f1 := hp(x1, s * _floor_hb(x1), FLOOR_H)
				k.quad(i0, i1, f1, f0, deck.darkened(0.08), Vector3(-s, 0, 0))
		if open:
			k.quad(hp(x0, -_floor_hb(x0), FLOOR_H), hp(x1, -_floor_hb(x1), FLOOR_H),
				hp(x1, _floor_hb(x1), FLOOR_H), hp(x0, _floor_hb(x0), FLOOR_H), floor_c, Vector3.UP)
	# Cockpit end bulkheads.
	for end: Array in [[COCKPIT_FWD, Vector3(0, 0, 1)], [COCKPIT_AFT, Vector3(0, 0, -1)]]:
		var x: float = end[0]
		var out: Vector3 = end[1]
		var pts := [_deck_inner(x, -1.0, true), hp(x, -_floor_hb(x), FLOOR_H), hp(x, _floor_hb(x), FLOOR_H),
			_deck_inner(x, 1.0, true), hp(x, 0.0, sheer_h(x) + CROWN)]
		var c := hp(x, 0.0, (FLOOR_H + sheer_h(x)) * 0.5)
		for i in pts.size():
			k.tri(c, pts[i], pts[(i + 1) % pts.size()], deck.darkened(0.08), out)

	# Centreboard trunk, thwart and hiking straps.
	k.box(hp(0.21, 0.0, FLOOR_H + 0.15), Vector3(0.08, 0.3, 0.82), wood)
	k.box(hp(-0.15, 0.0, 0.22), Vector3(1.1, 0.03, 0.18), wood)
	for s: float in [-1.0, 1.0]:
		k.box(hp(-0.8, s * 0.22, FLOOR_H + 0.07), Vector3(0.05, 0.015, 1.3), Color(0.1, 0.12, 0.3))

	# Mast and standing rigging.
	var mz := -BoatSim.MAST_X
	k.cyl(Vector3(0, 0.0, mz), Vector3(0, MAST_TOP, mz), 0.038, alu, 10, 0.024, true)
	var hounds := Vector3(0, HOUNDS, mz)
	for s: float in [-1.0, 1.0]:
		var tip := Vector3(s * 0.4, SPREADER_H, mz + 0.12)
		k.cyl(Vector3(0, SPREADER_H, mz), tip, 0.012, alu, 6)
		var chain := hp(0.55, s * (sheer_hb(0.55) - 0.02), sheer_h(0.55))
		k.cyl(hounds, tip, 0.006, wire, 4)
		k.cyl(tip, chain, 0.006, wire, 4)
	k.cyl(Vector3(0, JIB_TACK_H, -BoatSim.JIB_TACK_X), Vector3(0, HOUNDS, mz - 0.03), 0.005, wire, 4)
	k.box(Vector3(0, MAST_TOP + 0.03, mz), Vector3(0.05, 0.06, 0.12), alu)
	return k.commit(_shared_vcol)


func _deck_inner(x: float, s: float, open: bool) -> Vector3:
	var hb := sheer_hb(x)
	if open:
		return hp(x, s * (hb - SIDE_DECK), sheer_h(x) + CROWN * 0.3)
	return hp(x, s * hb * 0.5, sheer_h(x) + CROWN * 0.75)


func _floor_hb(x: float) -> float:
	var t := (FLOOR_H - chine_h(x)) / (sheer_h(x) - chine_h(x))
	var hull := lerpf(chine_hb(x), sheer_hb(x), t) - 0.04
	return minf(sheer_hb(x) - SIDE_DECK, hull)


## A hull panel between two longitudinal lines, smooth along its length, sharp at its edges.
func _strip(k: Kit, a: Array[Vector3], b: Array[Vector3], out: Vector3, col: Color) -> void:
	var n := a.size()
	var ns: Array[Vector3] = []
	for i in n:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, n - 1)
		var along := (a[i1] - a[i0]) + (b[i1] - b[i0])
		var nn := along.cross(b[i] - a[i])
		if nn.length() < 1e-6:
			nn = out
		nn = nn.normalized()
		if nn.dot(out) < 0.0:
			nn = -nn
		ns.append(nn)
	for i in n - 1:
		k.quad_n(a[i], a[i + 1], b[i + 1], b[i], ns[i], ns[i + 1], ns[i + 1], ns[i], col)


func _build_boom() -> ArrayMesh:
	var k := Kit.new()
	var alu := Color(0.78, 0.8, 0.83)
	k.cyl(Vector3(0, 0, 0.04), Vector3(0, 0, BoatSim.BOOM_LEN), 0.032, alu, 8, 0.028, true)
	k.box(Vector3(0, 0, 0.05), Vector3(0.05, 0.07, 0.08), Color(0.2, 0.2, 0.2))
	# Vang from the boom down to the mast base: both ends stay put as the boom swings.
	k.cyl(Vector3(0, -0.02, 0.6), Vector3(0, -(BOOM_H - 0.4), 0.04), 0.012, Color(0.15, 0.15, 0.15), 5)
	return k.commit(_shared_vcol)


func _build_rudder() -> ArrayMesh:
	var k := Kit.new()
	var white := Color(0.9, 0.9, 0.88)
	var wood := Color(0.6, 0.38, 0.19)
	# Blade: a thin foil below the stock, leading edge on the pivot, tapering toward the tip.
	var foil := [Vector3(0, 0, 0), Vector3(0.012, 0, 0.06), Vector3(0.008, 0, 0.18), Vector3(0, 0, 0.27),
		Vector3(-0.008, 0, 0.18), Vector3(-0.012, 0, 0.06)]
	for i in foil.size():
		var p0: Vector3 = foil[i]
		var p1: Vector3 = foil[(i + 1) % foil.size()]
		var out := Vector3(p0.x + p1.x, 0, 0)
		if out.length() < 1e-4:
			out = Vector3(0, 0, 1) if p0.z + p1.z > 0.2 else Vector3(0, 0, -1)
		k.quad(p0, p1, p1 * Vector3(1, 1, 0.8) + Vector3(0, -1.0, 0.03),
			p0 * Vector3(1, 1, 0.8) + Vector3(0, -1.0, 0.03), white, out)
	k.box(Vector3(0, 0.1, 0.08), Vector3(0.05, 0.28, 0.2), white)
	# Tiller running forward over the aft deck.
	k.cyl(Vector3(0, 0.2, 0.02), Vector3(0, 0.2, -1.05), 0.022, wood, 6, 0.017, true)
	return k.commit(_shared_vcol)


static func sail_grid() -> ArrayMesh:
	if _sail_grid != null:
		return _sail_grid
	var nu := 12
	var nv := 20
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in nv + 1:
		for i in nu + 1:
			var uv := Vector2(float(i) / nu, float(j) / nv)
			uvs.append(uv)
			verts.append(Vector3(0.0, uv.y * 5.0, uv.x * 2.0))
			norms.append(Vector3.RIGHT)
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var c := a + nu + 1
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	_sail_grid = ArrayMesh.new()
	_sail_grid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _sail_grid


func _build_sails() -> void:
	main_mat = ShaderMaterial.new()
	main_mat.shader = SailShader
	main_mat.set_shader_parameter("roach", 0.16)
	main_mat.set_shader_parameter("foot_attached", 1.0)
	main_mat.set_shader_parameter("batten_count", 4.0)
	main_mat.set_shader_parameter("phase", _phase)
	main_mat.set_shader_parameter("num_stbd", Vector4(0.2, 2.2, 1.1, 0.55))
	main_mat.set_shader_parameter("num_port", Vector4(0.2, 1.75, 1.1, 0.55))
	main_mat.set_shader_parameter("bird_box", Vector4(0.22, 3.2, 0.5, 0.5))
	main_mi = MeshInstance3D.new()
	main_mi.name = "Main"
	main_mi.mesh = sail_grid()
	main_mi.material_override = main_mat
	main_mi.custom_aabb = SAIL_AABB
	pivot.add_child(main_mi)

	jib_mat = ShaderMaterial.new()
	jib_mat.shader = SailShader
	jib_mat.set_shader_parameter("roach", 0.0)
	jib_mat.set_shader_parameter("foot_attached", 0.0)
	jib_mat.set_shader_parameter("phase", _phase + 1.3)
	jib_mat.set_shader_parameter("cloth", Color(0.96, 0.96, 0.95))
	jib_mi = MeshInstance3D.new()
	jib_mi.name = "Jib"
	jib_mi.mesh = sail_grid()
	jib_mi.material_override = jib_mat
	jib_mi.custom_aabb = SAIL_AABB
	pivot.add_child(jib_mi)
	_make_decal()


## Sail number and class insignia, drawn once into a small 2D viewport, then baked into a
## mipmapped texture so the print stays crisp without shimmering at distance.
func _make_decal() -> void:
	_decal_vp = SubViewport.new()
	_decal_vp.size = Vector2i(512, 512)
	_decal_vp.transparent_bg = true
	_decal_vp.disable_3d = true
	_decal_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lbl := Label.new()
	lbl.text = sail_number
	lbl.size = Vector2(512, 256)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 165 if sail_number.length() <= 5 else 130)
	lbl.add_theme_color_override("font_color", Color(0.06, 0.08, 0.14))
	lbl.add_theme_color_override("font_outline_color", Color(0.06, 0.08, 0.14))
	lbl.add_theme_constant_override("outline_size", 12)
	_decal_vp.add_child(lbl)
	# A snipe (the bird): body, head, long bill, tail and legs, facing +x.
	var red := Color(0.75, 0.1, 0.1)
	var o := Vector2(128, 256)
	var body := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		var p := Vector2(cos(a) * 0.3, sin(a) * 0.15).rotated(-0.18) + Vector2(0.45, 0.55)
		body.append(o + p * 256.0)
	var head := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		head.append(o + (Vector2(0.72, 0.4) + Vector2(cos(a), sin(a)) * 0.085) * 256.0)
	var bill := PackedVector2Array([Vector2(0.77, 0.37), Vector2(0.99, 0.42), Vector2(0.99, 0.435), Vector2(0.76, 0.43)])
	var tail := PackedVector2Array([Vector2(0.2, 0.55), Vector2(0.04, 0.66), Vector2(0.08, 0.7), Vector2(0.25, 0.64)])
	var neck := PackedVector2Array([Vector2(0.6, 0.47), Vector2(0.68, 0.36), Vector2(0.77, 0.43), Vector2(0.7, 0.55)])
	var leg1 := PackedVector2Array([Vector2(0.44, 0.66), Vector2(0.47, 0.66), Vector2(0.44, 0.92), Vector2(0.41, 0.92)])
	var leg2 := PackedVector2Array([Vector2(0.52, 0.65), Vector2(0.55, 0.65), Vector2(0.56, 0.92), Vector2(0.53, 0.92)])
	for poly in [body, head, bill, tail, neck, leg1, leg2]:
		var pts: PackedVector2Array = poly
		if poly != body and poly != head:
			for i in pts.size():
				pts[i] = o + pts[i] * 256.0
		var pg := Polygon2D.new()
		pg.polygon = pts
		pg.color = red
		pg.antialiased = true
		_decal_vp.add_child(pg)
	add_child(_decal_vp)
	main_mat.set_shader_parameter("decal", _decal_vp.get_texture())
	main_mat.set_shader_parameter("has_decal", true)
	_decal_wait = 4


## Called from sync(): a few frames after the 2D viewport has drawn, copy it into a mipmapped
## texture and drop the viewport. Until then the sail samples the live viewport texture.
func _bake_decal() -> void:
	if not is_inside_tree():
		return
	_decal_wait -= 1
	if _decal_wait > 0:
		return
	# No GPU in headless runs (tests): nothing to bake.
	if DisplayServer.get_name() == "headless":
		_decal_vp.queue_free()
		_decal_vp = null
		return
	var img := _decal_vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		main_mat.set_shader_parameter("decal", ImageTexture.create_from_image(img))
		_decal_vp.queue_free()
		_decal_vp = null
	else:
		_decal_wait = 30


@warning_ignore("integer_division")
func _build_crew() -> void:
	var palette := [Color(0.85, 0.12, 0.1), Color(0.95, 0.75, 0.1), Color(0.95, 0.45, 0.08),
		Color(0.12, 0.3, 0.75), Color(0.1, 0.1, 0.12), Color(0.15, 0.55, 0.3), Color(0.55, 0.15, 0.55)]
	var skins := [Color(0.93, 0.76, 0.62), Color(0.8, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.95, 0.8, 0.7)]
	var hairs := [Color(0.25, 0.17, 0.1), Color(0.08, 0.07, 0.06), Color(0.6, 0.45, 0.25), Color(0.5, 0.5, 0.5)]
	var shirts := [Color(0.95, 0.95, 0.95), Color(0.15, 0.2, 0.35), Color(0.35, 0.35, 0.38), Color(0.2, 0.45, 0.65)]
	var h := absi(hash(sail_number))
	for who in 2:
		var jacket: Color = palette[(h / (1 + who * 7)) % palette.size()]
		if is_player:
			jacket = Color(0.9, 0.1, 0.08) if who == 0 else Color(0.98, 0.8, 0.1)
		var skin: Color = skins[(h / (3 + who * 5)) % skins.size()]
		var hair: Color = hairs[(h / (11 + who)) % hairs.size()]
		var shirt: Color = shirts[(h / (13 + who * 3)) % shirts.size()]
		var fig := Node3D.new()
		fig.name = "Skipper" if who == 0 else "Crew"
		pivot.add_child(fig)
		var lk := Kit.new()
		var pants := Color(0.1, 0.12, 0.18)
		var sph := SphereMesh.new()
		sph.radius = 0.14
		sph.height = 0.28
		sph.radial_segments = 10
		sph.rings = 6
		lk.prim(sph, Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.25)), Vector3(0, 0.07, 0)), pants)
		for z: float in [-0.1, 0.1]:
			var knee := Vector3(-0.42, 0.08, z * 1.2)
			var ankle := Vector3(-0.47, -0.3, z * 1.25)
			lk.cyl(Vector3(0, 0.05, z), knee, 0.075, pants, 7, 0.058, true)
			lk.cyl(knee, ankle, 0.055, pants, 7, 0.045, true)
			lk.box(ankle + Vector3(-0.07, -0.03, 0), Vector3(0.24, 0.08, 0.1), Color(0.15, 0.15, 0.15))
		var lmi := MeshInstance3D.new()
		lmi.mesh = lk.commit(_shared_vcol)
		fig.add_child(lmi)
		var upper := Node3D.new()
		fig.add_child(upper)
		var uk := Kit.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.15
		cap.height = 0.62
		cap.radial_segments = 12
		cap.rings = 4
		uk.prim(cap, Transform3D(Basis.from_scale(Vector3(0.85, 1.0, 1.2)), Vector3(0, 0.36, 0)), jacket)
		uk.cyl(Vector3(0, 0.6, 0), Vector3(0, 0.72, 0), 0.05, skin, 6)
		var hs := SphereMesh.new()
		hs.radius = 0.105
		hs.height = 0.21
		hs.radial_segments = 12
		hs.rings = 8
		uk.prim(hs, Transform3D(Basis.IDENTITY, Vector3(-0.01, 0.79, 0)), skin)
		uk.prim(hs, Transform3D(Basis.from_scale(Vector3(1.06, 0.66, 1.06)), Vector3(0.012, 0.825, 0)), hair)
		if who == 0:
			uk.box(Vector3(-0.1, 0.84, 0), Vector3(0.12, 0.014, 0.16), jacket.darkened(0.2))
		uk.box(Vector3(-0.098, 0.795, 0), Vector3(0.02, 0.028, 0.1), Color(0.05, 0.05, 0.05))
		for z: float in [-1.0, 1.0]:
			var sh := Vector3(0, 0.56, z * 0.2)
			var el := Vector3(-0.14, 0.33, z * 0.25)
			var ha := Vector3(-0.34, 0.24, z * 0.15)
			uk.cyl(sh, el, 0.048, shirt, 6, 0.042, true)
			uk.cyl(el, ha, 0.042, shirt, 6, 0.035, true)
			var hand := SphereMesh.new()
			hand.radius = 0.04
			hand.height = 0.08
			hand.radial_segments = 6
			hand.rings = 4
			uk.prim(hand, Transform3D(Basis.IDENTITY, ha), skin)
		var umi := MeshInstance3D.new()
		umi.mesh = uk.commit(_shared_vcol)
		upper.add_child(umi)
		figs.append(fig)
		uppers.append(upper)
		legs.append(lmi)


func _build_wake() -> void:
	wake_mi = MeshInstance3D.new()
	wake_mi.name = "Wake"
	var qm := PlaneMesh.new()
	qm.size = Vector2(7.0, 14.0)
	wake_mi.mesh = qm
	wake_mi.position = Vector3(0.0, 0.035, 4.5)
	wake_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake_mi.material_override = _wake_material()
	add_child(wake_mi)


static var _wake_mat: ShaderMaterial


static func _wake_material() -> ShaderMaterial:
	if _wake_mat == null:
		_wake_mat = ShaderMaterial.new()
		_wake_mat.shader = preload("res://shaders/wake.gdshader")
	return _wake_mat




# --- Telltales and windex ---------------------------------------------------------------------

const DETAIL_DIST := 70.0
const JIB_YARN_V := [0.33, 0.66]
const LEECH_V := [0.4, 0.6, 0.8]
const YARN_PORT := Color(0.95, 0.08, 0.06)
const YARN_STBD := Color(0.1, 0.85, 0.2)
const YARN_LEECH := Color(1.0, 0.6, 0.05)
# Wind strings tied on the shrouds at eye height: height above the waterline, length, colour,
# how much it snakes, width. Old cassette tape (dark, flutters hard) low, red wool higher up.
const SHROUD_TT := [[1.3, 0.38, Color(0.22, 0.13, 0.07), 0.9, 0.35], [1.95, 0.28, Color(0.9, 0.12, 0.1), 0.45, 0.75]]

static var _yarn_mesh: ArrayMesh
static var _yarn_mat: ShaderMaterial
static var _jib_yarn_mat: ShaderMaterial

var yarns: Array[MeshInstance3D] = []   # 4 jib telltales (1/3 stbd, 1/3 port, 2/3 stbd, 2/3 port), 3 leech ribbons
var shroud_tts: Array = []   # {pos, len, flap} for yarns[7..]
var windex: Node3D
var windex_vane: Node3D
var _main_twist := 0.1


## Two crossed strips, 1 unit long along +Z; its node scales Z to the yarn length.
static func yarn_mesh() -> ArrayMesh:
	if _yarn_mesh != null:
		return _yarn_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.012
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP]:
		for i in 8:
			var z0 := i / 8.0
			var z1 := (i + 1) / 8.0
			var q := [Vector3(0, 0, z0) - axis * w, Vector3(0, 0, z0) + axis * w, Vector3(0, 0, z1) + axis * w, Vector3(0, 0, z1) - axis * w]
			var uvx := [0.0, 1.0, 1.0, 0.0]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(uvx[k], (z0 if k < 2 else z1)))
				st.set_normal(axis.cross(Vector3.BACK))
				st.add_vertex(q[k])
	_yarn_mesh = st.commit()
	var base: Shader = preload("res://shaders/telltale.gdshader")
	_yarn_mat = ShaderMaterial.new()
	_yarn_mat.shader = base
	# Jib telltales also draw faintly through everything, like the leeward yarn's shadow seen
	# through the translucent jib from the helm.
	var through := Shader.new()
	through.code = base.code.replace("shadows_disabled;", "shadows_disabled, depth_test_disabled;")
	var ghost := ShaderMaterial.new()
	ghost.shader = through
	ghost.set_shader_parameter("through", 0.3)
	_jib_yarn_mat = ShaderMaterial.new()
	_jib_yarn_mat.shader = base
	_jib_yarn_mat.next_pass = ghost
	return _yarn_mesh


func _build_details() -> void:
	yarns.clear()
	var cols := [YARN_STBD, YARN_PORT, YARN_STBD, YARN_PORT, YARN_LEECH, YARN_LEECH, YARN_LEECH]
	for i in cols.size():
		var y := MeshInstance3D.new()
		y.name = "Telltale%d" % i
		y.mesh = yarn_mesh()
		y.material_override = _jib_yarn_mat if i < 4 else _yarn_mat
		y.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		y.extra_cull_margin = 0.5
		pivot.add_child(y)
		y.set_instance_shader_parameter("yarn_color", cols[i])
		y.set_instance_shader_parameter("seed", fposmod(_phase * 3.7 + i * 0.37, 1.0))
		yarns.append(y)

	# Shroud telltales, two on each shroud: yarns[7..10] = port low, port high, stbd low, stbd high.
	shroud_tts.clear()
	for s: float in [-1.0, 1.0]:
		for t: Array in SHROUD_TT:
			var y := MeshInstance3D.new()
			y.name = "ShroudTelltale"
			y.mesh = yarn_mesh()
			y.material_override = _yarn_mat
			y.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			y.extra_cull_margin = 0.5
			pivot.add_child(y)
			y.set_instance_shader_parameter("yarn_color", t[2])
			y.set_instance_shader_parameter("seed", fposmod(_phase * 5.3 + s * 0.29 + t[0], 1.0))
			yarns.append(y)
			shroud_tts.append({"pos": _shroud_point(s, t[0]), "len": t[1], "flap": t[3], "width": t[4]})

	# Masthead wind indicator: a vane that swings to point into the apparent wind, between two
	# fixed reference tabs set for close-hauled.
	windex = Node3D.new()
	windex.name = "Windex"
	windex.position = Vector3(0.0, MAST_TOP + 0.03, -BoatSim.MAST_X)
	pivot.add_child(windex)
	var k := Kit.new()
	var black := Color(0.08, 0.08, 0.08)
	var white := Color(0.95, 0.95, 0.95)
	var red := Color(0.9, 0.1, 0.08)
	k.cyl(Vector3.ZERO, Vector3(0, 0.15, 0), 0.008, black, 5)
	for s: float in [-1.0, 1.0]:
		var e := Vector3(s * sin(deg_to_rad(32.0)) * 0.17, 0.12, cos(deg_to_rad(32.0)) * 0.17)
		k.cyl(Vector3(0, 0.12, 0), e, 0.004, white, 4)
		k.box(e, Vector3(0.012, 0.035, 0.035), red if s < 0.0 else Color(0.1, 0.7, 0.2))
	var fixed := MeshInstance3D.new()
	fixed.mesh = k.commit(_shared_vcol)
	fixed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	windex.add_child(fixed)
	windex_vane = Node3D.new()
	windex_vane.position = Vector3(0, 0.16, 0)
	windex.add_child(windex_vane)
	var vk := Kit.new()
	vk.cyl(Vector3(0, 0, 0.24), Vector3(0, 0, -0.2), 0.006, black, 5)
	vk.cyl(Vector3(0, 0, -0.2), Vector3(0, 0, -0.3), 0.028, red, 8, 0.0, true)
	for s: float in [-1.0, 1.0]:
		vk.quad(Vector3(0, -0.01, 0.12), Vector3(0, -0.01, 0.26), Vector3(0, 0.09, 0.27), Vector3(0, 0.07, 0.12), red, Vector3(s, 0, 0))
	vk.cyl(Vector3(0, -0.05, 0), Vector3(0, 0.005, 0), 0.01, black, 5)
	var vmi := MeshInstance3D.new()
	vmi.mesh = vk.commit(_shared_vcol)
	vmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	windex_vane.add_child(vmi)


## A point on a posed sail (the vertex shader's shape without the flutter), with the surface
## direction along the chord there and the chord normal: [point, along, normal].
static func sail_frame(tack: Vector3, head: Vector3, clew: Vector3, belly: float, twist: float, roach: float,
		foot_attached: float, u: float, v: float) -> Array:
	var side := 1.0 if belly >= 0.0 else -1.0
	var luff := tack.lerp(head, v)
	var d := clew.lerp(head, v) - luff
	var a := twist * v * side
	d = Vector3(d.x * cos(a) + d.z * sin(a), d.y, -d.x * sin(a) + d.z * cos(a))
	var cdir := d.normalized()
	d += cdir * roach * pow(sin(PI * v), 0.8)
	var ln := d.length()
	var n := Vector3(d.z, 0.0, -d.x).normalized()
	var shape := 3.05 * u * (1.0 - u) * (1.0 + 0.6 * (1.0 - u))
	var dshape := 3.05 * ((1.0 - 2.0 * u) * (1.0 + 0.6 * (1.0 - u)) - 0.6 * u * (1.0 - u))
	var foot := lerpf(1.0, smoothstep(0.0, 0.14, v), foot_attached)
	var p := luff + d * u + n * belly * ln * shape * foot
	var along := (d + n * belly * ln * dshape * foot).normalized()
	return [p, along, n]


func _aim_yarn(y: MeshInstance3D, p: Vector3, dir: Vector3, off: Vector3, length: float, flap: float, curl: float, width := 1.0) -> void:
	var z := dir.normalized()
	var x := off - z * off.dot(z)
	if x.length() < 1e-3:
		x = z.cross(Vector3.UP)
	x = x.normalized()
	var yv := z.cross(x)
	y.transform = Transform3D(Basis(x * width, yv * width, z * length), p)
	y.set_instance_shader_parameter("flap", flap)
	y.set_instance_shader_parameter("curl", curl)


## Telltales read the flow on each side of the sails: a windward jib yarn lifts and twirls
## when the jib luffs (|alpha| < ~0.07), the leeward one droops when it stalls (> ~0.38); the
## leech ribbons stream aft while the main is working and curl away behind it once it stalls.
func _pose_details(sim, near: bool, capsized: bool, time: float, jtack: Vector3, jhead: Vector3, jclew: Vector3,
		tack: Vector3, mhead: Vector3, clew: Vector3) -> void:
	windex.visible = near
	for y in yarns:
		y.visible = near and not capsized
	if not near:
		return
	windex_vane.rotation = Vector3(0.0, -float(sim.awa), 0.0)
	if capsized:
		return
	var up := Vector3.UP
	var ja := absf(float(sim.jib_alpha))
	var luff_k := 1.0 - smoothstep(0.05, 0.09, ja)
	var stall_k := smoothstep(0.33, 0.43, ja)
	var lee := 1.0 if _jib_belly >= 0.0 else -1.0
	for i in 4:
		var face_side := 1.0 if i % 2 == 0 else -1.0
		var f := sail_frame(jtack, jhead, jclew, _jib_belly, 0.14, 0.0, 0.0, 0.17, JIB_YARN_V[i >> 1])
		var p: Vector3 = f[0]
		var t: Vector3 = f[1]
		var face: Vector3 = f[2] * face_side
		var dir := t - up * 0.08
		var flap := 0.12
		if face_side != lee:
			var lift := (up * 0.85 - t * 0.3 + face * 0.45).normalized()
			lift = lift.rotated(t, sin(time * 8.0 + i * 1.9 + _phase) * 1.1)
			dir = dir.lerp(lift, luff_k)
			flap = lerpf(0.12, 1.0, luff_k)
		else:
			var droop := (-up * 0.85 + t * 0.2 + face * 0.3).normalized()
			droop = droop.rotated(up, sin(time * 5.0 + i + _phase) * 0.5)
			dir = dir.lerp(droop, stall_k)
			flap = lerpf(0.12, 0.75, stall_k)
		_aim_yarn(yarns[i], p + face * 0.014, dir, face, 0.26, flap, 0.0)
	var ma := absf(float(sim.main_alpha))
	var m_luff := 1.0 - smoothstep(0.05, 0.09, ma)
	var m_stall := smoothstep(0.4, 0.47, ma)
	var mlee := 1.0 if _main_belly >= 0.0 else -1.0
	for i in 3:
		var f := sail_frame(tack, mhead, clew, _main_belly, _main_twist, 0.16, 1.0, 1.0, LEECH_V[i])
		var p: Vector3 = f[0]
		var t: Vector3 = f[1]
		var lee_n: Vector3 = f[2] * mlee
		var behind := (lee_n * 0.75 - t * 0.45 - up * 0.3).normalized()
		var dir := (t - up * 0.05).lerp(behind, m_stall)
		var flap := lerpf(lerpf(0.18, 1.0, m_luff), 0.3, m_stall)
		_aim_yarn(yarns[4 + i], p, dir, lee_n, 0.26, flap, m_stall * 0.6)

	# Shroud telltales stream with the apparent wind (level in the world, whatever the heel);
	# in a near-calm they hang down the wire.
	var awa: float = sim.awa
	var aws: float = sim.aws
	var inv := pivot.basis.inverse()
	var flow := inv * Vector3(-sin(awa), 0.0, cos(awa))
	var down := inv * Vector3.DOWN
	var calm := 1.0 - smoothstep(0.6, 2.8, aws)
	var breeze := clampf(aws / 6.0 + 0.3, 0.3, 1.2)
	for j in shroud_tts.size():
		var d: Dictionary = shroud_tts[j]
		var dir := flow.lerp(down, calm * 0.9) + down * 0.1
		var flap := lerpf(float(d["flap"]) * breeze, 0.15, calm)
		_aim_yarn(yarns[7 + j], d["pos"], dir, flow.cross(Vector3.UP), d["len"], flap, 0.0, d["width"])


## A point on the lower shroud (chainplate to spreader tip) at height `h`, side `s` (+1 stbd).
func _shroud_point(s: float, h: float) -> Vector3:
	var mz := -BoatSim.MAST_X
	var tip := Vector3(s * 0.4, SPREADER_H, mz + 0.12)
	var chain := hp(0.55, s * (sheer_hb(0.55) - 0.02), sheer_h(0.55))
	return chain.lerp(tip, clampf((h - chain.y) / (tip.y - chain.y), 0.0, 1.0))


## Show or hide the two sailors, e.g. hide the skipper for a first-person helm camera.
func set_crew_visible(skipper: bool, crew: bool) -> void:
	if figs.size() == 2:
		figs[0].visible = skipper
		figs[1].visible = crew


## The skipper's eye point in world space (for a helm camera).
func skipper_eye() -> Vector3:
	var base := global_transform if is_inside_tree() else transform
	if figs.is_empty():
		return base * Vector3(0.0, 1.05, 1.4)
	return (base * pivot.transform * figs[0].transform * uppers[0].transform) * Vector3(-0.08, 0.8, 0.0)


# --- Per frame --------------------------------------------------------------------------------

var _main_belly := 0.0
var _jib_belly := 0.0
var _last_t := -1.0


func sync(sim, time: float) -> void:
	var dt := clampf(time - _last_t, 0.0, 0.1) if _last_t >= 0.0 else 0.0
	_last_t = time
	if _decal_vp != null:
		_bake_decal()
	var p: Vector2 = sim.pos
	position = Lake.to_3d(p)
	rotation = Vector3(0.0, -float(sim.heading), 0.0)
	var u: float = sim.u
	var heel: float = sim.heel
	var capsized: bool = sim.capsized
	var bob := 0.016 * sin(time * 1.9 + _phase) + 0.008 * sin(time * 3.3 + _phase * 2.0)
	var pitch := 0.01 * sin(time * 1.6 + _phase * 1.3) + 0.022 * smoothstep(1.5, 4.5, u)
	pivot.position = Vector3(0.0, bob - (0.12 if capsized else 0.0), 0.0)
	pivot.basis = Basis.from_euler(Vector3(pitch, 0.0, -heel))

	var boom: float = sim.boom
	var jib: float = sim.jib
	var awa: float = sim.awa
	var aws: float = sim.aws
	boom_node.rotation = Vector3(0.0, boom, 0.0)
	rudder_node.rotation = Vector3(0.0, clampf(sim.tiller, -1.0, 1.0) * BoatSim.MAX_RUDDER, 0.0)
	board_node.rotation = Vector3(-(1.0 - clampf(sim.board, 0.0, 1.0)) * 1.45, 0.0, 0.0)

	# Sails belly to leeward of their own chord; a backed jib bellies the other way.
	var fill := clampf(aws / 2.5, 0.2, 1.0)
	var mb := -signf(sin(awa + boom)) * 0.1 * fill * clampf(absf(sin(awa + boom)) * 5.0, 0.3, 1.0)
	var jb := -signf(sin(awa + jib)) * 0.12 * fill * clampf(absf(sin(awa + jib)) * 5.0, 0.3, 1.0)
	if capsized:
		mb = 0.03 * signf(_main_belly if _main_belly != 0.0 else 1.0)
		jb = 0.03 * signf(_jib_belly if _jib_belly != 0.0 else 1.0)
	if dt <= 0.0:
		_main_belly = mb
		_jib_belly = jb
	else:
		_main_belly = move_toward(_main_belly, mb, 0.8 * dt)
		_jib_belly = move_toward(_jib_belly, jb, 1.0 * dt)
	var ma: float = absf(sim.main_alpha)
	var ja: float = absf(sim.jib_alpha)
	var wind_ok := 0.0 if capsized else smoothstep(0.4, 1.5, aws)
	var main_flut := (1.0 - smoothstep(0.035, 0.085, ma)) * wind_ok
	var jib_flut := (1.0 - smoothstep(0.035, 0.085, ja)) * wind_ok
	var mz := -BoatSim.MAST_X
	var tack := Vector3(0.0, BOOM_H + 0.03, mz + 0.045)
	var mhead := Vector3(0.0, MAST_TOP - 0.13, mz + 0.04)
	var clew := tack + Vector3(sin(boom), 0.0, cos(boom)) * (BoatSim.BOOM_LEN - 0.08)
	main_mat.set_shader_parameter("tack", tack)
	main_mat.set_shader_parameter("head", mhead)
	main_mat.set_shader_parameter("clew", clew)
	main_mat.set_shader_parameter("belly", _main_belly)
	_main_twist = 0.1 + 0.22 * clampf(absf(boom) / 1.3, 0.0, 1.0)
	main_mat.set_shader_parameter("twist", _main_twist)
	main_mat.set_shader_parameter("flutter", main_flut)
	var jtack := Vector3(0.0, JIB_TACK_H + 0.04, -BoatSim.JIB_TACK_X + 0.03)
	var stay := (Vector3(0.0, HOUNDS, mz - 0.03) - jtack).normalized()
	var jclew := jtack + Vector3(sin(jib), 0.0, cos(jib)) * BoatSim.JIB_FOOT + Vector3(0.0, 0.2, 0.0)
	jib_mat.set_shader_parameter("tack", jtack)
	jib_mat.set_shader_parameter("head", jtack + stay * JIB_LUFF)
	jib_mat.set_shader_parameter("clew", jclew)
	jib_mat.set_shader_parameter("belly", _jib_belly)
	jib_mat.set_shader_parameter("twist", 0.14)
	jib_mat.set_shader_parameter("flutter", jib_flut)

	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var dist := cam.global_position.distance_to(global_position) if cam != null else 0.0
	var near := dist < DETAIL_DIST
	_pose_details(sim, near, capsized, time, jtack, jtack + stay * JIB_LUFF, jclew, tack, mhead, clew)
	sheet_mi.visible = near
	if near:
		aim_tube(sheet_mi, hp(-0.22, 0.0, 0.34), boom_node.transform * Vector3(0.0, -0.03, 1.25))
	_pose_crew(sim, capsized)
	if near and not capsized:
		var tiller_end := rudder_node.transform * Vector3(0.0, 0.2, -1.03)
		var hand := figs[0].transform * uppers[0].transform * Vector3(-0.34, 0.24, 0.15)
		aim_tube(ext_mi, tiller_end, hand)
	else:
		ext_mi.visible = false

	# Wakes are drawn by the water shader from each boat's track now; this old foam decal
	# (glued to the boat, so it swung round in turns) stays off.
	var wake_k := 0.0
	wake_mi.visible = false
	if wake_mi.visible:
		wake_mi.set_instance_shader_parameter("strength", wake_k)
		wake_mi.set_instance_shader_parameter("speed", u)
		wake_mi.set_instance_shader_parameter("seed", _phase)
	label.position.y = 3.0 if capsized else 8.0
	# The floating number fades out up close (the sail says it) and far away (clutter).
	if cam != null and label.visible:
		var a := smoothstep(18.0, 32.0, dist) * (1.0 - smoothstep(450.0, 700.0, dist))
		label.modulate.a = a * (0.95 if is_player else 0.85)
		label.outline_modulate.a = a * 0.6


func _pose_crew(sim, capsized: bool) -> void:
	var cy: float = sim.crew_y
	if capsized:
		var cs: float = signf(sim.heel) if sim.heel != 0.0 else 1.0
		var inv := pivot.transform.affine_inverse()
		for i in 2:
			var z := SKIPPER_X if i == 0 else CREW_X
			var want := Transform3D(Basis.from_scale(Vector3(-cs, 1.0, 1.0)),
				Vector3(-cs * (1.0 + 0.15 * i), -0.6, -z * 0.8 - 0.3))
			figs[i].transform = inv * want
			uppers[i].basis = Basis.IDENTITY
			legs[i].visible = false
		return
	var s := 1.0 if cy >= 0.0 else -1.0
	var a := absf(cy)
	for i in 2:
		legs[i].visible = true
		var x := SKIPPER_X if i == 0 else CREW_X
		var ai := a * (0.95 if i == 0 else 1.0)
		var t := smoothstep(0.12, 0.4, ai)
		var rail := sheer_hb(x) - 0.07
		var lat := lerpf(ai, rail - 0.06 + 0.06 * smoothstep(0.5, 0.9, ai), t)
		var hh := lerpf(FLOOR_H + 0.12, sheer_h(x) + 0.07, t)
		var lean := clampf((ai - 0.55) / 0.5, 0.0, 1.0) * 0.8 - 0.1 * (1.0 - t)
		var face := Basis(Vector3.UP, -0.35 if i == 0 else -0.55)
		figs[i].transform = Transform3D(Basis.from_scale(Vector3(s, 1.0, 1.0)) * face, hp(x, s * lat, hh))
		uppers[i].basis = Basis(Vector3.BACK, -lean)
