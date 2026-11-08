class_name PiecePlacer
extends Node
## Placing building pieces, Valheim-style: the see-through preview snaps to the nearest fitting
## snap point of a placed piece (shown as small dots), or otherwise goes freely wherever the
## crosshair is, on the ground or on other pieces, and may float (there's no support yet). Green
## where it can go, red where it bumps into another piece, a tree or a rock (the ground is fine,
## so pieces can sit partly in a slope). It keeps placing the same piece until cancelled. Also
## demolishes, for a full refund: with the middle mouse button held, the piece under the crosshair
## glows red and comes down on release; or holding X on a piece long enough takes it down. Either
## way, placing carries on afterwards as it was.
##
## Snapped, R turns the piece about its snap point in 90° steps (45° for round and triangle
## pieces), and Alt + mouse wheel in 15° steps; the turn stays as it moves between snap points.
## Free, R turns it 15° and Alt + mouse wheel turns it smoothly. Page Up / Page Down (or Ctrl +
## wheel) raise and lower any piece, snapped or free, in 0.25 m steps (0.05 m with Alt);
## Backspace resets that. The height and turn stay for the next piece of the same kind, and carry
## over when you switch pieces from the build menu while placing (the snapped turn only if the
## new piece turns in the same steps).
##
## Snapping is on or off for every piece (Z toggles it, see `snapping`). Shift is for sprinting, so
## it doesn't change snapping.
##
## Furniture works differently: it rests on whatever floor, foundation or ground is under the
## crosshair. With snapping on it sits on a 0.5 m grid in the floor's own frame, turned in 90°
## steps (R), and a bed, shelf or tool rack backs up flush against a wall it's close to. It never
## overlaps other furniture or walls (red instead).

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
## shrunk this much on every side for the check (a bit more than half a wall's thickness).
## Furniture is shrunk only a hair, so it can stand flush against a wall but never inside one.
const TOUCH_MARGIN := 0.11
const FURNITURE_MARGIN := 0.02
## Furniture: the grid it snaps to on a floor, how far below the crosshair it looks for something
## to stand on, and how close to a wall (beyond its back) it backs up against it
const FURNITURE_GRID := 0.5
const SUPPORT_DROP := 4.0
const WALL_BACK_REACH := 0.6
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
## The plots, to tell which one a new piece belongs to
var plots: PlotRegistry
## Snapping on or off (Z), for every piece and the workbench, chest and campfire too
var snapping := true

var _player: CharacterBody3D
var _buildable: PieceBuildable
var _shape: Dictionary
var _preview: Node3D
var _ghost: StandardMaterial3D
# What's solid about the piece, shrunk a little: [{"shape", "transform"}]
var _test_parts: Array = []
# Each shape's shrunk solid parts, made once: shape -> parts
var _test_part_cache := {}
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
# How furniture snapped this frame: "On grid", "Against wall", or "" (free, or not furniture)
var _furniture_snap := ""
var _markers: Array[MeshInstance3D] = []
var _marker_root: Node3D
var _marker_material: StandardMaterial3D
var _active_material: StandardMaterial3D
# Demolishing: the piece that would come down (glowing red), how long X has been held on it, and
# the glow
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
	set_physics_process(false)


func is_placing() -> bool:
	return _buildable != null


## The piece being placed (null if none)
func current() -> PieceBuildable:
	return _buildable


