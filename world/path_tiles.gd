class_name PathTiles
extends Node
## The path strips the player lays with the build menu's Paths tab (Dirt, Gravel, Stone and
## Remove; see PathTilePlacer). Paths are ground paint, not objects: nothing to collide with, and
## buildings, plots and furniture go over them freely. The valley makes this and hands it the
## ground material.
##
## What's kept: the strips as they were laid, in order, each as [rank, ax, az, bx, bz, caps]: its
## two ends and which of them are round (rank 0 is a Remove strip). Every strip is WIDTH wide. An
## end is square, or round where it meets another strip's end, so a chain of strips bending at an
## angle joins with no gap or notch. That list is all that's saved, and the ground is worked out
## from it the same way every time, so a save loads exactly as it was. Laying the same strip twice
## changes nothing; a Remove laid exactly over a strip takes it out of the list (and the Remove
## isn't kept if nothing else is under it), so the list stays about as long as the paths on the
## ground. (Older saves kept 2 × 4 m tiles: they load as the same strips, square at both ends.)
##
## What's drawn: a fine map (one pixel per TEXEL meters, in square tiles of TILE pixels, only
## where there's path) with a channel per rank: 1 Dirt, 2 Gravel, 3 Stone, 4 for a later type.
## Each channel holds how far inside or outside that rank's path the spot is (a signed distance,
## 1 = a meter or more inside, 0.5 = on the strip's edge, 0 = a meter or more outside), so strips
## laid side by side or end to end merge into one wider or longer path with no seam, and a Remove
## cuts its shape out of every channel. A signed distance at TEXEL spacing draws a straight edge
## exactly, so this map holds a clean strip. The ground shader turns each channel's distance into
## that type's own narrow, ragged worn edge (RANK_EDGES), and draws the ranks in order, so a higher
## rank always lies over a lower one, whatever order they were laid in. Like PaintedPaths, the map
## goes to the shader in one texture array, and only the map tiles that changed are uploaded (see
## PathTileUpload).
##
## Grass and ferns don't grow on path (see Foliage, PaintedPaths.sample_snapshot), and come back
## where it's removed.

## Meters per pixel, and pixels along a map tile's side (32 m)
const TEXEL := 0.25
const TILE := 128
const PADDED := TILE + 2
## Bytes per pixel: one channel per rank
const CHANNELS := 4
## The texture array starts with room for this many map tiles, and doubles when it fills
const FIRST_LAYERS := 8
## Every strip's width (m), and the old tiles' size (width, length), for older saves
const WIDTH := 2.0
const OLD_TILE := Vector2(2.0, 4.0)
## Numbers kept per strip: rank, ax, az, bx, bz, caps (bit 1: the a end is round, bit 2: the b end)
const STRIDE := 6
const ROUND_A := 1
const ROUND_B := 2
## The distance each channel spans: from RANGE / 2 inside (1) to RANGE / 2 outside (0)
const RANGE := 2.0
## The ragged edge built into every strip: its edge wanders in and out by up to WOBBLE meters, in
## a pattern WOBBLE_SIZE meters across, laid in the world (not the strip), so neighbouring strips
## wander together and still meet without a seam
const WOBBLE := 0.04
const WOBBLE_SIZE := 0.6
## Each strip is kept in the map this much bigger than it is (m), and every edge below reaches that
## much less far, so it looks the same size; but where strips meet, the spot on their shared edge
## is well inside the path rather than on its edge, so a type that stops short of its strip's edge
## (stone) still runs on across the join with no seam
const GROW := 0.3
## Rank 0 is a Remove strip; 1 to RANKS are path types, drawn in that order (higher on top)
const REMOVE := 0
const RANKS := 4
## The texture set each rank draws (see Valley.texture_sets), and its edge: (how far past the
## strip's edge it reaches, m (less than 0: it stops short), how soft that edge is, m, how far its
## noise pushes the edge in and out, m, and the noise's size, per meter), each reach measured on
## the grown strip (see GROW). Every edge stays on its strip with a narrow worn fray: dirt reaches
## 5 cm past it (10 to 20 cm at most with its fray), gravel stops 3 cm short, laid stone 10 cm
## short with a firmer edge, so layering them leaves worn borders: dirt round gravel, gravel round
## stone.
const RANK_SETS := ["paths/dirt/Ground103", "paths/gravel/Ground110", "paths/stone/Bricks089", ""]
const RANK_EDGES := [
	Vector4(0.05 - GROW, 0.04, 0.05, 3.0),
	Vector4(-0.03 - GROW, 0.03, 0.04, 3.5),
	Vector4(-0.10 - GROW, 0.02, 0.03, 4.0),
	Vector4(0.0 - GROW, 0.03, 0.03, 3.0),
]
## Two strip ends count as the same spot this close (m)
const SAME_SPOT := 0.02

