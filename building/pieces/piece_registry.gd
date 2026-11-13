class_name PieceRegistry
extends Node
## Every building piece in the world, by id: makes them, takes them away, and saves them.
## Pieces get ids that stay the same across saves, and an owner plot (empty for none), so the plot
## system can find, count and move the pieces it owns.

## A piece was added or taken away (plots check their requirements again)
signal changed

const CLEAR_ZONE_SCENE := preload("res://building/clear_zone.tscn")
## The pieces' textured surface, and the Poly Haven textures it uses (2K copies; the 4K originals
## are in assets/textures/hd/, kept out of git). Roofs use the wood too: the reed thatch in hd/
## has a ridge band along its top edge, so it doesn't tile down a slope.
const SURFACE_SHADER := preload("res://building/pieces/piece_surface.gdshader")
const WOOD_FOLDER := "res://assets/textures/wood_planks_dirt/wood_planks_dirt"
const STONE_FOLDER := "res://assets/textures/rock_wall_13/rock_wall_13"
## The close-up look (see PieceDetail) and how many versions of it each shape has
const DETAIL_SHADER := preload("res://building/pieces/piece_detail.gdshader")
const DETAIL_VARIANTS := 4
## Hybrid detail for the wood wall family, Standard and Tall (walls, half walls, strips, doorways,
## windows, gables and triangle walls): modelled planks up close, beyond BuildPiece.hybrid_range a
## slab wearing textures baked from those planks (see WallBaker), no middle look. Off: those pieces
## get the three looks every other piece has (for comparing).
static var hybrid_walls := true
## The same for the floors and foundations alone (WallBaker.FLOORS): off, they get the three looks
## again (for comparing, tests/floor_pass.gd)
static var hybrid_floors := true
## Stairs, pillars, poles and beams (the look pass, tests/structure_pass.gd), none baked:
##   LEAN (stairs, wood and stone pillars): the close-up look within BuildPiece.lean_range, beyond it
##   a lean far look (PieceDetail.far: the same parts in the same places, plain-edged, rope in fewer
##   segments, each stair tread one plank) in the plain box's place; the shadow from the far look at
##   every distance (BuildPiece.far_shadows), no middle look, no plain box.
##   SINGLE (poles and beams: one log, nothing finer to drop): the close-up look at every distance,
##   in the plain box's place, casting its own shadow; no switch at all.
## Off: they get the three looks again (for comparing).
static var lean_structure := true
const LEAN := ["stairs", "half_stairs", "stairs_tall", "half_stairs_tall",
	"pillar_wood", "pillar_wood_2m", "pillar_wood_half", "pillar_wood_half_tall",
	"pillar_stone", "pillar_stone_2m", "pillar_stone_half", "pillar_stone_half_tall"]
const SINGLE := ["pole_1", "pole_2", "pole_4", "beam_2", "beam_4",
	"beam_diag_26", "beam_diag_45", "beam_diag_26_4", "beam_diag_45_4"]

## Where pieces are added (the world). Set by the build placer.
var world: Node

# id -> BuildPiece
var _pieces := {}
var _next_id := 1
# Each shape's look, collision and snap points, made once: shape -> PieceShapes.build()
var _shapes := {}
var _material: StandardMaterial3D
# The textured surfaces, one per kind ("wood", "roof", "stone"...), made when first needed
var _surfaces := {}
# The close-up looks ("shape#variant" -> PieceDetail.build()), their material, and the corner posts
# and ridge logs worked out from the pieces
var _details := {}
var _detail_material: ShaderMaterial
var _joints: JointDetails
## The hybrid walls' far looks, baked from their close-up looks
var baker: WallBaker

## Debug runs from the project only: the close-up look code, checked every LOOK_CHECK_SECONDS for a
## change on disk while the game runs. The looks made once per shape and shared by every piece of
## it would otherwise keep the older code's shape for the rest of the session (and new pieces would
## get them too), however the code has changed; when it has, the code is reloaded and every
## piece's looks are made again (see remake_looks).
const LOOK_CODE := "res://building/pieces/piece_detail.gd"
const LOOK_CHECK_SECONDS := 2.0
var _look_stamp := 0
var _look_check := 0.0


