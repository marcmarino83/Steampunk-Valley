class_name PaintedPaths
extends Node
## Dirt paths the player paints in the game with the hammer's Dirt Path tool (see PathPainter).
## The valley makes this and hands it the ground material.
##
## How much path there is at each spot (0 = none, 1 = bare path) is kept in a fine map, one byte
## per TEXEL meters, cut into square tiles of TILE pixels. Only tiles that have been painted exist,
## so a world with a few paths keeps very little. The ground shader reads the tiles from one
## texture array (each tile with a one-pixel border copied from its neighbours, so blending
## across a tile's edge is seamless) and a small index saying which layer holds each tile, and
## draws them just like the editor's trails (see terrain.gdshader). Painting only uploads the
## few tiles that changed, so it never stalls a frame.
##
## Grass and ferns don't grow where the path is thicker than PLANTS_GONE_AT (see Foliage). It's
## saved with the game, as the painted tiles, compressed.

## Meters per pixel of the map
const TEXEL := 0.25
## Pixels along a tile's side (32 m)
const TILE := 128
## A tile in the texture array: the tile plus its one-pixel border
const PADDED := TILE + 2
## Grass doesn't grow where there's more path than this, ferns where there's more than FERNS_GONE_AT
const PLANTS_GONE_AT := 0.3
const FERNS_GONE_AT := 0.15
## The texture array starts with room for this many tiles, and doubles when it fills
const FIRST_LAYERS := 16

var valley: Node
var material: ShaderMaterial

# Where the map starts (x, z) and how many tiles across and down it is
var _origin := Vector2.ZERO
var _tiles := Vector2i.ZERO
# The painted tiles: tile (x, z) -> its pixels (TILE * TILE bytes, row by row)
var _data := {}
# Which texture array layer holds each painted tile, and each layer's padded picture
var _layer_of := {}
var _layer_images: Array[Image] = []
# Layers given back by tiles erased to nothing, to use again
var _free_layers: Array[int] = []
var _array: Texture2DArray
var _index_image: Image
var _index_texture: ImageTexture
# Tiles changed since the last upload, and whether the index changed
var _dirty := {}
var _index_dirty := false
var _array_dirty := false


## Sets the map up to cover the valley's ground (x, z), drawn by this ground material (again
## after the valley is rebuilt: what's painted stays)
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
		for tile: Vector2i in _data:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					_dirty[tile + Vector2i(dx, dz)] = true
	_upload_all()
	if not _dirty.is_empty():
		_upload()


func _ready() -> void:
	add_to_group("saveable")


func _process(_delta: float) -> void:
	if not _dirty.is_empty() or _index_dirty or _array_dirty:
		var timing := SpikeLog.begin()
		_upload()
		SpikeLog.end("painted paths: tiles uploaded", timing)


# ---- Reading ----

## How much path there is at a spot (0 to 1), blended between pixels like the ground shows it
func amount_at(x: float, z: float) -> float:
	if _data.is_empty():
		return 0.0
	var fx := (x - _origin.x) / TEXEL - 0.5
	var fz := (z - _origin.y) / TEXEL - 0.5
	var px := floori(fx)
	var pz := floori(fz)
	var tx := fx - px
	var tz := fz - pz
	var top := lerpf(_pixel(px, pz), _pixel(px + 1, pz), tx)
	var bottom := lerpf(_pixel(px, pz + 1), _pixel(px + 1, pz + 1), tx)
	return lerpf(top, bottom, tz) / 255.0


## True if anything at all is painted
func has_paths() -> bool:
	return not _data.is_empty()


## The painted tiles touching an area (x, z), as a snapshot a worker thread can read on its own
## (see sample_snapshot): {"origin", "tiles": {tile: bytes}}
func snapshot(area: Rect2) -> Dictionary:
	var found := {}
	if not _data.is_empty():
		var low := _tile_at(area.position - Vector2.ONE * TEXEL)
		var high := _tile_at(area.end + Vector2.ONE * TEXEL)
		for tz in range(low.y, high.y + 1):
			for tx in range(low.x, high.x + 1):
				var tile := Vector2i(tx, tz)
				if _data.has(tile):
					found[tile] = (_data[tile] as PackedByteArray).duplicate()
	return {"origin": _origin, "tiles": found}