var valley: Node
var material: ShaderMaterial

# Where the map starts (x, z) and how many map tiles across and down it is
var _origin := Vector2.ZERO
var _tiles := Vector2i.ZERO
# The strips laid, in order: STRIDE floats each, kept as 32-bit floats so what's saved is exactly
# what's used
var _ops := PackedFloat32Array()
# The map's tiles: tile (x, z) -> its pixels (TILE * TILE * CHANNELS bytes)
var _data := {}
# Hands the map to the ground shader, the map tiles that changed only (see PathTileUpload)
var _upload := PathTileUpload.new()


func _ready() -> void:
	add_to_group("saveable")


## Sets the map up to cover the valley's ground (x, z), drawn by this ground material (again after
## the valley is rebuilt: what's laid stays)
func setup(map: Rect2, ground: Material) -> void:
	material = ground as ShaderMaterial
	var tiles := Vector2i(ceili(map.size.x / (TEXEL * TILE)), ceili(map.size.y / (TEXEL * TILE)))
	_upload.material = material
	if _upload.needs_reset(tiles, map.position):
		_origin = map.position
		_tiles = tiles
		_upload.reset(tiles, map.position)
		_rebuild_all()
	_upload.upload_all()
	if not _upload.dirty.is_empty():
		_upload.upload(_data)


func _process(_delta: float) -> void:
	if _upload.pending():
		var timing := SpikeLog.begin()
		_upload.upload(_data)
		SpikeLog.end("path tiles: map uploaded", timing)


# ---- Laying ----

## Lays a strip: `rank` 1 to RANKS (a path type) or REMOVE, from end `a` to end `b` (x, z), with
## `caps` saying which ends are round (ROUND_A, ROUND_B). Returns the area (x, z) whose ground
## changed, or an empty Rect2 if nothing did.
func lay(rank: int, a: Vector2, b: Vector2, caps := 0) -> Rect2:
	var op := PackedFloat32Array([rank, a.x, a.y, b.x, b.y, caps])
	var area := _bounds_of(op, 0)
	if rank != REMOVE:
		if _find_same(op, rank) >= 0:
			return Rect2()
		_ops.append_array(op)
		_apply(strip_count() - 1, _pixels_of(area))
		return area
	# A Remove: strips exactly under it go from the list
	var pruned := false
	var found := _find_same(op, -1)
	while found >= 0:
		for k in STRIDE:
			_ops.remove_at(found * STRIDE)
		pruned = true
		found = _find_same(op, -1)
	# It's kept only if some other strip still reaches under it
	var under := false
	for i in strip_count():
		if _ops[i * STRIDE] > 0.5 and _bounds_of(_ops, i).intersects(area):
			under = true
			break
	if under:
		_ops.append_array(op)
	if not under and not pruned:
		return Rect2()
	_redo(area)
	return area


## Lays an old-style tile (OLD_TILE: 2 m wide, 4 m long, turned `turn` about its middle) as the
## same strip, square at both ends
func lay_tile(rank: int, middle: Vector2, turn: float) -> Rect2:
	var along := Vector2(sin(turn), cos(turn)) * OLD_TILE.y / 2.0
	return lay(rank, middle - along, middle + along)