func _init() -> void:
	# Made with the registry itself, not when it enters the tree: a registry used outside the world
	# (the icon updater's, the title screen's) still builds pieces, and every wall asks the baker for
	# its far look (it bakes once it's in the tree; until then those walls show their planks)
	baker = WallBaker.new()
	baker.name = "WallBaker"
	baker.registry = self
	add_child(baker)


func _ready() -> void:
	add_to_group("saveable")
	add_to_group("piece_registry")
	# Corner posts over wall joints and logs along ridges, worked out again whenever pieces change
	_joints = JointDetails.new()
	_joints.registry = self
	add_child(_joints)
	changed.connect(_joints.mark_dirty)
	_look_stamp = FileAccess.get_modified_time(LOOK_CODE) if OS.is_debug_build() else 0
	set_process(_look_stamp != 0)


func _process(delta: float) -> void:
	_look_check -= delta
	if _look_check > 0.0:
		return
	_look_check = LOOK_CHECK_SECONDS
	var stamp := FileAccess.get_modified_time(LOOK_CODE)
	if stamp == 0 or stamp == _look_stamp:
		return
	_look_stamp = stamp
	# The running game may still have the older code: take it from the file
	var script := load(LOOK_CODE) as GDScript
	var source := FileAccess.get_file_as_string(LOOK_CODE)
	if script and not source.is_empty() and source != script.source_code:
		script.source_code = source
		script.reload(true)
	remake_looks()
	print("[Pieces] the look code changed: every piece's looks made again")


## Every piece's close-up and middle looks made again from the current look code (ghosts too), and
## the corner posts and ridge logs with them; the looks made before are let go
func remake_looks() -> void:
	_details.clear()
	baker.clear()
	for piece in all_pieces():
		var ghost: bool = piece.is_ghost()
		if ghost:
			piece.set_ghost(false)
		piece.redress(detail_mesh(piece.shape_name, piece.piece_id), detail_material(), mid_mesh(piece.shape_name, piece.piece_id))
		if ghost:
			piece.set_ghost(true)
	_joints.mark_dirty()


func _exit_tree() -> void:
	# Let go of the meshes and shapes, so nothing is reported as leaked when the game closes
	_shapes.clear()
	_material = null
	_surfaces.clear()
	_details.clear()
	_detail_material = null
	BuildPiece.clear_fitted_cache()


## A shape's look, collision and snap points (see PieceShapes.build)
func shape_of(shape: String) -> Dictionary:
	if not _shapes.has(shape):
		var timing := SpikeLog.begin()
		_shapes[shape] = PieceShapes.build(shape)
		SpikeLog.end("piece shape made (first use)", timing)
	return _shapes[shape]


## The material a piece of this shape is drawn with (see piece_surface.gdshader): textured wood
## planks mapped to suit the piece (walls, floors, roofs with thatch on top, curved and round
## pieces, beams, posts), stone for stone pieces, or the plain painted colours for furniture
func material_for(shape: String) -> Material:
	var def := shape_of(shape)
	var kind := "wood"
	if def.get("furniture", false):
		return wood_material()
	if is_hybrid(shape) and not WallBaker.is_faceted(shape):
		# (its first variant's far look: each piece wears its own variant's, see mid_mesh; a roof keeps
		# its plain surface until it's dressed, when its far slab takes the plain box's place)
		return baker.far_material(shape, 0)
	if shape.contains("stone"):
		kind = "stone_round" if shape.begins_with("round") else "stone"
	elif shape == "cone_roof":
		kind = "cone"
	elif def.get("roof", false) or def.get("overhang", false):
		kind = "roof"
	elif shape.begins_with("curved_wall") or shape.begins_with("round"):
		kind = "round"
	elif shape == "beam_2":
		kind = "beam"
	elif shape.begins_with("pole") or shape.begins_with("pillar") or shape.begins_with("ladder"):
		kind = "post"
	if not _surfaces.has(kind):
		_surfaces[kind] = _make_surface(kind)
	return _surfaces[kind]


