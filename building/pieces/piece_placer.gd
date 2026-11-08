class_name PiecePlacer
extends Node
## Placing building pieces, Valheim-style: the see-through preview snaps to the nearest fitting
## snap point of a placed piece (shown as small dots), or otherwise goes freely wherever the
## crosshair is, on the ground or on other pieces, and may float (there's no support yet). Green
## where it can go, red where it bumps into another piece, a tree or a rock (the ground is fine,
## so pieces can sit partly in a slope). It keeps placing the same piece until cancelled. Also
## demolishes, for a full refund: in demolish mode (middle-click, run by the BuildPlacer) or while
## X is held, the piece under the crosshair glows red, and left-click (or holding X long enough)
## takes that one piece down.
##
## Snapped, R turns the piece about its snap point in 90° steps (45° for round and triangle
## pieces), and Alt + mouse wheel in 15° steps; the turn stays as it moves between snap points.
## Free, R turns it 15°, Alt + mouse wheel turns it smoothly, and Page Up / Page Down (or Ctrl +
## wheel) raise and lower it, in fine steps with Alt held. The height and the snapped turn stay
## for the next piece of the same kind; Backspace resets the height. Shift places freely,
## without snapping, at that height.

## How far ahead of the camera the crosshair reaches for a spot
const REACH := 8.0
const DROP_DISTANCE := 300.0
## How close (to the line from the camera to the crosshair's spot) a snap point must be to snap to
const SNAP_RADIUS := 1.2
## Snap points of pieces this close to the crosshair's spot are considered (and shown)
const SNAP_SEARCH := 9.0
const MARKER_REACH := 6.0
const MAX_MARKERS := 48
## How many of the nearest snap points are tried, looking for one the piece fits at
const SNAP_TRIES := 6
const FREE_STEP := PI / 12.0
const WHEEL_STEP := PI / 60.0
## Alt + wheel while snapped
const SNAPPED_WHEEL_STEP := PI / 12.0
## Raising and lowering a freely placed piece, in meters: normal steps, and with Alt held
const HEIGHT_STEP := 0.25
const FINE_HEIGHT_STEP := 0.05
## Pieces may touch, and walls overlap a little at corners: what's solid about the new piece is
## shrunk this much on every side for the check (a bit more than half a wall's thickness)
const TOUCH_MARGIN := 0.11
## Demolishing: how long X is held to take a piece down, and how far the crosshair reaches
const DEMOLISH_HOLD := 0.5
const DEMOLISH_REACH := 6.0
const DEMOLISH_GLOW := Color(1.0, 0.15, 0.1, 0.45)
const GOOD_COLOR := Color(0.25, 1.0, 0.35, 0.45)
const BAD_COLOR := Color(1.0, 0.2, 0.15, 0.45)
const MARKER_COLOR := Color(0.55, 0.85, 1.0, 0.8)
const ACTIVE_MARKER_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const BLOCKED := "Something's in the way"
const MAX_OVERLAPS := 16

var registry: PieceRegistry

var _player: CharacterBody3D
var _buildable: PieceBuildable
var _shape: Dictionary
var _preview: Node3D
var _ghost: StandardMaterial3D
# What's solid about the piece, shrunk a little: [{"shape", "transform"}]
var _test_parts: Array = []
# The box around the whole piece, in its own space
var _bounds := AABB()
var _free_turn := 0.0
# How far a freely placed piece is raised (or lowered) from where the crosshair is, and how far
# it's turned about its snap point when snapped, and which piece those are for: they're kept from
# one placement to the next of the same piece
var _height := 0.0
var _snap_turn := 0.0
var _kept_for := ""
var _where := Transform3D.IDENTITY
# The piece it's snapped to (null when placed freely), and which of its snap points
var _target: BuildPiece
var _snap_key := ""
var _problem := ""
var _markers: Array[MeshInstance3D] = []
var _marker_root: Node3D
var _marker_material: StandardMaterial3D
var _active_material: StandardMaterial3D
# Demolishing: the piece under the crosshair (glowing red), how long X has been held on it, and
# the glow
var _looked_at: BuildPiece
var _hold_time := 0.0
var _glow: StandardMaterial3D