## Rounds the end of every strip of this rank that ends at `spot` (where another strip of it now
## joins), so a join at an angle has no gap or notch. Returns the area whose ground changed
## (empty if none did).
func round_ends_at(spot: Vector2, rank: int) -> Rect2:
	var area := Rect2()
	for i in strip_count():
		if int(_ops[i * STRIDE]) != rank or rank == REMOVE:
			continue
		var caps := int(_ops[i * STRIDE + 5])
		var a := Vector2(_ops[i * STRIDE + 1], _ops[i * STRIDE + 2])
		var b := Vector2(_ops[i * STRIDE + 3], _ops[i * STRIDE + 4])
		var now := caps
		if a.distance_to(spot) <= SAME_SPOT:
			now |= ROUND_A
		if b.distance_to(spot) <= SAME_SPOT:
			now |= ROUND_B
		if now != caps:
			_ops[i * STRIDE + 5] = now
			var bounds := _bounds_of(_ops, i)
			area = bounds if not area.has_area() else area.merge(bounds)
	if area.has_area():
		_redo(area)
	return area


## The path strips (not Remove strips) with an end within `reach` of a spot (x, z), for snapping
## to: [{"rank", "a": Vector2, "b": Vector2, "caps"}]
func strips_near(spot: Vector2, reach: float) -> Array:
	var found := []
	for i in strip_count():
		var rank := int(_ops[i * STRIDE])
		var a := Vector2(_ops[i * STRIDE + 1], _ops[i * STRIDE + 2])
		var b := Vector2(_ops[i * STRIDE + 3], _ops[i * STRIDE + 4])
		if rank != REMOVE and (a.distance_to(spot) <= reach or b.distance_to(spot) <= reach):
			found.append({"rank": rank, "a": a, "b": b, "caps": int(_ops[i * STRIDE + 5])})
	return found


## How many strips are kept (path and Remove)
func strip_count() -> int:
	return _ops.size() / STRIDE


## True if a path strip of this rank lies exactly from `a` to `b` (either way round)
func has_strip(rank: int, a: Vector2, b: Vector2) -> bool:
	return _find_same(PackedFloat32Array([rank, a.x, a.y, b.x, b.y, 0]), rank) >= 0


# The index of a kept strip exactly where `op` is (of this rank, or any path rank for -1), or -1
func _find_same(op: PackedFloat32Array, rank: int) -> int:
	var a := Vector2(op[1], op[2])
	var b := Vector2(op[3], op[4])
	for i in strip_count():
		var r := int(_ops[i * STRIDE])
		if r == REMOVE or (rank >= 0 and r != rank):
			continue
		var oa := Vector2(_ops[i * STRIDE + 1], _ops[i * STRIDE + 2])
		var ob := Vector2(_ops[i * STRIDE + 3], _ops[i * STRIDE + 4])
		# (a strip looks the same laid the other way round)
		var same := oa.distance_to(a) <= SAME_SPOT and ob.distance_to(b) <= SAME_SPOT
		var reversed := oa.distance_to(b) <= SAME_SPOT and ob.distance_to(a) <= SAME_SPOT
		if same or reversed:
			return i
	return -1


# The area (x, z) strip `index` of `ops` can change: its ends, plus how far its channels reach
func _bounds_of(ops: PackedFloat32Array, index: int) -> Rect2:
	var a := Vector2(ops[index * STRIDE + 1], ops[index * STRIDE + 2])
	var b := Vector2(ops[index * STRIDE + 3], ops[index * STRIDE + 4])
	var reach := WIDTH / 2.0 + GROW + RANGE / 2.0 + WOBBLE + TEXEL
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
	return Rect2(low, high - low)


