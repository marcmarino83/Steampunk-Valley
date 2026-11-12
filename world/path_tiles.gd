class_name PathTiles
extends Node
## The path tiles the player lays with the build menu's Paths tab (Dirt, Gravel, Stone and
## Remove; see PathTilePlacer). Paths are ground paint, not objects: nothing to collide with, and
## buildings, plots and furniture go over them freely. The valley makes this and hands it the
## ground material.
##
## What's kept: the tiles as they were laid, in order, each as [rank, x, z, turn] (rank 0 is a
## Remove tile). That list is all that's saved, and the ground is worked out from it the same
## way every time, so a save loads exactly as it was. Laying the same tile twice changes nothing;
## a Remove laid exactly over a tile takes that tile out of the list (and the Remove isn't kept if
## nothing else is under it), so the list stays about as long as the paths on the ground.
##
## What's drawn: a fine map (one pixel per TEXEL meters, in square tiles of TILE pixels, only
## where there's path) with a channel per rank: 1 Dirt, 2 Gravel, 3 Stone, 4 for a later type.
## Each channel holds how far inside or outside that rank's path the spot is (a signed distance,
## 1 = a meter or more inside, 0.5 = on the tile's edge, 0 = a meter or more outside), so tiles laid
## side by side or end to end merge into one wider or longer path with no seam, and a Remove cuts
## its shape out of every channel. The ground shader turns each channel's distance into that
## type's own soft, ragged, noisy edge (RANK_EDGES), and draws the ranks in order, so a higher rank
## always lies over a lower one, whatever order they were laid in. Like PaintedPaths, the tiles go
## to the shader in one texture array, and only the tiles that changed are uploaded.
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
## A path tile's size (m): its width (across, its own X) and length (along, its own Z)
const TILE_SIZE := Vector2(2.0, 4.0)
## The distance each channel spans: from RANGE / 2 inside (1) to RANGE / 2 outside (0)
const RANGE := 2.0
## The ragged edge built into every tile: its edge wanders in and out by up to WOBBLE meters, in
## a pattern WOBBLE_SIZE meters across, laid in the world (not the tile), so neighbouring tiles
## wander together and still meet without a seam
const WOBBLE := 0.22
const WOBBLE_SIZE := 1.3
## Each tile is kept in the map this much bigger than it is (m), and every edge below reaches that
## much less far, so it looks the same size; but where tiles meet, the spot on their shared edge
## is well inside the path rather than on its edge, so a type that stops short of its tile's edge
## (stone) still runs on across the join with no seam
const GROW := 0.3
## Rank 0 is a Remove tile; 1 to RANKS are path types, drawn in that order (higher on top)
const REMOVE := 0
const RANKS := 4
## The texture set each rank draws (see Valley.texture_sets), and its edge: (how far past the
## tile's edge it reaches, m (less than 0: it stops short), how soft that edge is, m, how far its
## noise pushes the edge in and out, m, and the noise's size, per meter), each reach measured on
## the grown tile (see GROW). Dirt spreads softly past its tile (0.3 m), gravel scatters a little
## (0.1 m), laid stone stops just short (0.12 m) with a firmer edge, so layering them leaves worn
## borders.
const RANK_SETS := ["paths/dirt/Ground103", "paths/gravel/Ground110", "paths/stone/Bricks089", ""]
const RANK_EDGES := [
	Vector4(0.3 - GROW, 0.25, 0.5, 0.45),
	Vector4(0.1 - GROW, 0.12, 0.3, 0.8),
	Vector4(-0.12 - GROW, 0.05, 0.12, 1.3),
	Vector4(0.0 - GROW, 0.1, 0.1, 1.0),
]
## Two tiles count as the same spot this close (m), and turn (radians, either way round)
const SAME_SPOT := 0.02
const SAME_TURN := 0.01

var valley: Node
var material: ShaderMaterial

