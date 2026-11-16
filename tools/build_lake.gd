extends SceneTree
## Builds data/union_reservoir.json from the OpenStreetMap shoreline and the club's reference map.
##
## Shoreline: OSM way 43241479 ("Union Reservoir", natural=water), saved raw in
## tools/union_osm_raw.json (Overpass API, overpass-api.de). OSM data is (c) OpenStreetMap
## contributors, ODbL.
##
## Marks 1-9: the USC sailing instructions only say the marks are "located approximately as
## shown" on Appendix A. This registers that map image to the OSM shoreline (north-up, so
## scale + offset from the water bounding boxes), then finds the white mark numbers painted on
## the water and converts their centres to metres.
##
## Run: godot --headless --path . --script res://tools/build_lake.gd -- <reference_map_image>

const WAY_ID := 43241479
# WGS84 metres per degree near 40.18 N.
const LAT0 := 40.18
const M_PER_DEG_LAT := 111038.0
const M_PER_DEG_LON := 85167.0

var last_box := Rect2i()


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/union_osm_raw.json"))
	var geo: Array = []
	for el: Dictionary in raw["elements"]:
		if el.get("type") == "way" and int(el.get("id")) == WAY_ID:
			geo = el["geometry"]
	if geo.is_empty():
		push_error("way %d not found" % WAY_ID)
		quit(1)
		return

	# Origin: centre of the OSM bounding box.
	var min_lat := 999.0
	var max_lat := -999.0
	var min_lon := 999.0
	var max_lon := -999.0
	for g: Dictionary in geo:
		min_lat = minf(min_lat, g["lat"])
		max_lat = maxf(max_lat, g["lat"])
		min_lon = minf(min_lon, g["lon"])
		max_lon = maxf(max_lon, g["lon"])
	var lat0 := (min_lat + max_lat) * 0.5
	var lon0 := (min_lon + max_lon) * 0.5
	var shore := PackedVector2Array()
	for g: Dictionary in geo:
		shore.append(Vector2((g["lon"] - lon0) * M_PER_DEG_LON, (g["lat"] - lat0) * M_PER_DEG_LAT))
	if shore[0].distance_to(shore[shore.size() - 1]) < 0.01:
		shore.remove_at(shore.size() - 1)
	# Counter-clockwise (east, north) order.
	if _signed_area(shore) < 0.0:
		shore.reverse()
	var bb := _bbox(shore)
	print("shore points %d, area %.0f m^2 (%.0f acres), bbox %s" % [shore.size(), absf(_signed_area(shore)), absf(_signed_area(shore)) / 4046.86, bb])

	var reg := {}
	if args.size() > 0:
		reg = _register_marks(args[0], shore, bb)

	var out := {
		"source": "OpenStreetMap way %d (c) OpenStreetMap contributors, ODbL. Marks registered from USC SI Appendix A." % WAY_ID,
		"origin_lat": lat0,
		"origin_lon": lon0,
		"elevation_m": 1511.0,
		"shore": _vec_list(shore),
		"marks": reg.get("marks", {}),
		"usc_dock": reg.get("usc_dock", []),
	}
	var f := FileAccess.open("res://data/union_reservoir.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote data/union_reservoir.json")
	build_sdf(shore)
	quit()


