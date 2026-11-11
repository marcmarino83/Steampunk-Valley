class_name ValheimPlacer
extends Node
## Placing building pieces the way Valheim does (DESIGN.md, "Placing pieces"):
##
##   1. Target: the building piece under the crosshair is the target, tinted blue. Snapping only
##      uses its snap points and those of the pieces directly touching it (within TOUCH_GAP).
##      Aimed at the ground (or nothing, the spot then being the ground below the crosshair's
##      reach), there's no target and the piece sits free there, unless it's right beside a building
##      (see _beside).
##   2. Snap points are corners and ends only (see SnapCorners). The target's show as small yellow
##      dots, and the pair in use gets a yellow upright bar. No dots on anything else.
##   3. The ghost is the piece's real look at GHOST_OPACITY, red only where it can't go (an identical
##      piece already there, or not enough materials).
##   4. Turning: the wheel turns it WHEEL_STEP a notch, measured against the target (0° is lined up
##      with whatever you're pointing at; with no target, with the world). The turn stays until the
##      player changes it, across pieces too. Nothing else ever turns it. Holding Shift places it
##      free, without snapping, and the wheel turns FINE_WHEEL_STEP a notch meanwhile.
##   5. Snap: the ghost goes at the crosshair's hit, by its origin, at the player's turn, and slides
##      so the closest pair between its corners and the target's (and the touching pieces') corners
##      meet exactly (see _best_pair), skipping any pair that would sink it into the target or a
##      touching piece by more than PieceOverlap.MARGIN (a floor aimed at a floor's middle goes
##      beside it, on the side the crosshair is nearest), and preferring pairs where the pieces meet
##      edge to edge or face to face. Aimed at the target, the pair may be up to MAX_SLIDE apart;
##      aimed at the ground beside a building, up to SNAP_RANGE (see _beside).
##   6. Sticky corner: once snapped, it keeps the same target corner while the player turns it, only
##      re-picking which of its own corners meets it; it moves to another target corner only when the
##      crosshair gets nearer that one by more than STICKY_SWITCH.
##
## Left click places, the middle button demolishes (see Demolisher), right click cancels.
## Furniture stands on the floor or ground under the crosshair (see FurnitureSpot), turned by the
## wheel the same way.

## How far ahead of the camera the crosshair reaches, and how far below that it looks for the ground
const REACH := 8.0
const DROP_DISTANCE := 300.0
## A pair of snap points this close or closer meets
const SNAP_RANGE := 0.5
## Pieces this close to the target count as touching it (their snap points take part too)
const TOUCH_GAP := 0.1
## Aimed at the ground beside a building: how far round the spot to look for the piece it's beside
const BESIDE_REACH := 4.0
## Aimed at the target: how far apart the pair may be (the ghost slides at most this far)
const MAX_SLIDE := 3.0
## The sticky corner gives way to another only when the crosshair is this much nearer that one
const STICKY_SWITCH := 0.3
## A pair where the pieces only touch at a point wins over one where they meet edge to edge only if
## it's this much closer
const CONTACT_PREFERENCE := 0.25
## Two pairs this nearly as close are a tie (the one on the snap point nearer the crosshair wins,
## then the one whose corner is nearer the camera, so the piece reaches away from the player: aimed
## at a pole top, a beam's near end meets it whichever end is a few centimetres nearer); corners
## this close meet
const TIE := 0.15
const MEET := 0.01
## Turning: one wheel notch, and with Shift held
const WHEEL_STEP := PI / 8.0
const FINE_WHEEL_STEP := PI / 180.0
## The ghost: how opaque its real look is, and its red where it can't go
const GHOST_OPACITY := 0.7
const BAD_COLOR := Color(1.0, 0.18, 0.12, 0.55)
## The target's blue tint (strong and light, as in Valheim), and the snap point dots and bar
const TARGET_TINT := Color(0.35, 0.68, 1.0, 0.55)
const DOT_COLOR := Color(1.0, 0.85, 0.15, 0.95)
const DOT_RADIUS := 0.035
const MAX_DOTS := 64
const BAR_HEIGHT := 0.9
const BAR_RADIUS := 0.018
## The controls row while placing a building piece, and while placing furniture or the workbench,
## chest and campfire (which aren't raised or lowered)
const CONTROLS := [["Place", "LMB"], ["Turn", "Wheel"], ["Raise/Lower", "PgUp/PgDn"], ["No snap (turn 1°)", "Hold Shift"], ["Demolish", "MMB"], ["Cancel", "RMB"]]
const FURNITURE_CONTROLS := [["Place", "LMB"], ["Turn", "Wheel"], ["No snap (turn 1°)", "Hold Shift"], ["Demolish", "MMB"], ["Cancel", "RMB"]]
## Page Up / Page Down raise and lower a free (unsnapped) piece this much a press, with no limit
## (that moves it; no piece is ever reshaped to fit where it goes)
const RAISE_STEP := 0.25