# Where the map starts (x, z) and how many map tiles across and down it is
var _origin := Vector2.ZERO
var _tiles := Vector2i.ZERO
# The tiles laid, in order: 4 floats each (rank, x, z, turn), kept as 32-bit floats so what's
# saved is exactly what's used
var _ops := PackedFloat32Array()
# The map's tiles: tile (x, z) -> its pixels (TILE * TILE * CHANNELS bytes)
var _data := {}
var _layer_of := {}
var _layer_images: Array[Image] = []
var _free_layers: Array[int] = []
var _array: Texture2DArray
var _index_image: Image
var _index_texture: ImageTexture
var _dirty := {}
var _index_dirty := false
var _array_dirty := false


func _ready() -> void:
	add_to_group("saveable")


## Sets the map up to cover the valley's ground (x, z), drawn by this ground material (again after
## the valley is rebuilt: what's laid stays)
func setup(map: Rect2, ground: Material) -> void:
	material = ground as ShaderMaterial
	var tiles := Vector2i(ceili(map.size.x / (TEXEL * TILE)), ceili(map.size.y / (TEXEL * TILE)))
	if _index_image == null or tiles != _tiles or map.position != _origin:
		_origin = map.position
		_tiles = tiles
		_index_image = Image.create_empty(_tiles.x, _tiles.y, false, Image.FORMAT_RF)
		_index_texture = ImageTexture.create_from_image(_index_image)
		_layer_of.clear()
		_layer_images.clear()
		_free_layers.clear()
		_rebuild_all()
	_upload_all()
	if not _dirty.is_empty():
		_upload()


func _process(_delta: float) -> void:
	if not _dirty.is_empty() or _index_dirty or _array_dirty:
		var timing := SpikeLog.begin()
		_upload()
		SpikeLog.end("path tiles: map uploaded", timing)


# ---- Laying ----

## Lays a tile: `rank` 1 to RANKS (a path type) or REMOVE, its middle (x, z) and turn (radians).
## Returns the area (x, z) whose ground changed, or an empty Rect2 if nothing did.
func lay(rank: int, middle: Vector2, turn: float) -> Rect2:
	var op := PackedFloat32Array([rank, middle.x, middle.y, wrapf(turn, 0.0, TAU)])
	var area := _bounds(op[1], op[2])
	if rank != REMOVE:
		if _find_same(op, rank) >= 0:
			return Rect2()
		_ops.append_array(op)
		_apply(_ops.size() / 4 - 1, _pixels_of(area))
		return area
	# A Remove: tiles exactly under it go from the list
	var pruned := false
	var found := _find_same(op, -1)
	while found >= 0:
		for k in 4:
			_ops.remove_at(found * 4)
		pruned = true
		found = _find_same(op, -1)
	# It's kept only if some other tile still reaches under it
	var under := false
	for i in _ops.size() / 4:
		if _ops[i * 4] > 0.5 and _bounds(_ops[i * 4 + 1], _ops[i * 4 + 2]).intersects(area):
			under = true
			break
	if under:
		_ops.append_array(op)
	if not under and not pruned:
		return Rect2()
	_redo(area)
	return area


## The path tiles (not Remove tiles) within `reach` of a spot (x, z), for snapping to:
## [{"rank", "middle": Vector2, "turn"}]
func tiles_near(spot: Vector2, reach: float) -> Array:
	var found := []
	for i in _ops.size() / 4:
		var rank := int(_ops[i * 4])
		var middle := Vector2(_ops[i * 4 + 1], _ops[i * 4 + 2])
		if rank != REMOVE and middle.distance_to(spot) <= reach:
			found.append({"rank": rank, "middle": middle, "turn": float(_ops[i * 4 + 3])})
	return found


## How many tiles are kept (path and Remove)
func tile_count() -> int:
	return _ops.size() / 4


## True if a path tile of this rank lies exactly here (same spot and turn, either way round)
func has_tile(rank: int, middle: Vector2, turn: float) -> bool:
	return _find_same(PackedFloat32Array([rank, middle.x, middle.y, wrapf(turn, 0.0, TAU)]), rank) >= 0