func _ready() -> void:
	_player = get_parent().get_parent()
	set_physics_process(false)


func is_placing() -> bool:
	return _buildable != null


## The piece being placed (null if none)
func current() -> PieceBuildable:
	return _buildable


func begin(piece: PieceBuildable) -> void:
	cancel()
	_buildable = piece
	_shape = registry.shape_of(piece.shape)
	_snap_key = ""
	_problem = "Point at the ground or a piece"
	if piece.resource_path != _kept_for:
		_height = 0.0
		_snap_turn = 0.0
		_kept_for = piece.resource_path
	_ghost = StandardMaterial3D.new()
	_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview = Node3D.new()
	for mesh in [_shape["mesh"], _shape["door_mesh"]]:
		if mesh:
			var ghost := MeshInstance3D.new()
			ghost.mesh = mesh
			ghost.material_override = _ghost
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_preview.add_child(ghost)
	_preview.visible = false
	_player.get_parent().add_child(_preview)
	_make_test_parts()
	_make_markers()
	set_physics_process(true)


func cancel() -> void:
	if _preview:
		_preview.queue_free()
	if _marker_root:
		_marker_root.queue_free()
	_preview = null
	_marker_root = null
	_markers.clear()
	_buildable = null
	_target = null
	set_physics_process(false)


## Takes the keys and clicks that mean something while placing. Returns true if it used this one.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	# Raising and lowering repeats while the key is held
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN:
			_raise(1.0 if event.keycode == KEY_PAGEUP else -1.0, event.alt_pressed)
			return true
		if event.keycode == KEY_BACKSPACE:
			_height = 0.0
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if _target:
				_snap_turn = wrapf(_snap_turn + _shape.get("turn_step", PI / 2.0), 0.0, TAU)
			else:
				_free_turn = wrapf(_free_turn + FREE_STEP, 0.0, TAU)
			return true
		# Finish or cancel this before opening the menu or putting the hammer away
		if event.keycode == KEY_TAB or (event.keycode >= KEY_1 and event.keycode <= KEY_9):
			return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var up := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if event.ctrl_pressed:
				_raise(up, event.alt_pressed)
			elif event.alt_pressed and _target:
				_snap_turn = wrapf(_snap_turn + SNAPPED_WHEEL_STEP * up, 0.0, TAU)
			elif event.alt_pressed:
				_free_turn = wrapf(_free_turn + WHEEL_STEP * up, 0.0, TAU)
			return true
	# A click while the mouse is free just grabs it again, as it does any other time
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return true
	return false


## What the on-screen controls show while placing (see HudControls): the controls that apply
## right now, and the piece's panel (icon, name, cost in red if you can't afford it, and one line
## of details: snapped and turned, or the height; and why it can't go there, if it can't)
func hud_state() -> Dictionary:
	var details: PackedStringArray = []
	var controls := [["Place", "LMB"]]
	if _target:
		details.append("Snapped")
		var turn := roundi(rad_to_deg(_snap_turn)) % 360
		if turn != 0:
			details.append("turned %d°" % turn)
		controls.append(["Rotate %d°" % roundi(rad_to_deg(_shape.get("turn_step", PI / 2.0))), "R"])
		controls.append(["Rotate 15°", "Alt+Wheel"])
	else:
		details.append("Height %+.2f m" % _height)
		controls.append(["Rotate", "R"])
		controls.append(["Raise/Lower", "PgUp/PgDn"])
		if not is_zero_approx(_height):
			controls.append(["Reset height", "Backspace"])
	controls.append(["No snap", "Shift"])
	controls.append(["Demolish mode", "MMB"])
	controls.append(["Cancel", "RMB"])
	if not _problem.is_empty():
		details.append(_problem)
	var info := {
		"icon": _buildable.icon,
		"title": _buildable.display_name,
		"cost": _buildable.cost_text(),
		"cost_bad": not _buildable.can_afford(_player.inventory),
		"detail": "  ·  ".join(details),
		"detail_bad": not _problem.is_empty(),
	}
	return {"controls": controls, "info": info}