func _make_surface(kind: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("wood_albedo", load(WOOD_FOLDER + "_diff_2k.jpg"))
	material.set_shader_parameter("wood_normal", load(WOOD_FOLDER + "_nor_gl_2k.png"))
	material.set_shader_parameter("wood_rough", load(WOOD_FOLDER + "_rough_2k.png"))
	if kind.begins_with("stone"):
		material.set_shader_parameter("alt_albedo", load(STONE_FOLDER + "_diff_2k.jpg"))
		material.set_shader_parameter("alt_normal", load(STONE_FOLDER + "_nor_gl_2k.png"))
		material.set_shader_parameter("alt_rough", load(STONE_FOLDER + "_rough_2k.png"))
	material.set_shader_parameter("mode", {"round": 1, "stone_round": 1, "cone": 2, "beam": 3, "post": 4}.get(kind, 0))
	material.set_shader_parameter("alt_everywhere", kind.begins_with("stone"))
	return material


## A wood wall, Standard or Tall (walls, half walls, strips, doorways, windows, gables and triangle
## walls), a roof piece in WallBaker.ROOFS, or a floor or foundation in WallBaker.FLOORS, while
## hybrid_walls is on: modelled planks, shakes or stones up close, a slab baked from them from afar
## (see BuildPiece.dress, WallBaker)
static func is_hybrid(shape: String) -> bool:
	if WallBaker.is_floor(shape) and not hybrid_floors:
		return false
	return hybrid_walls and (shape in SnapEdges.WALLS or shape in SnapEdges.TRIANGLES or WallBaker.is_faceted(shape))


## A hybrid roof's, floor's or foundation's close-up look in its two layers (see PieceDetail.layer),
## for the variant this piece id picks: {"surface": a roof's deck and shakes, a floor's planks or
## flagstones (baked for its far look), "trim": a roof's fascia, barge boards, rafters and logs, a
## floor's base, a foundation's core, logs and stone courses (real geometry in its far look),
## "facets": the faces baked (a roof's shaked facets, a floor's top)}
func roof_parts(shape: String, piece_id: int) -> Dictionary:
	var variant := posmod(piece_id, DETAIL_VARIANTS)
	var key := "%s#%d#roof" % [shape, variant]
	if not _details.has(key):
		var seed_value := hash(shape) + variant * 7919
		var surface := PieceDetail.build(shape, seed_value, false, "surface")
		var trim := PieceDetail.build(shape, seed_value, false, "trim")
		_details[key] = {"surface": surface.get("mesh"), "trim": trim.get("mesh"), "facets": surface.get("facets", [])}
	return _details[key]


## A piece's close-up look (see PieceDetail): one of DETAIL_VARIANTS made once per shape, picked
## by the piece's id, so neighbours differ and a piece always looks the same. Pieces with the same
## variant share its mesh, so Godot draws them together; each piece's own slight colour comes
## from the shader (see BuildPiece.weather).
func detail_mesh(shape: String, piece_id: int) -> Dictionary:
	var variant := posmod(piece_id, DETAIL_VARIANTS)
	var key := "%s#%d" % [shape, variant]
	if not _details.has(key):
		var timing := SpikeLog.begin()
		_details[key] = PieceDetail.build(shape, hash(shape) + variant * 7919)
		SpikeLog.end("detail look made (first use)", timing)
	return _details[key]


## The same variant's simplified look, for the middle distance (see PieceDetail.build: simple).
## "shadow_from_mid" is set when it has fewer triangles than the shape's plain box (a foundation's
## box reaches far underground), so its shadow is cast with it instead (see BuildPiece.dress).
## A hybrid wall, roof or floor (see is_hybrid) has none: instead {"hybrid": true, "far": its variant's
## baked far look, "baker": the WallBaker, which says when a far look still baking is ready}, and for
## a roof or floor "far_mesh" (its slab and trim in one mesh, in the plain box's place:
## WallBaker.far_mesh).
func mid_mesh(shape: String, piece_id: int) -> Dictionary:
	if is_hybrid(shape):
		var variant := posmod(piece_id, DETAIL_VARIANTS)
		var hybrid := {"hybrid": true, "far": baker.far_material(shape, variant), "baker": baker}
		if WallBaker.is_faceted(shape):
			hybrid["far_mesh"] = baker.far_mesh(shape, variant)
		return hybrid
	if lean_structure and shape in SINGLE:
		return {"single": true}
	if lean_structure and shape in LEAN:
		return {"hybrid": true, "lean": true, "far": detail_material(), "far_mesh": lean_mesh(shape, piece_id)}
	var variant := posmod(piece_id, DETAIL_VARIANTS)
	var key := "%s#%d#mid" % [shape, variant]
	if not _details.has(key):
		var timing := SpikeLog.begin()
		var mid := PieceDetail.build(shape, hash(shape) + variant * 7919, true)
		SpikeLog.end("simplified look made (first use)", timing)
		if mid.get("mesh") != null:
			mid["shadow_from_mid"] = _triangles(mid["mesh"]) < _triangles(shape_of(shape)["mesh"])
		_details[key] = mid
	return _details[key]


## The same variant's lean far look (see LEAN, PieceDetail.far), made once and shared
func lean_mesh(shape: String, piece_id: int) -> Mesh:
	var variant := posmod(piece_id, DETAIL_VARIANTS)
	var key := "%s#%d#far" % [shape, variant]
	if not _details.has(key):
		var timing := SpikeLog.begin()
		_details[key] = PieceDetail.build(shape, hash(shape) + variant * 7919, false, "", true)
		SpikeLog.end("lean far look made (first use)", timing)
	return _details[key].get("mesh")


# How many triangles a mesh has
static func _triangles(mesh: Mesh) -> int:
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return 0
	var count := 0
	for s in array_mesh.get_surface_count():
		var indices := array_mesh.surface_get_array_index_len(s)
		count += (indices if indices > 0 else array_mesh.surface_get_array_len(s)) / 3
	return count


## The material the close-up looks (and corner posts and ridge logs) are drawn with
func detail_material() -> ShaderMaterial:
	if _detail_material == null:
		_detail_material = ShaderMaterial.new()
		_detail_material.shader = DETAIL_SHADER
		_detail_material.set_shader_parameter("wood_albedo", load(WOOD_FOLDER + "_diff_2k.jpg"))
		_detail_material.set_shader_parameter("wood_normal", load(WOOD_FOLDER + "_nor_gl_2k.png"))
		_detail_material.set_shader_parameter("wood_rough", load(WOOD_FOLDER + "_rough_2k.png"))
		_detail_material.set_shader_parameter("stone_albedo", load(STONE_FOLDER + "_diff_2k.jpg"))
		_detail_material.set_shader_parameter("stone_normal", load(STONE_FOLDER + "_nor_gl_2k.png"))
		_detail_material.set_shader_parameter("stone_rough", load(STONE_FOLDER + "_rough_2k.png"))
	return _detail_material


## The plain painted material (each face its own colour): furniture, and anything else drawn
## without textures
func wood_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.9
		_material.metallic_specular = 0.2
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# The pieces' colours are ordinary screen colours (the same ones their icons are drawn
		# with); without this they'd be taken as linear and come out pale and greyish
		_material.vertex_color_is_srgb = true
	return _material


## Puts a piece in the world. A new piece gets the next id; a loaded one keeps its own.
## The id the next piece put down will get (so the placement preview can wear its look and colour)
func next_id() -> int:
	return _next_id


func spawn(piece: PieceBuildable, where: Transform3D, paid: Dictionary, id := 0, owner_plot := "", state := {}) -> BuildPiece:
	var timing := SpikeLog.begin()
	var built: BuildPiece = _spawn(piece, where, paid, id, owner_plot, state)
	SpikeLog.end("pieces put in the world", timing)
	return built


func _spawn(piece: PieceBuildable, where: Transform3D, paid: Dictionary, id: int, owner_plot: String, state: Dictionary) -> BuildPiece:
	var built: BuildPiece = piece.scene.instantiate()
	var shape := piece.shape
	built.setup(piece, shape_of(shape), material_for(shape))
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)
	built.piece_id = id
	built.dress(detail_mesh(shape, id), detail_material(), mid_mesh(shape, id))
	built.weather()
	built.owner_plot = owner_plot
	built.paid = paid.duplicate()
	world.add_child(built)
	built.global_transform = where
	built.load_state(state)
	_pieces[id] = built
	_clear_grass_under(built)
	changed.emit()
	return built