# The index of a kept tile exactly where `op` is (of this rank, or any path rank for -1), or -1
func _find_same(op: PackedFloat32Array, rank: int) -> int:
	for i in _ops.size() / 4:
		var r := int(_ops[i * 4])
		if r == REMOVE or (rank >= 0 and r != rank):
			continue
		if absf(_ops[i * 4 + 1] - op[1]) > SAME_SPOT or absf(_ops[i * 4 + 2] - op[2]) > SAME_SPOT:
			continue
		# (a tile looks the same turned half round)
		var turn_gap := absf(wrapf(_ops[i * 4 + 3] - op[3], -PI / 2.0, PI / 2.0))
		if turn_gap <= SAME_TURN:
			return i
	return -1


# The area (x, z) a tile at this middle can change: its corners, plus how far its channels reach
func _bounds(x: float, z: float) -> Rect2:
	var reach := TILE_SIZE.length() / 2.0 + GROW + RANGE / 2.0 + WOBBLE + TEXEL
	return Rect2(x - reach, z - reach, reach * 2.0, reach * 2.0)


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
	for i in _ops.size() / 4:
		if _bounds(_ops[i * 4 + 1], _ops[i * 4 + 2]).intersects(area):
			_apply(i, pixels)
	_tidy(pixels)


# The whole map worked out again from the list (loading, or the map moved)
func _rebuild_all() -> void:
	_data.clear()
	for i in _ops.size() / 4:
		_apply(i, _pixels_of(_bounds(_ops[i * 4 + 1], _ops[i * 4 + 2])))
	for tile: Vector2i in _data:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				_dirty[tile + Vector2i(dx, dz)] = true


# Lays tile `index` onto the map within these pixels: a path tile raises its rank's channel to its
# shape (never lowering it); a Remove lowers every channel to its shape cut out
func _apply(index: int, pixels: Rect2i) -> void:
	var rank := int(_ops[index * 4])
	var cx: float = _ops[index * 4 + 1]
	var cz: float = _ops[index * 4 + 2]
	var turn: float = _ops[index * 4 + 3]
	var own := _pixels_of(_bounds(cx, cz)).intersection(pixels)
	if own.size.x <= 0 or own.size.y <= 0:
		return
	var c := cos(turn)
	var s := sin(turn)
	var half := TILE_SIZE / 2.0
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
					var dx := wx - cx
					var dz := wz - cz
					# Into the tile's own frame: across (its X) and along (its Z)
					var lx := dx * c - dz * s
					var lz := dx * s + dz * c
					var qx := absf(lx) - half.x
					var qz := absf(lz) - half.y
					var outside := Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()
					var d := outside + minf(maxf(qx, qz), 0.0) - (wobble(wx, wz) - 0.5) * 2.0 * WOBBLE - GROW
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
						_mark_dirty(px, pz)
			if existed or touched:
				_data[tile] = bytes


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
					_mark_dirty(px, pz)
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
						_dirty[tile + Vector2i(dx, dz)] = true


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


# A pixel changed: its map tile needs uploading again, and so does any neighbour whose border shows it
func _mark_dirty(px: int, pz: int) -> void:
	var tile := Vector2i(px / TILE, pz / TILE)
	_dirty[tile] = true
	var lx := px - tile.x * TILE
	var lz := pz - tile.y * TILE
	var sx := -1 if lx == 0 else (1 if lx == TILE - 1 else 0)
	var sz := -1 if lz == 0 else (1 if lz == TILE - 1 else 0)
	if sx != 0:
		_dirty[tile + Vector2i(sx, 0)] = true
	if sz != 0:
		_dirty[tile + Vector2i(0, sz)] = true
	if sx != 0 and sz != 0:
		_dirty[tile + Vector2i(sx, sz)] = true


# ---- Uploading to the ground shader ----