var registry: PieceRegistry
## The plots, to tell which one a new piece belongs to
var plots: PlotRegistry
## Taking pieces down (its red glow wins over the target's blue)
var demolisher: Demolisher
## The player's turn (radians), measured against the target: kept until the player changes it,
## across pieces, furniture and the workbench, chest and campfire
var turn := 0.0

var _player: CharacterBody3D
var _buildable: PieceBuildable
# The shape the ghost is built as (its buildable's), and its def
var _shape_name := ""
var _shape: Dictionary
# How far Page Up / Page Down have raised (+) or lowered (-) it while free
var _lift := 0.0
var _bounds := AABB()
# The point of its own it's held at the crosshair by (see hold_point)
var _hold := Vector3.ZERO
var _preview: Node3D
# The ghost's looks, and what each wore as its own (to go back to after red)
var _looks: Array[GeometryInstance3D] = []
var _own_looks := {}
var _bad_look: StandardMaterial3D
var _red := false
var _furniture: FurnitureSpot
var _where := Transform3D.IDENTITY
# The target (null for none), and the snap pair in use: [the ghost's corner, the built one] (empty
# when free)
var _target: BuildPiece
var _pair := []
var _problem := ""
var _highlighted: BuildPiece
var _tint: StandardMaterial3D
var _marker_root: Node3D
var _dots: Array[MeshInstance3D] = []
var _bar: MeshInstance3D
# Each piece with its touching pieces, and their snap points, worked out once until pieces change
var _round_cache := {}
# For each piece's snap points round it, what kind of piece each is a corner of (see _point_kind)
var _kind_cache := {}
## Kinds of snap point (see _point_kind): a floor's or foundation's corner (on its top's edge), a
## flight of stairs' corner, anything else's
const POINT_FLOOR := 1
const POINT_STAIRS := 2
const POINT_OTHER := 4
# The sticky corner: the piece and the snap point the ghost last met (Vector3.INF: none)
var _sticky_target: BuildPiece
var _sticky_point := Vector3.INF


func _ready() -> void:
	_player = get_parent().get_parent()
	_furniture = FurnitureSpot.new(_player)
	set_physics_process(false)
	if registry:
		registry.changed.connect(func():
			_round_cache.clear()
			_kind_cache.clear())


func is_placing() -> bool:
	return _buildable != null


## The piece being placed (null if none)
func current() -> PieceBuildable:
	return _buildable


## True if the piece being placed is furniture
func is_furniture() -> bool:
	return _buildable != null and _shape.get("furniture", false)


## Snapping right now: unless Shift is held
func snapping_now() -> bool:
	return not Input.is_key_pressed(KEY_SHIFT)


## Starts placing a piece (at the turn the player last set). `_keep` changes nothing.
func begin(piece: PieceBuildable, _keep := false) -> void:
	cancel()
	_buildable = piece
	_set_shape(piece.shape)
	_lift = 0.0
	_problem = "Point at the ground or a piece"
	_make_ghost()
	_make_markers()
	set_physics_process(true)


# The ghost is built as this shape
func _set_shape(shape: String) -> void:
	_shape_name = shape
	_shape = registry.shape_of(shape)
	_bounds = PieceShapes.bounds_of(_shape)
	_hold = hold_point(_shape)


func cancel() -> void:
	if _preview:
		_preview.queue_free()
	if _marker_root:
		_marker_root.queue_free()
	_preview = null
	_marker_root = null
	_dots.clear()
	_bar = null
	_looks.clear()
	_own_looks.clear()
	_red = false
	_buildable = null
	_shape_name = ""
	_set_target(null)
	_pair = []
	_sticky_target = null
	_sticky_point = Vector3.INF
	set_physics_process(false)