## Builds a ghost piece for real: it was paid for with `paid` (all of which comes back if it's
## demolished)
func fill(piece: BuildPiece, paid: Dictionary) -> void:
	piece.paid = paid.duplicate()
	piece.set_ghost(false)
	changed.emit()


## Two pieces of the same shape this close (meters) and this nearly the same way round (allowing
## for the shape's symmetry) are the same piece placed twice
const DUPLICATE_DISTANCE := 0.05
const DUPLICATE_TURN := deg_to_rad(5.0)


## The fixed flights of stairs, by shape (see PieceShapes.FLIGHTS and load_data)
const STAIRS_PATH := "res://buildables/structure/stairs.tres"
const FLIGHT_PATHS := {
	"stairs": STAIRS_PATH,
	"half_stairs": "res://buildables/structure/half_stairs.tres",
	"stairs_tall": "res://buildables/structure/stairs_tall.tres",
	"half_stairs_tall": "res://buildables/structure/half_stairs_tall.tres",
}


## An identical piece already at `where` (the same shape, within DUPLICATE_DISTANCE and
## DUPLICATE_TURN, its symmetry allowed for), ghosts included; null if there's none. `ignore`
## never counts.
func duplicate_of(shape_name: String, where: Transform3D, ignore: BuildPiece = null) -> BuildPiece:
	var symmetry: float = shape_of(shape_name).get("symmetry", 0.0)
	var step := symmetry if symmetry > 0.0 else TAU
	var yaw := atan2(where.basis.z.x, where.basis.z.z)
	for piece in pieces_near(where.origin, DUPLICATE_DISTANCE):
		if piece == ignore or piece.is_queued_for_deletion() or piece.shape_name != shape_name:
			continue
		var other_yaw := atan2(piece.global_basis.z.x, piece.global_basis.z.z)
		var apart := wrapf(yaw - other_yaw + step / 2.0, 0.0, step) - step / 2.0
		if absf(apart) <= DUPLICATE_TURN:
			return piece
	return null


