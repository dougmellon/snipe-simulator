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
const COCKPIT_AFT := -1.08    # leaves an aft deck of about 1.2 m, as in the overhead photo
const COCKPIT_HW := 0.32     # half-width of the cockpit opening at deck level, where the lip starts to
                             # roll down: about 0.6 m across with parallel sides, leaving side decks
                             # about 0.45 m wide to sit on (overhead photo)
const FLOOR_H := 0.02
const HALF_BEAM := 0.76
const BOW_ROUND := 0.1       # rounds the bow in plan: the tip comes to a radius of about 8 cm
const TIP_R := 0.083         # that radius, for spacing stations round the tip
const DECK_EDGE_R := 0.04    # radius of the rolled edge where the topsides turn into the deck, all round
const LIP_R := 0.022         # roll of the side deck down into the cockpit
const FWD_CROWN := 0.06      # deck camber at the centreline for a full-beam deck: foredeck / side decks / aft deck
const SIDE_CROWN := 0.012
const AFT_CROWN := 0.022
const COCKPIT_RC := 0.06     # plan radius of the cockpit's corners at the coaming: nearly square
const CORNER_MIN := 0.015    # the corners tighten toward the floor, down to this radius
const TANK_SLOPE := 0.11     # how far the tank sides come in from the coaming lip to the floor
const END_SLOPE := 0.05      # the same for the cockpit's end walls
const FILLET := 0.035        # the floor runs up into the walls round a fillet about this big
const FLOOR_CROWN := 0.006
const TRANSOM_RAKE := 0.13   # the transom's foot is this far forward of its top per metre of depth
const GUARD_APEX := 1.08     # the splash guard's point, on the centreline, and where its arms end
const GUARD_END := Vector2(0.5, 0.55)   # a wide V: the arms end out on the side decks, forward of the cockpit
const PAD_IN := 0.42        # non-skid pads on the side decks: inboard edge off the centreline, the
const PAD_FWD := 0.4         # forward end, and the slanted aft end (inboard and outboard corners),
const PAD_AFT := Vector2(-1.19, -1.42)  # which runs onto the aft deck (overhead photo)
const BRIDLE_X := Vector2(-1.46, -1.66) # mainsheet bridle on the aft deck: its block on the
const BRIDLE_Y := 0.6        # centreline, and the deck eyes its two legs run down to
const TOPSIDE_BULGE := 0.008
const BOTTOM_BULGE := 0.006
const SKIPPER_X := -0.6      # where the two sit along the side deck: the skipper in the after part of
const CREW_X := 0.05         # the cockpit, the crew just forward of them (overhead and side photos)
const TILLER_LEN := 1.45     # rudder stock to the extension's joint: forward over the aft deck to
                             # just past the cockpit's aft end, as in the overhead photo
const BOARD_LEN := 0.9       # pivot to tip: down, the board reaches 0.99 m below the waterline
const RATCHET_X := -0.22     # the mainsheet's ratchet block, on a post just aft of the trunk
const SPLIT_CY := 0.2        # with the crew's weight nearer the centreline than this, they sit one each side
const SAIL_AABB := AABB(Vector3(-4.0, -1.0, -4.5), Vector3(8.0, 9.0, 9.0))
const VANG_BOOM := Vector3(0.0, -0.035, 0.5)  # where the vang hangs under the boom (boom frame)
const VANG_FOOT_H := 0.5     # its fitting on the mast's aft face: height, and distance aft of the axis
const VANG_FOOT_R := 0.045
const BOARD_LIFT := 0.851    # the daggerboard's depth below the keel when down (class maximum)
const BOARD_W := 0.521       # its width fore and aft at the top
const BOARD_CASE_H := 0.31   # the case's top above the keel (class: 310 mm)
const BOARD_FWD_X := 0.36    # its forward edge, at the front of the cockpit
const BOARD_BAND_DECK := 0.18  # from the top of the case up to the deck, for the limit band
const COMPASS_X := 0.93      # the tactical compass, in the point of the splash guard
const POLE_MAST_H := 0.95   # where the whisker pole clips onto the mast


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

	## Adds this kit's triangles to `mesh` as one more surface with its own material.
	func commit_to(mesh: ArrayMesh, mat: Material) -> void:
		if count == 0:
			return
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

	## A smooth surface through a grid of points pts[i][j] (rows i, each the same length j).
	## Normals come from the grid itself, so it shades smoothly; they point along `hint`, or
	## away from centers[i] when that is given, or along dirs[i] (one Vector3 for the row, or a
	## PackedVector3Array with one per point) when that is given. `col` is a Color or a
	## Callable(i, j) -> Color for the quad from (i, j) to (i + 1, j + 1).
	func grid(pts: Array, col: Variant, hint := Vector3.ZERO, centers := [], wrap := false, dirs := []) -> void:
		var ni := pts.size()
		var nj: int = (pts[0] as PackedVector3Array).size()
		var ns := []
		for i in ni:
			var row := PackedVector3Array()
			var r: PackedVector3Array = pts[i]
			for j in nj:
				var jm := (j - 1 + nj) % nj if wrap else maxi(j - 1, 0)
				var jp := (j + 1) % nj if wrap else mini(j + 1, nj - 1)
				var du: Vector3 = r[jp] - r[jm]
				var dv: Vector3 = (pts[mini(i + 1, ni - 1)] as PackedVector3Array)[j] - (pts[maxi(i - 1, 0)] as PackedVector3Array)[j]
				var n := du.cross(dv)
				var away: Vector3 = hint
				if not dirs.is_empty():
					var d: Variant = dirs[i]
					away = (d as PackedVector3Array)[j] if d is PackedVector3Array else (d as Vector3)
				elif not centers.is_empty():
					away = r[j] - (centers[i] as Vector3)
				if n.length() < 1e-9:
					n = away
				n = n.normalized()
				if n.dot(away) < 0.0:
					n = -n
				row.append(n)
			ns.append(row)
		for i in ni - 1:
			var a: PackedVector3Array = pts[i]
			var b: PackedVector3Array = pts[i + 1]
			var na: PackedVector3Array = ns[i]
			var nb: PackedVector3Array = ns[i + 1]
			for j in (nj if wrap else nj - 1):
				var j2 := (j + 1) % nj
				var c: Color = col.call(i, j) if col is Callable else col
				if (a[j] - b[j]).length() < 1e-6 and (a[j2] - b[j2]).length() < 1e-6:
					continue
				quad_n(a[j], b[j], b[j2], a[j2], na[j], nb[j], nb[j2], na[j2], c)

	## A closed tube-like body through rings of points (each ring the same size), smooth all
	## round, with optional flat caps at either end.
	func loft(rings: Array, col: Color, cap_a := false, cap_b := false) -> void:
		var centers := []
		for r: PackedVector3Array in rings:
			var c := Vector3.ZERO
			for p in r:
				c += p
			centers.append(c / r.size())
		grid(rings, col, Vector3.ZERO, centers, true)
		for end: Array in [[cap_a, 0, 1], [cap_b, rings.size() - 1, rings.size() - 2]]:
			if not end[0]:
				continue
			var r: PackedVector3Array = rings[end[1]]
			var c: Vector3 = centers[end[1]]
			var out: Vector3 = c - (centers[end[2]] as Vector3)
			for j in r.size():
				tri(c, r[j], r[(j + 1) % r.size()], col, out)

	## A round tube of radius r along a polyline.
	func tube_path(path: PackedVector3Array, r: float, col: Color, seg := 8, caps := true) -> void:
		var rings := []
		for i in path.size():
			var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
			var ref := Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
			var u := t.cross(ref).normalized()
			var w := t.cross(u)
			var ring := PackedVector3Array()
			for k in seg:
				var a := TAU * k / seg
				ring.append(path[i] + (u * cos(a) + w * sin(a)) * r)
			rings.append(ring)
		loft(rings, col, caps, caps)

	## A flat strap of width w and thickness th along a polyline, its face toward `up`.
	func band(path: PackedVector3Array, w: float, th: float, up: Vector3, col: Color) -> void:
		var rings := []
		for i in path.size():
			var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
			var side := t.cross(up).normalized()
			var n := side.cross(t).normalized()
			var p := path[i]
			rings.append(PackedVector3Array([p - side * w * 0.5, p + side * w * 0.5, p + side * w * 0.5 + n * th, p - side * w * 0.5 + n * th]))
		loft(rings, col, true, true)


## Points round a symmetric aerofoil (NACA 00xx) of the given chord and thickness ratio, with
## its leading edge at `le`, chord along `along` and thickness along `across`.
static func foil_ring(le: Vector3, along: Vector3, across: Vector3, chord: float, thick: float, n := 9) -> PackedVector3Array:
	var xs := []
	for i in n + 1:
		xs.append(0.5 * (1.0 - cos(PI * i / n)))  # bunched at both edges
	var out := PackedVector3Array()
	for side: float in [1.0, -1.0]:
		var order := range(n, -1, -1) if side > 0.0 else range(1, n)
		for i: int in order:
			var x: float = xs[i]
			var yt := 5.0 * thick * (0.2969 * sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)
			out.append(le + along * x * chord + across * side * maxf(yt, 0.0015) * chord)
	return out


## Points round a rounded rectangle centred on c in the plane of u and v.
static func rrect_ring(c: Vector3, u: Vector3, v: Vector3, hu: float, hv: float, r: float, per_corner := 3) -> PackedVector3Array:
	var out := PackedVector3Array()
	r = minf(r, minf(hu, hv))
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for k in 4:
		var q: Vector2 = corners[k]
		var cc := Vector2(q.x * (hu - r), q.y * (hv - r))
		var a0 := PI * 0.5 * k
		for m in per_corner + 1:
			var a := a0 + PI * 0.5 * m / per_corner
			var p := cc + Vector2(cos(a), sin(a)) * r
			out.append(c + u * p.x + v * p.y)
	return out


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
		return HALF_BEAM - 0.02 * (0.35 - x) * (0.35 - x)
	# A full bow, as on a real Snipe: the sides carry their width well forward, then close into
	# a tip rounded to about 8 cm in plan (BOW_ROUND). (water.gdshader has a copy of this.)
	var t := clampf((x - 0.35) / (BoatSim.BOW_X - 0.35), 0.0, 1.0)
	var w := 1.0 - t * t
	return HALF_BEAM * sqrt(w) * pow((w + BOW_ROUND) / (1.0 + BOW_ROUND), 0.25)


## The sheer's outward normal in plan at station x, as (forward, outboard) on the starboard
## side. It swings round to dead ahead at the stem.
static func sheer_n(x: float) -> Vector2:
	if x >= BoatSim.BOW_X - 1e-5:
		return Vector2(1.0, 0.0)
	var e := minf(0.002, (BoatSim.BOW_X - x) * 0.5)
	return Vector2(sheer_hb(x - e) - sheer_hb(x + e), 2.0 * e).normalized()


static func chine_hb(x: float) -> float:
	if x <= 0.3:
		return sheer_hb(x) * 0.81
	var t := clampf((x - 0.3) / (BoatSim.BOW_X - 0.3), 0.0, 1.0)
	return sheer_hb(0.3) * 0.81 * (1.0 - pow(t, 1.35))


## Height of the sheer above the waterline: it springs up toward the bow (about 0.53 m at the
## stem against 0.33 m amidships) and a little toward the transom.
static func sheer_h(x: float) -> float:
	if x > 0.0:
		return 0.33 + 0.034 * x * x
	return 0.33 + 0.006 * x * x