## Takes the keys and clicks that mean something while placing. Returns true if it used this one.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	# Finish or cancel this before putting the hammer away (Tab opens the build menu to switch)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		return true
	# Page Up / Page Down: a free piece up or down (repeating while held)
	if event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] and not is_furniture():
		_lift += RAISE_STEP * (1.0 if event.keycode == KEY_PAGEUP else -1.0)
		return true
	if event is InputEventMouseButton and event.pressed:
		if turn_by_wheel(event):
			return true
		# A click while the mouse is free just grabs it again, as it does any other time
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_place()
				return true
			if event.button_index == MOUSE_BUTTON_RIGHT:
				cancel()
				return true
	return false


## The wheel: turns WHEEL_STEP a notch (FINE_WHEEL_STEP with Shift held; many mice send Shift +
## wheel as a sideways scroll, which does the same). True if it was a wheel notch.
func turn_by_wheel(event: InputEventMouseButton) -> bool:
	var button := event.button_index
	if not button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return false
	var up := 1.0 if button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else -1.0
	var fine: bool = event.shift_pressed or button in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT] or not snapping_now()
	turn = wrapf(turn + (FINE_WHEEL_STEP if fine else WHEEL_STEP) * up, 0.0, TAU)
	return true


## What the on-screen controls show while placing (see HudControls): the controls, and the piece's
## panel: icon, name, cost (red if you can't afford it), "Turn 45°" when it's turned, how far it's
## raised or lowered while free, and why it can't go there (red)
func hud_state() -> Dictionary:
	var details: PackedStringArray = []
	if not is_zero_approx(turn):
		details.append(turn_text(turn))
	if _pair.is_empty() and not is_zero_approx(_lift) and not is_furniture():
		details.append("%s %.2f m" % ["Raised" if _lift > 0.0 else "Lowered", absf(_lift)])
	if not _problem.is_empty():
		details.append(_problem)
	return {"controls": FURNITURE_CONTROLS if is_furniture() else CONTROLS, "info": {
		"icon": _buildable.icon,
		"title": _buildable.display_name,
		"cost": _buildable.cost_text(),
		"cost_bad": not _buildable.can_afford(_player.inventory),
		"detail": "  ·  ".join(details),
		"detail_bad": not _problem.is_empty(),
		"detail_warn": false,
	}}


## "Turn 45°", "Turn 22.5°", "Turn 23°" (to a tenth of a degree, trailing ".0" left off)
static func turn_text(angle: float) -> String:
	var degrees := snappedf(fposmod(rad_to_deg(angle), 360.0), 0.1)
	if degrees >= 359.95:
		degrees = 0.0
	return "Turn %s°" % (str(int(degrees)) if is_equal_approx(degrees, roundf(degrees)) else "%.1f" % degrees)


## A placement turned `angle` round the upright about `pivot` (furniture, and the workbench, chest
## and campfire: see BuildPlacer)
static func turned(where: Transform3D, pivot: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, angle), pivot) * Transform3D(Basis.IDENTITY, -pivot) * where


func _physics_process(_delta: float) -> void:
	var timing := SpikeLog.begin()
	_follow_crosshair()
	SpikeLog.end("placing: following the crosshair (snap search)", timing)


# ---- Following the crosshair ----