## Starts placing a piece. `keep` carries the height and turn over from the piece being placed
## before (switching pieces from the build menu); otherwise they're kept only for the same piece.
func begin(piece: PieceBuildable, keep := false) -> void:
	cancel()
	_buildable = piece
	_shape = registry.shape_of(piece.shape)
	_snap_key = ""
	_problem = "Point at the ground or a piece"
	if keep:
		# A snapped turn the new piece can't make (45° on a piece that turns in 90° steps) goes
		var step: float = _shape.get("turn_step", PI / 2.0)
		if not is_zero_approx(fmod(_snap_turn + 0.001, step) - 0.001):
			_snap_turn = 0.0
		_kept_for = piece.resource_path
	elif piece.resource_path != _kept_for:
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
			if _target or (is_furniture() and snapping_now()):
				_snap_turn = wrapf(_snap_turn + _shape.get("turn_step", PI / 2.0), 0.0, TAU)
			else:
				_free_turn = wrapf(_free_turn + FREE_STEP, 0.0, TAU)
			return true
		# Finish or cancel this before putting the hammer away (Tab opens the build menu to switch)
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
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
## of details: snapped (and turned, and raised or lowered), or free and its height; and why it
## can't go there, if it can't)
func hud_state() -> Dictionary:
	var details: PackedStringArray = []
	var controls := [["Place", "LMB"]]
	var offset := "%+.2f m" % _height
	if _target or _furniture_snap != "":
		details.append(_furniture_snap if _furniture_snap != "" else "Snapped")
		var turn := roundi(rad_to_deg(_snap_turn)) % 360
		if turn != 0 and _target:
			details.append("turned %d°" % turn)
		if not is_zero_approx(_height):
			details.append(offset)
		controls.append(["Rotate %d°" % roundi(rad_to_deg(_shape.get("turn_step", PI / 2.0))), "R"])
		if _target:
			controls.append(["Rotate 15°", "Alt+Wheel"])
	else:
		details.append("Snap off" if not snapping_now() else "Free")
		details.append("Height " + offset)
		controls.append(["Rotate", "R"])
	controls.append(["Raise/Lower", "PgUp/PgDn"])
	if not is_zero_approx(_height):
		controls.append(["Reset height", "Backspace"])
	controls.append(["Snap", "Z"])
	controls.append(["Demolish", "MMB / Hold X"])
	controls.append(["Cancel", "RMB"])
	var plot := _plot_here()
	if plot:
		details.insert(0, "Building for: %s" % plot.plot_name)
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

	if is_furniture():
		_place_furniture(hit, far_point)
		return
	var snapped := false
	if snapping_now():
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


# A snapped placement turned about its snap point by the player's turn, and raised or lowered by
# the height offset (Page Up / Page Down)
func _turned(where: Transform3D, pivot: Vector3) -> Transform3D:
	var shift := Transform3D(Basis.IDENTITY, Vector3.UP * _height)
	if is_zero_approx(_snap_turn):
		return shift * where
	var turn := Transform3D(Basis(Vector3.UP, _snap_turn), Vector3.ZERO)
	return shift * Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot) * where


## Snapping as it is right now: on or off (Z)
func snapping_now() -> bool:
	return snapping


## True if the piece being placed is furniture
func is_furniture() -> bool:
	return _buildable != null and _shape.get("furniture", false)


# ---- Furniture ----

# Where furniture goes: standing on the floor, foundation or ground under the crosshair
func _place_furniture(hit: Dictionary, far_point: Vector3) -> void:
	_target = null
	_snap_key = ""
	for marker in _markers:
		marker.visible = false
	var spot := furniture_spot(hit, far_point, _bounds, _shape.get("backs_to_wall", false), roundi(_snap_turn / (PI / 2.0)), _free_turn, [])
	if spot.is_empty():
		_preview.visible = false
		_furniture_snap = ""
		_problem = "Point at a floor or the ground"
		return
	_where = spot["where"]
	_where.origin.y += _height
	_furniture_snap = spot["snap"]
	_problem = _check(_where, null)
	_preview.visible = true
	_preview.global_transform = _where
	_ghost.albedo_color = GOOD_COLOR if _problem.is_empty() else BAD_COLOR


