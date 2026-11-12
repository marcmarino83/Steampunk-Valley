class_name WallBaker
extends Node
## The far look of the hybrid wood walls (see PieceRegistry.is_hybrid), baked from their own
## close-up look: each shape's DETAIL_VARIANTS close-up meshes are drawn straight on, unlit, by an
## orthographic camera in a viewport of their own (wall_bake.gdshader), once for their colour and
## once for their surface (the normal, close-up normal map included, and how deep each face sits).
## The far slab (wall_far.gdshader) wears those, so every board, joint, stagger and shade lines up
## with the close-up look across the switch, and only the fine depth changes.
##
## Every shape is prepared while the world opens, under the loading cover (see ShaderWarmup), so no
## bake or cache read happens mid-game; one asked for before that is baked then. A shape is baked
## with all its variants together, drawn SUPERSAMPLE times larger and shrunk (PIXELS_PER_METER
## after), mipmapped and compressed
## (DXT1), and kept in CACHE_DIR for the next run. The cache is keyed by the look code: when any of
## SOURCES changes, the old bakes are cleared and made again. Until a shape's bake is ready its walls
## show their close-up planks at every distance (see BuildPiece._dress_hybrid). Nothing is baked
## without a screen (headless runs), or before the baker is in the tree.

const BAKE_SHADER := preload("res://building/pieces/wall_bake.gdshader")
const FAR_SHADER := preload("res://building/pieces/wall_far.gdshader")
## The bakes' size: 256 pixels a metre (512 across a 2 m wall), drawn at twice that and shrunk
const PIXELS_PER_METER := 256
const SUPERSAMPLE := 2
const CACHE_DIR := "user://wall_bakes"
const BAKE_VERSION := 1
## The code a bake depends on: a change to any of these makes every bake again
const SOURCES := [
	"res://building/pieces/piece_detail.gd",
	"res://building/pieces/piece_detail.gdshader",
	"res://building/pieces/piece_shapes.gd",
	"res://building/pieces/piece_registry.gd",
	"res://building/pieces/wall_bake.gdshader",
	"res://building/pieces/wall_baker.gd",
]
## How far in front of the wall the bake's camera stands (+Z)
const CAMERA_Z := 5.0
## The bake's background: the wood's plain colour, and a face looking straight out at full depth
const BACKGROUND_COLOR := Color(0.29, 0.22, 0.145)
const BACKGROUND_SURFACE := Color(0.5, 0.5, 1.0)

## A shape's far looks have their bake now (walls showing their planks while it baked switch over)
signal shape_ready(shape: String)

var registry: PieceRegistry
## For reports: variants baked this session, variants read from the cache, and their textures'
## memory (bytes)
var made := 0
var loaded := 0
var memory := 0

# "shape#variant" -> ShaderMaterial (its far look)
var _materials := {}
var _queue: Array[String] = []
var _baking := false
var _stamp := ""


# (shapes asked for before it was in the tree are baked now)
func _ready() -> void:
	_bake_queued()


## A shape's far look for one variant: made now (from the cache when it's there), or still to be
## baked (see is_ready; shape_ready says when)
func far_material(shape: String, variant: int) -> ShaderMaterial:
	var key := _key(shape, variant)
	if not _materials.has(key):
		for v in PieceRegistry.DETAIL_VARIANTS:
			var material := ShaderMaterial.new()
			material.shader = FAR_SHADER
			_materials[_key(shape, v)] = material
		if not _load_cached(shape):
			_queue.append(shape)
			_bake_queued()
	return _materials[key]


## Every hybrid wall shape baked (or read from the cache) now
func prepare_all() -> void:
	for shape in all_shapes():
		far_material(shape, 0)


## Every hybrid wall shape (see PieceRegistry.is_hybrid)
static func all_shapes() -> Array:
	return SnapEdges.WALLS + SnapEdges.TRIANGLES


## True once this far look has its bake
static func is_ready(material: Material) -> bool:
	return material != null and material.get_meta(&"baked", false)


## True once every bake asked for is done
func is_idle() -> bool:
	return not _baking and _queue.is_empty()


## How many shapes are still waiting to be baked, the one being baked included
func remaining() -> int:
	return _queue.size() + (1 if _baking else 0)


## The far looks let go of, so they're made again (and baked again if the look code changed)
func clear() -> void:
	_materials.clear()
	_queue.clear()
	_stamp = ""


static func can_bake() -> bool:
	return DisplayServer.get_name() != "headless"


static func _key(shape: String, variant: int) -> String:
	return "%s#%d" % [shape, variant]


# Where the shape's close-up meshes sit (all variants within one box), and the bake's size
func _layout(shape: String) -> Dictionary:
	var meshes: Array = []
	var rect := Rect2()
	for v in PieceRegistry.DETAIL_VARIANTS:
		var mesh: Mesh = registry.detail_mesh(shape, v).get("mesh")
		meshes.append(mesh)
		var box := mesh.get_aabb()
		var r := Rect2(box.position.x, box.position.y, box.size.x, box.size.y)
		rect = r if v == 0 else rect.merge(r)
	var pixels := Vector2i(ceili(rect.size.x * PIXELS_PER_METER), ceili(rect.size.y * PIXELS_PER_METER))
	return {"meshes": meshes, "min": rect.position, "pixels": pixels, "size": Vector2(pixels) / float(PIXELS_PER_METER)}


