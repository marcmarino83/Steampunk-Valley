class_name PathTileUpload
extends RefCounted
## Hands PathTiles' map to the ground shader: every map tile with path in it is one layer of a
## texture array (with a one-pixel border from its neighbours, so the shader can blend across
## tile edges), and a small index image says which layer each map tile is (0: none). Only the map
## tiles marked dirty are uploaded again; the array is rebuilt, twice as big, when it fills.
## Owned by PathTiles, which marks what changed and passes its map tiles in.

## The ground material it sets the shader's tile_path_* parameters on (null: none, in tests)
var material: ShaderMaterial
## Map tiles (x, z) whose pixels changed and need uploading again
var dirty := {}

# Where the map starts (x, z), how many map tiles across and down it is, and its index image
var _origin := Vector2.ZERO
var _tiles := Vector2i.ZERO
var _index_image: Image
var _index_texture: ImageTexture
# Map tile -> its layer, every layer's picture, and layers given back for reuse
var _layer_of := {}
var _layer_images: Array[Image] = []
var _free_layers: Array[int] = []
var _array: Texture2DArray
var _index_dirty := false
var _array_dirty := false


## True if the map's size or place has changed (or it's never been set up), so it must start over
func needs_reset(tiles: Vector2i, origin: Vector2) -> bool:
	return _index_image == null or tiles != _tiles or origin != _origin


## Starts over for a map this many map tiles across and down, starting here (x, z): no layers
func reset(tiles: Vector2i, origin: Vector2) -> void:
	_origin = origin
	_tiles = tiles
	_index_image = Image.create_empty(_tiles.x, _tiles.y, false, Image.FORMAT_RF)
	_index_texture = ImageTexture.create_from_image(_index_image)
	_layer_of.clear()
	_layer_images.clear()
	_free_layers.clear()


## True if anything is waiting to be uploaded
func pending() -> bool:
	return not dirty.is_empty() or _index_dirty or _array_dirty


## A pixel changed: its map tile needs uploading again, and so does any neighbour whose border
## shows it
func mark_pixel(px: int, pz: int) -> void:
	var tile := Vector2i(px / PathTiles.TILE, pz / PathTiles.TILE)
	dirty[tile] = true
	var lx := px - tile.x * PathTiles.TILE
	var lz := pz - tile.y * PathTiles.TILE
	var sx := -1 if lx == 0 else (1 if lx == PathTiles.TILE - 1 else 0)
	var sz := -1 if lz == 0 else (1 if lz == PathTiles.TILE - 1 else 0)
	if sx != 0:
		dirty[tile + Vector2i(sx, 0)] = true
	if sz != 0:
		dirty[tile + Vector2i(0, sz)] = true
	if sx != 0 and sz != 0:
		dirty[tile + Vector2i(sx, sz)] = true


## Uploads the dirty map tiles, from PathTiles' map (map tile -> its pixels)
func upload(data: Dictionary) -> void:
	for tile: Vector2i in dirty:
		if tile.x < 0 or tile.y < 0 or tile.x >= _tiles.x or tile.y >= _tiles.y:
			continue
		var image := _padded(tile, data)
		if image == null:
			if _layer_of.has(tile):
				_index_image.set_pixel(tile.x, tile.y, Color(0, 0, 0))
				_index_dirty = true
				_layer_images[_layer_of[tile]] = Image.create_empty(PathTiles.PADDED,
						PathTiles.PADDED, false, Image.FORMAT_RGBA8)
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
	dirty.clear()
	if _array_dirty:
		upload_all()
	elif _index_dirty:
		_index_texture.update(_index_image)
		_index_dirty = false
	_show()


func _claim_layer() -> int:
	if not _free_layers.is_empty():
		return _free_layers.pop_back()
	if _layer_images.size() >= (_array.get_layers() if _array else 0):
		_array_dirty = true
	_layer_images.append(Image.create_empty(PathTiles.PADDED, PathTiles.PADDED, false,
			Image.FORMAT_RGBA8))
	return _layer_images.size() - 1


## The whole texture array made again (room for every layer, doubling from FIRST_LAYERS) and
## handed to the shader with the index
func upload_all() -> void:
	var layers := PathTiles.FIRST_LAYERS
	while layers < _layer_images.size():
		layers *= 2
	var images: Array[Image] = []
	for i in layers:
		images.append(_layer_images[i] if i < _layer_images.size() else Image.create_empty(
				PathTiles.PADDED, PathTiles.PADDED, false, Image.FORMAT_RGBA8))
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
		material.set_shader_parameter("tile_path_info", Vector4(_origin.x, _origin.y,
				PathTiles.TEXEL, 1.0 if not _layer_of.is_empty() else 0.0))


# A map tile's picture with its one-pixel border from its neighbours, or null if there's no path
# in it or its border
static func _padded(tile: Vector2i, data: Dictionary) -> Image:
	const TILE := PathTiles.TILE
	const PADDED := PathTiles.PADDED
	var any := false
	var image := Image.create_empty(PADDED, PADDED, false, Image.FORMAT_RGBA8)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var bytes = data.get(tile + Vector2i(dx, dz))
			if bytes == null:
				continue
			any = true
			var part := Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGBA8, bytes)
			var from := Vector2i(0 if dx == 0 else (TILE - 1 if dx < 0 else 0),
					0 if dz == 0 else (TILE - 1 if dz < 0 else 0))
			var size := Vector2i(TILE if dx == 0 else 1, TILE if dz == 0 else 1)
			var to := Vector2i(1 if dx == 0 else (0 if dx < 0 else PADDED - 1),
					1 if dz == 0 else (0 if dz < 0 else PADDED - 1))
			image.blit_rect(part, Rect2i(from, size), to)
	return image if any else null