func _upload() -> void:
	for tile: Vector2i in _dirty:
		if tile.x < 0 or tile.y < 0 or tile.x >= _tiles.x or tile.y >= _tiles.y:
			continue
		var image := _padded(tile)
		if image == null:
			if _layer_of.has(tile):
				_index_image.set_pixel(tile.x, tile.y, Color(0, 0, 0))
				_index_dirty = true
				_layer_images[_layer_of[tile]] = Image.create_empty(PADDED, PADDED, false, Image.FORMAT_RGBA8)
				_free_layers.append(_layer_of[tile])
				_layer_of.erase(tile)
			continue
		if not _layer_of.has(tile):
			var claimed := _claim_layer()
			_layer_of[tile] = claimed
			_index_image.set_pixel(tile.x, tile.y, Color(claimed + 1, 0, 0))
			_index_dirty = true
		var layer: int = _layer_of[tile]
		_layer_images[layer] = image
		if _array and not _array_dirty:
			_array.update_layer(image, layer)
	_dirty.clear()
	if _array_dirty:
		_upload_all()
	elif _index_dirty:
		_index_texture.update(_index_image)
		_index_dirty = false
	_show()


func _claim_layer() -> int:
	if not _free_layers.is_empty():
		return _free_layers.pop_back()
	if _layer_images.size() >= (_array.get_layers() if _array else 0):
		_array_dirty = true
	_layer_images.append(Image.create_empty(PADDED, PADDED, false, Image.FORMAT_RGBA8))
	return _layer_images.size() - 1


func _upload_all() -> void:
	var layers := FIRST_LAYERS
	while layers < _layer_images.size():
		layers *= 2
	var images: Array[Image] = []
	for i in layers:
		images.append(_layer_images[i] if i < _layer_images.size() else Image.create_empty(PADDED, PADDED, false, Image.FORMAT_RGBA8))
	_array = Texture2DArray.new()
	_array.create_from_images(images)
	if _index_texture:
		_index_texture.update(_index_image)
	_array_dirty = false
	_index_dirty = false
	if material:
		material.set_shader_parameter("tile_path_tiles", _array)
		material.set_shader_parameter("tile_path_index", _index_texture)
	_show()


func _show() -> void:
	if material:
		material.set_shader_parameter("tile_path_info", Vector4(_origin.x, _origin.y, TEXEL, 1.0 if not _layer_of.is_empty() else 0.0))


# A map tile's picture with its one-pixel border from its neighbours, or null if there's no path in
# it or its border
func _padded(tile: Vector2i) -> Image:
	var any := false
	var image := Image.create_empty(PADDED, PADDED, false, Image.FORMAT_RGBA8)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var bytes = _data.get(tile + Vector2i(dx, dz))
			if bytes == null:
				continue
			any = true
			var part := Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGBA8, bytes)
			var from := Vector2i(0 if dx == 0 else (TILE - 1 if dx < 0 else 0), 0 if dz == 0 else (TILE - 1 if dz < 0 else 0))
			var size := Vector2i(TILE if dx == 0 else 1, TILE if dz == 0 else 1)
			var to := Vector2i(1 if dx == 0 else (0 if dx < 0 else PADDED - 1), 1 if dz == 0 else (0 if dz < 0 else PADDED - 1))
			image.blit_rect(part, Rect2i(from, size), to)
	return image if any else null


# ---- Saving ----

func save_key() -> String:
	return "path_tiles"


## The tiles laid, in order, as their 32-bit numbers, compressed and written as text
func save_data() -> Dictionary:
	var bytes := _ops.to_byte_array()
	return {"version": 1, "count": _ops.size() / 4, "tiles": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}


func load_data(data: Dictionary) -> void:
	var count := int(data.get("count", 0))
	_ops = PackedFloat32Array()
	if count > 0:
		var bytes := Marshalls.base64_to_raw(str(data.get("tiles", ""))).decompress(count * 16, FileAccess.COMPRESSION_ZSTD)
		if bytes.size() == count * 16:
			_ops = bytes.to_float32_array()
		else:
			push_warning("PathTiles: the saved path tiles couldn't be read; none loaded")
	var had := not _data.is_empty()
	for tile in _data:
		_dirty[tile] = true
	_rebuild_all()
	_upload()
	# The grass and ferns keep off the paths (and grow back where old ones were)
	if valley and (had or not _data.is_empty()):
		var foliage = valley.get_node_or_null("Foliage")
		if foliage:
			foliage.regrow_plants_in(valley.map_rect())


## Every path tile gone
func clear() -> void:
	for tile in _data:
		_dirty[tile] = true
	_ops = PackedFloat32Array()
	_data.clear()