# The map's pixels covering an area, clamped to the map (its end is just past the last pixel)
func _pixels_of(area: Rect2) -> Rect2i:
	var first := Vector2i(((area.position - _origin) / TEXEL).floor())
	var last := Vector2i(((area.end - _origin) / TEXEL).ceil())
	first = first.clamp(Vector2i.ZERO, _tiles * TILE - Vector2i.ONE)
	last = last.clamp(Vector2i.ZERO, _tiles * TILE - Vector2i.ONE)
	return Rect2i(first, last - first + Vector2i.ONE)


# Works an area out again from scratch: cleared, then every tile reaching into it laid again, in
# order
func _redo(area: Rect2) -> void:
	var pixels := _pixels_of(area)
	_fill(pixels, 0)
	for i in strip_count():
		if _bounds_of(_ops, i).intersects(area):
			_apply(i, pixels)
	_tidy(pixels)


# The whole map worked out again from the list (loading, or the map moved)
func _rebuild_all() -> void:
	_data.clear()
	for i in strip_count():
		_apply(i, _pixels_of(_bounds_of(_ops, i)))
	for tile: Vector2i in _data:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				_upload.dirty[tile + Vector2i(dx, dz)] = true


# Lays strip `index` onto the map within these pixels: a path strip raises its rank's channel to
# its shape (never lowering it); a Remove lowers every channel to its shape cut out
func _apply(index: int, pixels: Rect2i) -> void:
	var at := index * STRIDE
	var rank := int(_ops[at])
	var a := Vector2(_ops[at + 1], _ops[at + 2])
	var b := Vector2(_ops[at + 3], _ops[at + 4])
	var caps := int(_ops[at + 5])
	var own := _pixels_of(_bounds_of(_ops, index)).intersection(pixels)
	if own.size.x <= 0 or own.size.y <= 0:
		return
	var middle := (a + b) / 2.0
	var length := a.distance_to(b)
	var along := (b - a) / length if length > 0.001 else Vector2(0.0, 1.0)
	var half := Vector2(WIDTH / 2.0, length / 2.0)
	var first := own.position
	var last := own.end - Vector2i.ONE
	for tz in range(first.y / TILE, last.y / TILE + 1):
		for tx in range(first.x / TILE, last.x / TILE + 1):
			var tile := Vector2i(tx, tz)
			var bytes: PackedByteArray = _data.get(tile, PackedByteArray())
			var existed := not bytes.is_empty()
			if not existed and rank == REMOVE:
				continue
			# (taken out while it changes, so writing doesn't copy it each time)
			_data.erase(tile)
			if not existed:
				bytes.resize(TILE * TILE * CHANNELS)
			var touched := false
			for pz in range(maxi(first.y, tz * TILE), mini(last.y, tz * TILE + TILE - 1) + 1):
				for px in range(maxi(first.x, tx * TILE), mini(last.x, tx * TILE + TILE - 1) + 1):
					var wx := _origin.x + (px + 0.5) * TEXEL
					var wz := _origin.y + (pz + 0.5) * TEXEL
					var spot := Vector2(wx, wz)
					var d := _strip_distance(spot - middle, along, half)
					# A round end is the strip's width as a circle on that end
					if caps & ROUND_A:
						d = minf(d, spot.distance_to(a) - half.x)
					if caps & ROUND_B:
						d = minf(d, spot.distance_to(b) - half.x)
					d -= (wobble(wx, wz) - 0.5) * 2.0 * WOBBLE + GROW
					if d >= RANGE / 2.0:
						continue
					var value := clampi(roundi((0.5 - d / RANGE) * 255.0), 0, 255)
					var i := ((pz - tz * TILE) * TILE + (px - tx * TILE)) * CHANNELS
					var changed := false
					if rank == REMOVE:
						for k in CHANNELS:
							var cut := mini(bytes[i + k], 255 - value)
							if cut != bytes[i + k]:
								bytes[i + k] = cut
								changed = true
					else:
						var k := rank - 1
						if value > bytes[i + k]:
							bytes[i + k] = value
							changed = true
					if changed:
						touched = true
						_upload.mark_pixel(px, pz)
			if existed or touched:
				_data[tile] = bytes


