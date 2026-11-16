extends RefCounted
## Wind waves on the reservoir, simulated on the GPU with FFTs (Tessendorf's method). Every frame
## a fetch-limited JONSWAP spectrum for the wind is evolved in time and transformed into three
## tiles of waves: the chop (2 to 4 m crest to crest on a lake this size in a sailing breeze), the
## short waves riding on it, and the capillary ripples a breeze raises in a second. The tiles are
## turned to different angles so their repeats never line up.
##
## The water shader samples the textures: displacement for the geometry near the camera, and
## slopes (mipmapped, with the squared slope so the detail the mips average away can become
## roughness) for the shading everywhere. Foam collects where the chop gets steep enough to break.
## Without a GPU (headless tests) `available` is false and the textures are flat.
## The compute shaders are in shaders/waves/.

const N := 256
const CASCADES := 3
const PATCH: Array[float] = [57.3, 13.7, 3.27]  # tile sizes (m)
const ROT: Array[float] = [0.31, 1.47, 2.66]     # each tile's frame (rad, anticlockwise from east)
const LOOP := 1000.0                            # s; frequencies are quantised so time can wrap
const CHOPPY := 1.0
const MIPS := 9

var available := false
var disp_tex: Array[Texture2D] = []
var slope_tex: Array[Texture2D] = []
var k_lo := PackedFloat32Array()
var k_hi := PackedFloat32Array()
## Test hook: Vector4i(x, y, cascade, 1) replaces the spectrum with one unit wave at that cell.
var debug_wave := Vector4i.ZERO

var _rd: RenderingDevice
var _shaders: Array[RID] = []
var _pipes: Array[RID] = []    # spectrum, fft, unpack, mip
var _buf := RID()
var _disp: Array[RID] = []
var _slope: Array[RID] = []
var _views: Array[RID] = []    # every mip view, for freeing
var _slope_mips := []          # [cascade][level] -> view RID
var _sets: Array[RID] = []     # every uniform set, for freeing
var _spec_set := RID()
var _fft_set := RID()
var _unpack_sets: Array[RID] = []
var _mip_sets := []            # [level][cascade]
var _last_time := -1.0


func _init() -> void:
	for c in CASCADES:
		var nyq := PI * N / PATCH[c]
		k_lo.append(0.0 if c == 0 else k_hi[c - 1])
		k_hi.append(nyq * (0.7 if c == CASCADES - 1 else 0.5))
	if RenderingServer.get_rendering_device() == null:
		_make_flat()
		return
	for c in CASCADES:
		disp_tex.append(Texture2DRD.new())
		slope_tex.append(Texture2DRD.new())
	available = true
	RenderingServer.call_on_render_thread(_init_gpu)


## Advance the waves to `time` (s) for a wind of `wind` m/s blowing toward `wind_to` (unit,
## east/north) over `fetch` metres of open water.
func update(time: float, wind: float, wind_to: Vector2, fetch: float) -> void:
	if not available:
		return
	var dt := clampf(time - _last_time, 0.0, 0.5) if _last_time >= 0.0 else 0.0
	_last_time = time
	var ang := atan2(wind_to.y, wind_to.x)
	var sp := [
		PATCH[0], PATCH[1], PATCH[2], 1.0,
		k_lo[0], k_lo[1], k_lo[2], 0.0,
		k_hi[0], k_hi[1], k_hi[2], 0.0,
		ang - ROT[0], ang - ROT[1], ang - ROT[2], 0.0,
		maxf(wind, 0.3), fetch, fposmod(time, LOOP), TAU / LOOP,
		debug_wave.x, debug_wave.y, debug_wave.z, debug_wave.w,
	]
	# Whitecaps where the chop folds over (the Jacobian drops). The threshold is set against
	# tests/waves_check.gd: nothing in light air, the odd one from about 13 knots, a few tenths of
	# a percent of the water breaking at any moment at 18 knots and about 1 percent at 22. The
	# short waves only micro-break, with hardly any white.
	var thr := 0.6 + 0.14 * smoothstep(4.5, 11.5, wind)
	var keep := exp(-dt / 3.0)
	var up := []
	for c in CASCADES:
		var t := thr - 0.08 * c if c < 2 else -10.0
		up.append(_pack([c, CHOPPY, t, 15.0, keep, 0.0, 0.0, 0.0]))
	RenderingServer.call_on_render_thread(_dispatch.bind(_pack(sp), up))


## Free the GPU resources (call before the owner goes away).
func free_gpu() -> void:
	if not available:
		return
	available = false
	for t in disp_tex + slope_tex:
		(t as Texture2DRD).texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_free_gpu)


## Test hook: read back cascade c's top-level textures as {"disp": [Vector4], "slope": [Vector4]}
## (call on the render thread, after an update).
func read_back(c: int) -> Dictionary:
	return {"disp": _read_tex(_disp[c]), "slope": _read_tex(_slope[c])}


# --- GPU --------------------------------------------------------------------------------------