func _follow_crosshair() -> void:
	var camera: Camera3D = _player.camera
	var from := camera.global_position
	var far_point := from - camera.global_basis.z * REACH
	var hit := _cast_ray(from, far_point)
	if is_furniture():
		_place_furniture(hit, far_point)
		return
	var spot := Vector3.INF
	var target: BuildPiece = null
	if not hit.is_empty():
		spot = hit["position"]
		if hit["collider"] is BuildPiece:
			target = hit["collider"]
	else:
		var below := _cast_ray(far_point, far_point + Vector3.DOWN * DROP_DISTANCE)
		if not below.is_empty():
			spot = below["position"]
	if spot == Vector3.INF:
		_preview.visible = false
		_problem = "Point at the ground or a piece"
		_set_target(null)
		_pair = []
		_show_markers()
		return
	_pair = []
	var snapping := snapping_now()
	if target == null:
		# On the ground (or nothing): a foundation stands proud of it, its top FOUNDATION_LIFT up
		spot += Vector3.UP * float(_shape.get("free_lift", 0.0))
	var aimed_at := target
	if target:
		_where = _ghost_at(spot, target)
		if snapping:
			var pair := _best_pair(target, spot, MAX_SLIDE)
			if not pair.is_empty():
				_use_pair(target, pair)
	elif snapping:
		target = _beside(spot)
	if target == null:
		_where = _ghost_at(spot, null)
		_sticky_target = null
		_sticky_point = Vector3.INF
	# Free (not snapped): Page Up / Page Down raise and lower it
	if _pair.is_empty():
		_where.origin.y += _lift
	_set_target(target if target else aimed_at)
	_problem = _check(_where)
	_preview.visible = true
	_preview.global_transform = _where
	_show_red(not _problem.is_empty())
	_show_markers()


# The ghost held at `spot` by its hold point (see hold_point), at the player's turn measured against
# `target` (or the world)
func _ghost_at(spot: Vector3, target: BuildPiece) -> Transform3D:
	var base := _yaw(target.global_basis) if target else 0.0
	var basis := Basis(Vector3.UP, base + turn)
	return Transform3D(basis, spot - basis * _hold)


## The point of its own a piece is held at the crosshair by: its origin (a floor's top middle, a
## wall's bottom middle, a roof's low edge middle, a flight's middle on the ground...), except a roof
## topper, held like a roof by the middle of one low edge (aimed at a roof's high edge, it reaches on
## over the ridge), and a piece whose origin isn't on it (curved walls and cone roofs have theirs at
## the middle of the circle), held by the middle of its base
static func hold_point(def: Dictionary) -> Vector3:
	var box := PieceShapes.bounds_of(def)
	var lows: Array = def["sockets"].filter(func(s): return (s["type"] as String).begins_with("topper_low"))
	if lows.size() == 2:
		return lows[0]["position"] if (lows[0]["position"] as Vector3).z < (lows[1]["position"] as Vector3).z else lows[1]["position"]
	if PieceOverlap.near_solid(def, Vector3.ZERO, 0.05):
		return Vector3.ZERO
	return Vector3(box.get_center().x, box.position.y, box.get_center().z)


# The snap with `target` (rules 5 and 6), the ghost held at `spot`: of the pairs between its corners
# and the target's and touching pieces' snap points no more than `reach` apart, the closest that
# doesn't sink it into any of those pieces (see PieceOverlap), a pair where the pieces meet edge to
# edge or face to face (two or more corners meeting) winning over a point-only one up to
# CONTACT_PREFERENCE closer, and of two equally close the one whose corner is nearer the camera.
# While the sticky corner is on this target and the crosshair isn't nearer another of its points by
# more than STICKY_SWITCH, only pairs on that corner count (unless none of them will do).
# {"own" (its corner), "at" (the snap point), "gap", "landed" (how many corners meet), "where"}, or
# empty for none.
func _best_pair(target: BuildPiece, spot: Vector3, reach: float) -> Dictionary:
	var ghost := _ghost_at(spot, target)
	var points := _points_round(target)
	if _sticky_target == target and points.any(func(p): return (p as Vector3).distance_to(_sticky_point) < MEET):
		var nearest := INF
		for p in points:
			nearest = minf(nearest, spot.distance_to(p))
		if spot.distance_to(_sticky_point) <= nearest + STICKY_SWITCH:
			var held := _pick(ghost, spot, points, [_sticky_point], target, reach)
			if not held.is_empty():
				return held
	return _pick(ghost, spot, points, points, target, reach)