# How far outside a square-ended strip a spot is (less than 0: inside), the spot given from the
# strip's middle, with its direction `along` and its half width and half length
static func _strip_distance(offset: Vector2, along: Vector2, half: Vector2) -> float:
	var qx := absf(offset.x * along.y - offset.y * along.x) - half.x
	var qz := absf(offset.dot(along)) - half.y
	var outside := Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()
	return outside + minf(maxf(qx, qz), 0.0)


# Every channel of these pixels set to one value
func _fill(pixels: Rect2i, value: int) -> void:
	var first := pixels.position
	var last := pixels.end - Vector2i.ONE
	for tz in range(first.y / TILE, last.y / TILE + 1):
		for tx in range(first.x / TILE, last.x / TILE + 1):
			var tile := Vector2i(tx, tz)
			if not _data.has(tile):
				continue
			var bytes: PackedByteArray = _data[tile]
			_data.erase(tile)
			for pz in range(maxi(first.y, tz * TILE), mini(last.y, tz * TILE + TILE - 1) + 1):
				var row := (pz - tz * TILE) * TILE
				for px in range(maxi(first.x, tx * TILE), mini(last.x, tx * TILE + TILE - 1) + 1):
					var i := (row + px - tx * TILE) * CHANNELS
					for k in CHANNELS:
						bytes[i + k] = value
					_upload.mark_pixel(px, pz)
			_data[tile] = bytes


# Map tiles in these pixels left with no path at all go, so they cost nothing
func _tidy(pixels: Rect2i) -> void:
	var first := pixels.position / TILE
	var last := (pixels.end - Vector2i.ONE) / TILE
	for tz in range(first.y, last.y + 1):
		for tx in range(first.x, last.x + 1):
			var tile := Vector2i(tx, tz)
			var bytes = _data.get(tile)
			if bytes != null and (bytes as PackedByteArray).count(0) == (bytes as PackedByteArray).size():
				_data.erase(tile)
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						_upload.dirty[tile + Vector2i(dx, dz)] = true


## The ragged edges' wander at a spot in the world (0 to 1): smooth value noise WOBBLE_SIZE meters
## across. The same everywhere for everyone, so the ground always comes out the same.
static func wobble(x: float, z: float) -> float:
	var fx := x / WOBBLE_SIZE
	var fz := z / WOBBLE_SIZE
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var top := lerpf(_hash(ix, iz), _hash(ix + 1, iz), tx)
	var bottom := lerpf(_hash(ix, iz + 1), _hash(ix + 1, iz + 1), tx)
	return lerpf(top, bottom, tz)