# Raises (+1) or lowers (-1) a freely placed piece by one step, or a fine step
func _raise(direction: float, fine: bool) -> void:
	var step := FINE_HEIGHT_STEP if fine else HEIGHT_STEP
	_height = snappedf(_height + step * direction, FINE_HEIGHT_STEP)


func _physics_process(_delta: float) -> void:
	var camera: Camera3D = _player.camera
	var from := camera.global_position
	var far_point := from - camera.global_basis.z * REACH
	var hit := _cast_ray(from, far_point)
	var end: Vector3 = hit["position"] if not hit.is_empty() else far_point
	var ground := hit
	if ground.is_empty():
		ground = _cast_ray(far_point, far_point + Vector3.DOWN * DROP_DISTANCE)

	var snapped := false
	if not Input.is_key_pressed(KEY_SHIFT):
		snapped = _snap(from, end)
	if not snapped:
		_target = null
		_snap_key = ""
		if ground.is_empty():
			_preview.visible = false
			_problem = "Point at the ground or a piece"
			_update_markers(end)
			return
		# Wherever the crosshair is (ground or piece), raised by the height offset; foundations
		# start out standing a meter proud of it
		var lift: float = _shape.get("free_lift", 0.0) + _height
		_where = Transform3D(Basis(Vector3.UP, _free_turn), ground["position"] + Vector3.UP * lift)
		_problem = _check(_where, null)
	else:
		_problem = _check(_where, _target)
	_preview.visible = true
	_preview.global_transform = _where
	_ghost.albedo_color = GOOD_COLOR if _problem.is_empty() else BAD_COLOR
	_update_markers(end)


# Looks for a snap point near the line from the camera to the crosshair's spot that this piece
# fits, and if there is one, sets where the piece goes: fitted there, then turned about the snap
# point by the player's turn. Nearest first; a snap point the piece fits without bumping into
# anything wins over a nearer one where it would.
func _snap(from: Vector3, end: Vector3) -> bool:
	var wanted := PieceShapes.targets_for(_shape["sockets"])
	var options := []
	for piece in registry.pieces_near(end, SNAP_SEARCH):
		var sockets: Array = piece.world_sockets()
		for i in sockets.size():
			var socket: Dictionary = sockets[i]
			if not wanted.has(socket["type"]):
				continue
			var gap := _distance_to_line(socket["position"], from, end)
			if gap < SNAP_RADIUS and (socket["position"] - from).length() > 0.8:
				options.append({"gap": gap, "piece": piece, "socket": socket, "key": "%d:%d" % [piece.piece_id, i]})
	if options.is_empty():
		return false
	options.sort_custom(func(a, b): return a["gap"] < b["gap"])
	var fallback := {}
	for option in options.slice(0, SNAP_TRIES):
		var pivot: Vector3 = option["socket"]["position"]
		var fits := _fits(option["socket"]).map(func(where): return _turned(where, pivot))
		var good := fits.filter(func(where): return _check(where, option["piece"]).is_empty())
		if not good.is_empty():
			_use_snap(option, good[0])
			return true
		if fallback.is_empty() and not fits.is_empty():
			fallback = option
			fallback["where"] = fits[0]
	if fallback.is_empty():
		return false
	# Nowhere it fits without bumping into something: shown red, turned as asked, so turning it
	# further can find a way that fits
	_use_snap(fallback, fallback["where"])
	return true


func _use_snap(option: Dictionary, where: Transform3D) -> void:
	_snap_key = option["key"]
	_target = option["piece"]
	_where = where


# A snapped placement turned about its snap point by the player's turn
func _turned(where: Transform3D, pivot: Vector3) -> Transform3D:
	if is_zero_approx(_snap_turn):
		return where
	var turn := Transform3D(Basis(Vector3.UP, _snap_turn), Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot) * where


# Every way this piece fits a placed snap point (see PieceShapes.fits)
func _fits(socket: Dictionary) -> Array:
	return PieceShapes.fits(_shape["sockets"], socket, _shape["symmetry"])