## Deck camber: how far the centreline stands above the deck edge where the deck is the full
## half-beam wide. A well-crowned foredeck, nearly flat side decks along the cockpit, a little on
## the aft deck, blended over a short distance at the cockpit ends. A narrower deck gets
## proportionally less, so the cross slope at the edge, and the look of the camber, holds right
## to the bow.
static func camber(x: float) -> float:
	var fwd := smoothstep(COCKPIT_FWD - 0.05, COCKPIT_FWD + 0.4, x)
	var aft := 1.0 - smoothstep(COCKPIT_AFT - 0.15, COCKPIT_AFT + 0.05, x)
	return SIDE_CROWN + (FWD_CROWN - SIDE_CROWN) * fwd + (AFT_CROWN - SIDE_CROWN) * aft


## Where the rolled edge hands over to the deck at station x: [x, half-width, height, crown at
## the centreline, the deck's cross slope there in radians]. The roll is a quarter round of
## DECK_EDGE_R square to the sheer in plan, so round the bow it ends a little aft of the
## station. It stops at the deck's own cross slope, so roll and deck shade as one surface.
static func deck_edge(x: float) -> Array:
	var n := sheer_n(x)
	var c := camber(x)
	var a := atan(2.0 * c / HALF_BEAM)
	var o := DECK_EDGE_R * (1.0 - sin(a))
	var w := maxf(sheer_hb(x) - n.y * o, 0.0)
	return [x - n.x * o, w, sheer_h(x) - DECK_EDGE_R * (1.0 - cos(a)), c * w / HALF_BEAM, a]


## Deck camber at the centreline at station x.
static func crown_at(x: float) -> float:
	return float(deck_edge(x)[3])


## Deck height at station x, y metres off the centreline (inside the rolled edge).
static func deck_h(x: float, y: float) -> float:
	var e := deck_edge(x)
	var t := clampf(absf(y) / maxf(float(e[1]), 0.002), 0.0, 1.0)
	return float(e[2]) + float(e[3]) * (1.0 - t * t)


## Half-width of the cockpit opening at deck level (where the lip starts to roll down), station
## x: COCKPIT_HW along the sides, turning in round corners of radius COCKPIT_RC at each end. The
## sides are parallel, so the side decks narrow a little aft with the sheer (about 0.45 m
## forward, 0.4 m at the aft end), as in the overhead photo.
static func coaming_y(x: float) -> float:
	var cf := COCKPIT_FWD - COCKPIT_RC
	var ca := COCKPIT_AFT + COCKPIT_RC
	var d := 0.0
	if x > cf:
		d = minf(x - cf, COCKPIT_RC)
	elif x < ca:
		d = minf(ca - x, COCKPIT_RC)
	return COCKPIT_HW - COCKPIT_RC + sqrt(COCKPIT_RC * COCKPIT_RC - d * d)


## A point on the stern station moved onto the transom, which is raked a little: its foot is
## further forward than its top.
static func _rake(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y, -(BoatSim.STERN_X + TRANSOM_RAKE * (sheer_h(BoatSim.STERN_X) - p.y)))


## How far the bottom has risen at station x on a run that leaves the flat at x0, curves up
## until x1 and from there runs aft straight, rising s per metre. (water.gdshader has a copy.)
static func _run(x: float, x0: float, x1: float, s: float) -> float:
	if x >= x0:
		return 0.0
	var d := x0 - x1
	if x >= x1:
		return s * (x0 - x) * (x0 - x) / (2.0 * d)
	return s * (x1 - x + d * 0.5)


## The chine rises aft with the keel, so the transom's corners stand about 7 cm above its foot.
static func chine_h(x: float) -> float:
	var h := -0.05
	if x > 0.6:
		h += 0.05 * (x - 0.6) * (x - 0.6)
	h += 0.25 * pow(smoothstep(BoatSim.BOW_X - 0.3, BoatSim.BOW_X, x), 1.6)
	return h + _run(x, 0.3, -0.6, 0.07)


## The keel line, floating at rest as the class figures have her: 0.15 m draft at the deepest
## point (by the centreboard); a straight run aft that leaves the water about 0.4 m forward of
## the transom, so its foot sits 3 cm clear; and a forefoot that meets the water about 0.46 m
## aft of the stem and curves up into it. That makes the class's 3.86 m waterline.
static func keel_h(x: float) -> float:
	var h := -0.15
	if x > 0.6:
		h += 0.0776 * (x - 0.6) * (x - 0.6)
	h += 0.19 * pow(smoothstep(BoatSim.BOW_X - 0.3, BoatSim.BOW_X, x), 1.6)
	h += _run(x, 0.6, -0.34, 0.075)
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
var pole_mi: MeshInstance3D
var vang_foot: MeshInstance3D
var vang_mi: MeshInstance3D
var sheet2_mi: MeshInstance3D
var jibsheet_mi: MeshInstance3D
var pole_line_mi: MeshInstance3D
var rope_mi: MeshInstance3D   # both jib sheets, rebuilt as smooth ropes when the clew moves
var _rope_clew := Vector3(1e6, 0.0, 0.0)
var lazy_mi: Array[MeshInstance3D] = []  # the slack jib sheet in three lengths, and [3] the working sheet's outer part
var _bridle_top := Vector3.ZERO  # top of the bridle block's sheave
var _lead_p := Vector3.ZERO      # top of the starboard jib lead block
var figs: Array[Node3D] = []
var uppers: Array[Node3D] = []
var label: Label3D
var wake_mi: MeshInstance3D
var _phase := 0.0
var _board_drawn := 1.0
var compass_labels: Array[Label3D] = []   # the heading, on the compass's two screens
var _compass_shown := -1
var skipper_side := 1.0   # the side the skipper sits on (1 starboard, -1 port), for the helm camera
var _crew_side := 1.0
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
	board_node.position = hp(BOARD_FWD_X, 0.0, -0.15)
	pivot.add_child(board_node)
	var cbi := MeshInstance3D.new()
	cbi.mesh = _build_board()
	board_node.add_child(cbi)

	sheet_mi = MeshInstance3D.new()
	sheet_mi.mesh = unit_tube(0.006, Color(0.15, 0.2, 0.35))
	sheet_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(sheet_mi)
	# Vang: its lower block swivels on the mast (it turns with the boom but doesn't lift with it),
	# and the purchase is drawn each frame from there to the block under the boom.
	vang_foot = MeshInstance3D.new()
	vang_foot.name = "VangFoot"
	vang_foot.mesh = _build_vang_foot()
	vang_foot.position = Vector3(0.0, VANG_FOOT_H, -BoatSim.MAST_X)
	pivot.add_child(vang_foot)
	vang_mi = MeshInstance3D.new()
	vang_mi.name = "Vang"
	vang_mi.mesh = _vang_lines()
	vang_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(vang_mi)
	# Running rigging drawn each frame: the mainsheet's after part down to the bridle, the working
	# jib sheet from the clew to its lead, and the whisker pole's launcher line to the clew.
	sheet2_mi = MeshInstance3D.new()
	sheet2_mi.mesh = unit_tube(0.006, Color(0.15, 0.2, 0.35))
	jibsheet_mi = MeshInstance3D.new()
	jibsheet_mi.mesh = unit_tube(0.005, Color(0.82, 0.82, 0.78))
	pole_line_mi = MeshInstance3D.new()
	pole_line_mi.mesh = unit_tube(0.003, Color(0.15, 0.4, 0.8))
	for mi: MeshInstance3D in [sheet2_mi, jibsheet_mi, pole_line_mi]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
	rope_mi = MeshInstance3D.new()
	rope_mi.name = "JibSheets"
	rope_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(rope_mi)
	_rope_clew = Vector3(1e6, 0.0, 0.0)
	lazy_mi.clear()
	for k in 4:
		var lm := MeshInstance3D.new()
		lm.mesh = jibsheet_mi.mesh
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(lm)
		lazy_mi.append(lm)
	_bridle_top = hp(BRIDLE_X.x, 0.0, deck_h(BRIDLE_X.x, 0.0) + 0.343)
	var lead_y := COCKPIT_HW + 0.2
	_lead_p = hp(0.2, lead_y, deck_h(0.2, lead_y) + 0.057)
	# Whisker pole, mast to jib clew, shown while it is out.
	pole_mi = MeshInstance3D.new()
	pole_mi.name = "WhiskerPole"
	pole_mi.mesh = unit_tube(0.018, Color(0.78, 0.8, 0.83))
	pole_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole_mi.visible = false
	pivot.add_child(pole_mi)

	# The heading in degrees on each of the compass's two screens.
	compass_labels.clear()
	for sd: float in [-1.0, 1.0]:
		var cl := Label3D.new()
		cl.name = "CompassPort" if sd < 0.0 else "CompassStbd"
		cl.text = "000"
		cl.font_size = 64
		cl.pixel_size = 0.00071
		cl.outline_size = 0
		cl.modulate = Color(0.04, 0.05, 0.04)
		cl.shaded = false
		cl.double_sided = false
		cl.position = hp(COMPASS_X, 0.0, deck_h(COMPASS_X, 0.0) - 0.004) + Vector3(sd * 0.04, 0.0525, 0.0045) + Vector3(sd * 0.7071, 0.0, 0.7071) * 0.003
		cl.rotation.y = sd * PI * 0.25
		pivot.add_child(cl)
		compass_labels.append(cl)
	_compass_shown = -1
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


static var _gel_mat: StandardMaterial3D
static var _deck_mat: StandardMaterial3D
static var _metal_mat: StandardMaterial3D
static var _dark_mat: StandardMaterial3D


## Materials for the boat, all coloured by vertex colour: glossy gelcoat (hull and foils), matt
## non-skid (deck and cockpit), anodised aluminium (spars and metal fittings) and black
## fittings.
static func _boat_mats() -> void:
	if _gel_mat != null:
		return
	_gel_mat = vcol_material(0.12)
	_gel_mat.clearcoat_enabled = true
	_gel_mat.clearcoat = 0.6
	_gel_mat.clearcoat_roughness = 0.08
	_deck_mat = vcol_material(0.72)
	_metal_mat = vcol_material(0.32, 0.85)
	_dark_mat = vcol_material(0.68)  # black plastic hardware: satin, not glossy


## Stations along the hull, bunched toward the bow where the shape changes fastest. The
## cockpit's rounded corners and the bow's rounded tip get stations of their own, spaced by
## angle round the curve, so the deck, the cockpit moulding and the rolled edge meet point for
## point.
static func _stations(n := 64) -> Array[float]:
	var xs: Array[float] = []
	for k in 5:
		var s := sin(PI * 0.5 * k / 4.0)
		xs.append(COCKPIT_FWD - COCKPIT_RC * (1.0 - s))
		xs.append(COCKPIT_AFT + COCKPIT_RC * (1.0 - s))
	for k in 8:
		xs.append(BoatSim.BOW_X - TIP_R * (1.0 - cos(PI * 0.5 * k / 8.0)))
	for i in n + 1:
		var t := float(i) / n
		var x := BoatSim.STERN_X + (BoatSim.BOW_X - BoatSim.STERN_X) * (1.0 - pow(1.0 - t, 1.5))
		if x > BoatSim.BOW_X - TIP_R - 0.01:
			continue
		if x > COCKPIT_FWD - COCKPIT_RC - 0.03 and x < COCKPIT_FWD + 0.03:
			continue
		if x > COCKPIT_AFT - 0.03 and x < COCKPIT_AFT + COCKPIT_RC + 0.03:
			continue
		xs.append(x)
	xs.sort()
	return xs