## How much path there is at a spot in a snapshot (0 to 1; see snapshot). Safe on any thread.
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
	var top := lerpf(_pixel_in(tiles, px, pz), _pixel_in(tiles, px + 1, pz), tx)
	var bottom := lerpf(_pixel_in(tiles, px, pz + 1), _pixel_in(tiles, px + 1, pz + 1), tx)
	return lerpf(top, bottom, tz) / 255.0


static func _pixel_in(tiles: Dictionary, px: int, pz: int) -> float:
	var tile := Vector2i(floori(float(px) / TILE), floori(float(pz) / TILE))
	var bytes = tiles.get(tile)
	if bytes == null:
		return 0.0
	return (bytes as PackedByteArray)[(pz - tile.y * TILE) * TILE + (px - tile.x * TILE)]


func _pixel(px: int, pz: int) -> float:
	return _pixel_in(_data, px, pz)


func _tile_at(spot: Vector2) -> Vector2i:
	return Vector2i(floori((spot.x - _origin.x) / (TEXEL * TILE)), floori((spot.y - _origin.y) / (TEXEL * TILE)))


# ---- Painting ----

## Paints one round dab of path, `radius` meters across to where it fades out: full in the middle,
## then softly thinning to nothing. Painting over path never makes it thinner. With `erase`, rubs
## path out instead, the same shape. Returns the area (x, z) it changed, or an empty Rect2.
func dab(center: Vector2, radius: float, erase := false) -> Rect2:
	var first := Vector2i(((center - _origin - Vector2.ONE * radius) / TEXEL).floor())
	var last := Vector2i(((center - _origin + Vector2.ONE * radius) / TEXEL).ceil())
	first = first.clamp(Vector2i.ZERO, _tiles * TILE - Vector2i.ONE)
	last = last.clamp(Vector2i.ZERO, _tiles * TILE - Vector2i.ONE)
	var solid := radius * 0.4
	var changed := false
	# A tile at a time: its pixels are taken out of the map while they change (a PackedByteArray
	# shared with the map would be copied on every write), then put back
	for tz in range(first.y / TILE, last.y / TILE + 1):
		for tx in range(first.x / TILE, last.x / TILE + 1):
			var tile := Vector2i(tx, tz)
			var bytes: PackedByteArray = _data.get(tile, PackedByteArray())
			var existed := not bytes.is_empty()
			if not existed and erase:
				continue
			_data.erase(tile)
			if not existed:
				bytes.resize(TILE * TILE)
			var touched := false
			for pz in range(maxi(first.y, tz * TILE), mini(last.y, tz * TILE + TILE - 1) + 1):
				for px in range(maxi(first.x, tx * TILE), mini(last.x, tx * TILE + TILE - 1) + 1):
					var spot := _origin + (Vector2(px, pz) + Vector2(0.5, 0.5)) * TEXEL
					var d := spot.distance_to(center)
					if d >= radius:
						continue
					var amount := 1.0 - smoothstep(solid, radius, d)
					var i := (pz - tz * TILE) * TILE + (px - tx * TILE)
					var old := bytes[i]
					var now := mini(old, roundi((1.0 - amount) * 255.0)) if erase else maxi(old, roundi(amount * 255.0))
					if now == old:
						continue
					bytes[i] = now
					touched = true
					_mark_dirty(px, pz)
			if existed or touched:
				_data[tile] = bytes
			changed = changed or touched
	if not changed:
		return Rect2()
	return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


## Takes away tiles left with no path at all (after erasing), so they cost nothing
func tidy() -> void:
	for tile in _data.keys():
		var bytes: PackedByteArray = _data[tile]
		if bytes.count(0) == bytes.size():
			_data.erase(tile)
			_dirty[tile] = true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					_dirty[tile + Vector2i(dx, dz)] = true