## Where a piece of furniture (or a workbench, chest or campfire) would stand, given the
## crosshair's hit (or the end of its reach): resting on the floor, foundation or ground beneath
## it. With snapping on, on a floor it sits on FURNITURE_GRID in the floor's own frame, turned
## `quarter_turns` 90° steps from the floor's own facing, and if it `backs` and a wall is close
## behind it, flush against that wall; otherwise it's turned `free_turn`. `bounds` is its own box
## (its back is -Z). Returns {"where", "support" (what it stands on), "on_floor", "normal",
## "snap" ("On grid", "Against wall" or "")}, or empty if there's nothing to stand on.
func furniture_spot(hit: Dictionary, far_point: Vector3, bounds: AABB, backs: bool, quarter_turns: int, free_turn: float, skip: Array[RID]) -> Dictionary:
	var camera: Camera3D = _player.camera
	var toward := (camera.global_position - far_point).normalized()
	var start: Vector3 = (hit["position"] + toward * 0.05) if not hit.is_empty() else far_point
	var support := _support_under(start, skip)
	if support.is_empty():
		return {}
	var floor_piece: BuildPiece = support["collider"] if support["collider"] is BuildPiece else null
	var spot: Vector3 = support["position"]
	var snap := ""
	var yaw := free_turn
	if snapping_now():
		var base_yaw := floor_piece.global_rotation.y if floor_piece else 0.0
		yaw = base_yaw + quarter_turns * PI / 2.0
		if floor_piece:
			var local := floor_piece.global_transform.affine_inverse() * spot
			local.x = snappedf(local.x, FURNITURE_GRID)
			local.z = snappedf(local.z, FURNITURE_GRID)
			spot = floor_piece.global_transform * local
			spot.y = support["position"].y
			snap = "On grid"
	var where := Transform3D(Basis(Vector3.UP, yaw), spot)
	if backs and snapping_now():
		var backed := _backed_to_wall(where, bounds, skip)
		if backed != where:
			where = backed
			snap = "Against wall"
	return {"where": where, "support": support["collider"], "on_floor": floor_piece != null, "normal": support["normal"], "snap": snap}


# The floor, foundation or ground straight below a spot (passing through furniture, walls and
# anything else), or empty
func _support_under(from: Vector3, skip: Array[RID]) -> Dictionary:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.05, from + Vector3.DOWN * SUPPORT_DROP)
	var exclude: Array[RID] = [_player.get_rid()]
	exclude.append_array(skip)
	for i in 8:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var other: Object = hit["collider"]
		if other.is_in_group("terrain_ground") or (other is BuildPiece and other.is_floor()):
			return hit
		exclude.append(hit["rid"])
	return {}


# Slides furniture back (along its -Z) until its back touches a wall close behind it, or returns
# it as it was if there's none within WALL_BACK_REACH
func _backed_to_wall(where: Transform3D, bounds: AABB, skip: Array[RID]) -> Transform3D:
	var space := _player.get_world_3d().direct_space_state
	var back := -where.basis.z
	var depth := -bounds.position.z
	var nearest := INF
	for height: float in [0.3, 0.9]:
		var from := where.origin + Vector3.UP * height
		var query := PhysicsRayQueryParameters3D.create(from, from + back * (depth + WALL_BACK_REACH))
		var exclude: Array[RID] = [_player.get_rid()]
		exclude.append_array(skip)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var wall: Object = hit["collider"]
		# A wall: a building piece with an upright face, not furniture
		if wall is BuildPiece and not wall.is_furniture() and absf((hit["normal"] as Vector3).y) < 0.3:
			nearest = minf(nearest, from.distance_to(hit["position"]))
	if nearest == INF:
		return where
	return Transform3D(where.basis, where.origin + back * (nearest - depth - 0.005))


# Every way this piece fits a placed snap point (see PieceShapes.fits), the likeliest first. Stairs
# can meet an edge by their top or their bottom: an edge above your eyes gets their top (stairs
# coming down to you from a raised floor), one below gets their bottom (stairs going up from it).
func _fits(socket: Dictionary) -> Array:
	var own: Array = _shape["sockets"]
	if (socket["position"] as Vector3).y > _player.camera.global_position.y:
		own = own.filter(func(s): return s["type"] == "stairs_top") + own.filter(func(s): return s["type"] != "stairs_top")
	return PieceShapes.fits(own, socket, _shape["symmetry"])


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
	var plot := _plot_here()
	registry.spawn(_buildable, _where, cost, 0, plot.plot_id if plot else "")
	_player.report_progress("Build", _buildable.display_name)
	# A new snap point may now be nearer; start its turns from the first
	_snap_key = ""