func _init_gpu() -> void:
	_rd = RenderingServer.get_rendering_device()
	for name in ["spectrum", "fft", "unpack", "mip"]:
		var sh := _compile(name)
		if not sh.is_valid():
			available = false
			return
		_shaders.append(sh)
		_pipes.append(_rd.compute_pipeline_create(sh))
	_buf = _rd.storage_buffer_create(CASCADES * 4 * N * N * 8)
	for c in CASCADES:
		_disp.append(_make_tex(1))
		_slope.append(_make_tex(MIPS))
		var mips: Array[RID] = []
		for m in MIPS:
			var v := _rd.texture_create_shared_from_slice(RDTextureView.new(), _slope[c], 0, m, 1, RenderingDevice.TEXTURE_SLICE_2D)
			mips.append(v)
			_views.append(v)
		_slope_mips.append(mips)
	_spec_set = _make_set([_buffer_uniform(0)], _shaders[0])
	_fft_set = _make_set([_buffer_uniform(0)], _shaders[1])
	for c in CASCADES:
		_unpack_sets.append(_make_set([_buffer_uniform(0), _image_uniform(1, _disp[c]), _image_uniform(2, _slope_mips[c][0])], _shaders[2]))
	_mip_sets.append([])
	for m in range(1, MIPS):
		var row: Array[RID] = []
		for c in CASCADES:
			row.append(_make_set([_image_uniform(0, _slope_mips[c][m - 1]), _image_uniform(1, _slope_mips[c][m])], _shaders[3]))
		_mip_sets.append(row)
	for c in CASCADES:
		(disp_tex[c] as Texture2DRD).texture_rd_rid = _disp[c]
		(slope_tex[c] as Texture2DRD).texture_rd_rid = _slope[c]


func _dispatch(spec_pc: PackedByteArray, unpack_pc: Array) -> void:
	if not available or _pipes.size() < 4:
		return
	var rd := _rd
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipes[0])
	rd.compute_list_bind_uniform_set(cl, _spec_set, 0)
	rd.compute_list_set_push_constant(cl, spec_pc, spec_pc.size())
	rd.compute_list_dispatch(cl, N / 16, N / 16, CASCADES)
	rd.compute_list_end()
	for vertical in 2:
		var fpc := _pack([vertical, 0, 0, 0])
		cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, _pipes[1])
		rd.compute_list_bind_uniform_set(cl, _fft_set, 0)
		rd.compute_list_set_push_constant(cl, fpc, fpc.size())
		rd.compute_list_dispatch(cl, 1, N, CASCADES * 4)
		rd.compute_list_end()
	cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipes[2])
	for c in CASCADES:
		var upc: PackedByteArray = unpack_pc[c]
		rd.compute_list_bind_uniform_set(cl, _unpack_sets[c], 0)
		rd.compute_list_set_push_constant(cl, upc, upc.size())
		rd.compute_list_dispatch(cl, N / 16, N / 16, 1)
	rd.compute_list_end()
	for m in range(1, MIPS):
		var size := maxi(N >> m, 1)
		var groups := maxi((size + 7) / 8, 1)
		cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, _pipes[3])
		for c in CASCADES:
			rd.compute_list_bind_uniform_set(cl, _mip_sets[m][c], 0)
			rd.compute_list_dispatch(cl, groups, groups, 1)
		rd.compute_list_end()


func _free_gpu() -> void:
	if _rd == null:
		return
	for r in _sets:
		if _rd.uniform_set_is_valid(r):
			_rd.free_rid(r)
	for r in _views:
		_rd.free_rid(r)
	for r in _disp + _slope:
		_rd.free_rid(r)
	if _buf.is_valid():
		_rd.free_rid(_buf)
	for r in _pipes:
		_rd.free_rid(r)
	for r in _shaders:
		_rd.free_rid(r)
	_sets.clear()
	_views.clear()
	_disp.clear()
	_slope.clear()
	_pipes.clear()
	_shaders.clear()
	_buf = RID()


func _compile(name: String) -> RID:
	var code := FileAccess.get_file_as_string("res://shaders/waves/%s.glsl" % name)
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = code.replace("#[compute]", "")
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("shaders/waves/%s.glsl: %s" % [name, spirv.compile_error_compute])
		return RID()
	return _rd.shader_create_from_spirv(spirv, name)


func _make_tex(mips: int) -> RID:
	var f := RDTextureFormat.new()
	f.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	f.width = N
	f.height = N
	f.mipmaps = mips
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var t := _rd.texture_create(f, RDTextureView.new(), [])
	_rd.texture_clear(t, Color(0, 0, 0, 0), 0, mips, 0, 1)
	return t


func _make_set(uniforms: Array[RDUniform], shader: RID) -> RID:
	var s := _rd.uniform_set_create(uniforms, shader, 0)
	_sets.append(s)
	return s


func _buffer_uniform(binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(_buf)
	return u


func _image_uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _read_tex(tex: RID) -> Array[Vector4]:
	var b := _rd.texture_get_data(tex, 0)
	var out: Array[Vector4] = []
	out.resize(N * N)
	for i in N * N:
		var o := i * 8
		out[i] = Vector4(b.decode_half(o), b.decode_half(o + 2), b.decode_half(o + 4), b.decode_half(o + 6))
	return out


## Flat stand-ins when there's no GPU to run the waves on.
func _make_flat() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBAH)
	img.fill(Color(0, 0, 0, 0))
	var t := ImageTexture.create_from_image(img)
	var d := Image.create(4, 4, false, Image.FORMAT_RGBAH)
	d.fill(Color(0, 0, 0, 1))
	var dt := ImageTexture.create_from_image(d)
	for c in CASCADES:
		disp_tex.append(dt)
		slope_tex.append(t)


## Push constants: ints and floats as 32-bit words, padded to 16 bytes.
static func _pack(values: Array) -> PackedByteArray:
	var n := ((values.size() + 3) / 4) * 4
	var b := PackedByteArray()
	b.resize(n * 4)
	for i in values.size():
		if values[i] is int:
			b.encode_s32(i * 4, values[i])
		else:
			b.encode_float(i * 4, values[i])
	return b
