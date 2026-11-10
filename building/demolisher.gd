class_name Demolisher
extends Node
## Taking building pieces down with the hammer, for a full refund. Two ways, with the hammer out,
## placing or not:
##   - Middle mouse button: pressing it picks the piece under the crosshair, which glows red while
##     the button is held; letting go takes it down. Looking off that piece first cancels.
##   - Holding X (for mice without a middle button): the piece under the crosshair glows red and
##     comes down after DEMOLISH_HOLD; looking away or letting go early starts over.
## Placing carries on afterwards as it was. (Moved as it was from the old piece placer.)

## How long X is held to take a piece down, and how far the crosshair reaches
const DEMOLISH_HOLD := 0.5
const DEMOLISH_REACH := 6.0
const DEMOLISH_GLOW := Color(1.0, 0.15, 0.1, 0.45)

var registry: PieceRegistry

var _player: CharacterBody3D
# The piece that would come down (glowing red), how long X has been held on it, and the glow
var _looked_at: BuildPiece
var _hold_time := 0.0
var _glow: StandardMaterial3D
# The middle button: held down, the piece it picked on the press, and whether looking off that
# piece cancelled it
var _mmb_down := false
var _mmb_piece: BuildPiece
var _mmb_cancelled := false


func _ready() -> void:
	_player = get_parent().get_parent()


## The piece glowing red right now (null for none), so the placer doesn't tint it blue meanwhile
func glowing() -> BuildPiece:
	return _looked_at if is_instance_valid(_looked_at) else null


## Middle button pressed: picks the piece under the crosshair (it glows red until released)
func press() -> void:
	_mmb_down = true
	_mmb_piece = _piece_in_view()
	_mmb_cancelled = false


## Middle button released: takes down the piece picked on the press, if the crosshair is still on
## it; `active` is false if the hammer was put away or a menu opened meanwhile
func release(active: bool) -> void:
	if not _mmb_down:
		return
	_mmb_down = false
	var piece: BuildPiece = _mmb_piece if is_instance_valid(_mmb_piece) else null
	_mmb_piece = null
	if not active or _mmb_cancelled:
		return
	if piece == null:
		_player.flash("Aim at a building piece to demolish it")
	elif _piece_in_view() == piece:
		_demolish(piece)


## Called every frame: `active` while the hammer is out (and no menu is open), `holding_x` while
## X is held. Keeps the red glow on the piece that would come down (the middle button's pick while
## it's held, or what X is aimed at), and counts X's hold.
func update(delta: float, active: bool, holding_x: bool) -> void:
	if not active:
		_mmb_down = false
		_mmb_piece = null
	if _mmb_down and is_instance_valid(_mmb_piece) and _piece_in_view() != _mmb_piece:
		# Looked off the piece before letting go: cancelled
		_mmb_piece = null
		_mmb_cancelled = true
	var piece: BuildPiece = null
	if _mmb_down:
		piece = _mmb_piece if is_instance_valid(_mmb_piece) else null
	elif active and holding_x:
		piece = _piece_in_view()
	if piece != _looked_at:
		if is_instance_valid(_looked_at):
			_looked_at.set_highlight(null)
		_looked_at = piece
		_hold_time = 0.0
		if piece:
			piece.set_highlight(_glow_material())
	if piece and holding_x and not _mmb_down:
		_hold_time += delta
		if _hold_time >= DEMOLISH_HOLD:
			_demolish(piece)
	else:
		_hold_time = 0.0


# Takes the piece down, giving back everything it cost (what won't fit in a full backpack is left
# on the ground in a bundle), with a short message
func _demolish(piece: BuildPiece) -> void:
	if piece == _looked_at:
		_looked_at = null
	_hold_time = 0.0
	# The bundle (if any) goes on whatever is under the piece, not on the piece itself
	var spot := piece.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.5, spot + Vector3.DOWN * 30.0)
	query.exclude = [piece.get_rid(), _player.get_rid()]
	var below := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if not below.is_empty():
		spot = below["position"]
	var left: Dictionary = _player.give_or_drop(piece.paid, spot)
	var notes: PackedStringArray = []
	if not piece.paid.is_empty():
		notes.append("+" + _items_text(piece.paid))
	if not left.is_empty():
		notes.append("backpack full: %s left on the ground" % _items_text(left))
	var message := "Demolished %s" % piece.display_name()
	if not notes.is_empty():
		message += " (%s)" % "; ".join(notes)
	_player.flash(message)
	registry.remove(piece)


## The piece panel while X is held on a piece (see HudControls): its name, refund in red, and how
## far along the hold is. Empty otherwise.
func info() -> Dictionary:
	if _hold_time > 0.0 and is_instance_valid(_looked_at):
		return {
			"icon": _looked_at.buildable.icon if _looked_at.buildable else null,
			"title": _looked_at.display_name(),
			"cost": "Refund: %s" % (_items_text(_looked_at.paid) if not _looked_at.paid.is_empty() else "nothing"),
			"cost_bad": true,
			"detail": "Demolishing... %d%%" % int(_hold_time / DEMOLISH_HOLD * 100.0),
		}
	return {}


func _piece_in_view() -> BuildPiece:
	var camera: Camera3D = _player.camera
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * DEMOLISH_REACH)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] is BuildPiece:
		return hit["collider"]
	return null


func _glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glow.albedo_color = DEMOLISH_GLOW
	return _glow


# "4 Planks, 1 Rope"
static func _items_text(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item in items:
		parts.append("%d %s" % [items[item], item])
	return ", ".join(parts)
