extends RefCounted
## Union Reservoir geometry. World coordinates are Vector2(east, north) in metres, origin at the
## centre of the reservoir's bounding box. In 3D, east is +X and north is -Z.

var shore := PackedVector2Array()
var marks := {}  # "1".."9" -> Vector2
var dock := Vector2.ZERO
var origin_lat := 0.0
var origin_lon := 0.0
var elevation_m := 1511.0
var bounds := Rect2()

var sdf := PackedFloat32Array()
var sdf_w := 0
var sdf_h := 0
var sdf_origin := Vector2.ZERO
var sdf_cell := 5.0


func _init() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/union_reservoir.json"))
	for p: Array in d["shore"]:
		shore.append(Vector2(p[0], p[1]))
	for k: String in d["marks"]:
		marks[k] = Vector2(d["marks"][k][0], d["marks"][k][1])
	dock = Vector2(d["usc_dock"][0], d["usc_dock"][1])
	origin_lat = d["origin_lat"]
	origin_lon = d["origin_lon"]
	elevation_m = d["elevation_m"]
	bounds = Rect2(shore[0], Vector2.ZERO)
	for p in shore:
		bounds = bounds.expand(p)
	var f := FileAccess.open("res://data/shore_sdf.bin", FileAccess.READ)
	sdf_w = f.get_32()
	sdf_h = f.get_32()
	sdf_origin = Vector2(f.get_float(), f.get_float())
	sdf_cell = f.get_float()
	sdf = f.get_buffer(sdf_w * sdf_h * 4).to_float32_array()


func contains(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, shore)


## Signed distance to the shoreline in metres: negative on the water, positive on land.
func shore_distance(p: Vector2) -> float:
	var g := (p - sdf_origin) / sdf_cell
	if g.x < 0.0 or g.y < 0.0 or g.x > sdf_w - 1.001 or g.y > sdf_h - 1.001:
		return 500.0
	var i := int(g.x)
	var j := int(g.y)
	var fx := g.x - i
	var fy := g.y - j
	var a := sdf[j * sdf_w + i]
	var b := sdf[j * sdf_w + i + 1]
	var c := sdf[(j + 1) * sdf_w + i]
	var e := sdf[(j + 1) * sdf_w + i + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, e, fx), fy)


func closest_shore_point(p: Vector2) -> Vector2:
	var best := shore[0]
	var best_d := INF
	for i in shore.size():
		var q := Geometry2D.get_closest_point_to_segment(p, shore[i], shore[(i + 1) % shore.size()])
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


## Distance along a ray until it leaves the water (INF if it does not within max_dist).
func ray_to_shore(from: Vector2, dir: Vector2, max_dist: float) -> float:
	var to := from + dir * max_dist
	var best := INF
	for i in shore.size():
		var hit = Geometry2D.segment_intersects_segment(from, to, shore[i], shore[(i + 1) % shore.size()])
		if hit != null:
			best = minf(best, from.distance_to(hit))
	return best


## The distance field as a single-channel float texture for shaders.
func sdf_texture() -> ImageTexture:
	var img := Image.create_from_data(sdf_w, sdf_h, false, Image.FORMAT_RF, sdf.to_byte_array())
	return ImageTexture.create_from_image(img)


static func to_3d(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, -p.y)


static func to_2d(v: Vector3) -> Vector2:
	return Vector2(v.x, -v.z)