## One side of the hull at station x: [bottom (keel to chine), topside (chine up to the deck
## edge, then the rolled edge over into the deck)]. Both panels are very slightly convex.
## Topside points: 0-6 the side (with a pinstripe between 4 and 5), 6-10 the rolled edge. The
## roll is square to the sheer in plan, so round the bow it turns forward over the stem.
static func _section(x: float, s: float) -> Array:
	var k := Vector2(0.0, keel_h(x))
	var hb := sheer_hb(x)
	var c := Vector2(s * chine_hb(x), chine_h(x))
	var r := DECK_EDGE_R
	var t := Vector2(s * hb, sheer_h(x) - r)
	var bottom := PackedVector3Array()
	var db := c - k
	var ob := Vector2(db.y, -db.x).normalized() * s
	for v: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var p := k.lerp(c, v) + ob * BOTTOM_BULGE * sin(PI * v)
		bottom.append(hp(x, p.x, p.y))
	var side := PackedVector3Array()
	var dt := t - c
	var ot := Vector2(dt.y, -dt.x).normalized() * s
	for v: float in [0.0, 0.25, 0.5, 0.75, 0.9, 0.94, 1.0]:
		var p := c.lerp(t, v) + ot * TOPSIDE_BULGE * sin(PI * v)
		side.append(hp(x, p.x, p.y))
	var n := sheer_n(x)
	var a_end := PI * 0.5 - float(deck_edge(x)[4])
	for m in range(1, 5):
		var a := a_end * m / 4.0
		var o := r * (1.0 - cos(a))
		side.append(hp(x - n.x * o, s * (hb - n.y * o), t.y + r * sin(a)))
	if x <= BoatSim.STERN_X + 1e-5:
		for i in bottom.size():
			bottom[i] = _rake(bottom[i])
		for i in side.size():
			side[i] = _rake(side[i])
	return [bottom, side]