func _register_marks(path: String, shore: PackedVector2Array, bb: Rect2) -> Dictionary:
	var img := Image.load_from_file(path)
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	# Water on this image is a dark teal: blue at or above red, not bright.
	var water := PackedByteArray()
	water.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var is_water := c.b >= c.r - 0.005 and c.g > c.r and c.v < 0.55 and c.v > 0.08
			water[y * w + x] = 1 if is_water else 0
	var comp := _largest_component(water, w, h)
	# Fill small holes (the painted numbers and "North" arrow sit on the water).
	var minx := w
	var maxx := 0
	var miny := h
	var maxy := 0
	var count := 0
	for y in h:
		for x in w:
			if comp[y * w + x] == 1:
				count += 1
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)
	print("image %dx%d, water component %d px, bbox x %d..%d y %d..%d" % [w, h, count, minx, maxx, miny, maxy])
	var sx := bb.size.x / float(maxx - minx)
	var sy := bb.size.y / float(maxy - miny)
	print("scale x %.3f m/px, y %.3f m/px (should agree)" % [sx, sy])
	# The two scales differ by a few percent (image resampling), so map each axis on its own.
	var to_m := func(px: Vector2) -> Vector2:
		return Vector2(bb.position.x + (px.x - minx) * sx, bb.end.y - (px.y - miny) * sy)

	# White paint inside the water bounding box: the digits 1-9, "North" and its arrow.
	var white := PackedByteArray()
	white.resize(w * h)
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var c := img.get_pixel(x, y)
			if c.r > 0.7 and c.g > 0.7 and c.b > 0.7:
				white[y * w + x] = 1
	var blobs := _blobs(white, w, h, 3)
	print("white blobs: %d" % blobs.size())
	for b: Dictionary in blobs:
		var ctr: Vector2 = b["center"]
		print("  blob px %s size %s n %d -> m %s inside=%s" % [ctr, b["size"], b["n"], to_m.call(ctr), Geometry2D.is_point_in_polygon(to_m.call(ctr), shore)])
	return _name_marks(blobs, to_m, shore)


