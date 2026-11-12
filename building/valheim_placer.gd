class_name ValheimPlacer
extends Node
## Placing building pieces (DESIGN.md, "Snapping redesign" and "Placing pieces"). Every building
## piece snaps by typed edges or typed points (SnapEdges), chosen by aim (see _edge_fit, _point_fit):
## no hold point, no sliding, never a single corner. Snapped, the wheel steps through the turns that
## fit there (flights of stairs, pillars, poles, beams and chimney pieces keep the player's turn,
## 22.5° a notch); with no fit, the piece is free at the crosshair with "No fit here".
##
##   - The target: the piece the crosshair hits (or, aimed at the ground, the piece the fit is on),
##     tinted blue; its corners show as small yellow dots while snapping, and the joint in use gets a
##     yellow upright bar.
##   - The ghost is the piece's real look, solid (its own materials and colour; see _make_ghost),
##     with a light tint and thin outline over it (see PreviewLook): warm, or red only where it can't
##     go (an identical piece already there, or not enough materials). Overlapping other pieces never
##     stops it.
##   - Turning: the wheel turns it WHEEL_STEP a notch, measured against the target (0° is lined up
##     with whatever you're pointing at; with no target, with the world). The turn stays until the
##     player changes it, across pieces too. Z turns snapping off (the piece goes free where the
##     crosshair is, and the wheel turns FINE_WHEEL_STEP a notch) and on again; it stays as set,
##     across pieces. (Shift is sprint and does nothing here.) Free, Page Up / Page Down raise and
##     lower it.
##
## Left click places, the middle button demolishes (see Demolisher), right click cancels.
## Furniture stands on the floor or ground under the crosshair (see FurnitureSpot), turned by the
## wheel the same way.

## How far ahead of the camera the crosshair reaches, and how far below that it looks for the ground
const REACH := 8.0
const DROP_DISTANCE := 300.0
## A point piece keeps the placed point it's on while the crosshair stays this close to where it
## snapped there (it turns in place: see _point_fit); dots this close are one
const STICKY_SWITCH := 0.3
const MEET := 0.01
## Turning: one wheel notch, and with snapping off
const WHEEL_STEP := PI / 8.0
const FINE_WHEEL_STEP := PI / 180.0
## The target's blue tint (strong and light, as in Valheim), and the snap point dots and bar
const TARGET_TINT := Color(0.35, 0.68, 1.0, 0.55)
const DOT_COLOR := Color(1.0, 0.95, 0.2, 0.95)
const DOT_RADIUS := 0.035
const MAX_DOTS := 64
const BAR_HEIGHT := 0.9
const BAR_RADIUS := 0.018
## The controls row while placing a building piece, and while placing furniture or the workbench,
## chest and campfire (which aren't raised or lowered)
const CONTROLS := [["Place", "LMB"], ["Turn", "Wheel"], ["Raise/Lower", "PgUp/PgDn"], ["Snap", "Z"], ["Demolish", "MMB"], ["Cancel", "RMB"]]
const FURNITURE_CONTROLS := [["Place", "LMB"], ["Turn", "Wheel"], ["Snap", "Z"], ["Demolish", "MMB"], ["Cancel", "RMB"]]
## What the placement panel says while snapping is off
const SNAP_OFF_TEXT := "Snapping off (turn 1°)"
## Page Up / Page Down raise and lower a free (unsnapped) piece this much a press, with no limit
## (that moves it; no piece is ever reshaped to fit where it goes)
const RAISE_STEP := 0.25
## Whole-edge pieces (see SnapEdges and _edge_fit; flights of stairs and doors among them): the aimed piece's edges this close to the
## crosshair's hit, and any piece's edges this close to the crosshair's line before the hit, are
## candidates; a fit whose body is farther than BODY_REACH from that line is dropped
const AIM_EDGE_REACH := 1.0
const LINE_EDGE_REACH := 1.5
const BODY_REACH := 0.5
## A flight aimed at a side face this close to the seam with the next piece's face (in line with it)
## counts as aimed at either piece's edge
const SEAM := 0.02
## How far round each point along the crosshair's line to look for pieces (by their origin): the
## line reach plus the farthest a piece's edge is from its origin
const NEAR_PIECES := 5.0
## Fits whose bodies are this nearly as close to the line count as equally close; fits whose middles
## are this close together are the same spot (only the turn differs)
const BODY_TIE := 0.05
const SAME_SPOT := 0.05
## What the panel says when a whole-edge piece is aimed at a piece it can't fit
const NO_FIT_TEXT := "No fit here"