func _build_hull() -> ArrayMesh:
	_boat_mats()
	var gel := Kit.new()
	var deck := Kit.new()
	var metal := Kit.new()
	var dark := Kit.new()
	var topside := hull_color
	var bottom_c := hull_color.darkened(0.12)
	var stripe := Color(0.06, 0.1, 0.22) if hull_color.get_luminance() > 0.5 else Color(0.95, 0.95, 0.93)
	var deck_c := Color(0.94, 0.94, 0.92)
	var wall_c := Color(0.78, 0.79, 0.8)
	var skid_c := Color(0.66, 0.7, 0.74)
	var floor_c := Color(0.72, 0.73, 0.73)
	var alu := Color(0.8, 0.82, 0.85)
	var black := Color(0.07, 0.07, 0.08)
	var grey := Color(0.24, 0.25, 0.27)
	var xs := _stations()

	# Hull: bottom and topsides on each side, smooth within each panel and sharp at the chine.
	var col_side := func(_i: int, j: int) -> Color:
		if j >= 6:
			return deck_c
		return stripe if j == 4 else topside
	for s: float in [-1.0, 1.0]:
		var bot := []
		var top := []
		var bdir := []
		var tdir := []
		for x in xs:
			var sec := _section(x, s)
			bot.append(sec[0])
			top.append(sec[1])
			var n := sheer_n(x)
			var out := Vector3(s * n.y, 0.0, -n.x)
			bdir.append(out + Vector3.DOWN)
			tdir.append(out + Vector3.UP * 0.4)
		gel.grid(bot, bottom_c, Vector3.ZERO, [], false, bdir)
		gel.grid(top, col_side, Vector3.ZERO, [], false, tdir)
	# Rubbing strake along the hull-deck joint, right round the bow.
	var rail := PackedVector3Array()
	for s: float in [-1.0, 1.0]:
		var order := xs.duplicate()
		if s > 0.0:
			order.reverse()
		for x: float in order:
			if s > 0.0 and x >= BoatSim.BOW_X - 1e-5:
				continue
			var n := sheer_n(x)
			var p := hp(x + n.x * 0.004, s * (sheer_hb(x) + n.y * 0.004), sheer_h(x) - DECK_EDGE_R)
			rail.append(_rake(p) if x <= BoatSim.STERN_X + 1e-5 else p)
	dark.tube_path(rail, 0.012, grey, 6)

	# Transom: the stern section closed off flat, raked a little, with a crisp edge all round.
	var xt := xs[0]
	var stb: Array = _section(xt, 1.0)
	var prt: Array = _section(xt, -1.0)
	var ring := PackedVector3Array()
	ring.append_array(stb[0])
	var ss: PackedVector3Array = stb[1]
	for i in range(1, ss.size()):
		ring.append(ss[i])
	var wbt: float = deck_edge(xt)[1]
	for k in range(1, 12):
		var y := wbt * (1.0 - k / 6.0)
		ring.append(_rake(hp(xt, y, deck_h(xt, y))))
	var ps: PackedVector3Array = prt[1]
	for i in range(ps.size() - 1, -1, -1):
		ring.append(ps[i])
	var pb: PackedVector3Array = prt[0]
	for i in range(pb.size() - 2, 0, -1):
		ring.append(pb[i])
	var tc := _rake(hp(xt, 0.0, (keel_h(xt) + sheer_h(xt)) * 0.5))
	for i in ring.size():
		gel.tri(tc, ring[i], ring[(i + 1) % ring.size()], topside, Vector3(0, 0, 1))

	# Stem band, from the forefoot up the stem and over the top of the rolled edge.
	var stem := PackedVector3Array()
	for x: float in [1.75, 2.0, 2.2, 2.35, BoatSim.BOW_X]:
		stem.append(hp(x, 0.0, keel_h(x) - 0.003))
	var st_top := sheer_h(BoatSim.BOW_X) - DECK_EDGE_R
	for h: float in [0.36, 0.42, st_top]:
		stem.append(hp(BoatSim.BOW_X + 0.003, 0.0, h))
	for a: float in [0.4, 0.8]:
		var rr := DECK_EDGE_R + 0.003
		stem.append(hp(BoatSim.BOW_X - DECK_EDGE_R + rr * cos(a), 0.0, st_top + rr * sin(a)))
	metal.tube_path(stem, 0.009, alu, 6)

	# Deck: the foredeck (glossy, crowned right to the bow) and the aft deck right across; beside
	# the cockpit, side decks out to the coaming, which turns in round the cockpit's corners.
	var fwd_rows := []
	var aft_rows := []
	var strips := [[], []]
	for x in xs:
		var e := deck_edge(x)
		var w: float = e[1]
		if x >= COCKPIT_FWD - 1e-4 or x <= COCKPIT_AFT + 1e-4:
			var row := PackedVector3Array()
			for k in 13:
				var y := w * (k / 6.0 - 1.0)
				var p := hp(float(e[0]), y, deck_h(x, y))
				row.append(_rake(p) if x <= BoatSim.STERN_X + 1e-5 else p)
			if x >= COCKPIT_FWD - 1e-4:
				fwd_rows.append(row)
			else:
				aft_rows.append(row)
		if x >= COCKPIT_AFT - 1e-4 and x <= COCKPIT_FWD + 1e-4:
			var yc := coaming_y(x)
			for si in 2:
				var s := -1.0 if si == 0 else 1.0
				var row := PackedVector3Array()
				for k in 5:
					var f := k / 4.0
					var y := lerpf(w, yc, f)
					row.append(hp(lerpf(float(e[0]), x, f), s * y, deck_h(x, y)))
				strips[si].append(row)
	gel.grid(fwd_rows, deck_c, Vector3.UP)
	gel.grid(aft_rows, deck_c, Vector3.UP)
	for si in 2:
		gel.grid(strips[si], deck_c, Vector3.UP)
	# Grey non-skid pads on the side decks, where the two sit, inside smooth white margins along
	# the coaming and the deck edge. They run from the cockpit's forward end to past its aft end,
	# where they're cut on a slant onto the aft deck; the foredeck and the rest of the aft deck are
	# smooth gelcoat (overhead photo). Each pad is its own thin surface laid 3 mm over the deck.
	for s: float in [-1.0, 1.0]:
		var pad := []
		for i in 25:
			var v := i / 24.0
			var row := PackedVector3Array()
			for k in 4:
				var u := k / 3.0
				var x := lerpf(lerpf(PAD_AFT.x, PAD_AFT.y, u), PAD_FWD, v)
				var y := lerpf(PAD_IN, float(deck_edge(x)[1]) - 0.02, u)
				row.append(hp(x, s * y, deck_h(x, y) + 0.003))
			pad.append(row)
		deck.grid(pad, skid_c, Vector3.UP)
	# Round inspection port in the aft deck, a little off the centreline.
	var ip_x := -1.25
	var ip := hp(ip_x, -0.05, deck_h(ip_x, 0.05))
	dark.cyl(ip - Vector3(0, 0.006, 0), ip + Vector3(0, 0.008, 0), 0.085, black, 20, 0.08, true)
	dark.cyl(ip + Vector3(0, 0.008, 0), ip + Vector3(0, 0.011, 0), 0.06, grey, 20, 0.06, true)
	# Mainsheet bridle: two legs from eyes near the deck edges up to a block on the centreline, a
	# V pointing forward from above (overhead photo), high enough for the tiller to pass under.
	var bx := BRIDLE_X.x
	var blk_p := hp(bx, 0.0, deck_h(bx, 0.0) + 0.3)
	for s: float in [-1.0, 1.0]:
		var ex := BRIDLE_X.y
		var eye := hp(ex, s * BRIDLE_Y, deck_h(ex, BRIDLE_Y))
		metal.cyl(eye - Vector3(0, 0.003, 0), eye + Vector3(0, 0.012, 0), 0.012, alu, 8, 0.009, true)
		dark.cyl(eye + Vector3(0, 0.01, 0), blk_p, 0.0045, Color(0.86, 0.86, 0.8), 6)
	_block(dark, metal, blk_p + Vector3.UP * 0.026, Vector3.DOWN, Vector3.RIGHT, 0.018)
	# The traveler line across between the bridle's legs.
	var eye_s := hp(BRIDLE_X.y, BRIDLE_Y, deck_h(BRIDLE_X.y, BRIDLE_Y))
	var eye_p := hp(BRIDLE_X.y, -BRIDLE_Y, deck_h(BRIDLE_X.y, BRIDLE_Y))
	# The same white rope as the bridle (the mainsheet is the dark blue one), tied round each leg.
	var rope := Color(0.86, 0.86, 0.8)
	var bar_s := eye_s.lerp(blk_p, 0.45)
	var bar_p := eye_p.lerp(blk_p, 0.45)
	dark.cyl(bar_s, bar_p, 0.0045, rope, 6)
	for e: Array in [[eye_s, bar_s], [eye_p, bar_p]]:
		var leg: Vector3 = (blk_p - (e[0] as Vector3)).normalized()
		var at: Vector3 = e[1]
		dark.cyl(at - leg * 0.02, at + leg * 0.02, 0.009, rope.darkened(0.3), 8, 0.009, true)

	# The cockpit moulding, one surface right round: from the coaming over the lip, down the
	# sloping tank sides and end walls, round a fillet and across a slightly crowned floor. Each
	# ring of it is the opening shrunk by that ring's inset (the side walls slope in further than
	# the end walls), so the corners tighten toward the floor instead of folding over.
	var outline := _cockpit_outline(xs)
	var tub := []
	var tub_dirs := []
	for q in 11:
		tub.append([])
		tub_dirs.append([])
	for smp: Array in outline:
		var p: Vector2 = smp[0]
		var m: Vector2 = smp[1]
		var wgt: float = smp[2]
		var h0 := deck_h(p.x, absf(p.y))
		var p_side := _tub_profile(h0, LIP_R + TANK_SLOPE)
		var p_end := _tub_profile(h0, LIP_R + END_SLOPE)
		var mw := Vector3(m.y, 0.0, -m.x)
		for q in p_side.size():
			var pl := _cockpit_inset(smp, p_side[q].x, p_end[q].x)
			tub[q].append(hp(pl.x, pl.y, lerpf(p_side[q].y, p_end[q].y, wgt)))
			tub_dirs[q].append(mw + Vector3.UP * 0.7)
		var fp := _cockpit_inset(smp, p_side[7].x, p_end[7].x)
		# The floor's spine: the centreline between the floor's own corner centres.
		var fr := maxf(COCKPIT_RC - p_end[7].x, CORNER_MIN)
		var spine := Vector2(clampf(fp.x, COCKPIT_AFT + p_end[7].x + fr, COCKPIT_FWD - p_end[7].x - fr), 0.0)
		for q in range(1, 4):
			var f := q / 3.0
			var pl := fp.lerp(spine, f)
			tub[7 + q].append(hp(pl.x, pl.y, FLOOR_H + FLOOR_CROWN * (1.0 - (1.0 - f) * (1.0 - f))))
			tub_dirs[7 + q].append(Vector3.UP)
	for q in tub.size():
		tub[q] = PackedVector3Array(tub[q])
		tub_dirs[q] = PackedVector3Array(tub_dirs[q])
	var col_tub := func(i: int, _j: int) -> Color:
		if i < 3:
			return deck_c
		return wall_c if i < 6 else floor_c
	deck.grid(tub, col_tub, Vector3.ZERO, [], true, tub_dirs)
	# Two venturi bailers in the cockpit floor, near its aft end, inboard of the hiking straps.
	for s: float in [-1.0, 1.0]:
		var c := hp(COCKPIT_AFT + 0.24, s * 0.055, FLOOR_H + 0.004)
		dark.loft([rrect_ring(c, Vector3.RIGHT, Vector3.BACK, 0.04, 0.07, 0.02), rrect_ring(c + Vector3(0, 0.01, 0), Vector3.RIGHT, Vector3.BACK, 0.032, 0.062, 0.016)], grey, false, true)

	# Splash guard: a V-shaped breakwater on the foredeck ahead of the mast, its arms sweeping
	# back to the cockpit's forward corners. Tallest at the point, curling forward along the top,
	# with a fillet down its back into the deck.
	var guard := []
	var guard_dirs := []
	for i in 29:
		var v := -1.0 + 2.0 * i / 28.0
		var u := signf(v) * pow(absf(v), 1.3)
		var pl := _guard_plan(u)
		var tg := (_guard_plan(u + 0.01) - _guard_plan(u - 0.01)).normalized()
		var nf := Vector2(tg.y, -tg.x)
		if nf.x < 0.0:
			nf = -nf
		var a := absf(u)
		var hh := lerpf(0.1, 0.045, pow(a, 1.3)) * lerpf(1.0, 0.3, smoothstep(0.86, 1.0, a))
		var th := 0.014
		var base := hp(pl.x, pl.y, deck_h(pl.x, absf(pl.y)))
		var fw := Vector3(nf.y, 0.0, -nf.x)
		var lean := func(z: float) -> float:
			return 0.2 * z + 0.25 * hh * pow(clampf(z / hh, 0.0, 1.0), 3.0)
		var sec := PackedVector3Array()
		var sdir := PackedVector3Array()
		for z: float in [-0.012, 0.3 * hh, 0.6 * hh, 0.85 * hh]:
			sec.append(base + fw * (th * 0.5 + lean.call(z)) + Vector3.UP * z)
			sdir.append(fw)
		var zt := hh - th * 0.5
		for k in 5:
			var ang := PI * k / 4.0
			sec.append(base + fw * (lean.call(zt) + th * 0.5 * cos(ang)) + Vector3.UP * (zt + th * 0.5 * sin(ang)))
			sdir.append(fw * cos(ang) + Vector3.UP * sin(ang))
		for z: float in [0.85 * hh, 0.6 * hh, 0.3 * hh, 0.08 * hh, -0.012]:
			var fil := 0.03 * pow(1.0 - clampf(z / (0.45 * hh), 0.0, 1.0), 2.0)
			sec.append(base + fw * (-th * 0.5 + lean.call(z) - fil) + Vector3.UP * z)
			sdir.append(Vector3.UP - fw)
		guard.append(sec)
		guard_dirs.append(sdir)
	gel.grid(guard, deck_c, Vector3.ZERO, [], true, guard_dirs)
	for end: Array in [[0, 1], [guard.size() - 1, guard.size() - 2]]:
		var er: PackedVector3Array = guard[end[0]]
		var ec := Vector3.ZERO
		for p in er:
			ec += p / er.size()
		var eo := ec - (guard[end[1]] as PackedVector3Array)[0]
		for j in er.size():
			gel.tri(ec, er[j], er[(j + 1) % er.size()], deck_c, eo)

	# Mast partners: the mast goes down through a slot in the foredeck (the pusher/puller moves
	# it fore and aft), with an aluminium plate round the slot and a rubber collar on the mast.
	var mx := BoatSim.MAST_X
	var fa := hp(mx + 0.15, 0.0, deck_h(mx + 0.15, 0.0))
	var ab := hp(mx - 0.15, 0.0, deck_h(mx - 0.15, 0.0))
	var along := (ab - fa).normalized()
	var up_d := along.cross(Vector3.RIGHT).normalized()
	var pc := hp(mx, 0.0, deck_h(mx, 0.0))
	metal.loft([rrect_ring(pc - up_d * 0.004, Vector3.RIGHT, along, 0.06, 0.15, 0.045),
		rrect_ring(pc + up_d * 0.003, Vector3.RIGHT, along, 0.057, 0.147, 0.042)], alu, false, true)
	dark.loft([rrect_ring(pc + up_d * 0.0025, Vector3.RIGHT, along, 0.03, 0.105, 0.028),
		rrect_ring(pc + up_d * 0.0036, Vector3.RIGHT, along, 0.029, 0.104, 0.027)], black, false, true)
	dark.loft([rrect_ring(pc, Vector3.RIGHT, along, 0.042, 0.05, 0.034),
		rrect_ring(pc + up_d * 0.026, Vector3.RIGHT, along, 0.035, 0.043, 0.03)], black, false, true)
	# Stemhead fitting for the forestay.
	var fx := BoatSim.JIB_TACK_X
	var fb := hp(fx, 0.0, deck_h(fx, 0.0))
	metal.loft([rrect_ring(fb - Vector3(0, 0.004, 0), Vector3.RIGHT, Vector3.BACK, 0.02, 0.05, 0.015),
		rrect_ring(fb + Vector3(0, 0.003, 0), Vector3.RIGHT, Vector3.BACK, 0.017, 0.047, 0.013)], alu, false, true)
	metal.cyl(fb, Vector3(0, JIB_TACK_H + 0.035, -fx), 0.006, alu, 6, 0.006, true)

	# Centreboard trunk: a moulded case with a rounded top.
	var trunk := []
	# The daggerboard case: low (310 mm above the keel), from just aft of the board to the cockpit's
	# forward wall.
	var case_top := -0.15 + BOARD_CASE_H
	var case_mid := (FLOOR_H + case_top) * 0.5 - 0.01
	var xa := BOARD_FWD_X - BOARD_W - 0.04
	for x: float in [xa, xa + 0.015, COCKPIT_FWD - 0.065, COCKPIT_FWD - 0.05]:
		var bevel := 0.008 if x < xa + 0.01 or x > COCKPIT_FWD - 0.06 else 0.0
		trunk.append(rrect_ring(hp(x, 0.0, case_mid), Vector3.RIGHT, Vector3.UP, 0.04 - bevel, case_top - case_mid - bevel, 0.03))
	deck.loft(trunk, wall_c, true, true)
	# Mainsheet ratchet block on its post just aft of the trunk, between skipper and crew.
	dark.cyl(hp(RATCHET_X, 0.0, FLOOR_H), hp(RATCHET_X, 0.0, 0.29), 0.016, black, 10)
	dark.cyl(hp(RATCHET_X, 0.0, 0.285), hp(RATCHET_X, 0.0, 0.302), 0.026, Color(0.15, 0.15, 0.16), 14, 0.024, true)
	_block(dark, metal, hp(RATCHET_X, 0.0, 0.345), Vector3.DOWN, Vector3.RIGHT, 0.03)

	# Hiking straps, from the foot of the cockpit's aft wall forward along the floor beside the
	# trunk to the foot of the forward wall, under the feet of both sailors.
	var floor_hw := COCKPIT_HW - LIP_R - TANK_SLOPE - FILLET
	for s: float in [-1.0, 1.0]:
		var strap := PackedVector3Array()
		for k in 9:
			var t := k / 8.0
			strap.append(hp(lerpf(COCKPIT_AFT + 0.12, COCKPIT_FWD - 0.11, t), s * lerpf(floor_hw - 0.025, 0.085, t), FLOOR_H + 0.01 + 0.07 * sin(PI * t)))
		dark.band(strap, 0.045, 0.006, Vector3.UP, Color(0.08, 0.12, 0.32))
		# Jib fairlead and cam cleat on the inboard part of the side deck.
		var y := COCKPIT_HW + 0.2
		_jib_lead(dark, metal, hp(0.2, s * y, deck_h(0.2, y)), Vector3(0, 0, -1), Vector3.UP)
		_cam_cleat(dark, metal, hp(-0.05, s * y, deck_h(-0.05, y)), Vector3(-s * 0.5, 0.0, 1.0), Vector3.UP)
		# The jib sheet's tail from the lead block back through the cleat.
		dark.cyl(hp(0.2, s * y, deck_h(0.2, y) + 0.043), hp(-0.05, s * y, deck_h(-0.05, y) + 0.016), 0.005, Color(0.82, 0.82, 0.78), 6)
		dark.cyl(hp(-0.05, s * y, deck_h(-0.05, y) + 0.016), hp(-0.3, s * (y - 0.12), deck_h(-0.3, y - 0.12) + 0.006), 0.005, Color(0.82, 0.82, 0.78), 6)

	# Rudder fittings on the transom.
	for h: float in [0.05, 0.3]:
		metal.cyl(hp(BoatSim.STERN_X + 0.01, 0.0, h), hp(BoatSim.STERN_X - 0.07, 0.0, h), 0.012, alu, 8, 0.012, true)

	# Mast: a pear-ish section, tapering above the hounds, through a collar at the deck.
	var mz := -BoatSim.MAST_X
	var mast := []
	for y: float in [-0.05, 1.0, 3.0, HOUNDS, (HOUNDS + MAST_TOP) * 0.5, MAST_TOP]:
		var taper := clampf((y - HOUNDS) / (MAST_TOP - HOUNDS), 0.0, 1.0)
		var mr := PackedVector3Array()
		for k in 14:
			var a := TAU * k / 14
			var fwd := 1.0 if sin(a) < 0.0 else 0.85
			mr.append(Vector3(cos(a) * lerpf(0.03, 0.019, taper), y, mz + sin(a) * lerpf(0.037, 0.023, taper) * fwd))
		mast.append(mr)
	metal.loft(mast, alu, false, false)
	dark.cyl(Vector3(0, MAST_TOP - 0.02, mz), Vector3(0, MAST_TOP + 0.04, mz), 0.026, black, 10, 0.02, true)
	var dh := deck_h(BoatSim.MAST_X, 0.0)
	dark.cyl(Vector3(0, dh - 0.01, mz), Vector3(0, dh + 0.05, mz), 0.05, black, 14, 0.042, true)
	# Tactical compass, tucked into the point of the splash guard: a grey wedge with two screens
	# angled out to port and starboard, so the helm reads one from either side deck.
	var cmp_cc := hp(COMPASS_X, 0.0, deck_h(COMPASS_X, 0.0) - 0.004)
	var cmp_ch := 0.105
	var cmp_case_c := Color(0.36, 0.37, 0.4)
	var cmp_plan := [Vector2(0.0, 0.045), Vector2(0.08, -0.036), Vector2(0.027, -0.075), Vector2(-0.027, -0.075), Vector2(-0.08, -0.036)]
	var cmp_ctop := cmp_cc + Vector3(0.0, cmp_ch, -0.02)
	for i in cmp_plan.size():
		var cmp_a2: Vector2 = cmp_plan[i]
		var cmp_b2: Vector2 = cmp_plan[(i + 1) % cmp_plan.size()]
		var cmp_a3 := cmp_cc + Vector3(cmp_a2.x, 0.0, cmp_a2.y)
		var cmp_b3 := cmp_cc + Vector3(cmp_b2.x, 0.0, cmp_b2.y)
		var cmp_outn := Vector3(cmp_b2.y - cmp_a2.y, 0.0, -(cmp_b2.x - cmp_a2.x))
		if cmp_outn.dot(Vector3((cmp_a2.x + cmp_b2.x) * 0.5, 0.0, (cmp_a2.y + cmp_b2.y) * 0.5 + 0.02)) < 0.0:
			cmp_outn = -cmp_outn
		dark.quad(cmp_a3, cmp_b3, cmp_b3 + Vector3(0, cmp_ch, 0), cmp_a3 + Vector3(0, cmp_ch, 0), cmp_case_c, cmp_outn)
		dark.tri(cmp_ctop, cmp_a3 + Vector3(0, cmp_ch, 0), cmp_b3 + Vector3(0, cmp_ch, 0), cmp_case_c.lightened(0.1), Vector3.UP)
	for cmp_sd: float in [-1.0, 1.0]:
		var face_n := Vector3(cmp_sd * 0.7071, 0.0, 0.7071)
		var face_along := Vector3(cmp_sd * 0.7071, 0.0, -0.7071)
		var face_c := cmp_cc + Vector3(cmp_sd * 0.04, cmp_ch * 0.5, 0.0045) + face_n * 0.0012
		gel.quad(face_c - face_along * 0.043 - Vector3(0, 0.027, 0), face_c + face_along * 0.043 - Vector3(0, 0.027, 0),
			face_c + face_along * 0.043 + Vector3(0, 0.027, 0), face_c - face_along * 0.043 + Vector3(0, 0.027, 0), Color(0.66, 0.71, 0.62), face_n)

	# Standing rigging: aerofoil spreaders, shrouds with adjusters, forestay.
	var hounds := Vector3(0, HOUNDS, mz)
	var wire := Color(0.35, 0.36, 0.38)
	for s: float in [-1.0, 1.0]:
		var root := Vector3(0, SPREADER_H, mz)
		var tip := Vector3(s * 0.4, SPREADER_H, mz + 0.12)
		var ax := (tip - root).normalized()
		var chord_dir := (Vector3.BACK - ax * ax.dot(Vector3.BACK)).normalized()
		var thick_dir := ax.cross(chord_dir).normalized()
		var sp := []
		for t: float in [0.03, 0.5, 0.97, 1.0]:
			var ch := lerpf(0.05, 0.032, t) * (0.6 if t > 0.98 else 1.0)
			var c := root.lerp(tip, t)
			var spr := PackedVector3Array()
			for k in 10:
				var a := TAU * k / 10
				spr.append(c + chord_dir * cos(a) * ch * 0.5 + thick_dir * sin(a) * 0.008)
			sp.append(spr)
		metal.loft(sp, alu, false, true)
		var chain := hp(0.55, s * (sheer_hb(0.55) - 0.02), sheer_h(0.55))
		metal.cyl(hounds, tip, 0.0045, wire, 5)
		metal.cyl(tip, chain + (tip - chain).normalized() * 0.14, 0.0045, wire, 5)
		dark.cyl(chain, chain + (tip - chain).normalized() * 0.14, 0.011, grey, 8, 0.008, true)
		metal.cyl(chain - Vector3(0, 0.05, 0), chain + Vector3(0, 0.02, 0), 0.012, alu, 6, 0.012, true)
	metal.cyl(Vector3(0, JIB_TACK_H + 0.03, -BoatSim.JIB_TACK_X), Vector3(0, HOUNDS, mz - 0.03), 0.0045, wire, 5)

	var mesh := ArrayMesh.new()
	gel.commit_to(mesh, _gel_mat)
	deck.commit_to(mesh, _deck_mat)
	metal.commit_to(mesh, _metal_mat)
	dark.commit_to(mesh, _dark_mat)
	return mesh