func _bake_queued() -> void:
	if _baking or not can_bake() or not is_inside_tree():
		return
	_baking = true
	while not _queue.is_empty():
		await _bake(_queue.pop_front())
	_baking = false


func _bake(shape: String) -> void:
	var timing := SpikeLog.begin()
	var layout := _layout(shape)
	var count := PieceRegistry.DETAIL_VARIANTS
	var px: Vector2i = layout["pixels"] * SUPERSAMPLE
	var tile: Vector2 = layout["size"]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(px.x * count, px.y)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = tile.y
	camera.near = 0.05
	camera.far = CAMERA_Z * 2.0
	camera.position = Vector3(0.0, layout["min"].y + tile.y / 2.0, CAMERA_Z)
	camera.environment = environment
	viewport.add_child(camera)
	camera.current = true
	var material := ShaderMaterial.new()
	material.shader = BAKE_SHADER
	var detail := registry.detail_material()
	for param in ["wood_albedo", "wood_normal", "stone_albedo", "stone_normal"]:
		material.set_shader_parameter(param, detail.get_shader_parameter(param))
	material.set_shader_parameter("camera_z", CAMERA_Z)
	# The variants side by side, each in its own tile
	for v in count:
		var look := MeshInstance3D.new()
		look.mesh = layout["meshes"][v]
		look.material_override = material
		look.position = Vector3((v - count / 2.0) * tile.x - layout["min"].x, 0.0, 0.0)
		viewport.add_child(look)
	var drawn: Array[Image] = []
	for bake_pass in 2:
		material.set_shader_parameter("bake_pass", bake_pass)
		environment.background_color = BACKGROUND_COLOR.linear_to_srgb() if bake_pass == 0 else BACKGROUND_SURFACE
		for i in 3:
			await RenderingServer.frame_post_draw
		drawn.append(viewport.get_texture().get_image())
	viewport.queue_free()
	for v in count:
		var key := _key(shape, v)
		if not _materials.has(key):
			continue
		var images: Array[Image] = []
		for image in drawn:
			var part := image.get_region(Rect2i(v * px.x, 0, px.x, px.y))
			part.convert(Image.FORMAT_RGB8)
			part.resize(layout["pixels"].x, layout["pixels"].y, Image.INTERPOLATE_LANCZOS)
			images.append(part)
		_finish(images[0], true)
		_finish(images[1], false)
		_save(shape, v, images)
		_apply(shape, v, images, layout)
		made += 1
	SpikeLog.end("wall far look baked (first use)", timing)
	shape_ready.emit(shape)


# Mipmapped and compressed (DXT1, half a byte a pixel) where this build can compress
static func _finish(image: Image, colour: bool) -> void:
	image.generate_mipmaps()
	image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB if colour else Image.COMPRESS_SOURCE_GENERIC)


func _apply(shape: String, variant: int, images: Array[Image], layout: Dictionary) -> void:
	var material: ShaderMaterial = _materials[_key(shape, variant)]
	material.set_shader_parameter("baked_color", ImageTexture.create_from_image(images[0]))
	material.set_shader_parameter("baked_surface", ImageTexture.create_from_image(images[1]))
	material.set_shader_parameter("bake_min", layout["min"])
	material.set_shader_parameter("bake_size", layout["size"])
	material.set_shader_parameter("baked", true)
	material.set_meta(&"baked", true)
	memory += images[0].get_data_size() + images[1].get_data_size()


# ---- The cache ----

func _cache_path(shape: String, variant: int) -> String:
	if _stamp.is_empty():
		var text := "%d/%d/%d/" % [BAKE_VERSION, PIXELS_PER_METER, SUPERSAMPLE]
		for path in SOURCES:
			text += FileAccess.get_md5(path)
		_stamp = text.md5_text().substr(0, 12)
		# (bakes made by older look code are cleared away)
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		var dir := DirAccess.open(CACHE_DIR)
		if dir:
			for file in dir.get_files():
				if not file.begins_with(_stamp):
					dir.remove(file)
	return CACHE_DIR.path_join("%s_%s_%d.bake" % [_stamp, shape, variant])


func _save(shape: String, variant: int, images: Array[Image]) -> void:
	var file := FileAccess.open(_cache_path(shape, variant), FileAccess.WRITE)
	if file == null:
		return
	for image in images:
		file.store_var({"width": image.get_width(), "height": image.get_height(), "mipmaps": image.has_mipmaps(), "format": image.get_format(), "data": image.get_data()})


# A shape's bakes from the cache: every variant's, or none (false)
func _load_cached(shape: String) -> bool:
	var found := []
	for v in PieceRegistry.DETAIL_VARIANTS:
		var file := FileAccess.open(_cache_path(shape, v), FileAccess.READ)
		if file == null:
			return false
		var images: Array[Image] = []
		for i in 2:
			var entry = file.get_var()
			if not entry is Dictionary:
				return false
			var image := Image.create_from_data(int(entry["width"]), int(entry["height"]), bool(entry["mipmaps"]), int(entry["format"]), entry["data"])
			if image == null or image.is_empty():
				return false
			images.append(image)
		found.append(images)
	var layout := _layout(shape)
	for v in found.size():
		_apply(shape, v, found[v], layout)
		loaded += 1
	return true