# The plot the piece being placed would belong to (its middle is inside), or null
func _plot_here() -> Plot:
	if plots == null or _preview == null or not _preview.visible:
		return null
	return plots.find(plots.owner_for(_where * _bounds.get_center(), _player.global_position))


# The piece's solid parts, each shrunk a little so pieces may touch, and its overall box
func _make_test_parts() -> void:
	_test_parts = _test_parts_of(_buildable.shape)
	_bounds = PieceShapes.bounds_of(_shape)


## What a placed piece, put at `where`, would bump into (other than the ground, the bodies in
## `skip`, and pieces it may rest against), or null if nothing: for moving a plot's pieces
func piece_blocked(piece: BuildPiece, where: Transform3D, skip: Array[RID]) -> Object:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.exclude = skip
	var slender := piece.is_slender()
	for part in _test_parts_of(piece.buildable.shape):
		query.shape = part["shape"]
		query.transform = where * (part["transform"] as Transform3D)
		for found in space.intersect_shape(query, MAX_OVERLAPS):
			var other: Object = found["collider"]
			if other.is_in_group("terrain_ground"):
				continue
			if other is BuildPiece and other.is_slender() != slender:
				continue
			return other
	return null


# A shape's solid parts, each shrunk a little so pieces may touch (made once per shape)
func _test_parts_of(shape_name: String) -> Array:
	if _test_part_cache.has(shape_name):
		return _test_part_cache[shape_name]
	var parts := []
	var def := registry.shape_of(shape_name)
	var margin := FURNITURE_MARGIN if def.get("furniture", false) else TOUCH_MARGIN
	for part in def["collision"]:
		var shape: Shape3D = part["shape"]
		var test: Shape3D
		if shape is BoxShape3D:
			var box := BoxShape3D.new()
			box.size = ((shape as BoxShape3D).size - Vector3.ONE * margin * 2.0).max(Vector3.ONE * 0.02)
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
				shrunk.append(middle + away.normalized() * maxf(away.length() - margin * 1.5, 0.0))
			var convex := ConvexPolygonShape3D.new()
			convex.points = shrunk
			test = convex
		else:
			test = shape
		parts.append({"shape": test, "transform": part["transform"]})
	_test_part_cache[shape_name] = parts
	return parts


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
#
# Two ways, both with the hammer out, placing or not:
#   - Middle mouse button: pressing it picks the piece under the crosshair, which glows red while
#     the button is held; letting go takes it down. Looking off that piece first cancels.
#   - Holding X (for mice without a middle button): the piece under the crosshair glows red and
#     comes down after DEMOLISH_HOLD; looking away or letting go early starts over.

## Middle button pressed: picks the piece under the crosshair (it glows red until released)
func press_demolish() -> void:
	_mmb_down = true
	_mmb_piece = _piece_in_view()
	_mmb_cancelled = false


## Middle button released: takes down the piece picked on the press, if the crosshair is still on
## it; `active` is false if the hammer was put away or a menu opened meanwhile
func release_demolish(active: bool) -> void:
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
func update_demolish(delta: float, active: bool, holding_x: bool) -> void:
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
func demolish_info() -> Dictionary:
	if _hold_time > 0.0 and is_instance_valid(_looked_at):
		return {
			"icon": _looked_at.buildable.icon if _looked_at.buildable else null,
			"title": _looked_at.display_name(),
			"cost": "Refund: %s" % _refund_text(_looked_at),
			"cost_bad": true,
			"detail": "Demolishing... %d%%" % int(_hold_time / DEMOLISH_HOLD * 100.0),
		}
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