## Points round the cockpit opening at deck level: up the starboard side from aft to forward
## (the corners at the stations _stations() put there), across the forward end, down the port
## side and across the aft end. Each is [position (x, y), inward normal in plan, how much it
## belongs to an end wall (0 on the sides, 1 on the ends), which end it's at (1 forward, -1 aft,
## 0 along a side), which side (1 starboard, -1 port, 0 across an end)].
static func _cockpit_outline(xs: Array[float]) -> Array:
	var cf := COCKPIT_FWD - COCKPIT_RC
	var ca := COCKPIT_AFT + COCKPIT_RC
	var yf := COCKPIT_HW - COCKPIT_RC
	var stbd := []
	for x in xs:
		if x < COCKPIT_AFT - 1e-4 or x > COCKPIT_FWD + 1e-4:
			continue
		var p := Vector2(x, coaming_y(x))
		var m := Vector2(0.0, -1.0)
		var wgt := 0.0
		var ex := 0.0
		if x > cf + 1e-5:
			m = (Vector2(cf, yf) - p).normalized()
			wgt = asin(clampf((x - cf) / COCKPIT_RC, 0.0, 1.0)) / (PI * 0.5)
			ex = 1.0
		elif x < ca - 1e-5:
			m = (Vector2(ca, yf) - p).normalized()
			wgt = asin(clampf((ca - x) / COCKPIT_RC, 0.0, 1.0)) / (PI * 0.5)
			ex = -1.0
		stbd.append([p, m, wgt, ex, 1.0])
	var out := stbd.duplicate()
	for k in range(1, 6):
		out.append([Vector2(COCKPIT_FWD, yf * (1.0 - k / 3.0)), Vector2(-1.0, 0.0), 1.0, 1.0, 0.0])
	for i in range(stbd.size() - 1, -1, -1):
		var smp: Array = stbd[i]
		var p: Vector2 = smp[0]
		var m: Vector2 = smp[1]
		out.append([Vector2(p.x, -p.y), Vector2(m.x, -m.y), smp[2], smp[3], -1.0])
	for k in range(1, 6):
		out.append([Vector2(COCKPIT_AFT, -yf * (1.0 - k / 3.0)), Vector2(1.0, 0.0), 1.0, -1.0, 0.0])
	return out


## Where an outline point of _cockpit_outline() goes when the opening is shrunk by ds on the
## sides and de at the ends: the sides and ends move straight in, and each corner shrinks round
## its own centre to radius COCKPIT_RC - inset (never below CORNER_MIN; past that the centre
## moves in instead, and the points along the sides and ends close up to make room).
static func _cockpit_inset(smp: Array, ds: float, de: float) -> Vector2:
	var p: Vector2 = smp[0]
	var ex: float = smp[3]
	var ey: float = smp[4]
	var cf := COCKPIT_FWD - COCKPIT_RC
	var ca := COCKPIT_AFT + COCKPIT_RC
	var yf := COCKPIT_HW - COCKPIT_RC
	var rx := maxf(COCKPIT_RC - de, CORNER_MIN)
	var ry := maxf(COCKPIT_RC - ds, CORNER_MIN)
	var cf2 := COCKPIT_FWD - de - rx
	var ca2 := COCKPIT_AFT + de + rx
	var yf2 := COCKPIT_HW - ds - ry
	if ex == 0.0:
		return Vector2(lerpf(ca2, cf2, (p.x - ca) / (cf - ca)), ey * (COCKPIT_HW - ds))
	var c2 := cf2 if ex > 0.0 else ca2
	if ey == 0.0:
		return Vector2(c2 + ex * rx, p.y * yf2 / yf)
	var c := cf if ex > 0.0 else ca
	return Vector2(c2 + (p.x - c) * rx / COCKPIT_RC, ey * yf2 + (p.y - ey * yf) * ry / COCKPIT_RC)


## The moulding's section from the coaming down at one point, as (inset, height) pairs: the
## coaming at h0, three points round the lip, which rolls over until it meets the slope of the
## wall below it, the wall (inset df at the floor), and four round the fillet to the floor.
static func _tub_profile(h0: float, df: float) -> PackedVector2Array:
	var a_end := PI * 0.5 - atan((df - LIP_R) / (h0 - LIP_R - FLOOR_H))
	var prof := PackedVector2Array([Vector2(0.0, h0)])
	for q in range(1, 4):
		var a := a_end * q / 3.0
		prof.append(Vector2(LIP_R * sin(a), h0 - LIP_R + LIP_R * cos(a)))
	var corner := Vector2(df, FLOOR_H)
	var pw := corner - (corner - prof[3]).normalized() * FILLET
	var pf := corner + Vector2(FILLET, 0.0)
	prof.append(prof[3].lerp(pw, 0.5))
	prof.append(pw)
	prof.append(pw * 0.25 + corner * 0.5 + pf * 0.25)
	prof.append(pf)
	return prof


## The splash guard's line in plan: u runs from -1 (the port end) through 0 (the point) to 1
## (the starboard end). A V with straight arms and a rounded point.
static func _guard_plan(u: float) -> Vector2:
	var a := absf(u)
	var d := 0.12
	var f := (sqrt(a * a + d * d) - d) / (sqrt(1.0 + d * d) - d)
	return Vector2(lerpf(GUARD_APEX, GUARD_END.x, f), GUARD_END.y * u)