# A pixel changed: its tile needs uploading again, and so does any neighbour whose border shows it
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
		var empty := image == null
		if empty:
			# Nothing there, around it either: its layer stays, unused (the index points nowhere)
			if _layer_of.has(tile):
				_index_image.set_pixel(tile.x, tile.y, Color(0, 0, 0))
				_index_dirty = true
				_layer_images[_layer_of[tile]] = Image.create_empty(PADDED, PADDED, false, Image.FORMAT_R8)
				_free_layers.append(_layer_of[tile])
				_layer_of.erase(tile)
			continue
		if not _layer_of.has(tile):
			var layer := _claim_layer()
			_layer_of[tile] = layer
			_index_image.set_pixel(tile.x, tile.y, Color(layer + 1, 0, 0))
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
		# Full: a bigger array, made afresh (rare: it doubles each time)
		_array_dirty = true
	_layer_images.append(Image.create_empty(PADDED, PADDED, false, Image.FORMAT_R8))
	return _layer_images.size() - 1


# The whole texture array and index made afresh, with room to spare
func _upload_all() -> void:
	var layers := FIRST_LAYERS
	while layers < _layer_images.size():
		layers *= 2
	var images: Array[Image] = []
	for i in layers:
		images.append(_layer_images[i] if i < _layer_images.size() else Image.create_empty(PADDED, PADDED, false, Image.FORMAT_R8))
	_array = Texture2DArray.new()
	_array.create_from_images(images)
	_index_texture.update(_index_image)
	_array_dirty = false
	_index_dirty = false
	if material:
		material.set_shader_parameter("path_tiles", _array)
		material.set_shader_parameter("path_index", _index_texture)
	_show()


func _show() -> void:
	if material:
		material.set_shader_parameter("path_info", Vector4(_origin.x, _origin.y, TEXEL, 1.0 if not _layer_of.is_empty() else 0.0))


# A tile's picture with its one-pixel border from the tiles around it, or null if there's no path
# in it or its border
func _padded(tile: Vector2i) -> Image:
	var any := false
	var image := Image.create_empty(PADDED, PADDED, false, Image.FORMAT_R8)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var bytes = _data.get(tile + Vector2i(dx, dz))
			if bytes == null:
				continue
			any = true
			var part := Image.create_from_data(TILE, TILE, false, Image.FORMAT_R8, bytes)
			# The part of that tile that lands in this one's picture (all of it for this tile,
			# one row or column, or one corner pixel, for a neighbour)
			var from := Vector2i(0 if dx == 0 else (TILE - 1 if dx < 0 else 0), 0 if dz == 0 else (TILE - 1 if dz < 0 else 0))
			var size := Vector2i(TILE if dx == 0 else 1, TILE if dz == 0 else 1)
			var to := Vector2i(1 if dx == 0 else (0 if dx < 0 else PADDED - 1), 1 if dz == 0 else (0 if dz < 0 else PADDED - 1))
			image.blit_rect(part, Rect2i(from, size), to)
	return image if any else null


# ---- Saving ----

func save_key() -> String:
	return "painted_paths"


## Each painted tile ("x,z"), compressed and written as text
func save_data() -> Dictionary:
	var tiles := {}
	for tile: Vector2i in _data:
		var bytes: PackedByteArray = _data[tile]
		tiles["%d,%d" % [tile.x, tile.y]] = Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	return {"texel": TEXEL, "tile": TILE, "tiles": tiles}


func load_data(data: Dictionary) -> void:
	clear()
	if float(data.get("texel", TEXEL)) != TEXEL or int(data.get("tile", TILE)) != TILE:
		push_warning("PaintedPaths: saved paths use a different map size; not loading them")
		return
	var tiles: Dictionary = data.get("tiles", {})
	for key in tiles:
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var bytes := Marshalls.base64_to_raw(str(tiles[key])).decompress(TILE * TILE, FileAccess.COMPRESSION_ZSTD)
		if bytes.size() == TILE * TILE:
			_data[tile] = bytes
	for tile: Vector2i in _data:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				_dirty[tile + Vector2i(dx, dz)] = true
	_upload()
	# The grass and ferns there now keep off the paths
	if valley and not _data.is_empty():
		var foliage = valley.get_node_or_null("Foliage")
		if foliage:
			foliage.regrow_plants_in(valley.map_rect())


## Every painted path gone
func clear() -> void:
	for tile in _data:
		_dirty[tile] = true
	_data.clear()
	_layer_of.clear()
	_layer_images.clear()
	_free_layers.clear()
	_index_image.fill(Color(0, 0, 0))
	_dirty.clear()
	_array_dirty = true
	_upload_all()
