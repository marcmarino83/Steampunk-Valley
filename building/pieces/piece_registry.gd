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
const DETAIL_VARIANTS := 8

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


func _ready() -> void:
	add_to_group("saveable")
	add_to_group("piece_registry")
	# Corner posts over wall joints and logs along ridges, worked out again whenever pieces change
	_joints = JointDetails.new()
	_joints.registry = self
	add_child(_joints)
	changed.connect(_joints.mark_dirty)


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
		_shapes[shape] = PieceShapes.build(shape)
	return _shapes[shape]


## The material a piece of this shape is drawn with (see piece_surface.gdshader): textured wood
## planks mapped to suit the piece (walls, floors, roofs with thatch on top, curved and round
## pieces, beams, posts), stone for stone pieces, or the plain painted colours for furniture
func material_for(shape: String) -> Material:
	var def := shape_of(shape)
	var kind := "wood"
	if def.get("furniture", false):
		return wood_material()
	if shape.contains("stone"):
		kind = "stone_round" if shape.begins_with("round") else "stone"
	elif shape == "cone_roof":
		kind = "cone"
	elif def.get("roof", false) or def.get("overhang", false):
		kind = "roof"
	elif shape.begins_with("curved_wall") or shape.begins_with("round"):
		kind = "round"
	elif shape == "beam_1" or shape == "beam_2":
		kind = "beam"
	elif shape.begins_with("pole") or shape.begins_with("pillar") or shape == "ladder":
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


## A piece's close-up look (see PieceDetail): one of DETAIL_VARIANTS made once per shape, picked
## by the piece's id, so neighbours differ and a piece always looks the same
func detail_mesh(shape: String, piece_id: int) -> Dictionary:
	var variant := posmod(piece_id, DETAIL_VARIANTS)
	var key := "%s#%d" % [shape, variant]
	if not _details.has(key):
		_details[key] = PieceDetail.build(shape, hash(shape) + variant * 7919)
	return _details[key]


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
func spawn(piece: PieceBuildable, where: Transform3D, paid: Dictionary, id := 0, owner_plot := "", state := {}) -> BuildPiece:
	var built: BuildPiece = piece.scene.instantiate()
	built.setup(piece, shape_of(piece.shape), material_for(piece.shape))
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)
	built.piece_id = id
	built.dress(detail_mesh(piece.shape, id), detail_material())
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


## An identical piece already at `where` (the same shape, within DUPLICATE_DISTANCE and
## DUPLICATE_TURN, its symmetry allowed for), ghosts included; null if there's none. `ignore`
## never counts.
func duplicate_of(shape_name: String, where: Transform3D, ignore: BuildPiece = null) -> BuildPiece:
	var symmetry: float = shape_of(shape_name).get("symmetry", 0.0)
	var step := symmetry if symmetry > 0.0 else TAU
	var yaw := atan2(where.basis.z.x, where.basis.z.z)
	for piece in pieces_near(where.origin, DUPLICATE_DISTANCE):
		if piece == ignore or piece.is_queued_for_deletion() or piece.buildable.shape != shape_name:
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


## Pieces whose origin is within `reach` meters of a spot
func pieces_near(spot: Vector3, reach: float) -> Array:
	var found := []
	for piece in all_pieces():
		if piece.global_position.distance_to(spot) <= reach:
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
		if not piece.owner_plot.is_empty():
			entry["plot"] = piece.owner_plot
		var state: Dictionary = piece.save_state()
		if not state.is_empty():
			entry["state"] = state
		list.append(entry)
	return {"next_id": _next_id, "list": list}


func load_data(data: Dictionary) -> void:
	for piece in all_pieces():
		remove(piece)
	_pieces.clear()
	_next_id = int(data.get("next_id", 1))
	for entry in data.get("list", []):
		var piece := load(str(entry.get("buildable", ""))) as PieceBuildable
		if piece == null:
			continue
		var where := Transform3D(Basis(Vector3.UP, float(entry.get("turn", 0.0))), SaveGame.to_vector(entry.get("position")))
		var paid := {}
		var saved_paid: Dictionary = entry.get("paid", {})
		for item in saved_paid:
			paid[item] = int(saved_paid[item])
		spawn(piece, where, paid, int(entry.get("id", 0)), str(entry.get("plot", "")), entry.get("state", {}))