## A dinghy block: two flat cheek plates round a sheave on a pin, and a wire shackle at the
## head. `c` is the sheave's centre, `up` points toward what it's shackled to, `axle` along the
## pin, `r` the sheave's radius.
static func _block(dark: Kit, metal: Kit, c: Vector3, up: Vector3, axle: Vector3, r: float, col := Color(0.08, 0.08, 0.09)) -> void:
	var u := up.normalized()
	var ax := (axle - u * axle.dot(u)).normalized()
	var w := u.cross(ax).normalized()
	var th := r * 0.16
	var gap := r * 0.32
	var steel := Color(0.72, 0.74, 0.77)
	for sd: float in [-1.0, 1.0]:
		var pc := c + u * r * 0.25 + ax * sd * (gap + th * 0.5)
		dark.loft([rrect_ring(pc - ax * th * 0.5, u, w, r * 1.55, r * 0.98, r * 0.6),
			rrect_ring(pc + ax * th * 0.5, u, w, r * 1.55, r * 0.98, r * 0.6)], col, true, true)
	metal.cyl(c - ax * gap, c + ax * gap, r * 0.95, Color(0.5, 0.52, 0.55), 14, r * 0.95, true)
	metal.cyl(c - ax * (gap + th * 1.5), c + ax * (gap + th * 1.5), r * 0.16, steel, 6, r * 0.16, true)
	var head := c + u * r * 1.45
	var loop := PackedVector3Array()
	for k in 7:
		var a := PI * k / 6.0
		loop.append(head + ax * cos(a) * gap * 1.15 + u * sin(a) * r * 0.55)
	metal.tube_path(loop, r * 0.09, steel, 5)


## A cam cleat on the deck: a base plate, two toothed cams and a wire fairlead on the side the
## line is pulled from. `pull` points that way, `up` is the deck's normal.
static func _cam_cleat(dark: Kit, metal: Kit, c: Vector3, pull: Vector3, up: Vector3) -> void:
	var n := up.normalized()
	var f := (pull - n * pull.dot(n)).normalized()
	var sd := n.cross(f).normalized()
	dark.loft([rrect_ring(c, f, sd, 0.04, 0.017, 0.008), rrect_ring(c + n * 0.007, f, sd, 0.038, 0.015, 0.007)],
		Color(0.13, 0.13, 0.14), true, true)
	for k: float in [-1.0, 1.0]:
		var cc := c + sd * k * 0.0105 + n * 0.007 - f * 0.004
		dark.cyl(cc, cc + n * 0.016, 0.0085, Color(0.05, 0.05, 0.06), 12, 0.0085, true)
	var arch := PackedVector3Array()
	for k in 7:
		var a := PI * k / 6.0
		arch.append(c + f * 0.03 + sd * cos(a) * 0.012 + n * (0.007 + sin(a) * 0.017))
	metal.tube_path(arch, 0.0022, Color(0.72, 0.74, 0.77), 5)


## A jib lead: a short track along the deck, a car on it and a block standing on the car.
static func _jib_lead(dark: Kit, metal: Kit, c: Vector3, along: Vector3, up: Vector3) -> void:
	var n := up.normalized()
	var f := (along - n * along.dot(n)).normalized()
	var sd := n.cross(f).normalized()
	metal.loft([rrect_ring(c, f, sd, 0.11, 0.011, 0.004), rrect_ring(c + n * 0.006, f, sd, 0.11, 0.011, 0.004)],
		Color(0.72, 0.74, 0.77), true, true)
	dark.loft([rrect_ring(c + n * 0.006, f, sd, 0.028, 0.016, 0.006), rrect_ring(c + n * 0.018, f, sd, 0.028, 0.016, 0.006)],
		Color(0.08, 0.08, 0.09), true, true)
	_block(dark, metal, c + n * 0.043, -n, sd, 0.016)


## A polyline with each inner corner rounded off over `rnd` metres.
static func _round_path(pts: Array, rnd: float) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i - 1]
		var p: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var r := minf(rnd, minf(a.distance_to(p), b.distance_to(p)) * 0.45)
		var p0 := p + (a - p).normalized() * r
		var p1 := p + (b - p).normalized() * r
		for k in 7:
			var t := k / 6.0
			out.append(p0.lerp(p, t).lerp(p.lerp(p1, t), t))
	out.append(pts[pts.size() - 1])
	return out


## The two jib sheets as ropes, each one piece (rebuilt when the clew has moved). The working
## one runs from its lead to the clew, and round the inboard, forward face of the shroud when the
## clew is out past the wire. The other is slack: from the clew it hangs round the front of the
## mast and lies along the deck to its lead.
func _draw_jib_sheets(jclew: Vector3, mz: float) -> void:
	if rope_mi.mesh != null and jclew.distance_to(_rope_clew) < 0.004:
		return
	_rope_clew = jclew
	var k := Kit.new()
	var col := Color(0.82, 0.82, 0.78)
	var sd := -1.0 if jclew.x < 0.0 else 1.0
	var jl := Vector3(sd * _lead_p.x, _lead_p.y, _lead_p.z)
	var work: Array = [jl]
	if jclew.z < -0.6:
		var tt := clampf((-0.55 - jl.z) / (jclew.z - jl.z), 0.0, 1.0)
		var h := lerpf(jl.y, jclew.y, tt)
		var ts := clampf((h - 0.34) / (SPREADER_H - 0.34), 0.0, 1.0)
		var wx := lerpf(sheer_hb(0.55) - 0.02, 0.4, ts)
		var wz := lerpf(-0.55, mz + 0.12, ts)
		if absf(lerpf(jl.x, jclew.x, tt)) > wx - 0.014:
			work.append(Vector3(sd * (wx - 0.014), h, wz - 0.014))
	work.append(jclew)
	k.tube_path(_round_path(work, 0.05), 0.005, col, 6)
	var ld := Vector3(-sd * _lead_p.x, _lead_p.y, _lead_p.z)
	var front := Vector3(sd * 0.03, minf(jclew.y, 0.6), mz - 0.1)
	var hang := jclew.lerp(front, 0.5) - Vector3(0.0, 0.07, 0.0)
	var deck := front.lerp(ld, 0.55)
	deck.y = _lead_p.y + 0.02
	k.tube_path(_round_path([jclew, hang, front, deck, ld], 0.22), 0.005, col, 6)
	rope_mi.mesh = k.commit(_shared_vcol)


## The vang's direction, from its fitting on the mast up to its bail under the boom, in the
## boom's frame (z along the boom).
static func _vang_dir() -> Vector3:
	return (Vector3(0.0, BOOM_H + VANG_BOOM.y - VANG_FOOT_H, VANG_BOOM.z - VANG_FOOT_R)).normalized()


## The vang's lower block on a tang from the mast, in a frame at the mast's axis with z along
## the boom.
func _build_vang_foot() -> ArrayMesh:
	_boat_mats()
	var metal := Kit.new()
	var dark := Kit.new()
	var d := _vang_dir()
	var m := Vector3(0.0, 0.0, VANG_FOOT_R)
	metal.cyl(Vector3.ZERO, m + Vector3(0, 0, 0.004), 0.007, Color(0.72, 0.74, 0.77), 8, 0.007, true)
	_block(dark, metal, m + d * 0.029, -d, Vector3.RIGHT, 0.02)
	var mesh := ArrayMesh.new()
	metal.commit_to(mesh, _metal_mat)
	dark.commit_to(mesh, _dark_mat)
	return mesh


## The vang's purchase: three parts of line side by side, one unit long along +y (aim_tube
## stretches it between the two blocks).
static func _vang_lines() -> ArrayMesh:
	_boat_mats()
	var k := Kit.new()
	for o: float in [-0.006, 0.0, 0.006]:
		k.cyl(Vector3(o, 0.0, 0.0), Vector3(o, 1.0, 0.0), 0.0032, Color(0.62, 0.16, 0.12), 5)
	var mesh := ArrayMesh.new()
	k.commit_to(mesh, _dark_mat)
	return mesh


func _build_boom() -> ArrayMesh:
	_boat_mats()
	var metal := Kit.new()
	var dark := Kit.new()
	var alu := Color(0.8, 0.82, 0.85)
	var black := Color(0.07, 0.07, 0.08)
	# Oval section, deeper than wide.
	var rings := []
	for z: float in [0.06, 0.5, 1.5, 2.5, BoatSim.BOOM_LEN - 0.04]:
		var ring := PackedVector3Array()
		for k in 12:
			var a := TAU * k / 12
			ring.append(Vector3(cos(a) * 0.025, sin(a) * 0.035, z))
		rings.append(ring)
	metal.loft(rings, alu, false, false)
	# Gooseneck and end fitting, mainsheet and vang blocks, and the vang down to the mast foot:
	# both its ends stay put as the boom swings.
	dark.cyl(Vector3(0, 0, -0.03), Vector3(0, 0, 0.08), 0.03, black, 10, 0.036, true)
	dark.cyl(Vector3(0, 0, BoatSim.BOOM_LEN - 0.05), Vector3(0, 0, BoatSim.BOOM_LEN + 0.02), 0.037, black, 10, 0.024, true)
	# Mainsheet blocks hanging under the boom, one over the ratchet block and one over the bridle,
	# and the sheet running along under the boom between them.
	for z: float in [1.0, 2.2]:
		_block(dark, metal, Vector3(0, -0.035 - 0.03, z), Vector3.UP, Vector3.RIGHT, 0.02)
	dark.cyl(Vector3(0, -0.047, 1.0), Vector3(0, -0.047, 2.2), 0.006, Color(0.15, 0.2, 0.35), 6)
	# Vang: the upper block, shackled to a bail under the boom and lying along the vang's line.
	# (Its lower block and the purchase are separate nodes: see setup.)
	var vd := _vang_dir()
	metal.cyl(VANG_BOOM + Vector3(0, 0.012, 0), VANG_BOOM - Vector3(0, 0.004, 0), 0.008, Color(0.72, 0.74, 0.77), 8, 0.008, true)
	_block(dark, metal, VANG_BOOM - vd * 0.029, vd, Vector3.RIGHT, 0.02)
	var mesh := ArrayMesh.new()
	metal.commit_to(mesh, _metal_mat)
	dark.commit_to(mesh, _dark_mat)
	return mesh


func _build_rudder() -> ArrayMesh:
	_boat_mats()
	var gel := Kit.new()
	var dark := Kit.new()
	# Blade: NACA 0010 sections with the leading edge on the pivot, raked aft a little, and a
	# rounded tip.
	var rings := []
	for y: float in [0.0, -0.15, -0.3, -0.45, -0.6, -0.72, -0.82, -0.9, -0.95, -0.98, -1.0]:
		var depth := -y
		var full := lerpf(0.27, 0.22, depth)
		var tip := clampf((depth - 0.8) / 0.2, 0.0, 1.0)
		var chord := full * sqrt(maxf(1.0 - tip * tip, 0.02))
		rings.append(foil_ring(Vector3(0, y, 0.03 * depth + (full - chord) * 0.6), Vector3.BACK, Vector3.RIGHT, chord, 0.1))
	gel.loft(rings, Color(0.93, 0.93, 0.91), false, true)
	# Rudder head: aluminium cheeks round the top of the blade, with the tiller socket.
	var metal := Kit.new()
	var head := []
	for y: float in [-0.04, -0.025, 0.16, 0.175]:
		var b := 0.005 if y < -0.03 or y > 0.17 else 0.0
		head.append(rrect_ring(Vector3(0, y, 0.075), Vector3.RIGHT, Vector3.BACK, 0.026 - b, 0.09 - b, 0.02))
	metal.loft(head, Color(0.72, 0.74, 0.77), true, true)
	var sock := []
	for z: float in [0.1, 0.07, -0.06, -0.08]:
		var b := 0.004 if z > 0.09 or z < -0.07 else 0.0
		sock.append(rrect_ring(Vector3(0, 0.2, z), Vector3.RIGHT, Vector3.UP, 0.026 - b, 0.034 - b, 0.012))
	metal.loft(sock, Color(0.72, 0.74, 0.77), true, true)
	# Carbon tiller, oval and tapering, forward over the aft deck to just past the cockpit's aft
	# end; joint for the extension.
	var tiller := []
	for z: float in [0.08, -0.1, -0.6, -1.1, -TILLER_LEN - 0.01]:
		var t := clampf((0.08 - z) / (TILLER_LEN + 0.09), 0.0, 1.0)
		var tr := PackedVector3Array()
		for k in 10:
			var a := TAU * k / 10
			tr.append(Vector3(cos(a) * lerpf(0.018, 0.013, t), 0.2 + sin(a) * lerpf(0.027, 0.017, t), z))
		tiller.append(tr)
	dark.loft(tiller, Color(0.09, 0.09, 0.1), true, true)
	# Rubber universal joint at the tip, where the extension would clip on.
	dark.cyl(Vector3(0, 0.2, -TILLER_LEN + 0.012), Vector3(0, 0.2, -TILLER_LEN - 0.035), 0.012, Color(0.13, 0.13, 0.14), 10, 0.011, true)
	var mesh := ArrayMesh.new()
	gel.commit_to(mesh, _gel_mat)
	metal.commit_to(mesh, _metal_mat)
	dark.commit_to(mesh, _dark_mat)
	return mesh