func _largest_component(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var label := PackedInt32Array()
	label.resize(w * h)
	var best_id := 0
	var best_n := 0
	var next_id := 1
	for i in w * h:
		if mask[i] == 1 and label[i] == 0:
			var n := _flood(mask, label, w, h, i, next_id)
			if n > best_n:
				best_n = n
				best_id = next_id
			next_id += 1
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 if label[i] == best_id else 0
	return out


func _flood(mask: PackedByteArray, label: PackedInt32Array, w: int, h: int, start: int, id: int) -> int:
	var stack := [start]
	label[start] = id
	var n := 0
	last_box = Rect2i(start % w, start / w, 1, 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		n += 1
		var x := i % w
		var y := i / w
		last_box = last_box.expand(Vector2i(x, y))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			if mask[j] == 1 and label[j] == 0:
				label[j] = id
				stack.append(j)
	return n


## Connected blobs of set pixels, merged when their boxes are within `gap` px (digit strokes).
func _blobs(mask: PackedByteArray, w: int, h: int, gap: int) -> Array:
	var label := PackedInt32Array()
	label.resize(w * h)
	var boxes := []
	var next_id := 1
	for i in w * h:
		if mask[i] == 1 and label[i] == 0:
			var n := _flood(mask, label, w, h, i, next_id)
			var r := last_box
			boxes.append({"r": r, "n": n})
			next_id += 1
	var merged := true
	while merged:
		merged = false
		for a in boxes.size():
			for b in range(a + 1, boxes.size()):
				if boxes[a]["r"].grow(gap).intersects(boxes[b]["r"]):
					boxes[a]["r"] = boxes[a]["r"].merge(boxes[b]["r"])
					boxes[a]["n"] += boxes[b]["n"]
					boxes.remove_at(b)
					merged = true
					break
			if merged:
				break
	var out := []
	for bx: Dictionary in boxes:
		if bx["n"] < 6:
			continue
		var r: Rect2i = bx["r"]
		out.append({"center": Vector2(r.position) + Vector2(r.size) * 0.5, "size": r.size, "n": bx["n"]})
	return out


func _signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


func _bbox(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


func _vec_list(p: PackedVector2Array) -> Array:
	var out := []
	for v in p:
		out.append([snappedf(v.x, 0.01), snappedf(v.y, 0.01)])
	return out


## Where each number is painted on the Appendix A image (read by eye), snapped to the detected
## blob. The USC dock is the small pier just left of the "USC" label, snapped to the shoreline.
const MARK_PX := {
	"1": Vector2(382, 394), "2": Vector2(384, 291), "3": Vector2(474, 324),
	"4": Vector2(493, 395), "5": Vector2(473, 471), "6": Vector2(383, 499),
	"7": Vector2(294, 463), "8": Vector2(276, 394), "9": Vector2(295, 323),
}
const DOCK_PX := Vector2(522, 605)


func _name_marks(blobs: Array, to_m: Callable, shore: PackedVector2Array) -> Dictionary:
	var marks := {}
	for key: String in MARK_PX:
		var best: Vector2 = MARK_PX[key]
		var best_d := 12.0
		for b: Dictionary in blobs:
			var d: float = b["center"].distance_to(MARK_PX[key])
			if d < best_d:
				best_d = d
				best = b["center"]
		if best_d >= 12.0:
			push_warning("mark %s: no painted number found near %s, using the hand position" % [key, MARK_PX[key]])
		var m: Vector2 = to_m.call(best)
		assert(Geometry2D.is_point_in_polygon(m, shore))
		marks[key] = [snappedf(m.x, 0.1), snappedf(m.y, 0.1)]
		print("mark %s px %s -> %s m" % [key, best, marks[key]])
	var dock_m: Vector2 = to_m.call(DOCK_PX)
	var best_p := shore[0]
	for i in shore.size():
		var p := Geometry2D.get_closest_point_to_segment(dock_m, shore[i], shore[(i + 1) % shore.size()])
		if p.distance_to(dock_m) < best_p.distance_to(dock_m):
			best_p = p
	print("dock px %s -> %s m, snapped to shore %s (%.0f m)" % [DOCK_PX, dock_m, best_p, best_p.distance_to(dock_m)])
	return {"marks": marks, "usc_dock": [snappedf(best_p.x, 0.1), snappedf(best_p.y, 0.1)]}


## Signed distance to the shoreline (metres, negative on the water) on a regular grid, saved as
## data/shore_sdf.bin: int32 w, int32 h, float32 origin_x, origin_y, cell, then w*h float32 rows
## from south to north. Used by the water/land shaders and by the AI's shore avoidance.
const SDF_CELL := 5.0
const SDF_MARGIN := 400.0


func build_sdf(shore: PackedVector2Array) -> void:
	var bb := _bbox(shore).grow(SDF_MARGIN)
	var w := int(ceil(bb.size.x / SDF_CELL)) + 1
	var h := int(ceil(bb.size.y / SDF_CELL)) + 1
	var n := shore.size()
	var ax := PackedFloat32Array()
	var ay := PackedFloat32Array()
	var dx := PackedFloat32Array()
	var dy := PackedFloat32Array()
	var ll := PackedFloat32Array()
	for i in n:
		var a := shore[i]
		var b := shore[(i + 1) % n]
		ax.append(a.x)
		ay.append(a.y)
		dx.append(b.x - a.x)
		dy.append(b.y - a.y)
		ll.append(maxf((b - a).length_squared(), 1e-6))
	var vals := PackedFloat32Array()
	vals.resize(w * h)
	for j in h:
		var py := bb.position.y + j * SDF_CELL
		for i in w:
			var px := bb.position.x + i * SDF_CELL
			var best := 1e12
			for k in n:
				var t := clampf(((px - ax[k]) * dx[k] + (py - ay[k]) * dy[k]) / ll[k], 0.0, 1.0)
				var ex := ax[k] + dx[k] * t - px
				var ey := ay[k] + dy[k] * t - py
				best = minf(best, ex * ex + ey * ey)
			var d := sqrt(best)
			vals[j * w + i] = -d if Geometry2D.is_point_in_polygon(Vector2(px, py), shore) else d
	var f := FileAccess.open("res://data/shore_sdf.bin", FileAccess.WRITE)
	f.store_32(w)
	f.store_32(h)
	f.store_float(bb.position.x)
	f.store_float(bb.position.y)
	f.store_float(SDF_CELL)
	f.store_buffer(vals.to_byte_array())
	f.close()
	print("wrote data/shore_sdf.bin %dx%d" % [w, h])
