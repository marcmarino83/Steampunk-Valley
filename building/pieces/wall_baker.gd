class_name WallBaker
extends Node
## The far looks of the hybrid pieces (see PieceRegistry.is_hybrid): walls (below), roofs (ROOFS) and
## floors and foundations (FLOORS), each baked from its own close-up look.
##
## The far look of the hybrid wood walls, baked from their own
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
const ROOF_FAR_SHADER := preload("res://building/pieces/roof_far.gdshader")
const FLOOR_FAR_SHADER := preload("res://building/pieces/floor_far.gdshader")
## The roof pieces with a hybrid look, at both pitches: roof panels, eaves, gable overhangs, inner
## and outer corners, hip ends, toppers and topper overhangs. Each shaked facet of their close-up look
## is baked straight on in its own plane, from above and from below (see _roof_layout), and their far
## look is a thin slab over those facets (far_mesh) with their trim (fascia and barge boards, rafters,
## logs) kept as real geometry. Left out: eave corners (half a metre square), valley and outer eave
## corners (no close-up look of their own), ridge caps (only a log) and the cone roof (round family).
const ROOFS := ["roof", "roof_45", "eave_26", "eave_45", "gable_overhang_26", "gable_overhang_45",
	"roof_inner_26", "roof_inner_45", "roof_outer_26", "roof_outer_45", "hip_end_26", "hip_end_45",
	"topper_26", "topper_45", "topper_overhang_26", "topper_overhang_45"]
## The floors and foundations with a hybrid look, wood and stone: square, 1 m (floor only), both
## triangles and the round wedges, 45° and 22.5°. Their close-up look is baked from straight above (one
## top facet, see PieceDetail) and their far look is a thin slab over the top with the close-up look's
## sides kept as real geometry, drawn as up close (see far_mesh, floor_far.gdshader)
const FLOORS := ["floor", "floor_1", "floor_rtri", "floor_tri45", "round_floor", "round_floor_22",
	"foundation_wood", "foundation_wood_rtri", "foundation_wood_tri45", "round_foundation_wood", "round_foundation_wood_22",
	"foundation_stone", "foundation_stone_rtri", "foundation_stone_tri45", "round_foundation_stone", "round_foundation_stone_22"]
## A roof's far slab: how far its top lies out from the deck's underside along the facet (level with
## the fascia boards' tops; the shakes' tops average about this), and the margin baked round each facet
const ROOF_TOP := 0.135
const ROOF_MARGIN := 0.03
## Roofs' bakes are half the walls' resolution (128 pixels a metre): their far look only shows from
## BuildPiece.roof_range out, where a 2 m roof is under 200 pixels across
const ROOF_PIXELS_PER_METER := 128
## The far look's trim (merged into its slab, see far_mesh) in plain colours by what it's made of, as
## the close-up look's average (piece_detail.gdshader: wood, stone, rope, iron, dark), times each
## part's own shade
const TRIM_COLORS := [Color(0.35, 0.266, 0.176), Color(0.38, 0.33, 0.228), Color(0.232, 0.143, 0.058), Color(0.12, 0.115, 0.11), Color(0.06, 0.055, 0.05)]
## How deep a roof's top faces sit (see wall_bake.gdshader): the deck seen between shakes, and the
## shakes' faces
const ROOF_CORE_DEPTH := 0.09
const ROOF_FACE_DEPTH := 0.13
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
# A roof shape's far slab (shape -> ArrayMesh) and its bake's layout (shape -> Dictionary)
var _far_meshes := {}
var _roof_layouts := {}
# shape -> its bakes' texture memory (bytes)
var _memory_by_shape := {}
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
			material.shader = ROOF_FAR_SHADER if is_roof(shape) else (FLOOR_FAR_SHADER if is_floor(shape) else FAR_SHADER)
			# (a floor's far look draws its sides as the close-up look does, with the same textures)
			if is_floor(shape):
				var detail := registry.detail_material()
				for param in ["wood_albedo", "wood_normal", "wood_rough", "stone_albedo", "stone_normal", "stone_rough"]:
					material.set_shader_parameter(param, detail.get_shader_parameter(param))
			_materials[_key(shape, v)] = material
		if not _load_cached(shape):
			_queue.append(shape)
			_bake_queued()
	return _materials[key]