var registry: PieceRegistry
## The plots, to tell which one a new piece belongs to
var plots: PlotRegistry
## Taking pieces down (its red glow wins over the target's blue)
var demolisher: Demolisher
## The player's turn (radians), measured against the target: kept until the player changes it,
## across pieces, furniture and the workbench, chest and campfire
var turn := 0.0
## Snapping on or off (Z): stays as set, across pieces
var snap_on := true
## Its middle, as aimed at (see _set_shape), in its own space
var _middle := Vector3.ZERO
## For the tests: the top-ranked point or edge fits of the last frame, with their ranking keys
var last_ranking := []

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
# The preview's looks, and whether it shows red (it can't go there; see _show_red)
var _looks: Array[GeometryInstance3D] = []
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
# Whole-edge pieces: each placed piece's typed edges in the world (until pieces change); the turns
# (world yaws) that fit at the spot it's snapped to, sorted; the yaw it's shown at; the yaw the
# player's turn is measured from (the aimed piece's, or the world's); and the panel's note
var _edge_cache := {}
var _fit_yaws: Array[float] = []
var _shown_yaw := 0.0
var _turn_ref := 0.0
var _note := ""
# The face the crosshair hit: its normal (zero with no hit), for a flight aimed at a floor's edge face
var _hit_normal := Vector3.ZERO
# Point pieces: the placed point it's on (Vector3.INF: none), which of its own points, and where the
# crosshair was when it snapped there (it stays on that point while it turns: see _point_fit)
var _stick_pivot := Vector3.INF
var _stick_index := -1
var _stick_spot := Vector3.INF


func _ready() -> void:
	_player = get_parent().get_parent()
	_furniture = FurnitureSpot.new(_player)
	set_physics_process(false)
	if registry:
		registry.changed.connect(func(): _edge_cache.clear())


func is_placing() -> bool:
	return _buildable != null


## The piece being placed (null if none)
func current() -> PieceBuildable:
	return _buildable


## True if the piece being placed is furniture
func is_furniture() -> bool:
	return _buildable != null and _shape.get("furniture", false)


## Snapping right now: unless Z has turned it off
func snapping_now() -> bool:
	return snap_on