# Why the piece can't go here, or empty if it can: anything solid in the way (other pieces,
# trees, boulders, buildings, you), other than the ground and the piece it's snapping to, or a
# scattered rock. Slender pieces (pillars, poles, beams, ladders) only bump into each other: a
# floor or roof resting on several pillar tops, or a wall against a beam, overlaps them a little.
func _check(where: Transform3D, target: BuildPiece) -> String:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	if target:
		query.exclude = [target.get_rid()]
	var placing_slender: bool = _shape.get("slender", false)
	for part in _test_parts:
		query.shape = part["shape"]
		query.transform = where * (part["transform"] as Transform3D)
		for found in space.intersect_shape(query, MAX_OVERLAPS):
			var other: Object = found["collider"]
			if other.is_in_group("terrain_ground"):
				continue
			if other is BuildPiece and other.is_slender() != placing_slender:
				continue
			return BLOCKED
	var foliage = _foliage()
	if foliage and foliage.rock_in_box(where * _bounds):
		return "A rock is in the way"
	return ""


func _foliage() -> Node:
	var valley = get_tree().get_first_node_in_group("valley")
	return valley.get_node_or_null("Foliage") if valley else null


func _place() -> void:
	if not _preview.visible:
		return
	if not _problem.is_empty():
		_player.flash(_problem)
		return
	var cost := _buildable.cost_to_pay(_player.inventory)
	if cost.is_empty():
		_player.flash("Not enough: you need %s" % _buildable.missing_text(_player.inventory))
		return
	for item in cost:
		_player.remove_item(item, cost[item])
	registry.spawn(_buildable, _where, cost)
	_player.report_progress("Build", _buildable.display_name)
	# A new snap point may now be nearer; start its turns from the first
	_snap_key = ""


# The piece's solid parts, each shrunk a little so pieces may touch, and its overall box
func _make_test_parts() -> void:
	_test_parts.clear()
	_bounds = AABB()
	for part in _shape["collision"]:
		var shape: Shape3D = part["shape"]
		var test: Shape3D
		if shape is BoxShape3D:
			var box := BoxShape3D.new()
			box.size = ((shape as BoxShape3D).size - Vector3.ONE * TOUCH_MARGIN * 2.0).max(Vector3.ONE * 0.02)
			test = box
		elif shape is ConvexPolygonShape3D:
			var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
			var middle := Vector3.ZERO
			for p in points:
				middle += p
			middle /= maxf(points.size(), 1)
			var shrunk := PackedVector3Array()
			for p in points:
				var away := p - middle
				shrunk.append(middle + away.normalized() * maxf(away.length() - TOUCH_MARGIN * 1.5, 0.0))
			var convex := ConvexPolygonShape3D.new()
			convex.points = shrunk
			test = convex
		else:
			test = shape
		_test_parts.append({"shape": test, "transform": part["transform"]})
		var box_here: AABB = (part["transform"] as Transform3D) * _shape_box(shape)
		_bounds = box_here if _bounds.size == Vector3.ZERO else _bounds.merge(box_here)


func _shape_box(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size / 2.0, size)
	if shape is ConvexPolygonShape3D:
		var box := AABB()
		var first := true
		for p in (shape as ConvexPolygonShape3D).points:
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
		return box
	return AABB()


# ---- Snap point markers ----

func _make_markers() -> void:
	_marker_root = Node3D.new()
	_player.get_parent().add_child(_marker_root)
	_marker_material = _marker_look(MARKER_COLOR)
	_active_material = _marker_look(ACTIVE_MARKER_COLOR)
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	dot.radial_segments = 8
	dot.rings = 4
	for i in MAX_MARKERS:
		var marker := MeshInstance3D.new()
		marker.mesh = dot
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.visible = false
		_marker_root.add_child(marker)
		_markers.append(marker)


func _marker_look(color: Color) -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = color
	look.no_depth_test = true
	return look