## Every hybrid wall shape baked (or read from the cache) now
func prepare_all() -> void:
	for shape in all_shapes():
		far_material(shape, 0)


## Every hybrid wall, roof and floor shape (see PieceRegistry.is_hybrid)
static func all_shapes() -> Array:
	return SnapEdges.WALLS + SnapEdges.TRIANGLES + ROOFS + FLOORS


## A hybrid roof shape (see ROOFS)
static func is_roof(shape: String) -> bool:
	return shape in ROOFS


## A hybrid floor or foundation shape (see FLOORS)
static func is_floor(shape: String) -> bool:
	return shape in FLOORS


## A shape baked by its facets, with a far mesh of its own (a roof or a floor), not a wall's slab
static func is_faceted(shape: String) -> bool:
	return shape in ROOFS or shape in FLOORS


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
	_far_meshes.clear()
	_roof_layouts.clear()
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
		var shape: String = _queue.pop_front()
		if is_faceted(shape):
			await _bake_roof(shape)
		else:
			await _bake(shape)
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


# ---- Roofs ----

## A hybrid roof's far look for one variant, in one mesh (one draw): a slab over each shaked facet,
## its top ROOF_TOP out from the deck's underside and its underside on it, with narrow faces round its
## edges, its texture coordinates pointing into the facet's tiles of the bake and its tangents along
## the bake's frame; and the variant's trim (fascia and barge boards, rafters, logs: PieceRegistry
## roof_parts) as real geometry in plain colours (TRIM_COLORS), so the roof's edges don't change at
## the switch. Vertex colour alpha says which is which (see roof_far.gdshader). Made once.
## A floor's or foundation's (FLOORS) is the same with one facet, its top (baked from above only: the
## slab's underside, inside the piece, takes the top's colours unmapped), and its trim (a floor's base,
## a foundation's core, logs and stone courses) kept exactly as the close-up look draws it: its texture
## coordinates, what each part is made of and its tangents (see floor_far.gdshader), so its sides don't
## change at the switch.
func far_mesh(shape: String, variant: int) -> ArrayMesh:
	var key := _key(shape, variant)
	if _far_meshes.has(key):
		return _far_meshes[key]
	var layout := _roof_layout(shape)
	var tiles: Array = layout["tiles"]
	var atlas := Vector2(layout["pixels"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in tiles.size():
		var top: Dictionary = tiles[i]
		if not top["top"]:
			continue
		var f: Dictionary = top["facet"]
		var bottom: Dictionary = tiles[i + 1] if i + 1 < tiles.size() and not tiles[i + 1]["top"] and tiles[i + 1]["facet"] == f else {}
		var n: Vector3 = f["n"]
		var lift := n * float(f.get("lift", ROOF_TOP))
		var poly: PackedVector2Array = f["poly"]
		var pts: Array[Vector3] = []
		for p in poly:
			pts.append((f["o"] as Vector3) + (f["u"] as Vector3) * p.x + (f["s"] as Vector3) * p.y)
		var tris := Geometry2D.triangulate_polygon(poly)
		for k in range(0, tris.size(), 3):
			var corners: Array[Vector3] = [pts[tris[k]], pts[tris[k + 1]], pts[tris[k + 2]]]
			_far_tri(st, corners.map(func(p): return p + lift), corners.map(func(p): return _tile_uv(top, p, atlas)), n, top["basis"].x, true)
			if bottom.is_empty():
				_far_tri(st, corners, corners.map(func(p): return _tile_uv(top, p, atlas)), -n, top["basis"].x, false)
			else:
				_far_tri(st, corners, corners.map(func(p): return _tile_uv(bottom, p, atlas)), -n, bottom["basis"].x, true)
		# The narrow faces round its edges, coloured as the top's edge
		var middle := Vector3.ZERO
		for p in pts:
			middle += p / pts.size()
		for j in pts.size():
			var a := pts[j]
			var b := pts[(j + 1) % pts.size()]
			var along := (b - a).normalized()
			var out := along.cross(n).normalized()
			if out.dot((a + b) / 2.0 - middle) < 0.0:
				out = -out
			var uv_a := _tile_uv(top, a, atlas)
			var uv_b := _tile_uv(top, b, atlas)
			_far_tri(st, [a, b, b + lift], [uv_a, uv_b, uv_b], out, along, false)
			_far_tri(st, [a, b + lift, a + lift], [uv_a, uv_b, uv_a], out, along, false)
	if is_floor(shape):
		_append_trim_as_drawn(st, registry.roof_parts(shape, variant)["trim"])
	else:
		_append_trim(st, registry.roof_parts(shape, variant)["trim"])
	var mesh := st.commit()
	_far_meshes[key] = mesh
	return mesh


# A close-up trim mesh's triangles added to a far look exactly as drawn up close: the same winding,
# normals, tangents, texture coordinates, shades and what each part is made of (UV2.x), with vertex
# colour alpha 0 so floor_far.gdshader draws them as piece_detail.gdshader does
static func _append_trim_as_drawn(st: SurfaceTool, trim: Mesh) -> void:
	if trim == null:
		return
	for s in trim.get_surface_count():
		var arrays := trim.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var kinds: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if order.is_empty():
			order = PackedInt32Array(range(verts.size()))
		for i in order:
			var shade: Color = colors[i] if i < colors.size() else Color.WHITE
			st.set_normal(normals[i])
			if tangents.size() >= (i + 1) * 4:
				st.set_tangent(Plane(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2], tangents[i * 4 + 3]))
			else:
				st.set_tangent(Plane(Vector3.RIGHT, 1.0))
			st.set_color(Color(shade.r, shade.g, shade.b, 0.0))
			st.set_uv(uvs[i] if i < uvs.size() else Vector2.ZERO)
			st.set_uv2(kinds[i] if i < kinds.size() else Vector2.ZERO)
			st.add_vertex(verts[i])


# A close-up trim mesh's triangles added to a far look, as they are (the same winding), each in its
# plain colour (TRIM_COLORS by what it's made of, times its shade) with vertex colour alpha 0
static func _append_trim(st: SurfaceTool, trim: Mesh) -> void:
	if trim == null:
		return
	for s in trim.get_surface_count():
		var arrays := trim.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var kinds: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if order.is_empty():
			order = PackedInt32Array(range(verts.size()))
		for i in order:
			var kind := clampi(roundi(kinds[i].x) if i < kinds.size() else 0, 0, TRIM_COLORS.size() - 1)
			var shade: Color = colors[i] if i < colors.size() else Color.WHITE
			var plain: Color = TRIM_COLORS[kind]
			st.set_normal(normals[i])
			st.set_tangent(Plane(Vector3.RIGHT, 1.0))
			st.set_color(Color(plain.r * shade.r, plain.g * shade.g, plain.b * shade.b, 0.0))
			st.set_uv(Vector2.ZERO)
			st.set_uv2(Vector2.ZERO)
			st.add_vertex(verts[i])


# One triangle of a far slab, wound to face along `normal` (as PieceDetail winds its triangles);
# `mapped`: its face takes the bake's normals (vertex colour alpha 1; a narrow edge face 0.5)
static func _far_tri(st: SurfaceTool, points: Array, uvs: Array, normal: Vector3, tangent: Vector3, mapped: bool) -> void:
	var order := [0, 1, 2]
	if ((points[1] as Vector3) - (points[0] as Vector3)).cross((points[2] as Vector3) - (points[0] as Vector3)).dot(normal) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(normal)
		st.set_tangent(Plane(tangent, 1.0))
		st.set_color(Color(1.0, 1.0, 1.0, 1.0 if mapped else 0.5))
		st.set_uv(uvs[i])
		# (every vertex of a far mesh has a UV2, so a floor's trim can carry what its parts are made of)
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(points[i])


# Where a point on a facet falls in the bake (0 to 1 across the whole atlas), through its tile
static func _tile_uv(tile: Dictionary, p: Vector3, atlas: Vector2) -> Vector2:
	var f: Dictionary = tile["facet"]
	var q: Vector3 = (tile["basis"] as Basis).transposed() * (p - (f["o"] as Vector3))
	var lo: Vector2 = tile["min"]
	var px: Vector2i = tile["pixels"]
	return Vector2(tile["x"] + (q.x - lo.x) * ROOF_PIXELS_PER_METER, px.y - (q.y - lo.y) * ROOF_PIXELS_PER_METER) / atlas


# A roof shape's bake layout: each shaked facet twice, from above then from below, as tiles side by
# side in one atlas a variant. A tile's frame ("basis") is the camera's: x across, y up the slope, z
# out of the face toward the camera; "min" is its corner in (x, y), "pixels" its size, "x" where it
# starts in the atlas.
func _roof_layout(shape: String) -> Dictionary:
	if _roof_layouts.has(shape):
		return _roof_layouts[shape]
	var tiles := []
	var x := 0
	var height := 1
	for f in registry.roof_parts(shape, 0)["facets"]:
		# (a floor's top is baked from above only)
		for side in ([1.0] if f.get("top_only", false) else [1.0, -1.0]):
			var n: Vector3 = (f["n"] as Vector3) * side
			var s: Vector3 = f["s"]
			var basis := Basis(s.cross(n).normalized(), s, n)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in f["poly"]:
				var point: Vector3 = (f["u"] as Vector3) * p.x + s * p.y
				var q := Vector2(point.dot(basis.x), point.dot(s))
				lo = lo.min(q)
				hi = hi.max(q)
			lo -= Vector2.ONE * ROOF_MARGIN
			hi += Vector2.ONE * ROOF_MARGIN
			var pixels := Vector2i(ceili((hi.x - lo.x) * ROOF_PIXELS_PER_METER), ceili((hi.y - lo.y) * ROOF_PIXELS_PER_METER))
			tiles.append({"facet": f, "basis": basis, "min": lo, "pixels": pixels, "x": x, "top": side > 0.0})
			x += pixels.x
			height = maxi(height, pixels.y)
	var layout := {"tiles": tiles, "pixels": Vector2i(maxi(x, 1), height)}
	_roof_layouts[shape] = layout
	return layout


func _bake_roof(shape: String) -> void:
	var timing := SpikeLog.begin()
	var layout := _roof_layout(shape)
	var count := PieceRegistry.DETAIL_VARIANTS
	var atlas: Vector2i = layout["pixels"]
	var meshes: Array = []
	var atlases: Array = []
	for v in count:
		# (a floor bakes its whole close-up look from above: the base or deck seen between its planks or
		# flagstones is trim, and what's under the top is hidden from the camera anyway)
		meshes.append(registry.detail_mesh(shape, v)["mesh"] if is_floor(shape) else registry.roof_parts(shape, v)["surface"])
		var colour := Image.create(atlas.x, atlas.y, false, Image.FORMAT_RGB8)
		colour.fill(BACKGROUND_COLOR.linear_to_srgb())
		var surface := Image.create(atlas.x, atlas.y, false, Image.FORMAT_RGB8)
		surface.fill(BACKGROUND_SURFACE)
		atlases.append([colour, surface])
	for tile in layout["tiles"]:
		var drawn := await _render_tile(meshes, tile)
		var px: Vector2i = tile["pixels"] * SUPERSAMPLE
		for v in count:
			for bake_pass in 2:
				var part: Image = drawn[bake_pass].get_region(Rect2i(v * px.x, 0, px.x, px.y))
				part.convert(Image.FORMAT_RGB8)
				part.resize(tile["pixels"].x, tile["pixels"].y, Image.INTERPOLATE_LANCZOS)
				(atlases[v][bake_pass] as Image).blit_rect(part, Rect2i(Vector2i.ZERO, tile["pixels"]), Vector2i(tile["x"], 0))
	for v in count:
		if not _materials.has(_key(shape, v)):
			continue
		var images: Array[Image] = [atlases[v][0], atlases[v][1]]
		_finish(images[0], true)
		_finish(images[1], false)
		_save(shape, v, images)
		_apply(shape, v, images, layout)
		made += 1
	SpikeLog.end("roof far look baked (first use)", timing)
	shape_ready.emit(shape)


# One tile of a roof's bake, every variant side by side: their surface layers turned so the tile's
# facet lies flat facing the orthographic camera, drawn for colour, then for the surface
func _render_tile(meshes: Array, tile: Dictionary) -> Array[Image]:
	var count := meshes.size()
	var px: Vector2i = tile["pixels"] * SUPERSAMPLE
	var size := Vector2(tile["pixels"]) / float(ROOF_PIXELS_PER_METER)
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
	camera.size = size.y
	camera.near = 0.05
	camera.far = CAMERA_Z * 2.0
	camera.position = Vector3(0.0, size.y / 2.0, CAMERA_Z)
	camera.environment = environment
	viewport.add_child(camera)
	camera.current = true
	var material := ShaderMaterial.new()
	material.shader = BAKE_SHADER
	var detail := registry.detail_material()
	for param in ["wood_albedo", "wood_normal", "stone_albedo", "stone_normal"]:
		material.set_shader_parameter(param, detail.get_shader_parameter(param))
	material.set_shader_parameter("camera_z", CAMERA_Z)
	# From above, the deck seen between shakes is the gaps' depth; from below, it's all one depth
	var from_above: bool = tile["top"]
	var f: Dictionary = tile["facet"]
	# (a floor's facet says how deep its gaps and its faces sit, measured up from the facet's plane)
	material.set_shader_parameter("core_depth", float(f.get("core", ROOF_CORE_DEPTH)) if from_above else -2.0)
	material.set_shader_parameter("face_depth", float(f.get("face", ROOF_FACE_DEPTH)) if from_above else -1.0)
	var flat := (tile["basis"] as Basis).transposed()
	var lo: Vector2 = tile["min"]
	for v in count:
		var look := MeshInstance3D.new()
		look.mesh = meshes[v]
		look.material_override = material
		var slot := (v - count / 2.0) * size.x
		look.transform = Transform3D(flat, flat * -(f["o"] as Vector3) + Vector3(slot - lo.x, -lo.y, 0.0))
		viewport.add_child(look)
	var drawn: Array[Image] = []
	for bake_pass in 2:
		material.set_shader_parameter("bake_pass", bake_pass)
		environment.background_color = BACKGROUND_COLOR.linear_to_srgb() if bake_pass == 0 else BACKGROUND_SURFACE
		for i in 3:
			await RenderingServer.frame_post_draw
		drawn.append(viewport.get_texture().get_image())
	viewport.queue_free()
	return drawn


# Mipmapped and compressed (DXT1, half a byte a pixel) where this build can compress
static func _finish(image: Image, colour: bool) -> void:
	image.generate_mipmaps()
	image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB if colour else Image.COMPRESS_SOURCE_GENERIC)


func _apply(shape: String, variant: int, images: Array[Image], layout: Dictionary) -> void:
	var material: ShaderMaterial = _materials[_key(shape, variant)]
	material.set_shader_parameter("baked_color", ImageTexture.create_from_image(images[0]))
	material.set_shader_parameter("baked_surface", ImageTexture.create_from_image(images[1]))
	if layout.has("min"):
		material.set_shader_parameter("bake_min", layout["min"])
		material.set_shader_parameter("bake_size", layout["size"])
	material.set_shader_parameter("baked", true)
	material.set_meta(&"baked", true)
	var bytes := images[0].get_data_size() + images[1].get_data_size()
	memory += bytes
	_memory_by_shape[shape] = int(_memory_by_shape.get(shape, 0)) + bytes


## The bakes' texture memory (bytes) for these shapes
func memory_of(shapes: Array) -> int:
	var total := 0
	for shape in shapes:
		total += int(_memory_by_shape.get(shape, 0))
	return total


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
	var layout: Dictionary = _roof_layout(shape) if is_faceted(shape) else _layout(shape)
	for v in found.size():
		_apply(shape, v, found[v], layout)
		loaded += 1
	return true