## Z: turns snapping off or on again. True if it was Z.
func toggle_snap(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z:
		snap_on = not snap_on
		return true
	return false


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
	# (a floor's or foundation's middle as aimed at is the middle of its top: a foundation's block
	# reaches 2 m into the ground, and its box's middle is underground, where no one aims)
	_middle = _bounds.get_center()
	if _shape.get("floor", false):
		_middle.y = _bounds.end.y - 0.1


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
	_red = false
	_buildable = null
	_shape_name = ""
	_set_target(null)
	_pair = []
	_fit_yaws.clear()
	_note = ""
	_stick_pivot = Vector3.INF
	set_physics_process(false)


## Takes the keys and clicks that mean something while placing. Returns true if it used this one.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	# Finish or cancel this before putting the hammer away (Tab opens the build menu to switch)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		return true
	if toggle_snap(event):
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


## The wheel: turns WHEEL_STEP a notch (FINE_WHEEL_STEP with snapping off; Shift changes nothing).
## True if it was a wheel notch.
func turn_by_wheel(event: InputEventMouseButton) -> bool:
	var button := event.button_index
	if not button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return false
	var up := 1.0 if button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else -1.0
	# A whole-edge piece snapped: the next turn that fits at that spot, that way round (not a flight of
	# stairs: it keeps the player's turn, turned freely, and snaps where it fits that way round)
	if snapping_now() and edge_piece() and not _pair.is_empty() and not _fit_yaws.is_empty() and not _shape_name in SnapEdges.FLIGHTS:
		var next := _shown_yaw
		var best := INF
		for yaw in _fit_yaws:
			var delta := fposmod((yaw - _shown_yaw) * up, TAU)
			if delta > 0.001 and delta < best:
				best = delta
				next = yaw
		turn = wrapf(next - _turn_ref, 0.0, TAU)
		return true
	turn = wrapf(turn + (WHEEL_STEP if snapping_now() else FINE_WHEEL_STEP) * up, 0.0, TAU)
	return true


## True while placing a piece that snaps by whole edges (see SnapEdges)
func edge_piece() -> bool:
	return _buildable != null and SnapEdges.edge_shape(_shape_name)


## True while placing a pillar, pole, beam or chimney piece, which snap by typed points (see _point_fit)
func point_piece() -> bool:
	return _buildable != null and SnapEdges.point_shape(_shape_name)


## What the on-screen controls show while placing (see HudControls): the controls, and the piece's
## panel: icon, name, cost (red if you can't afford it), "Turn 45°" when it's turned, how far it's
## raised or lowered while free, and why it can't go there (red)
func hud_state() -> Dictionary:
	var details: PackedStringArray = []
	# (a whole-edge piece snapped shows the turn it's at, which may differ from the player's)
	var shown := wrapf(_shown_yaw - _turn_ref, 0.0, TAU) if edge_piece() and snapping_now() and not _pair.is_empty() else turn
	if not is_zero_approx(shown) and not is_equal_approx(shown, TAU):
		details.append(turn_text(shown))
	if _pair.is_empty() and not is_zero_approx(_lift) and not is_furniture():
		details.append("%s %.2f m" % ["Raised" if _lift > 0.0 else "Lowered", absf(_lift)])
	if not snapping_now():
		details.append(SNAP_OFF_TEXT)
	if not _note.is_empty():
		details.append(_note)
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
	_note = ""
	_fit_yaws.clear()
	var snapping := snapping_now()
	if target == null:
		# On the ground (or nothing): a foundation stands proud of it, its top FOUNDATION_LIFT up
		spot += Vector3.UP * float(_shape.get("free_lift", 0.0))
	var aimed_at := target
	_turn_ref = _yaw(target.global_basis) if target else 0.0
	if snapping and (edge_piece() or point_piece()):
		# Whole edges (or, for pillars, poles and beams, typed points), chosen by aim: no hold point,
		# no sliding
		var line_end: Vector3 = far_point
		var hit_point := Vector3.INF
		_hit_normal = Vector3.ZERO
		if not hit.is_empty():
			hit_point = hit["position"]
			_hit_normal = hit.get("normal", Vector3.ZERO)
			line_end = hit_point + (hit_point - from).normalized() * 0.1
		var fit: Dictionary = _point_fit(from, line_end, target, hit_point) if point_piece() else _edge_fit(from, line_end, target, hit_point)
		if fit.is_empty():
			_where = _ghost_at(spot, target)
			if target:
				_note = NO_FIT_TEXT
		else:
			_where = fit["where"]
			_pair = [fit["own_mid"], fit["at_mid"], 0.0]
			if target == null:
				target = fit["piece"]
	else:
		# Snapping off: free at the crosshair, at the player's turn
		_where = _ghost_at(spot, target)
	if target == null and _pair.is_empty():
		_where = _ghost_at(spot, null)
	# Free (not snapped): Page Up / Page Down raise and lower it
	if _pair.is_empty():
		_where.origin.y += _lift
	_set_target(target if target else aimed_at)
	_problem = _check(_where)
	_preview.visible = true
	_preview.global_transform = _where
	_show_red(not _problem.is_empty())
	_show_markers()


# ---- Whole edges (converted families: see SnapEdges) ----

# The fit chosen by aim, the crosshair's line running from `from` to `to` (just past the hit, or the
# end of its reach), `aimed` the piece it hit (or null) at `hit_point`. Candidates: the aimed piece's
# edges within AIM_EDGE_REACH of the hit, and any piece's edges within LINE_EDGE_REACH of the line;
# every way the ghost fits them (SnapEdges.placements: whole edges, the table's turns, grid steps).
# Dropped: fits whose body is more than BODY_REACH from the line, and fits that are taken (see
# _taken). A flight of stairs looks for edges its own length farther off, ranks first the fits at the
# player's turn (it keeps the turn, as pillars and beams do), and of its fits as near the line, aimed
# at a piece's side face, one on that piece's edge by the hit, then one standing on something by its
# bottom edge. Ranked: body nearest the line (to BODY_TIE), then most of its edges matching placed ones,
# then its middle nearest the line, then (exactly in line, one behind the other) the nearer one. Of the fits at that spot (and,
# for joins that go either way round, the same join on the other side), the turn nearest the
# player's. Sets _fit_yaws (the turns that fit there) and _shown_yaw.
# {"where", "piece", "own_mid", "at_mid"}, or empty for none.
func _edge_fit(from: Vector3, to: Vector3, aimed: BuildPiece, hit_point: Vector3) -> Dictionary:
	var pieces: Dictionary = _pieces_along(from, to, aimed)
	var all_edges := []
	var sources := []
	var post_tops := []
	# (a flight of stairs reaches up to its own length from the edge it fits: aimed at the ground
	# where its body goes, the floor edge it hangs from is that far off, so it looks that much farther)
	var flight: bool = _shape_name in SnapEdges.FLIGHTS
	var extra_reach: float = _bounds.size.length() if flight else 0.0
	for piece in pieces:
		for e in _edges_of(piece):
			all_edges.append(e)
			var near_hit: bool = piece == aimed and hit_point != Vector3.INF and SnapEdges.point_segment(hit_point, e["a"], e["b"]) <= AIM_EDGE_REACH + extra_reach
			if near_hit or SnapEdges.segment_segment(from, to, e["a"], e["b"]) <= LINE_EDGE_REACH + extra_reach:
				sources.append(e)
		# (a floor also fits a corner on a post top: porches and stilt buildings)
		if _shape_name in SnapEdges.FLOORS:
			for p in SnapEdges.points_in_world(piece):
				if p["type"] == "post_top" and _near_aim(p["p"], piece == aimed, from, to, hit_point):
					post_tops.append(p)
	var extra: Array = _post_top_fits(post_tops)
	if sources.is_empty() and extra.is_empty():
		return {}
	var step_up: float = SnapEdges.vertical_step(_buildable.display_name)
	var scored := []
	var seen := {}
	for c in SnapEdges.placements(_shape_name, _shape, step_up, sources) + extra:
		var candidate: Transform3D = c["where"]
		var key := _place_key(candidate)
		if seen.has(key):
			continue
		seen[key] = true
		# (far from the line by its middle: no need to measure its body)
		var middle := candidate * _middle
		if SnapEdges.point_segment(middle, from, to) > BODY_REACH + _bounds.size.length() / 2.0:
			continue
		var body: float = SnapEdges.box_distance(candidate, _bounds, from, to)
		if body > BODY_REACH:
			continue
		scored.append({"c": c, "body": roundf(body / BODY_TIE), "middle": middle, "line": SnapEdges.point_segment(middle, from, to), "near": from.distance_to(middle)})
	if scored.is_empty():
		return {}
	var want := _turn_ref + turn
	for s in scored:
		s["matched"] = SnapEdges.matched(_shape_name, _shape, s["c"]["where"], all_edges)
		# (a flight keeps the player's turn, as pillars and beams do: the wheel says which way it
		# climbs, and it snaps where it fits that way round; only with no fit that way round does it
		# take another turn)
		s["turned"] = 0 if not flight or absf(angle_difference(_yaw((s["c"]["where"] as Transform3D).basis), want)) < 0.01 else 1
		# (and of a flight's fits as near the line: aimed at a piece's side face (a floor's edge face, not
		# its top), one on that piece's edge by the hit first, as aiming there means "at this edge"; then
		# one standing on something by its bottom edge)
		var at: Dictionary = s["c"]["at"]
		var at_face: bool = false
		if flight and aimed != null and hit_point != Vector3.INF and absf(_hit_normal.y) < 0.5 and SnapEdges.point_segment(hit_point, at["a"], at["b"]) <= AIM_EDGE_REACH:
			# (the aimed piece's edge; or, aimed exactly at the seam between two pieces' faces, the
			# neighbour's edge in line with that face too, so neither side of the seam wins by the hit)
			var seam: bool = absf(((at["a"] as Vector3) - hit_point).dot(_hit_normal)) < SEAM \
				and SnapEdges.point_segment(Vector3(hit_point.x, (at["a"] as Vector3).y, hit_point.z), at["a"], at["b"]) < SEAM
			at_face = at.get("piece") == aimed or seam
		s["face"] = 0 if at_face or not flight else 1
		s["standing"] = 0 if not flight or _flight_stands(s["c"]["where"], all_edges) else 1
	scored.sort_custom(func(a, b):
		if a["turned"] != b["turned"]:
			return a["turned"] < b["turned"]
		if a["body"] != b["body"]:
			return a["body"] < b["body"]
		if a["face"] != b["face"]:
			return a["face"] < b["face"]
		if a["standing"] != b["standing"]:
			return a["standing"] < b["standing"]
		if a["matched"] != b["matched"]:
			return a["matched"] > b["matched"]
		# (and of two exactly in line with the crosshair, one behind the other, the nearer)
		if absf(a["line"] - b["line"]) > 0.001:
			return a["line"] < b["line"]
		return a["near"] < b["near"])
	last_ranking = scored.map(func(s): return {"origin": (s["c"]["where"] as Transform3D).origin, "turned": s["turned"], "body": s["body"], "face": s["face"], "standing": s["standing"], "matched": s["matched"], "line": s["line"]})
	var best := {}
	for s in scored:
		if not _taken(s["c"]["where"], pieces):
			best = s
			break
	if best.is_empty():
		return {}
	# The turns that fit at that spot (from every edge round it, not only those near the line), and
	# the one nearest the player's
	var spot: Vector3 = best["middle"]
	var round_spot := []
	for e in all_edges:
		if SnapEdges.point_segment(spot, e["a"], e["b"]) <= _bounds.size.length():
			round_spot.append(e)
	# (the same spot: its middle there; or, for a join that goes either way round (standing on or
	# lying along an edge: a roof on a wall top, an overhang along a gable's slope), the same join on
	# the other side, next to the crosshair too)
	var joint := _joint_of(best["c"])
	var chosen: Dictionary = best["c"]
	var nearest := INF
	var tried := {}
	# (a floor's corner on a post top: every turn of the wheel fits there, the floor swinging round
	# the post top on the same corner)
	var around_post: bool = best["c"].has("pivot")
	var turns: Array = extra.filter(func(c): return (c["pivot"] as Vector3).distance_to(best["c"]["pivot"]) < 0.001 and c["corner"] == best["c"]["corner"]) if around_post \
		else SnapEdges.placements(_shape_name, _shape, step_up, round_spot)
	for c in turns:
		var candidate: Transform3D = c["where"]
		var key := _place_key(candidate)
		if tried.has(key):
			continue
		tried[key] = true
		if not around_post and (candidate * _middle).distance_to(spot) > SAME_SPOT:
			var either_way: bool = SnapEdges.RULES.get(c["own"]["type"], {}).get(c["at"]["type"], []) == [0.0, 180.0]
			if not either_way or not _same_joint(joint, _joint_of(c)):
				continue
		# (every turn there keeps its body near the crosshair's line too: a triangle turned about its
		# middle lies over the other half of its square, and a floor swung round a post top swings
		# away from where it's aimed)
		if c != best["c"] and SnapEdges.box_distance(candidate, _bounds, from, to) > BODY_REACH:
			continue
		if _taken(candidate, pieces):
			continue
		var yaw := _yaw(candidate.basis)
		if not _fit_yaws.any(func(y): return absf(angle_difference(y, yaw)) < 0.001):
			_fit_yaws.append(yaw)
		var off := absf(angle_difference(yaw, want))
		if off < nearest - 0.001:
			nearest = off
			chosen = c
	_fit_yaws.sort()
	var fit: Dictionary = chosen
	var where: Transform3D = fit["where"]
	_shown_yaw = _yaw(where.basis)
	var own: Dictionary = fit["own"]
	var at: Dictionary = fit["at"]
	return {"where": where, "piece": fit["piece"], "own_mid": where * (((own["a"] as Vector3) + (own["b"] as Vector3)) / 2.0),
		"at_mid": ((at["a"] as Vector3) + (at["b"] as Vector3)) / 2.0}


# True if a flight put at `where` stands on something: its bottom edge along a placed edge it may
# meet (see SnapEdges.RULES)
func _flight_stands(where: Transform3D, edges: Array) -> bool:
	for g in SnapEdges.of(_shape_name, _shape):
		if g["type"] != "stairs_bottom":
			continue
		var rule: Dictionary = SnapEdges.RULES.get(g["type"], {})
		var a: Vector3 = where * (g["a"] as Vector3)
		var b: Vector3 = where * (g["b"] as Vector3)
		for t in edges:
			if rule.has(t["type"]) and SnapEdges.along(a, b, t["a"], t["b"]):
				return true
	return false


# The pieces round the crosshair's line from `from` to `to` (and the aimed piece), as keys
func _pieces_along(from: Vector3, to: Vector3, aimed: BuildPiece) -> Dictionary:
	var pieces := {}
	if aimed:
		pieces[aimed] = true
	var samples := int(ceil(from.distance_to(to) / 1.5)) + 1
	# (pieces are found by their origin, which can be 2.5 m from their far edge: a Tall wall's foot)
	for i in samples + 1:
		var p := from.lerp(to, float(i) / samples)
		for piece in registry.pieces_near(p, NEAR_PIECES):
			pieces[piece] = true
	for piece in pieces.keys():
		if not is_instance_valid(piece) or (piece as BuildPiece).is_queued_for_deletion():
			pieces.erase(piece)
	return pieces


# True for a placed point that's a candidate: on the aimed piece within AIM_EDGE_REACH of the hit, or
# within LINE_EDGE_REACH of the crosshair's line, plus `size` (a pillar's or beam's own length: aimed
# at the middle of a 4 m pole's spot, the floor corner its foot goes on is 2 m from the crosshair)
func _near_aim(p: Vector3, on_aimed: bool, from: Vector3, to: Vector3, hit_point: Vector3, size := 0.0) -> bool:
	if on_aimed and hit_point != Vector3.INF and p.distance_to(hit_point) <= AIM_EDGE_REACH + size:
		return true
	return SnapEdges.point_segment(p, from, to) <= LINE_EDGE_REACH + size


# A floor with a corner on each of these post tops, at every wheel step (22.5°) against the post:
# fits like the edge fits, with the post top as their "pivot" and which corner as "corner"
func _post_top_fits(post_tops: Array) -> Array:
	var found := []
	var corners: Array = SnapCorners.of(_shape_name, _shape)
	for p in post_tops:
		var q: Vector3 = p["p"]
		var base := _yaw((p["piece"] as BuildPiece).global_basis)
		for k in 16:
			var basis := Basis(Vector3.UP, base + k * WHEEL_STEP)
			for i in corners.size():
				var c: Vector3 = corners[i]
				found.append({"where": Transform3D(basis, q - basis * c), "piece": p["piece"], "own": {"a": c, "b": c, "type": "corner"},
					"at": {"a": q, "b": q, "type": "post_top"}, "pivot": q, "corner": i})
	return found


# ---- Typed points (pillars, poles, beams: see SnapEdges.POINT_RULES) ----

# The fit chosen by aim for a point piece, at the player's own turn (the one exception to the fitting
# turns: it keeps the wheel's 22.5° steps while snapped): one of its points on a placed point the
# table allows (SnapEdges.POINT_RULES), or, for a beam, its whole line along a wall top, floor edge or
# triangle's slope that turn makes it parallel to (SnapEdges.line_placements). Candidates and ranking
# as for whole edges (see _edge_fit): placed points and edges near the aim; body within BODY_REACH of
# the crosshair's line; body nearest it, then its axis (foot to top, end to end) nearest it, then most
# of its points on placed ones, then its middle nearest it, then the nearer (each to BODY_TIE). While the crosshair stays within STICKY_SWITCH of where it snapped, it
# keeps the same point of its own on the same placed point (it turns in place there).
# {"where", "piece", "own_mid", "at_mid"}, or empty for none.
func _point_fit(from: Vector3, to: Vector3, aimed: BuildPiece, hit_point: Vector3) -> Dictionary:
	var pieces: Dictionary = _pieces_along(from, to, aimed)
	var basis := Basis(Vector3.UP, _turn_ref + turn)
	var mine: Array = SnapEdges.points_of(_shape_name, _shape)
	# (its axis, foot to top or end to end, moved to run through the middle of its body: a beam's
	# ends are on its top)
	var axis_shift := Vector3.ZERO
	if mine.size() >= 2:
		axis_shift = _bounds.get_center() - ((mine[0]["p"] as Vector3) + (mine[1]["p"] as Vector3)) / 2.0
	var all_points := []
	var candidates := []
	var size := _bounds.size.length()
	var half_size := size / 2.0
	for piece in pieces:
		var on_aimed: bool = piece == aimed
		for p in SnapEdges.points_in_world(piece):
			all_points.append(p)
			if not _near_aim(p["p"], on_aimed, from, to, hit_point, size):
				continue
			for i in mine.size():
				if p["type"] in SnapEdges.POINT_RULES.get(mine[i]["type"], []):
					var own: Vector3 = mine[i]["p"]
					candidates.append({"where": Transform3D(basis, (p["p"] as Vector3) - basis * own), "piece": piece, "own": own, "at": p["p"], "pivot": p["p"], "index": i})
		for e in _edges_of(piece):
			if not e["type"] in SnapEdges.LINE_RULES:
				continue
			var near_hit: bool = on_aimed and hit_point != Vector3.INF and SnapEdges.point_segment(hit_point, e["a"], e["b"]) <= AIM_EDGE_REACH + size
			if not near_hit and SnapEdges.segment_segment(from, to, e["a"], e["b"]) > LINE_EDGE_REACH + size:
				continue
			for where in SnapEdges.line_placements(_shape_name, _shape, basis, e):
				var line := SnapEdges.beam_line(_shape_name, _shape)
				candidates.append({"where": where, "piece": piece, "own": ((line[0] as Vector3) + (line[1] as Vector3)) / 2.0, "at": ((e["a"] as Vector3) + (e["b"] as Vector3)) / 2.0})
	var scored := []
	var seen := {}
	for c in candidates:
		var where: Transform3D = c["where"]
		var key := _place_key(where)
		if seen.has(key):
			continue
		seen[key] = true
		# (far from the line by its middle: no need to measure its body)
		var middle := where * _bounds.get_center()
		if SnapEdges.point_segment(middle, from, to) > BODY_REACH + half_size:
			continue
		var body: float = SnapEdges.box_distance(where, _bounds, from, to)
		if body > BODY_REACH or registry.duplicate_of(_shape_name, where) != null:
			continue
		var held := 0
		for m in mine:
			var at: Vector3 = where * (m["p"] as Vector3)
			if all_points.any(func(q): return (q["p"] as Vector3).distance_to(at) < 0.001):
				held += 1
		# (how near the crosshair's line passes its axis, foot to top or end to end: aimed anywhere
		# along a slender piece, the line goes through its axis, not only near its middle)
		var axis := SnapEdges.segment_segment(from, to, where * ((mine[0]["p"] as Vector3) + axis_shift), where * ((mine[1]["p"] as Vector3) + axis_shift)) if mine.size() >= 2 else 0.0
		# (and how near its placed point is to where the crosshair hits: the spot under the crosshair)
		var under := ((c["at"] as Vector3).distance_to(hit_point) if hit_point != Vector3.INF else 0.0)
		scored.append({"c": c, "body": roundf(body / BODY_TIE), "axis": roundf(axis / BODY_TIE), "held": held, "under": roundf(under / 0.25), "line": SnapEdges.point_segment(middle, from, to), "near": from.distance_to(middle)})
	if scored.is_empty():
		_stick_pivot = Vector3.INF
		return {}
	scored.sort_custom(func(a, b):
		if a["body"] != b["body"]:
			return a["body"] < b["body"]
		if a["axis"] != b["axis"]:
			return a["axis"] < b["axis"]
		if a["held"] != b["held"]:
			return a["held"] > b["held"]
		if roundf(a["line"] / 0.25) != roundf(b["line"] / 0.25):
			return a["line"] < b["line"]
		if a["under"] != b["under"]:
			return a["under"] < b["under"]
		if absf(a["line"] - b["line"]) > 0.001:
			return a["line"] < b["line"]
		return a["near"] < b["near"])
	last_ranking = scored.slice(0, 4).map(func(s): return {"origin": (s["c"]["where"] as Transform3D).origin, "body": s["body"], "axis": s["axis"], "held": s["held"], "line": s["line"], "pivot": s["c"].has("pivot")})
	var chosen: Dictionary = scored[0]["c"]
	var spot_now: Vector3 = hit_point if hit_point != Vector3.INF else to
	# (staying on its point while it turns, as long as the crosshair hasn't moved off it)
	if _stick_pivot != Vector3.INF and spot_now.distance_to(_stick_spot) <= STICKY_SWITCH:
		for s in scored:
			if s["c"].has("pivot") and (s["c"]["pivot"] as Vector3).distance_to(_stick_pivot) < 0.001 and s["c"]["index"] == _stick_index:
				chosen = s["c"]
				break
	if chosen.has("pivot"):
		if _stick_pivot == Vector3.INF or (chosen["pivot"] as Vector3).distance_to(_stick_pivot) > 0.001 or chosen["index"] != _stick_index:
			_stick_spot = spot_now
		_stick_pivot = chosen["pivot"]
		_stick_index = chosen["index"]
	else:
		_stick_pivot = Vector3.INF
	var placed: Transform3D = chosen["where"]
	return {"where": placed, "piece": chosen["piece"], "own_mid": placed * (chosen["own"] as Vector3), "at_mid": chosen["at"]}


# True if a fit at `where` is taken: an identical piece already there, or it would sink into a piece
# of its own kind among `pieces` (floors and foundations; walls and triangle walls; roof pieces: see
# SnapEdges.kind) by more than PieceOverlap.MARGIN (touching, stacking, side by side and walls meeting
# in an L don't count). Pieces of other kinds may overlap it, as designs have them do (a 45° gable
# into a 26° eave, say).
func _taken(where: Transform3D, pieces: Dictionary) -> bool:
	if registry.duplicate_of(_shape_name, where) != null:
		return true
	var mine := SnapEdges.kind(_shape_name)
	for piece in pieces:
		if is_instance_valid(piece) and SnapEdges.kind((piece as BuildPiece).shape_name) == mine and PieceOverlap.overlaps(_shape_name, _shape, where, piece):
			return true
	return false


# Where a fit's own edge lies in the world (the join): [a, b]
static func _joint_of(fit: Dictionary) -> Array:
	var where: Transform3D = fit["where"]
	return [where * (fit["own"]["a"] as Vector3), where * (fit["own"]["b"] as Vector3)]


static func _same_joint(a: Array, b: Array) -> bool:
	var near := 0.01
	return ((a[0] as Vector3).distance_to(b[0]) < near and (a[1] as Vector3).distance_to(b[1]) < near) \
		or ((a[0] as Vector3).distance_to(b[1]) < near and (a[1] as Vector3).distance_to(b[0]) < near)


# A placed piece's typed edges in the world (worked out once until pieces change)
func _edges_of(piece: BuildPiece) -> Array:
	var key := piece.get_instance_id()
	if not _edge_cache.has(key):
		_edge_cache[key] = SnapEdges.in_world(piece)
	return _edge_cache[key]


static func _place_key(where: Transform3D) -> String:
	var o := (where.origin * 1000.0).round()
	return "%d,%d,%d,%d" % [o.x, o.y, o.z, roundi(fposmod(rad_to_deg(_yaw(where.basis)), 360.0) * 10.0) % 3600]


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
	# (the next piece has the next id: its look and colour)
	if not _buildable.model_scene:
		_dress_ghost()


# ---- The ghost ----

# The preview: the piece's real look, solid, exactly as the piece it'll become: its close-up look
# (the variant the next piece's id picks, see PieceRegistry.detail_mesh; it's always within that
# look's range while placing) or its model, its own materials, and the slight colour of its own the
# piece will wear (BuildPiece.weather_tint), casting its shadow. Its placement state shows over it
# as a light tint and a thin outline (see PreviewLook and _show_red).
func _make_ghost() -> void:
	_preview = Node3D.new()
	_preview.visible = false
	_player.get_parent().add_child(_preview)
	_dress_ghost()


# The preview's looks made (again) for the next piece's id: after a piece goes down, the next one
# has another id, so another variant and colour
func _dress_ghost() -> void:
	for child in _preview.get_children():
		_preview.remove_child(child)
		child.queue_free()
	_looks.clear()
	var id: int = registry.next_id()
	if _buildable.model_scene:
		_preview.add_child(BuildPiece.fitted_model(_buildable, _shape))
	else:
		var detail := registry.detail_mesh(_shape_name, id)
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
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_looks.append(g)
		if g is MeshInstance3D and g.material_override is ShaderMaterial:
			# (as the built piece will wear it: see BuildPiece.weather)
			g.set_instance_shader_parameter("tint", BuildPiece.weather_tint(id))
			g.set_instance_shader_parameter("box_min", _bounds.position)
			g.set_instance_shader_parameter("box_max", _bounds.end)
			g.set_instance_shader_parameter("frame_offset", _shape.get("frame_offset", 0.0))
	PreviewLook.apply(_preview, PreviewLook.State.INVALID if _red else PreviewLook.State.VALID)


# Its placement state over its real look: red where it can't go, a soft white glow where it can
func _show_red(on: bool) -> void:
	if on == _red:
		return
	_red = on
	PreviewLook.apply(_preview, PreviewLook.State.INVALID if on else PreviewLook.State.VALID)


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
	# (a pillar, pole or beam also shows the target's 1 m spots it may take)
	if not points.is_empty() and point_piece():
		for p: Vector3 in SnapCorners.post_spots_in_world(_target):
			if not points.any(func(q): return (q as Vector3).distance_to(p) < MEET):
				points.append(p)
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
