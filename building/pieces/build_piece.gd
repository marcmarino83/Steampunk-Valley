class_name BuildPiece
extends StaticBody3D
## One placed building piece. It builds its look, collision and snap points from its shape
## (PieceShapes) when the piece registry makes it. Doors open and close with E.
##
## For plots (coming later): every piece has an id that stays the same across saves, and the
## plot that owns it (empty for none). The registry lists them all.

## How far a door swings open, in degrees
const DOOR_OPEN_DEGREES := 95.0
const DOOR_SWING_SECONDS := 0.35

## Its id, unique in this world, and the plot that owns it (empty: no plot)
var piece_id := 0
var owner_plot := ""
## What it is, and what was paid for it (all of which comes back when it's taken down)
var buildable: PieceBuildable
var paid := {}

var _def: Dictionary
var _door_open := false
var _door_angle := 0.0
# The door's swinging parts and how each one sits when closed
var _door_parts: Array = []
var _door_tween: Tween


## Builds it from its shape. Called before it's added to the world.
func setup(piece: PieceBuildable, def: Dictionary, material: Material) -> void:
	buildable = piece
	_def = def
	name = "Piece"
	add_to_group("build_pieces")
	if piece.model_scene:
		add_child(piece.model_scene.instantiate())
	else:
		var look := MeshInstance3D.new()
		look.mesh = def["mesh"]
		look.material_override = material
		add_child(look)
	if def["door_mesh"]:
		var panel := MeshInstance3D.new()
		panel.mesh = def["door_mesh"]
		panel.material_override = material
		add_child(panel)
		_door_parts.append({"node": panel, "rest": Transform3D.IDENTITY})
	for part in def["collision"]:
		var solid := CollisionShape3D.new()
		solid.shape = part["shape"]
		solid.transform = part["transform"]
		add_child(solid)
		if part["door"]:
			_door_parts.append({"node": solid, "rest": part["transform"]})


func display_name() -> String:
	return buildable.display_name if buildable else "Piece"


## Its snap points in the world: [{"position", "yaw", "type"}]
func world_sockets() -> Array:
	var found := []
	for socket in _def["sockets"]:
		found.append({
			"position": global_transform * (socket["position"] as Vector3),
			"yaw": global_rotation.y + socket["yaw"],
			"type": socket["type"],
		})
	return found


## A roof (or cone roof) section: standing under it counts as shelter
func is_roof() -> bool:
	return _def.get("roof", false)


## A floor or round floor wedge
func is_floor() -> bool:
	return _def.get("floor", false)


## Lays a glow over the piece (the hammer's demolish target shows red), or takes it off (null)
func set_highlight(glow: Material) -> void:
	for look in find_children("*", "GeometryInstance3D", true, false):
		(look as GeometryInstance3D).material_overlay = glow


## Slender: a pillar, pole, beam or ladder (these only bump into each other)
func is_slender() -> bool:
	return _def.get("slender", false)


## A ladder: W climbs it while you look at it
func is_ladder() -> bool:
	return _def.get("ladder", false)


func is_door() -> bool:
	return not _door_parts.is_empty()


## True unless it's a door standing open
func is_closed() -> bool:
	return not (is_door() and _door_open)


## The circle of grass it keeps clear (radius 0 for none), from its origin
func clear_area() -> Dictionary:
	return {"center": _def.get("clear_center", Vector3.ZERO), "radius": _def.get("clear_radius", 0.0)}


# ---- Doors ----

func can_interact() -> bool:
	return is_door()


func get_prompt() -> String:
	return "Close Door" if _door_open else "Open Door"


func interact(_player) -> void:
	if is_door():
		set_open(not _door_open)


## Swings the door open or shut (at once, when `instantly`, for loading a save)
func set_open(open: bool, instantly := false) -> void:
	_door_open = open
	var target := DOOR_OPEN_DEGREES if open else 0.0
	if _door_tween:
		_door_tween.kill()
	if instantly:
		_set_door_angle(target)
		return
	_door_tween = create_tween()
	_door_tween.tween_method(_set_door_angle, _door_angle, target, DOOR_SWING_SECONDS).set_trans(Tween.TRANS_SINE)


# Turns the door's parts about its hinge, down its left edge
func _set_door_angle(degrees: float) -> void:
	_door_angle = degrees
	var hinge := Vector3(-(PieceShapes.DOOR_WIDTH - 0.04) / 2.0, 0, 0)
	var swing := Transform3D(Basis.IDENTITY, hinge) * Transform3D(Basis(Vector3.UP, deg_to_rad(-degrees)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -hinge)
	for part in _door_parts:
		part["node"].transform = swing * (part["rest"] as Transform3D)


## What the save keeps of it beyond where it is (a door's open or shut)
func save_state() -> Dictionary:
	return {"open": true} if _door_open else {}


func load_state(state: Dictionary) -> void:
	if state.get("open", false):
		set_open(true, true)