static func _hash(ix: int, iz: int) -> float:
	var h := (ix * 374761393 + iz * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


# ---- Reading ----

## How much path there is at a spot (0 to 1): the most of any type there, by its own edge (without
## the shader's fine noise)
func amount_at(x: float, z: float) -> float:
	return sample_snapshot({"origin": _origin, "tiles": _data}, x, z)


## The map tiles touching an area (x, z), as a snapshot a worker thread can read on its own (see
## sample_snapshot): {"origin", "tiles": {tile: bytes}}
func snapshot(area: Rect2) -> Dictionary:
	var found := {}
	if not _data.is_empty():
		var low := Vector2i(((area.position - _origin) / (TEXEL * TILE) - Vector2.ONE * 0.01).floor())
		var high := Vector2i(((area.end - _origin) / (TEXEL * TILE) + Vector2.ONE * 0.01).floor())
		for tz in range(low.y, high.y + 1):
			for tx in range(low.x, high.x + 1):
				var tile := Vector2i(tx, tz)
				if _data.has(tile):
					found[tile] = (_data[tile] as PackedByteArray).duplicate()
	return {"origin": _origin, "tiles": found}


## How much path there is at a spot in a snapshot (0 to 1). Safe on any thread.
static func sample_snapshot(shot: Dictionary, x: float, z: float) -> float:
	var tiles: Dictionary = shot["tiles"]
	if tiles.is_empty():
		return 0.0
	var origin: Vector2 = shot["origin"]
	var fx := (x - origin.x) / TEXEL - 0.5
	var fz := (z - origin.y) / TEXEL - 0.5
	var px := floori(fx)
	var pz := floori(fz)
	var tx := fx - px
	var tz := fz - pz
	var most := 0.0
	for k in RANKS:
		var top := lerpf(_pixel_in(tiles, px, pz, k), _pixel_in(tiles, px + 1, pz, k), tx)
		var bottom := lerpf(_pixel_in(tiles, px, pz + 1, k), _pixel_in(tiles, px + 1, pz + 1, k), tx)
		var value := lerpf(top, bottom, tz) / 255.0
		if value <= 0.0:
			continue
		var edge: Vector4 = RANK_EDGES[k]
		var distance := (0.5 - value) * RANGE
		most = maxf(most, 1.0 - smoothstep(edge.x - edge.y, edge.x + edge.y, distance))
	return most


static func _pixel_in(tiles: Dictionary, px: int, pz: int, channel: int) -> float:
	var tile := Vector2i(floori(float(px) / TILE), floori(float(pz) / TILE))
	var bytes = tiles.get(tile)
	if bytes == null:
		return 0.0
	return (bytes as PackedByteArray)[((pz - tile.y * TILE) * TILE + (px - tile.x * TILE)) * CHANNELS + channel]


# ---- Saving ----

func save_key() -> String:
	return "path_tiles"


## The strips laid, in order, as their 32-bit numbers, compressed and written as text (version 2;
## version 1 kept 2 × 4 m tiles as rank, x, z, turn)
func save_data() -> Dictionary:
	var packed := _ops.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)
	return {"version": 2, "count": strip_count(), "tiles": Marshalls.raw_to_base64(packed)}


func load_data(data: Dictionary) -> void:
	var count := int(data.get("count", 0))
	var stride := STRIDE if int(data.get("version", 1)) >= 2 else 4
	_ops = PackedFloat32Array()
	if count > 0:
		var size := count * stride * 4
		var bytes := Marshalls.base64_to_raw(str(data.get("tiles", ""))).decompress(size,
				FileAccess.COMPRESSION_ZSTD)
		if bytes.size() != size:
			push_warning("PathTiles: the saved path tiles couldn't be read; none loaded")
		elif stride == STRIDE:
			_ops = bytes.to_float32_array()
		else:
			_ops = _from_old_tiles(bytes.to_float32_array())
	var had := not _data.is_empty()
	for tile in _data:
		_upload.dirty[tile] = true
	_rebuild_all()
	_upload.upload(_data)
	# The grass and ferns keep off the paths (and grow back where old ones were)
	if valley and (had or not _data.is_empty()):
		var foliage = valley.get_node_or_null("Foliage")
		if foliage:
			foliage.regrow_plants_in(valley.map_rect())


# Old tiles (rank, x, z, turn) as the same strips, square at both ends
static func _from_old_tiles(old: PackedFloat32Array) -> PackedFloat32Array:
	var ops := PackedFloat32Array()
	for i in old.size() / 4:
		var middle := Vector2(old[i * 4 + 1], old[i * 4 + 2])
		var turn: float = old[i * 4 + 3]
		var along := Vector2(sin(turn), cos(turn)) * OLD_TILE.y / 2.0
		var a := middle - along
		var b := middle + along
		ops.append_array(PackedFloat32Array([old[i * 4], a.x, a.y, b.x, b.y, 0]))
	return ops


## Every path strip gone
func clear() -> void:
	for tile in _data:
		_upload.dirty[tile] = true
	_ops = PackedFloat32Array()
	_data.clear()
