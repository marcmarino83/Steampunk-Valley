class_name PieceRegistry
extends Node
## Every building piece in the world, by id: makes them, takes them away, and saves them.
## Pieces get ids that stay the same across saves, and an owner plot (empty for none), so the plot
## system can find, count and move the pieces it owns.

## A piece was added or taken away (plots check their requirements again)
signal changed

const CLEAR_ZONE_SCENE := preload("res://building/clear_zone.tscn")

## Where pieces are added (the world). Set by the build placer.
var world: Node

# id -> BuildPiece
var _pieces := {}
var _next_id := 1
# Each shape's look, collision and snap points, made once: shape -> PieceShapes.build()
var _shapes := {}
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("saveable")
	add_to_group("piece_registry")


func _exit_tree() -> void:
	# Let go of the meshes and shapes, so nothing is reported as leaked when the game closes
	_shapes.clear()
	_material = null


## A shape's look, collision and snap points (see PieceShapes.build)
func shape_of(shape: String) -> Dictionary:
	if not _shapes.has(shape):
		_shapes[shape] = PieceShapes.build(shape)
	return _shapes[shape]


## The plain wood material every piece without a model of its own is drawn with
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
	built.setup(piece, shape_of(piece.shape), wood_material())
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)
	built.piece_id = id
	built.owner_plot = owner_plot
	built.paid = paid.duplicate()
	world.add_child(built)
	built.global_transform = where
	built.load_state(state)
	_pieces[id] = built
	_clear_grass_under(built)
	changed.emit()
	return built


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