# The pair chosen of the ghost's corners and `anchors` (see _best_pair); `points` are all the snap
# points round the target, for counting how many corners meet. Of two equally close pairs, the one
# on the snap point nearer the crosshair, then the one whose corner is nearer the camera.
func _pick(ghost: Transform3D, spot: Vector3, points: Array, anchors: Array, target: BuildPiece, reach: float) -> Dictionary:
	var eye: Vector3 = (_player.camera as Camera3D).global_position
	var pairs := []
	for own in SnapCorners.of(_shape_name, _shape):
		var at: Vector3 = ghost * (own as Vector3)
		for p in anchors:
			var gap := at.distance_to(p)
			if gap <= reach and _may_meet(_point_kind(target, p)):
				pairs.append([gap, at, p])
	pairs.sort_custom(func(a, b):
		if absf(float(a[0]) - float(b[0])) > TIE:
			return float(a[0]) < float(b[0])
		var a_spot := (a[2] as Vector3).distance_to(spot)
		var b_spot := (b[2] as Vector3).distance_to(spot)
		if absf(a_spot - b_spot) > TIE:
			return a_spot < b_spot
		return (a[1] as Vector3).distance_to(eye) < (b[1] as Vector3).distance_to(eye))
	var best := {}
	for pair in pairs:
		if not best.is_empty() and float(pair[0]) > float(best["gap"]) + CONTACT_PREFERENCE:
			break
		var where := ghost.translated((pair[2] as Vector3) - (pair[1] as Vector3))
		if _sinks_in(where, target):
			continue
		var landed := _landed(where, points)
		if best.is_empty() or (landed >= 2 and int(best["landed"]) < 2):
			best = {"own": pair[1], "at": pair[2], "gap": pair[0], "landed": landed, "where": where}
			if landed >= 2:
				break
	return best


# How many of the ghost's corners, put at `where`, meet one of `points`
func _landed(where: Transform3D, points: Array) -> int:
	var count := 0
	for own in SnapCorners.of(_shape_name, _shape):
		var at: Vector3 = where * (own as Vector3)
		if points.any(func(p): return at.distance_to(p) < MEET):
			count += 1
	return count


# True if the ghost at `where` would sink into the target or a piece touching it (see PieceOverlap)
func _sinks_in(where: Transform3D, target: BuildPiece) -> bool:
	for piece in _pieces_round(target):
		if PieceOverlap.overlaps(_shape_name, _shape, where, piece):
			return true
	return false


# Snaps the ghost by `pair` with `target`, and makes that the sticky corner
func _use_pair(target: BuildPiece, pair: Dictionary) -> void:
	_where = pair["where"]
	_pair = [pair["own"], pair["at"], pair["gap"]]
	_sticky_target = target
	_sticky_point = pair["at"]


# Aimed at the ground (or nothing) right beside a building: the sticky corner's piece while the
# crosshair stays within the ghost's reach of that corner (so turning it keeps it there); otherwise,
# of the pieces round the spot, the one with the closest pair (see _best_pair) within SNAP_RANGE,
# the ghost turned against it. It's then the target and the ghost is snapped to it. Null (free) if
# none is that close.
func _beside(spot: Vector3) -> BuildPiece:
	if is_instance_valid(_sticky_target) and spot.distance_to(_sticky_point) <= _bounds.size.length() + SNAP_RANGE:
		var held := _best_pair(_sticky_target, spot, MAX_SLIDE)
		if not held.is_empty():
			_use_pair(_sticky_target, held)
			return _sticky_target
	var best: BuildPiece = null
	var best_pair := {}
	for piece in registry.pieces_near(spot, BESIDE_REACH + _bounds.size.length()):
		if not is_instance_valid(piece) or piece.is_queued_for_deletion():
			continue
		var pair := _best_pair(piece, spot, SNAP_RANGE)
		if not pair.is_empty() and (best_pair.is_empty() or float(pair["gap"]) < float(best_pair["gap"])):
			best = piece
			best_pair = pair
	if best:
		_use_pair(best, best_pair)
	return best


# A piece's snap points with those of the pieces directly touching it (their boxes within TOUCH_GAP
# of its box), in the world
func _points_round(piece: BuildPiece) -> Array:
	var key := piece.get_instance_id()
	if not _round_cache.has(key):
		var points := []
		var kinds := {}
		for other in _pieces_round(piece):
			var def: Dictionary = other.shape_def()
			var kind := POINT_FLOOR if def.get("floor", false) else (POINT_STAIRS if def.get("stairs", false) else POINT_OTHER)
			for p: Vector3 in SnapCorners.in_world(other):
				points.append(p)
				var at := _point_key(p)
				kinds[at] = int(kinds.get(at, 0)) | kind
		_round_cache[key] = points
		_kind_cache[key] = kinds
	return _round_cache[key]