# Dots on the snap points this piece could attach to, near the crosshair; the one it's using
# is bigger and yellow
func _update_markers(end: Vector3) -> void:
	var wanted := PieceShapes.targets_for(_shape["sockets"])
	var used := 0
	var active := Vector3.INF
	if _target:
		var parts := _snap_key.split(":")
		var sockets: Array = _target.world_sockets()
		if parts.size() == 2 and int(parts[1]) < sockets.size():
			active = sockets[int(parts[1])]["position"]
	for piece in registry.pieces_near(end, SNAP_SEARCH):
		for socket in piece.world_sockets():
			if used >= MAX_MARKERS or not wanted.has(socket["type"]):
				continue
			var spot: Vector3 = socket["position"]
			if spot.distance_to(end) > MARKER_REACH:
				continue
			var marker := _markers[used]
			used += 1
			var is_active := spot.distance_to(active) < 0.01
			marker.global_position = spot
			marker.scale = Vector3.ONE * (1.8 if is_active else 1.0)
			marker.material_override = _active_material if is_active else _marker_material
			marker.visible = true
	for i in range(used, _markers.size()):
		_markers[i].visible = false


# ---- Demolishing ----

## Called every frame: `active` while the hammer is out (and no menu is open), `in_mode` while
## demolish mode is on (see BuildPlacer), `holding_x` while X is held. Only then does the piece
## under the crosshair glow red, ready to demolish; otherwise nothing is targeted. Holding X on a
## piece for DEMOLISH_HOLD takes it down; letting go early starts over.
func update_demolish(delta: float, active: bool, in_mode: bool, holding_x: bool) -> void:
	var piece: BuildPiece = _piece_in_view() if active and (in_mode or holding_x) else null
	if piece != _looked_at:
		if is_instance_valid(_looked_at):
			_looked_at.set_highlight(null)
		_looked_at = piece
		_hold_time = 0.0
		if piece:
			piece.set_highlight(_glow_material())
	if piece and holding_x:
		_hold_time += delta
		if _hold_time >= DEMOLISH_HOLD:
			demolish()
	else:
		_hold_time = 0.0


## The piece that would be demolished (glowing red), or null
func demolish_target() -> BuildPiece:
	return _looked_at if is_instance_valid(_looked_at) else null


## Takes down the piece under the crosshair, giving back everything it cost (what won't fit in
## a full backpack is left on the ground in a bundle). False if there's no piece there.
func demolish() -> bool:
	if _looked_at == null or not is_instance_valid(_looked_at):
		return false
	var piece := _looked_at
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
	var refund := _items_text(piece.paid)
	var message := "Demolished %s" % piece.display_name()
	if not refund.is_empty():
		message += ": +" + refund
	if not left.is_empty():
		message += " (backpack full: %s left on the ground)" % _items_text(left)
	_player.flash(message)
	registry.remove(piece)
	return true


## The piece panel while demolishing (see HudControls): in demolish mode, or while X is held, the
## targeted piece's name and refund, in red. Empty otherwise.
func demolish_info(in_mode: bool) -> Dictionary:
	var target := demolish_target()
	if target and (in_mode or _hold_time > 0.0):
		var detail := "Demolishing... %d%%" % int(_hold_time / DEMOLISH_HOLD * 100.0) if _hold_time > 0.0 else "Demolish mode"
		return {
			"icon": target.buildable.icon if target.buildable else null,
			"title": target.display_name(),
			"cost": "Refund: %s" % _refund_text(target),
			"cost_bad": true,
			"detail": detail,
		}
	if in_mode:
		return {"title": "Demolish mode", "detail": "Aim at a building piece"}
	return {}


func _refund_text(piece: BuildPiece) -> String:
	return _items_text(piece.paid) if not piece.paid.is_empty() else "nothing"


func _piece_in_view() -> BuildPiece:
	var camera: Camera3D = _player.camera
	var hit := _cast_ray(camera.global_position, camera.global_position - camera.global_basis.z * DEMOLISH_REACH)
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
func _items_text(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item in items:
		parts.append("%d %s" % [items[item], item])
	return ", ".join(parts)


func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query)


# How far a point is from the line segment between two points
func _distance_to_line(point: Vector3, a: Vector3, b: Vector3) -> float:
	var along := b - a
	var t := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + along * t)