## The daggerboard, to the class drawing: a flat aluminium plate 521 mm fore and aft at the top
## and 254 mm at the bottom, its after edge vertical and its forward edge raked over the lower
## 900 mm; 1161 mm long, so that with its two rubber stoppers resting on top of the case (310 mm
## above the keel) it reaches 851 mm below the keel. A U is cut out of the top under the handle
## bar, and a red band marks how far it may be raised. Origin: the top forward corner's position
## at keel level, with the board down; +z aft, +y up.
func _build_board() -> ArrayMesh:
	_boat_mats()
	var metal := Kit.new()
	var dark := Kit.new()
	var gel := Kit.new()
	var alu := Color(0.74, 0.76, 0.79)
	var th := 0.005
	var w := BOARD_W
	var d := BOARD_LIFT
	var top := BOARD_CASE_H
	var rake_top := -d + 0.9
	var fwd_z := func(y: float) -> float:
		return (w - 0.254) * clampf((rake_top - y) / 0.9, 0.0, 1.0)
	var quads := [[Vector2(w - 0.254, -d), Vector2(w, -d), Vector2(w, rake_top), Vector2(0.0, rake_top)]]
	var post := 0.06
	var r := (w - 2.0 * post) * 0.5
	var zc := w * 0.5
	var yc := top - 0.02
	quads.append([Vector2(0.0, rake_top), Vector2(post, rake_top), Vector2(post, top), Vector2(0.0, top)])
	quads.append([Vector2(w - post, rake_top), Vector2(w, rake_top), Vector2(w, top), Vector2(w - post, top)])
	for k in 12:
		var z0 := post + 2.0 * r * k / 12.0
		var z1 := post + 2.0 * r * (k + 1) / 12.0
		var y0 := yc - sqrt(maxf(r * r - (z0 - zc) * (z0 - zc), 0.0))
		var y1 := yc - sqrt(maxf(r * r - (z1 - zc) * (z1 - zc), 0.0))
		quads.append([Vector2(z0, rake_top), Vector2(z1, rake_top), Vector2(z1, y1), Vector2(z0, y0)])
	for q: Array in quads:
		for sx: float in [-1.0, 1.0]:
			var v := []
			for c: Vector2 in q:
				v.append(Vector3(sx * th, c.y, c.x))
			metal.quad(v[0], v[1], v[2], v[3], alu, Vector3(sx, 0.0, 0.0))
	# Edges of the plate.
	for e: Array in [[Vector2(w, -d), Vector2(w, top), Vector3(0, 0, 1)], [Vector2(w - 0.254, -d), Vector2(w, -d), Vector3.DOWN],
			[Vector2(w - 0.254, -d), Vector2(0.0, rake_top), Vector3(0, -0.3, -1)], [Vector2(0.0, rake_top), Vector2(0.0, top), Vector3(0, 0, -1)]]:
		var ea: Vector2 = e[0]
		var eb: Vector2 = e[1]
		metal.quad(Vector3(-th, ea.y, ea.x), Vector3(th, ea.y, ea.x), Vector3(th, eb.y, eb.x), Vector3(-th, eb.y, eb.x), alu.darkened(0.12), e[2])
	# The limit band: its top is 615 mm plus the case-to-deck distance above the board's bottom.
	var band_top := -d + 0.615 + BOARD_BAND_DECK
	for sx: float in [-1.0, 1.0]:
		var x := sx * (th + 0.0008)
		gel.quad(Vector3(x, band_top - 0.03, float(fwd_z.call(band_top - 0.03))), Vector3(x, band_top - 0.03, w),
			Vector3(x, band_top, w), Vector3(x, band_top, float(fwd_z.call(band_top))), Color(0.82, 0.1, 0.07), Vector3(sx, 0.0, 0.0))
	# Handle bar across the top, and the two rubber stoppers that sit on top of the case.
	metal.cyl(Vector3(0, top + 0.012, -0.015), Vector3(0, top + 0.012, w + 0.015), 0.012, alu, 8, 0.012, true)
	for zz: float in [0.035, w - 0.035]:
		dark.cyl(Vector3(-0.03, top + 0.022, zz), Vector3(0.03, top + 0.022, zz), 0.022, Color(0.06, 0.06, 0.07), 12, 0.022, true)
	var mesh := ArrayMesh.new()
	metal.commit_to(mesh, _metal_mat)
	dark.commit_to(mesh, _dark_mat)
	gel.commit_to(mesh, _gel_mat)
	return mesh


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
	# The shroud the main lies against when the boom is right out (see rig_fit in the shader).
	main_mat.set_shader_parameter("mast_z", -BoatSim.MAST_X)
	main_mat.set_shader_parameter("shroud_base", Vector3(sheer_hb(0.55) - 0.02, sheer_h(0.55), -0.55))
	main_mat.set_shader_parameter("shroud_tip", Vector3(0.4, SPREADER_H, -BoatSim.MAST_X + 0.12))
	main_mat.set_shader_parameter("shroud_top", Vector3(0.0, HOUNDS, -BoatSim.MAST_X))
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
	jib_mat.set_shader_parameter("mast_z", -BoatSim.MAST_X)
	jib_mat.set_shader_parameter("window_box", Vector4(0.3, 0.115, 0.62, 0.175))
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


## The two sailors aren't drawn (Doug, 18 Nov: "just remove the people"). Their weight and how
## far out they sit are in the physics (BoatSim.crew_mass and crew_y). Each still has an empty
## node, posed every frame where they would sit, so the helm camera is at the skipper's eye.
func _build_crew() -> void:
	for who in 2:
		var fig := Node3D.new()
		fig.name = "Skipper" if who == 0 else "Crew"
		pivot.add_child(fig)
		var upper := Node3D.new()
		fig.add_child(upper)
		figs.append(fig)
		uppers.append(upper)

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




# --- Telltales --------------------------------------------------------------------------------

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


## A point on a posed sail (the vertex shader's shape without the flutter), with the surface
## direction along the chord there and the chord normal: [point, along, normal].
static func sail_frame(tack: Vector3, head: Vector3, clew: Vector3, belly: float, twist: float, roach: float,
		foot_attached: float, u: float, v: float, draft := 0.444, luff_sag := 0.0) -> Array:
	var side := 1.0 if belly >= 0.0 else -1.0
	var luff := tack.lerp(head, v)
	var d := clew.lerp(head, v) - luff
	var a := twist * v * side
	d = Vector3(d.x * cos(a) + d.z * sin(a), d.y, -d.x * sin(a) + d.z * cos(a))
	var cdir := d.normalized()
	d += cdir * roach * pow(sin(PI * v), 0.8)
	var ln := d.length()
	var n := Vector3(d.z, 0.0, -d.x).normalized()
	# The shader's camber(): u^a (1-u)^b, 1 at the draft position.
	var ea := maxf(1.0, draft / (1.0 - draft))
	var eb := maxf(1.0, (1.0 - draft) / draft)
	var peak := pow(draft, ea) * pow(1.0 - draft, eb)
	var uc := clampf(u, 0.0, 1.0)
	var shape := pow(uc, ea) * pow(1.0 - uc, eb) / peak
	var dshape := (ea * pow(uc, ea - 1.0) * pow(1.0 - uc, eb) - eb * pow(uc, ea) * pow(1.0 - uc, eb - 1.0)) / peak
	var foot := lerpf(1.0, smoothstep(0.0, 0.14, v), foot_attached)
	var sag := luff_sag * sin(PI * v)
	var p := luff + d * u + n * belly * ln * shape * foot + n * side * sag * (1.0 - u)
	var along := (d + n * belly * ln * dshape * foot - n * side * sag).normalized()
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
	for y in yarns:
		y.visible = near and not capsized
	if not near:
		return
	if capsized:
		return
	var up := Vector3.UP
	var lee := 1.0 if _jib_belly >= 0.0 else -1.0
	for i in 4:
		# Each pair reads the flow at its own height: with too much twist the top pair lifts first.
		var ja := absf(_alpha(sim, false, JIB_YARN_V[i >> 1]))
		var luff_k := 1.0 - smoothstep(0.05, 0.09, ja)
		var stall_k := smoothstep(0.33, 0.43, ja)
		var face_side := 1.0 if i % 2 == 0 else -1.0
		var f := sail_frame(jtack, jhead, jclew, _jib_belly, _jib_twist, 0.0, 0.0, 0.17, JIB_YARN_V[i >> 1], _jib_draft, _jib_sag)
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
	var mlee := 1.0 if _main_belly >= 0.0 else -1.0
	for i in 3:
		# The top leech ribbon stalls first when the leech is closed (guide: top batten parallel
		# to the boom, top telltale flying most of the time in light air).
		var ma := absf(_alpha(sim, true, LEECH_V[i]))
		var m_luff := 1.0 - smoothstep(0.05, 0.09, ma)
		var m_stall := smoothstep(0.4, 0.47, ma)
		var f := sail_frame(tack, mhead, clew, _main_belly, _main_twist, 0.16, 1.0, 1.0, LEECH_V[i], _main_draft)
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


## Angle of attack at height fraction v of a sail, from the sim's three strips; a posed sim
## (tests/view_test) only has the one angle per sail.
static func _alpha(sim, is_main: bool, v: float) -> float:
	var arr: PackedFloat32Array = sim.main_alphas if is_main else sim.jib_alphas
	if arr[0] == 0.0 and arr[1] == 0.0 and arr[2] == 0.0:
		return float(sim.main_alpha if is_main else sim.jib_alpha)
	return sim.alpha_at(is_main, v)


## A point on the lower shroud (chainplate to spreader tip) at height `h`, side `s` (+1 stbd).
func _shroud_point(s: float, h: float) -> Vector3:
	var mz := -BoatSim.MAST_X
	var tip := Vector3(s * 0.4, SPREADER_H, mz + 0.12)
	var chain := hp(0.55, s * (sheer_hb(0.55) - 0.02), sheer_h(0.55))
	return chain.lerp(tip, clampf((h - chain.y) / (tip.y - chain.y), 0.0, 1.0))