# What the snap point `p` round a piece is (see _points_round): POINT_FLOOR, POINT_STAIRS and
# POINT_OTHER together, for each kind of piece with a corner there
func _point_kind(piece: BuildPiece, p: Vector3) -> int:
	_points_round(piece)
	return int(_kind_cache[piece.get_instance_id()].get(_point_key(p), 0))


static func _point_key(p: Vector3) -> Vector3i:
	return Vector3i((p * 1000.0).round())


# Which snap points the ghost's corners may meet. A flight of stairs (Stairs, Half Stairs,
# Foundation Steps), by its top corners or its bottom ones alike, only a floor's or foundation's
# corners (all of which are on its top's edge); on bare ground it simply stands where it's put. And
# so the other way round: a point that is only a flight's corners only takes a floor or foundation.
# Nothing else pairs with a flight, so a flight never meets anything by a wrong corner, leaving a gap.
func _may_meet(kind: int) -> bool:
	if _shape.get("stairs", false):
		return kind & POINT_FLOOR != 0
	if kind & POINT_STAIRS and kind & (POINT_FLOOR | POINT_OTHER) == 0:
		return _shape.get("floor", false)
	return true


# A piece and the pieces directly touching it
func _pieces_round(piece: BuildPiece) -> Array:
	var key := -piece.get_instance_id()
	if not _round_cache.has(key):
		var found := [piece]
		var box := _world_box(piece).grow(TOUCH_GAP)
		for other in registry.pieces_near(piece.global_position, 8.0):
			if other != piece and is_instance_valid(other) and not other.is_queued_for_deletion() and _world_box(other).intersects(box):
				found.append(other)
		_round_cache[key] = found
	return _round_cache[key]


static func _world_box(piece: BuildPiece) -> AABB:
	return piece.global_transform * PieceShapes.bounds_of(piece.shape_def())


static func _yaw(basis: Basis) -> float:
	return atan2(basis.z.x, basis.z.z)


# ---- Furniture ----

# Furniture stands on the floor, foundation or ground under the crosshair (see FurnitureSpot),
# turned by the player's turn about where it stands, measured against the floor
func _place_furniture(hit: Dictionary, far_point: Vector3) -> void:
	_set_target(null)
	_pair = []
	_show_markers()
	var spot := _furniture.find(hit, far_point, _bounds, _shape.get("backs_to_wall", false), _shape.get("wall_mount", 0.0), snapping_now())
	if spot.is_empty():
		_preview.visible = false
		_problem = "Point at a floor or the ground"
		return
	var start: Transform3D = spot["where"]
	_where = turned(start, start.origin, turn)
	_problem = _check(_where)
	_preview.visible = true
	_preview.global_transform = _where
	_show_red(not _problem.is_empty())


## Where furniture (or a workbench, chest or campfire) would stand before its turn (see FurnitureSpot)
func furniture_spot(hit: Dictionary, far_point: Vector3, bounds: AABB, backs: bool) -> Dictionary:
	return _furniture.find(hit, far_point, bounds, backs, 0.0, snapping_now())


# ---- Placing ----

# Why the piece can't go here, or empty if it can: only an identical piece already in its place,
# or not having the materials. It may overlap anything and sink into the ground as far as you like;
# anyone standing there glides aside when it goes down (see PeopleMover).
func _check(where: Transform3D) -> String:
	var twin := registry.duplicate_of(_shape_name, where)
	if twin:
		return "Already placed" + (": build its ghost instead" if twin.is_ghost() else "")
	if not _buildable.can_afford(_player.inventory):
		return "Not enough: you need %s" % _buildable.missing_text(_player.inventory)
	return ""


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
	cost = _player.pay(cost)
	var plot: Plot = null
	if plots:
		plot = plots.find(plots.owner_for(_where * _bounds.get_center(), _player.global_position))
	var built := registry.spawn(_buildable, _where, cost, 0, plot.plot_id if plot else "")
	# Anyone standing where it went down glides aside
	PeopleMover.clear_from([built])
	_player.report_progress("Build", _buildable.display_name)


# ---- The ghost ----