## Every ghost piece (a placed template's pieces still to be built)
func ghost_pieces() -> Array:
	return all_pieces().filter(func(p): return p.is_ghost())


## Takes a piece out of the world (and lets the grass grow back under a floor)
func remove(piece: BuildPiece) -> void:
	SpikeLog.note("a piece taken away")
	_pieces.erase(piece.piece_id)
	var valley = get_tree().get_first_node_in_group("valley")
	var zone := piece.get_node_or_null("ClearZone")
	if zone and valley:
		valley.remove_clear_zone(zone)
	piece.queue_free()
	changed.emit()


func find(id: int) -> BuildPiece:
	var piece = _pieces.get(id)
	return piece if is_instance_valid(piece) else null


func all_pieces() -> Array:
	return _pieces.values().filter(func(p): return is_instance_valid(p))


## The pieces a plot owns
func pieces_owned_by(plot: String) -> Array:
	return all_pieces().filter(func(p): return p.owner_plot == plot)


## Pieces whose origin is within `reach` meters of a spot (one pass, no copy of the whole list: the
## placer asks every frame)
func pieces_near(spot: Vector3, reach: float) -> Array:
	var found := []
	var reach_squared := reach * reach
	for piece in _pieces.values():
		if is_instance_valid(piece) and not piece.is_queued_for_deletion() and (piece as Node3D).global_position.distance_squared_to(spot) <= reach_squared:
			found.append(piece)
	return found


## Pieces whose origin is within `reach` meters of the line from `from` to `to` (one pass)
func pieces_along(from: Vector3, to: Vector3, reach: float) -> Array:
	var found := []
	var lo := from.min(to) - Vector3.ONE * reach
	var hi := from.max(to) + Vector3.ONE * reach
	var line := to - from
	var length_squared := maxf(line.length_squared(), 1e-9)
	var reach_squared := reach * reach
	for piece in _pieces.values():
		if not is_instance_valid(piece) or piece.is_queued_for_deletion():
			continue
		var p: Vector3 = (piece as Node3D).global_position
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			continue
		var t := clampf((p - from).dot(line) / length_squared, 0.0, 1.0)
		if p.distance_squared_to(from + line * t) <= reach_squared:
			found.append(piece)
	return found