## The skipper's eye point in world space (for a helm camera).
func skipper_eye() -> Vector3:
	var base := global_transform if is_inside_tree() else transform
	if figs.is_empty():
		return base * Vector3(0.0, 1.05, -SKIPPER_X)
	return (base * pivot.transform * figs[0].transform * uppers[0].transform) * Vector3(-0.08, 0.8, 0.0)


# --- Per frame --------------------------------------------------------------------------------

var _main_belly := 0.0
var _jib_belly := 0.0
var _jib_twist := 0.14
var _main_draft := 0.444
var _jib_draft := 0.42
var _jib_sag := 0.0
var _last_t := -1.0
var drawn_heel := 0.0  # the heel this view was last drawn with (interpolated), for the cameras


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
	drawn_heel = heel
	var capsized: bool = sim.capsized
	var bob := 0.016 * sin(time * 1.9 + _phase) + 0.008 * sin(time * 3.3 + _phase * 2.0)
	var pitch := 0.01 * sin(time * 1.6 + _phase * 1.3) + 0.022 * smoothstep(1.5, 4.5, u)
	# The crew's weight fore and aft trims her (bow down is a negative pitch here).
	if sim.has_method("trim"):
		pitch -= float(sim.trim())
	pivot.position = Vector3(0.0, bob - (0.12 if capsized else 0.0), 0.0)
	pivot.basis = Basis.from_euler(Vector3(pitch, 0.0, -heel))

	var boom: float = sim.boom
	var jib: float = sim.jib
	var awa: float = sim.awa
	var aws: float = sim.aws
	# A free leech lets the boom lift (the vang or the mainsheet over the traveler holds it down).
	var rise := -0.09 * (1.0 - clampf(float(sim.leech_hold), 0.0, 1.0)) if not capsized else 0.0
	boom_node.rotation = Vector3(rise, boom, 0.0)
	rudder_node.rotation = Vector3(0.0, clampf(sim.tiller, -1.0, 1.0) * BoatSim.MAX_RUDDER, 0.0)
	# The daggerboard lifts straight up through the trunk, its head standing up in the cockpit.
	var bwant := clampf(float(sim.board), 0.0, 1.0)
	_board_drawn = move_toward(_board_drawn, bwant, 1.6 * dt) if dt > 0.0 else bwant
	board_node.position.y = -0.15 + (1.0 - _board_drawn) * BOARD_LIFT

	# Sails belly to leeward of their own chord; a backed jib bellies the other way.
	# Depth from the sim's shape (middle third), filling with the breeze.
	var fill := clampf(aws / 2.5, 0.2, 1.0)
	var md := clampf(float(sim.main_depth[1]), 0.04, 0.16)
	var jd := clampf(float(sim.jib_depth[1]), 0.04, 0.18)
	var mb := -signf(sin(awa + boom)) * md * fill * clampf(absf(sin(awa + boom)) * 5.0, 0.3, 1.0)
	var jb := -signf(sin(awa + jib)) * jd * fill * clampf(absf(sin(awa + jib)) * 5.0, 0.3, 1.0)
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
	var clew := tack + Basis.from_euler(Vector3(rise, boom, 0.0)) * Vector3(0.0, 0.0, BoatSim.BOOM_LEN - 0.08)
	main_mat.set_shader_parameter("tack", tack)
	main_mat.set_shader_parameter("head", mhead)
	main_mat.set_shader_parameter("clew", clew)
	main_mat.set_shader_parameter("belly", _main_belly)
	# Twist and draft from the sim (a posed sim that was never stepped has no twist yet).
	var mt: float = sim.main_twist
	_main_twist = clampf(mt, 0.0, 0.6) if mt > 0.0 else 0.1 + 0.22 * clampf(absf(boom) / 1.3, 0.0, 1.0)
	_main_draft = clampf(float(sim.main_draft), 0.35, 0.6)
	main_mat.set_shader_parameter("twist", _main_twist)
	main_mat.set_shader_parameter("draft", _main_draft)
	main_mat.set_shader_parameter("flutter", main_flut)
	var jtack := Vector3(0.0, JIB_TACK_H + 0.04, -BoatSim.JIB_TACK_X + 0.03)
	var stay := (Vector3(0.0, HOUNDS, mz - 0.03) - jtack).normalized()
	var jclew := jtack + Vector3(sin(jib), 0.0, cos(jib)) * BoatSim.JIB_FOOT + Vector3(0.0, 0.2, 0.0)
	jib_mat.set_shader_parameter("tack", jtack)
	jib_mat.set_shader_parameter("head", jtack + stay * JIB_LUFF)
	jib_mat.set_shader_parameter("clew", jclew)
	# The jib's after part goes round the mast on the side its clew is on, not through it.
	jib_mat.set_shader_parameter("mast_side", 1.0 if jclew.x >= 0.0 else -1.0)
	jib_mat.set_shader_parameter("boom_keep", tan(minf(absf(boom), 1.3)) if boom * jclew.x > 0.0 else 0.0)
	jib_mat.set_shader_parameter("belly", _jib_belly)
	var jt: float = sim.jib_twist
	_jib_twist = clampf(jt, 0.0, 0.5) if jt > 0.0 else 0.14
	_jib_draft = clampf(float(sim.jib_draft), 0.35, 0.6)
	# Forestay sag: the luff bows to leeward on a slack rig.
	_jib_sag = 0.0254 * clampf(float(sim.stay_sag), 0.0, 6.0) * (0.0 if capsized else 1.0)
	jib_mat.set_shader_parameter("twist", _jib_twist)
	jib_mat.set_shader_parameter("draft", _jib_draft)
	jib_mat.set_shader_parameter("luff_sag", _jib_sag)
	jib_mat.set_shader_parameter("flutter", jib_flut)

	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var dist := cam.global_position.distance_to(global_position) if cam != null else 0.0
	var near := dist < DETAIL_DIST
	_pose_details(sim, near, capsized, time, jtack, jtack + stay * JIB_LUFF, jclew, tack, mhead, clew)
	var hd := int(fposmod(rad_to_deg(float(sim.heading)), 360.0))
	for cl in compass_labels:
		cl.visible = near
		if near and hd != _compass_shown:
			cl.text = "%03d" % hd
	if near:
		_compass_shown = hd
	sheet_mi.visible = near
	sheet2_mi.visible = near
	jibsheet_mi.visible = false
	for lm in lazy_mi:
		lm.visible = false
	rope_mi.visible = near
	if near:
		# From the top of the ratchet block's sheave to the bottom of the forward boom block's, and
		# from the after boom block down to the block on the bridle.
		aim_tube(sheet_mi, hp(RATCHET_X, 0.0, 0.372), boom_node.transform * Vector3(0.0, -0.083, 1.0))
		aim_tube(sheet2_mi, _bridle_top, boom_node.transform * Vector3(0.0, -0.083, 2.2))
		_draw_jib_sheets(jclew, mz)
	vang_foot.rotation.y = boom
	vang_mi.visible = near
	if near:
		var vd := _vang_dir()
		aim_tube(vang_mi, vang_foot.transform * (Vector3(0.0, 0.0, VANG_FOOT_R) + vd * 0.029), boom_node.transform * (VANG_BOOM - vd * 0.029))
	# The pole runs out from the mast to the clew as the crew sets it.
	var po: float = sim.pole_out
	pole_mi.visible = not capsized and dist < 300.0
	var pole_tip := jclew
	if po > 0.02:
		# It runs out from the mast to the clew, and from POLE_ON_CLEW on its tip is on the clew.
		var m0 := Vector3(0.0, POLE_MAST_H, mz + 0.03)
		pole_tip = m0.lerp(jclew, clampf(po / BoatSim.POLE_ON_CLEW, 0.05, 1.0))
		aim_tube(pole_mi, m0, pole_tip)
	else:
		# Stowed alongside the boom, its tip forward by the gooseneck.
		pole_tip = boom_node.transform * Vector3(0.05, 0.0, 0.15)
		aim_tube(pole_mi, boom_node.transform * Vector3(0.05, 0.0, 0.15 + BoatSim.POLE_LEN), pole_tip)
	# The launcher line, from the pole's tip to the jib's clew: pulling it runs the pole out.
	pole_line_mi.visible = near and not capsized and pole_tip.distance_to(jclew) > 0.03
	if pole_line_mi.visible:
		aim_tube(pole_line_mi, pole_tip, jclew)
	_pose_crew(sim, capsized)

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
			# In the water by the upturned hull, both aft of the centreboard (the skipper about
			# 0.8 m aft of the CG, the crew about 0.1 m).
			var want := Transform3D(Basis.from_scale(Vector3(-cs, 1.0, 1.0)),
				Vector3(-cs * (1.0 + 0.15 * i), -0.6, 0.82 if i == 0 else 0.1))
			figs[i].transform = inv * want
			uppers[i].basis = Basis.IDENTITY
		return
	# Which side each sits on. With their weight well off the centreline both sit on that side;
	# near it, they sit one each side (the cockpit is too narrow to sit in). Each stays put until
	# they have to move, so in a tack the crew crosses first and the skipper follows.
	# The crew only rejoins the skipper once the weight is well out (crew_y wobbles through a tack).
	var a := absf(cy)
	var want := 1.0 if cy >= 0.0 else -1.0
	if a >= SPLIT_CY and want != skipper_side:
		skipper_side = want
		_crew_side = want
	elif a >= SPLIT_CY + 0.1 and _crew_side != skipper_side:
		_crew_side = skipper_side
	elif a < SPLIT_CY and _crew_side == skipper_side:
		_crew_side = -skipper_side
	var bang := clampf(float(sim.boom), -1.4, 1.4)
	for i in 2:
		var x: float = (SKIPPER_X if i == 0 else CREW_X) + float(sim.crew_x)
		var s := skipper_side if i == 0 else _crew_side
		# Sat across from the skipper, the crew sits in.
		var ai := a * 0.95 if i == 0 else (a if s == skipper_side else 0.0)
		# Both sit on the side deck: just outboard of the coaming when they move in, sliding out
		# to the deck edge as they sit out, then leaning out from the edge to hike.
		var t := smoothstep(0.1, 0.4, ai)
		var inner := COCKPIT_HW + 0.13
		var rail := sheer_hb(x) - 0.07
		var lat := lerpf(inner, rail - 0.06 + 0.06 * smoothstep(0.5, 0.9, ai), t)
		var hh := lerpf(deck_h(x, inner), sheer_h(x), t) + 0.07
		var lean := clampf((ai - 0.55) / 0.5, 0.0, 1.0) * 0.8 - 0.1 * (1.0 - t)
		# Duck when the boom is over their head (a tack, or sat to leeward under it): it is at
		# about head height for someone sat on the deck.
		var d := BoatSim.MAST_X - x
		if d < BoatSim.BOOM_LEN * cos(bang):
			var duck := 1.0 - smoothstep(0.2, 0.5, absf(d * tan(bang) - s * lat))
			lean = lerpf(lean, -0.9, duck)
		# Both face forward and in. Sat in, they turn further forward, so their feet stay on the
		# floor beside the trunk instead of reaching across it.
		var face := Basis(Vector3.UP, lerpf(-0.9, -0.35, t) if i == 0 else lerpf(-0.75, -0.45, t))
		figs[i].transform = Transform3D(Basis.from_scale(Vector3(s, 1.0, 1.0)) * face, hp(x, s * lat, hh))
		uppers[i].basis = Basis(Vector3.BACK, -lean)