# The piece's real look (its full close-up look, or its model), at GHOST_OPACITY
func _make_ghost() -> void:
	_preview = Node3D.new()
	if _buildable.model_scene:
		_preview.add_child(BuildPiece.fitted_model(_buildable, _shape))
	else:
		var detail := registry.detail_mesh(_shape_name, 0)
		var look_material: Material = registry.detail_material()
		var meshes: Array = [detail.get("mesh"), detail.get("door_mesh")]
		if detail.get("mesh") == null:
			meshes = [_shape["mesh"], _shape["door_mesh"]]
			look_material = registry.material_for(_shape_name)
		for mesh in meshes:
			if mesh:
				var look := MeshInstance3D.new()
				look.mesh = mesh
				look.material_override = look_material
				_preview.add_child(look)
	for look in _preview.find_children("*", "GeometryInstance3D", true, false):
		var g := look as GeometryInstance3D
		g.transparency = 1.0 - GHOST_OPACITY
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_own_looks[g] = g.material_override
		_looks.append(g)
		if g is MeshInstance3D and g.material_override is ShaderMaterial:
			# (as a built piece wears it: see BuildPiece.weather)
			g.set_instance_shader_parameter("tint", Color.WHITE)
			g.set_instance_shader_parameter("box_min", _bounds.position)
			g.set_instance_shader_parameter("box_max", _bounds.end)
			g.set_instance_shader_parameter("frame_offset", _shape.get("frame_offset", 0.0))
	_preview.visible = false
	_player.get_parent().add_child(_preview)


# Red where it can't go, its own look otherwise
func _show_red(on: bool) -> void:
	if on == _red:
		return
	_red = on
	if _bad_look == null:
		_bad_look = StandardMaterial3D.new()
		_bad_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bad_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bad_look.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bad_look.albedo_color = BAD_COLOR
	for look in _looks:
		if is_instance_valid(look):
			look.material_override = _bad_look if on else _own_looks.get(look)


# ---- The target's tint, dots and bar ----

# The target tinted blue (unless it's glowing red to come down)
func _set_target(target: BuildPiece) -> void:
	_target = target
	var glowing: BuildPiece = demolisher.glowing() if demolisher else null
	var wanted: BuildPiece = target if target and target != glowing else null
	if wanted == _highlighted:
		return
	if is_instance_valid(_highlighted) and _highlighted != glowing:
		_highlighted.set_highlight(null)
	_highlighted = wanted
	if wanted:
		if _tint == null:
			_tint = StandardMaterial3D.new()
			_tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_tint.albedo_color = TARGET_TINT
		wanted.set_highlight(_tint)


func _make_markers() -> void:
	_marker_root = Node3D.new()
	_player.get_parent().add_child(_marker_root)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = DOT_COLOR
	look.no_depth_test = true
	var dot := SphereMesh.new()
	dot.radius = DOT_RADIUS
	dot.height = DOT_RADIUS * 2.0
	dot.radial_segments = 8
	dot.rings = 4
	dot.material = look
	for i in MAX_DOTS:
		var marker := MeshInstance3D.new()
		marker.mesh = dot
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.visible = false
		_marker_root.add_child(marker)
		_dots.append(marker)
	var rod := CylinderMesh.new()
	rod.top_radius = BAR_RADIUS
	rod.bottom_radius = BAR_RADIUS
	rod.height = BAR_HEIGHT
	rod.radial_segments = 8
	rod.material = look
	_bar = MeshInstance3D.new()
	_bar.mesh = rod
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.visible = false
	_marker_root.add_child(_bar)


# The target's snap points as dots (while snapping), and the bar on the pair in use
func _show_markers() -> void:
	if _marker_root == null:
		return
	var points: Array = SnapCorners.in_world(_target) if is_instance_valid(_target) and snapping_now() else []
	for i in _dots.size():
		_dots[i].visible = i < points.size()
		if i < points.size():
			_dots[i].global_position = points[i]
	_bar.visible = not _pair.is_empty()
	if _bar.visible:
		_bar.global_position = _pair[1]


## The snap points shown as dots right now (the target's), and the bar's spot (Vector3.INF for
## none): for tests and measuring
func shown_markers() -> Dictionary:
	var dots := []
	for dot in _dots:
		if dot.visible:
			dots.append(dot.global_position)
	return {"dots": dots, "bar": _bar.global_position if _bar and _bar.visible else Vector3.INF}


func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query)