# Floors keep the grass and ferns out from under them; they count as under a building, so
# gathered things don't respawn there
func _clear_grass_under(piece: BuildPiece) -> void:
	var area := piece.clear_area()
	if area["radius"] <= 0.0:
		return
	var zone: Node3D = CLEAR_ZONE_SCENE.instantiate()
	zone.name = "ClearZone"
	zone.clear_trees = false
	zone.clear_resources = false
	zone.clear_rocks = false
	zone.clear_plants = true
	zone.radius = area["radius"]
	zone.set_meta(&"under_building", true)
	piece.add_child(zone)
	zone.position = area["center"]
	var valley = get_tree().get_first_node_in_group("valley")
	if valley:
		valley.add_clear_zone(zone)


func save_key() -> String:
	return "pieces"


func save_priority() -> int:
	return 31


## Every piece: id, which piece, where and which way, what it cost, its plot and its state
func save_data() -> Dictionary:
	var list: Array = []
	for piece in all_pieces():
		var entry := {
			"id": piece.piece_id,
			"buildable": piece.buildable.resource_path,
			"position": SaveGame.from_vector(piece.global_position),
			"turn": piece.global_rotation.y,
			"paid": piece.paid,
		}
		# Tilted or tipped: its whole rotation too
		if SaveGame.is_leaning(piece.global_basis):
			entry["rotation"] = SaveGame.from_rotation(piece.global_basis)
		if not piece.owner_plot.is_empty():
			entry["plot"] = piece.owner_plot
		var state: Dictionary = piece.save_state()
		if not state.is_empty():
			entry["state"] = state
		list.append(entry)
	# (made on the building grid standard: see GridUpgrade)
	return {"next_id": _next_id, "list": list, "grid": GridUpgrade.GRID_VERSION}


func load_data(data: Dictionary) -> void:
	for piece in all_pieces():
		remove(piece)
	_pieces.clear()
	_next_id = int(data.get("next_id", 1))
	var dropped := {}
	# Every piece as saved, then (in a save from before the building grid standard) brought up to it
	var pieces := []
	for entry in data.get("list", []):
		pieces.append({"buildable": str(entry.get("buildable", "")), "where": Transform3D(SaveGame.to_rotation(entry), SaveGame.to_vector(entry.get("position"))), "entry": entry})
	if int(data.get("grid", 1)) < GridUpgrade.GRID_VERSION:
		GridUpgrade.upgrade(pieces, int(data.get("grid", 1)))
	for p in pieces:
		var entry: Dictionary = p["entry"]
		var path: String = p["buildable"]
		var where: Transform3D = p["where"]
		var state: Dictionary = entry.get("state", {})
		# A flight of stairs saved while stairs were fitted to their drop (its height saved with it,
		# at 35°) comes back as the fixed flight nearest that height, its top step where it was (it was
		# saved as Stairs, which a save that old brings back as Tall Stairs first: see GridUpgrade)
		if path in FLIGHT_PATHS.values() and state.has("stairs_height"):
			var old_height := float(state["stairs_height"])
			var top_edge := where * Vector3(0, old_height, old_height / tan(deg_to_rad(35.0)) / 2.0)
			var nearest := "stairs"
			for flight in PieceShapes.FLIGHTS:
				if absf(float(PieceShapes.FLIGHTS[flight][0]) - old_height) < absf(float(PieceShapes.FLIGHTS[nearest][0]) - old_height):
					nearest = flight
			var size: Array = PieceShapes.FLIGHTS[nearest]
			path = FLIGHT_PATHS[nearest]
			state = state.duplicate()
			state.erase("stairs_height")
			where.origin = top_edge - where.basis * Vector3(0, float(size[0]), float(size[1]) / 2.0)
		# A piece that's since been taken out of the game (its buildable file is gone) is dropped
		# quietly, without refunding it
		if not ResourceLoader.exists(path):
			dropped[path] = int(dropped.get(path, 0)) + 1
			continue
		var piece := load(path) as PieceBuildable
		if piece == null:
			continue
		var paid := {}
		var saved_paid: Dictionary = entry.get("paid", {})
		for item in saved_paid:
			paid[item] = int(saved_paid[item])
		spawn(piece, where, paid, int(entry.get("id", 0)), str(entry.get("plot", "")), state)
	for path in dropped:
		print("[Pieces] %d piece(s) of %s left out: that piece is no longer in the game" % [dropped[path], path])
