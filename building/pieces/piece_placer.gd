class_name PiecePlacer
extends Node
## Placing building pieces, Valheim-style: the see-through preview snaps to the snap point of a
## placed piece nearest where the crosshair points (shown as small dots, the one in use as a
## bigger bright one), or otherwise goes freely wherever the crosshair is, on the ground or on
## other pieces, and may float (there's no support yet). It may overlap other pieces; it's red only
## where it really can't go (see _check). It keeps placing the same piece until cancelled. Also
## demolishes, for a full refund: with the middle mouse button held, the piece under the crosshair
## glows red and comes down on release; or holding X on a piece long enough takes it down. Either
## way, placing carries on afterwards as it was.
##
## Snapping follows the player (see _snap): the target is the snap point nearest the crosshair's
## spot (within TARGET_RADIUS of it, or close to the crosshair's line on screen), never a farther
## one that would fit better. The piece's attach point (Q; "any" picks one) goes exactly on it,
## first lined up with the piece it's snapping to. From there its angle is the player's, to any
## angle, snapped or free, always about its attach point (the target point; free, where it stands),
## so a snapped piece stays attached there: the mouse wheel turns it round the upright, Shift +
## wheel tilts it toward or away from the player, Ctrl + wheel tips it left or right as the player
## sees it, 5° a notch (1° with Alt); R puts it back to its starting alignment. Furniture only
## turns, freely, on floors and off. Page Up / Page Down raise and lower any piece, snapped
## or free, in 0.25 m steps (0.05 m with Alt); Backspace resets that. The height and angles stay
## for the next piece of the same kind, and carry over when you switch pieces from the build menu
## while placing.
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
## A snap point is the target if it's within this far of the crosshair's spot, or this close to the
## crosshair's line on screen (radians: about 12 cm off it 4 m away); the nearest wins
const TARGET_RADIUS := 0.5
const TARGET_SCREEN := 0.03
## Snap points of pieces this close to the crosshair's spot are considered (and shown)
const SNAP_SEARCH := 9.0
## How far a piece may reach into the ground before it's refused (foundations go in freely)
const GROUND_TOLERANCE := 0.4
## With snapping off, how far an arrow key nudges the piece (with Shift: the fine step)
const NUDGE_STEP := 0.05
const NUDGE_FINE_STEP := 0.01
## Snap point dots: shown within this far of the crosshair ("Nearby", the default), or this far
## ("All"); how big they are, and how much bigger the one in use is
const MARKER_REACH := 3.0
const MARKER_REACH_ALL := 9.0
const MARKER_RADIUS := 0.024
const ACTIVE_MARKER_SCALE := 2.5
const MAX_MARKERS := 96
## Turning, tilting and tipping: one wheel notch, and with Alt held (see handle_input)
const WHEEL_STEP := PI / 36.0
const FINE_WHEEL_STEP := PI / 180.0
## How far walls, posts, pillars and fences may sink into the ground, and other pieces (foundations
## go in freely)
const SINK_TOLERANCE := 1.5
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
const MARKER_COLOR := Color(0.55, 0.85, 1.0, 0.25)
const ACTIVE_MARKER_COLOR := Color(1.0, 0.92, 0.6, 0.95)
const MAX_OVERLAPS := 16
## The physics layers people are on: the player (1) and settlers (Settler.LAYER)
const PERSON_LAYERS := 1 | 4

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
# How far the piece is raised (or lowered) from where it would go, and how it's turned about its
# attach point (see _angled): round the upright (turn), forward and back (tilt), side to side (tip),
# from its starting alignment, and which piece those are for: they're kept from one placement to the
# next of the same piece
var _height := 0.0
var _snap_turn := 0.0
var _tilt := 0.0
var _tip := 0.0
# With snapping off, how far the arrow keys have nudged the piece (world space; Backspace clears it)
var _nudge := Vector3.ZERO
## Which of its own snap points attaches (0: any; see _own_sockets), and the choices Q steps through
var _attach := 0
var _attach_choices: Array = []
## The snap points around the target, this frame (see _anchor_count), and where the crosshair's
## line meets something (or ends), this frame
var _pool: Array = []
var _aim_at := Vector3.ZERO
## How near (m) a piece's own snap point must come to a placed one to count as resting on it
const ANCHOR_DISTANCE := 0.03
var _kept_for := ""
var _where := Transform3D.IDENTITY
# The piece it's snapped to (null when placed freely), which of its snap points, and where that is
var _target: BuildPiece
var _snap_key := ""
var _target_at := Vector3.ZERO
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
	# (what furniture snapped to last time says nothing about this piece)
	_furniture_snap = ""
	_problem = "Point at the ground or a piece"
	if keep:
		# (the attach point chosen is the old piece's own)
		if piece.resource_path != _kept_for:
			_attach = 0
		_kept_for = piece.resource_path
	elif piece.resource_path != _kept_for:
		_height = 0.0
		_snap_turn = 0.0
		_tilt = 0.0
		_tip = 0.0
		_nudge = Vector3.ZERO
		_attach = 0
		_kept_for = piece.resource_path
	_attach_choices = _make_attach_choices()
	if _attach > _attach_choices.size():
		_attach = 0
	_ghost = StandardMaterial3D.new()
	_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview = Node3D.new()
	if piece.model_scene:
		# The piece's own model, see-through
		var model := BuildPiece.fitted_model(piece, _shape)
		for found in model.find_children("*", "MeshInstance3D", true, false):
			(found as MeshInstance3D).material_override = _ghost
			(found as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_preview.add_child(model)
	else:
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
			_nudge = Vector3.ZERO
			return true
		# With snapping off: the arrow keys nudge the piece a little, relative to the camera
		# (repeating while held)
		if not snapping_now() and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			var camera: Camera3D = _player.camera
			var forward := -camera.global_basis.z
			forward.y = 0.0
			forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
			var right := forward.cross(Vector3.UP)
			var step := NUDGE_FINE_STEP if event.shift_pressed else NUDGE_STEP
			match event.keycode:
				KEY_UP:
					_nudge += forward * step
				KEY_DOWN:
					_nudge -= forward * step
				KEY_RIGHT:
					_nudge += right * step
				KEY_LEFT:
					_nudge -= right * step
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		# Q: which of its own snap points attaches (snapping on)
		if event.keycode == KEY_Q and snapping_now() and _attach_choices.size() > 1:
			_cycle_attach()
			return true
		# R: back to its starting alignment (no turn, tilt or tip)
		if event.keycode == KEY_R:
			_snap_turn = 0.0
			_tilt = 0.0
			_tip = 0.0
			return true
		# Finish or cancel this before putting the hammer away (Tab opens the build menu to switch)
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var up := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			# The wheel turns it round the upright, Shift + wheel tilts it forward and back, Ctrl +
			# wheel tips it side to side: 5° a notch, 1° with Alt, always about its attach point
			# (furniture only turns: it stands on the floor)
			var step := (FINE_WHEEL_STEP if event.alt_pressed else WHEEL_STEP) * up
			if event.shift_pressed and not is_furniture():
				_tilt = wrapf(_tilt + step, -PI, PI)
			elif event.ctrl_pressed and not is_furniture():
				_tip = wrapf(_tip + step, -PI, PI)
			else:
				_snap_turn = wrapf(_snap_turn + step, 0.0, TAU)
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
		if not is_zero_approx(_height):
			details.append(offset)
	else:
		details.append("Snap off" if not snapping_now() else "Free")
		details.append("Height " + offset)
		if not snapping_now():
			controls.append(["Nudge", "Arrows"])
	# Its angles, always shown ("Turn 37° · Tilt 0° · Tip 0°"; furniture only turns)
	var angles := "Turn %d°" % (roundi(rad_to_deg(_snap_turn)) % 360)
	if not is_furniture():
		angles += " · Tilt %d° · Tip %d°" % [roundi(rad_to_deg(_tilt)), roundi(rad_to_deg(_tip))]
	details.append(angles)
	controls.append(["Turn 5° / 1°", "Wheel / Alt+Wheel"])
	if not is_furniture():
		controls.append(["Tilt / Tip", "Shift / Ctrl+Wheel"])
	controls.append(["Reset angle", "R"])
	# Which of its own snap points attaches (Q)
	if snapping_now() and _attach_choices.size() > 1:
		details.append("Attach: " + attach_label())
		controls.append(["Attach point", "Q"])
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
	var timing := SpikeLog.begin()
	_follow_crosshair()
	SpikeLog.end("placing: following the crosshair (snap search)", timing)


func _follow_crosshair() -> void:
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
		var nudged: Vector3 = _nudge if not snapping_now() else Vector3.ZERO
		# Turned, tilted and tipped about where it stands
		var spot: Vector3 = ground["position"] + Vector3.UP * lift + nudged
		_where = _angled(Transform3D(Basis.IDENTITY, spot), spot)
		_problem = _check(_where, null)
	else:
		_problem = _check(_where, _target)
	_preview.visible = true
	_preview.global_transform = _where
	_ghost.albedo_color = GOOD_COLOR if _problem.is_empty() else BAD_COLOR
	_update_markers(end)


# Snapping follows where the player points. The target is the snap point nearest the crosshair's
# spot: within TARGET_RADIUS of it, or within TARGET_SCREEN of the crosshair's line on screen (a
# pillar top the line passes just over), not behind the spot by more than TARGET_RADIUS. Nothing
# about how well the piece would fit elsewhere moves it to a farther point. The only thing that
# passes over the nearest is a point the piece can't attach to at all (no snap rule joins them, or,
# lined up, an edge that doesn't meet whole). Then see _snapped_at for where the piece goes.
func _snap(from: Vector3, end: Vector3) -> bool:
	var middle := _attach_is_middle()
	var wanted := PieceShapes.targets_for(_own_sockets())
	var options := []
	_aim_at = end
	var ray := end - from
	var length := ray.length()
	if length < 0.01:
		return false
	var dir := ray / length
	for piece in registry.pieces_near(end, SNAP_SEARCH):
		var sockets: Array = piece.world_sockets()
		for i in sockets.size():
			var socket: Dictionary = sockets[i]
			# (the piece's middle may go on any snap point)
			if not middle and not wanted.has(socket["type"]):
				continue
			var spot: Vector3 = socket["position"]
			var along := (spot - from).dot(dir)
			if along < 0.8 or along > length + TARGET_RADIUS:
				continue
			var off_line := spot.distance_to(from + dir * along)
			var off_spot := spot.distance_to(end)
			if off_spot > TARGET_RADIUS and off_line > along * TARGET_SCREEN:
				continue
			options.append({"gap": minf(off_spot, off_line), "piece": piece, "socket": socket, "key": "%d:%d" % [piece.piece_id, i]})
	if options.is_empty():
		return false
	options.sort_custom(func(a, b): return a["gap"] < b["gap"])
	for option in options:
		var where = _snapped_at(option)
		if where != null:
			_snap_key = option["key"]
			_target = option["piece"]
			_target_at = option["socket"]["position"]
			_where = where
			return true
	return false


# Where the piece goes on a target snap point, or null if it can't attach there at all. Its attach
# point goes exactly on the target, lined up with the piece it's snapping to:
#   - "any": of the ways one of its own points meets the target (see PieceShapes.fits), the one
#     reaching toward where the crosshair is (a roof on a wall top rises inward when you aim
#     inside); hip corners and hip ends ("anchored") first take the way that lands the most of
#     their own points on matching ones round the target, as they fit many ways at one point.
#     Square pieces (floors, foundations) start with the plank direction of a square piece they
#     snap to.
#   - a chosen point (Q): the same, with only that point.
#   - "middle": the piece's middle on the target, turned like the piece it's snapping to.
# Then it's turned about the target point by the player's turn (wheel, Alt + wheel, R), so it
# stays attached there, and raised or lowered by the height offset. Whole edges (triangle pieces)
# must meet only while its turn is a multiple of 90°; turned otherwise it just sits on the point.
func _snapped_at(option: Dictionary):
	var socket: Dictionary = option["socket"]
	var pivot: Vector3 = socket["position"]
	var neighbour: BuildPiece = option["piece"]
	var base: Transform3D
	if _attach_is_middle():
		var turned := Basis(Vector3.UP, _yaw(neighbour.global_basis))
		base = Transform3D(turned, pivot - turned * _middle_point())
	else:
		var fits := _fits(socket, _aligned())
		if fits.is_empty():
			return null
		var centre := _bounds.get_center()
		var scores := {}
		if _shape.get("anchored", false):
			_gather_pool(pivot)
			for where in fits:
				scores[where] = _anchor_count(where)
		base = fits[0]
		for where in fits:
			var more: bool = scores.get(where, 0) > scores.get(base, 0)
			var same: bool = scores.get(where, 0) == scores.get(base, 0)
			if more or (same and (where * centre).distance_to(_aim_at) < (base * centre).distance_to(_aim_at) - 0.01):
				base = where
		if _is_square(_shape) and _is_square(neighbour.shape_def()) and not neighbour.shape_def().get("slender", false) and not _shape.get("slender", false):
			# Start with the neighbour's plank direction (turning a square piece about its own middle
			# by quarter turns doesn't move it)
			var offset := wrapf(_yaw(neighbour.global_basis) - _yaw(base.basis), -PI, PI)
			base = _turned_about(base, base * centre, roundf(offset / (PI / 2.0)) * (PI / 2.0))
	return Transform3D(Basis.IDENTITY, Vector3.UP * _height) * _angled(base, pivot)


# A placement turned, tilted and tipped about `pivot` (its attach point) by the player's angles:
# turned round the upright first, then leaned as the player sees it, whatever way the piece lies:
# tilted about the view's level sideways line (the top leaning away from the player as the angle
# grows, so a beam you face along changes its slope) and tipped about the view's level forward line
# (the top leaning to the player's right)
func _angled(where: Transform3D, pivot: Vector3) -> Transform3D:
	var camera: Camera3D = _player.camera
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	# (about the sideways line, a positive angle brings the top toward the player: hence -_tilt;
	# about the forward line, a positive angle takes it to the right)
	var lean := Basis(right, -_tilt) * Basis(forward, _tip)
	var spin := lean * Basis(Vector3.UP, _snap_turn)
	return Transform3D(Basis.IDENTITY, pivot) * Transform3D(spin, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot) * where


# True while the piece happens to be lined up: turned a multiple of 90°, not tilted or tipped
# (whole edges must meet then; see _snapped_at)
func _aligned() -> bool:
	var square := deg_to_rad(0.5)
	return absf(wrapf(_snap_turn, -PI / 4.0, PI / 4.0)) < square and absf(_tilt) < square and absf(_tip) < square


# The snap points round a spot (for _anchor_count)
func _gather_pool(spot: Vector3) -> void:
	_pool.clear()
	for piece in registry.pieces_near(spot, SNAP_SEARCH):
		for socket in piece.world_sockets():
			if (socket["position"] as Vector3).distance_to(spot) < 4.0:
				_pool.append(socket)


# ---- Choosing which of its own snap points attaches (Q) ----
#
# A piece's own snap points, grouped by where they are on it (several types at one spot are one
# choice; an edge's points, every EDGE_STEP along it, are one choice: the whole edge). Q steps
# through them, after "any" (every snap point, as normal), and every piece has a "middle" (if no
# snap point of its own is there, its middle, which may go on any snap point), so Q to the middle
# and then turning turns it about its centre. The choice sticks while the same piece is picked
# again (see begin).

## The snap points of its own the piece may attach by right now: all of them, or the chosen group's
## (none for a "middle" that isn't one of its snap points; see _attach_is_middle)
func _own_sockets() -> Array:
	var all: Array = _shape["sockets"]
	if _attach <= 0 or _attach > _attach_choices.size():
		return all
	var chosen: Array = _attach_choices[_attach - 1]["indices"]
	return chosen.map(func(i): return all[i])


# True while the attach choice is the piece's own middle (not one of its snap points)
func _attach_is_middle() -> bool:
	return _attach > 0 and _attach <= _attach_choices.size() and _attach_choices[_attach - 1].get("middle", false)


# The piece's middle, in its own space: halfway between a beam's ends (a diagonal's box sits a hair
# off-centre; see PieceShapes._diagonal_beam), otherwise the middle of its box
func _middle_point() -> Vector3:
	var ends: Array = _shape["sockets"].filter(func(s): return s["type"] == "beam_end")
	if ends.size() == 2:
		return ((ends[0]["position"] as Vector3) + (ends[1]["position"] as Vector3)) / 2.0
	return _bounds.get_center()


## What the attach choice is called in the placement panel
func attach_label() -> String:
	if _attach <= 0 or _attach > _attach_choices.size():
		return "any"
	return _attach_choices[_attach - 1]["label"]


## Q: the next attach point (after the last, back to "any")
func _cycle_attach() -> void:
	if _attach_choices.size() < 2:
		return
	_attach = (_attach + 1) % (_attach_choices.size() + 1)
	_snap_key = ""


# The piece's attach choices: [{"label", "indices" (into its snap points), "at"}], in order along
# it (beams: end A, middle, end B)
func _make_attach_choices() -> Array:
	if is_furniture():
		return []
	var sockets: Array = _shape["sockets"]
	var groups := {}
	var order := []
	for i in sockets.size():
		var s: Dictionary = sockets[i]
		var key := ""
		var at: Vector3 = s["position"]
		var edge := s.has("edge_dir")
		if edge:
			var start: Vector3 = at - (s["edge_dir"] as Vector3) * float(s["edge_t"])
			key = "e%s%s" % [start.snapped(Vector3.ONE * 0.01), (s["edge_dir"] as Vector3).snapped(Vector3.ONE * 0.01)]
			at = start + (s["edge_dir"] as Vector3) * float(s["edge_len"]) / 2.0
		else:
			key = "p%s" % at.snapped(Vector3.ONE * 0.01)
		if not groups.has(key):
			groups[key] = {"indices": [], "at": at, "edge": edge, "types": {}}
			order.append(key)
		groups[key]["indices"].append(i)
		groups[key]["types"][s["type"]] = true
	var choices: Array = order.map(func(key): return groups[key])
	choices.sort_custom(func(a, b):
		var p: Vector3 = a["at"]
		var q: Vector3 = b["at"]
		if absf(p.x - q.x) > 0.01:
			return p.x < q.x
		if absf(p.y - q.y) > 0.01:
			return p.y < q.y
		return p.z < q.z)
	var box := PieceShapes.bounds_of(_shape)
	var middle := box.get_center()
	var ends_named := 0
	var used := {}
	for choice in choices:
		var types: Dictionary = choice["types"]
		var at: Vector3 = choice["at"]
		var label := ""
		if types.has("beam_end"):
			label = "end A" if ends_named == 0 else "end B"
			ends_named += 1
		elif types.keys().any(func(t): return (t as String).begins_with("beam_mid")):
			label = "middle"
		else:
			var words := []
			if at.y <= box.position.y + 0.05:
				words.append("bottom")
			elif at.y >= box.end.y - 0.05:
				words.append("top")
			if at.x < middle.x - 0.1:
				words.append("left")
			elif at.x > middle.x + 0.1:
				words.append("right")
			if at.z > middle.z + 0.1:
				words.append("front")
			elif at.z < middle.z - 0.1:
				words.append("back")
			label = " ".join(words) if not words.is_empty() else "middle"
			if choice["edge"]:
				label = label + " edge"
		var count: int = used.get(label, 0) + 1
		used[label] = count
		choice["label"] = label if count == 1 else "%s %d" % [label, count]
	# Its middle, where none of its own snap points is (to turn it about its centre)
	if not used.has("middle") and not choices.is_empty():
		choices.append({"label": "middle", "indices": [], "at": middle, "edge": false, "types": {}, "middle": true})
	return choices


# How many of the piece's own snap points, put here, land on a placed snap point they fit (from
# this frame's _pool; facings aside)
func _anchor_count(where: Transform3D) -> int:
	var count := 0
	for own in _shape["sockets"]:
		var rules: Dictionary = PieceShapes.SNAP_RULES.get(own["type"], {})
		if rules.is_empty():
			continue
		var at: Vector3 = where * (own["position"] as Vector3)
		for placed in _pool:
			if rules.has(placed["type"]) and at.distance_to(placed["position"]) < ANCHOR_DISTANCE:
				count += 1
				break
	return count


# A placement turned about an upright line through `pivot`
static func _turned_about(where: Transform3D, pivot: Vector3, turn: float) -> Transform3D:
	if is_zero_approx(turn):
		return where
	var spin := Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, pivot) * spin * Transform3D(Basis.IDENTITY, -pivot) * where


# True for a piece that looks the same turned 90° (square floors and foundations, pillars, poles)
static func _is_square(def: Dictionary) -> bool:
	var symmetry: float = def.get("symmetry", 0.0)
	return symmetry > 0.0 and absf(symmetry - PI / 2.0) < 0.001


static func _yaw(basis: Basis) -> float:
	return atan2(basis.z.x, basis.z.z)


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
	# Turned freely (wheel 5°, Alt + wheel 1°), on a floor counted from the floor's own facing
	var spot := furniture_spot(hit, far_point, _bounds, _shape.get("backs_to_wall", false), 0, _snap_turn, [], _shape.get("wall_mount", 0.0), true)
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
## `quarter_turns` 90° steps from the floor's own facing (or, with `free_on_floor`, `free_turn` from
## it, to any angle: furniture placed with the hammer), and if it `backs` and a wall is close behind
## it, flush against that wall; otherwise it's turned `free_turn`. `bounds` is its own box (its back
## is -Z). Returns {"where", "support" (what it stands on), "on_floor", "normal", "snap" ("On
## grid", "Against wall" or "")}, or empty if there's nothing to stand on.
func furniture_spot(hit: Dictionary, far_point: Vector3, bounds: AABB, backs: bool, quarter_turns: int, free_turn: float, skip: Array[RID], mount := 0.0, free_on_floor := false) -> Dictionary:
	var camera: Camera3D = _player.camera
	var toward := (camera.global_position - far_point).normalized()
	# Aimed at a wall's face: furniture that backs onto walls stands (or, wall-mounted, hangs)
	# flush against that face, on the side aimed at
	if (backs or mount > 0.0) and snapping_now() and not hit.is_empty() and _is_wall_face(hit):
		var on_wall := _against_wall_face(hit, bounds, mount, skip)
		if not on_wall.is_empty():
			return on_wall
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
		yaw = base_yaw + (free_turn if free_on_floor else quarter_turns * PI / 2.0)
		if floor_piece:
			var local := floor_piece.global_transform.affine_inverse() * spot
			local.x = snappedf(local.x, FURNITURE_GRID)
			local.z = snappedf(local.z, FURNITURE_GRID)
			spot = floor_piece.global_transform * local
			spot.y = support["position"].y
			snap = "On grid"
	var where := Transform3D(Basis(Vector3.UP, yaw), spot)
	if (backs or mount > 0.0) and snapping_now():
		var backed := _backed_to_wall(where, bounds, skip)
		if backed != where:
			where = backed
			snap = "Against wall"
			# Wall-mounted: hung on the wall it backed onto, not standing on the floor
			if mount > 0.0:
				where.origin.y += mount
				snap = "On wall"
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


# True if a ray hit is on an upright face of a building piece that isn't furniture (a wall)
func _is_wall_face(hit: Dictionary) -> bool:
	var other: Object = hit.get("collider")
	return other is BuildPiece and not other.is_furniture() and not other.is_ghost() and absf((hit["normal"] as Vector3).y) < 0.3


# Furniture against the wall face a ray hit: facing out of it, its back flush on the face (just off
# it), slid along the wall on FURNITURE_GRID in the wall's own frame. Standing furniture rests on
# the floor under it (on the side aimed at); wall-mounted furniture (`mount` > 0) hangs with its
# bottom `mount` above the wall's foot. Empty if standing furniture finds no floor there.
func _against_wall_face(hit: Dictionary, bounds: AABB, mount: float, skip: Array[RID]) -> Dictionary:
	var wall: BuildPiece = hit["collider"]
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	normal = normal.normalized()
	var face: Vector3 = hit["position"]
	# Along the wall, on the grid (its own frame), staying on the face aimed at
	var local := wall.global_transform.affine_inverse() * face
	local.x = snappedf(local.x, FURNITURE_GRID)
	var along := wall.global_transform * local
	face += (along - face) - normal * (along - face).dot(normal)
	var y: float
	var support = null
	if mount > 0.0:
		y = wall.global_position.y + mount
	else:
		var under := _support_under(face + normal * 0.3, skip)
		if under.is_empty():
			return {}
		y = under["position"].y
		support = under["collider"]
	var origin := face + normal * (-bounds.position.z + 0.005)
	origin.y = y
	var where := Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z)), origin)
	return {"where": where, "support": support if support else wall, "on_floor": support is BuildPiece, "normal": Vector3.UP, "snap": "On wall" if mount > 0.0 else "Against wall"}


# Slides furniture back (along its -Z) until its back touches a wall close behind it, or returns
# it as it was if there's none within WALL_BACK_REACH. The rays start at its front, so a spot that
# begins inside a wall still finds the wall's near face (and comes out on that side).
func _backed_to_wall(where: Transform3D, bounds: AABB, skip: Array[RID]) -> Transform3D:
	var space := _player.get_world_3d().direct_space_state
	var back := -where.basis.z
	var depth := -bounds.position.z
	var front := maxf(bounds.end.z, 0.0)
	var nearest := INF
	for height: float in [0.3, 0.9]:
		var from := where.origin + Vector3.UP * height - back * front
		var query := PhysicsRayQueryParameters3D.create(from, from + back * (front + depth + WALL_BACK_REACH))
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
	return Transform3D(where.basis, where.origin + back * (nearest - front - depth - 0.005))


# Every way this piece fits a placed snap point (see PieceShapes.fits), the likeliest first. Stairs
# can meet an edge by their top or their bottom: an edge above your eyes gets their top (stairs
# coming down to you from a raised floor), one below gets their bottom (stairs going up from it).
# `whole_edges`: edges must meet whole (only while the piece is lined up; see _snapped_at).
func _fits(socket: Dictionary, whole_edges := true) -> Array:
	var own: Array = _own_sockets()
	if (socket["position"] as Vector3).y > _player.camera.global_position.y:
		own = own.filter(func(s): return s["type"] == "stairs_top") + own.filter(func(s): return s["type"] != "stairs_top")
	return PieceShapes.fits(own, socket, _shape["symmetry"], whole_edges)


# Why the piece can't go here, or empty if it can. Pieces and furniture may overlap or clip into
# other pieces, furniture, trees and rocks, snapped or not. Only these stop it:
#   - someone standing inside it, or an identical piece already in its place (see blocked_reason)
#   - reaching too far into the ground: walls, posts, pillars and fences SINK_TOLERANCE, anything
#     else GROUND_TOLERANCE (foundations go in as deep as they like)
# A piece that lands in no plot places normally, belonging to none.
func _check(where: Transform3D, _target: BuildPiece) -> String:
	var reason := blocked_reason(_buildable.shape, where)
	if not reason.is_empty():
		return reason
	if _into_ground(where) > (SINK_TOLERANCE if _sinks(_buildable.shape) else GROUND_TOLERANCE):
		return "Too far into the ground"
	return ""


# True for pieces that may sink deep into the ground: walls (any kind, curved too), posts, pillars,
# fences and railings
static func _sinks(shape: String) -> bool:
	for word in ["wall", "doorway", "window", "pillar", "pole", "fence", "railing"]:
		if shape.contains(word):
			return true
	return false


# How deep (m) the bottom of the piece put here reaches below the ground at its deepest (its box's
# bottom corners and middle; 0 if it's all above), or 0 for a foundation, which is meant to go in
func _into_ground(where: Transform3D) -> float:
	if _shape.get("free_lift", 0.0) > 0.0 or _buildable.shape.contains("foundation"):
		return 0.0
	var valley = get_tree().get_first_node_in_group("valley")
	if valley == null or not valley.has_heights():
		return 0.0
	var box := _bounds
	var y := box.position.y
	var deepest := 0.0
	for p in [Vector3(box.position.x, y, box.position.z), Vector3(box.end.x, y, box.position.z), Vector3(box.position.x, y, box.end.z), Vector3(box.end.x, y, box.end.z), Vector3(box.get_center().x, y, box.get_center().z)]:
		var at: Vector3 = where * p
		deepest = maxf(deepest, Plot.ground_at(_player, at.x, at.z) - at.y)
	return deepest


## Why a piece of this shape can't go here, or empty if it can (Valheim-style: overlapping
## anything is fine):
##   - you or a settler would be inside it: "You're in the way" / "Someone's in the way"
##   - an identical piece is already there (within DUPLICATE_DISTANCE and DUPLICATE_TURN, allowing
##     for the shape's symmetry): "Already placed"
## `ignore` is a piece that doesn't count as the duplicate (the one being moved, say).
func blocked_reason(shape_name: String, where: Transform3D, ignore: BuildPiece = null) -> String:
	var someone := person_inside(shape_name, where)
	if someone == _player:
		return "You're in the way"
	if someone:
		return "Someone's in the way"
	var twin := registry.duplicate_of(shape_name, where, ignore)
	if twin:
		return "Already placed" + (": build its ghost instead" if twin.is_ghost() else "")
	return ""


## You or a settler, if either would be inside a piece of this shape put here (its solid parts,
## shrunk a little, so standing against it is fine), or null
func person_inside(shape_name: String, where: Transform3D) -> Object:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PERSON_LAYERS
	for part in _test_parts_of(shape_name):
		query.shape = part["shape"]
		query.transform = where * (part["transform"] as Transform3D)
		for found in space.intersect_shape(query, MAX_OVERLAPS):
			var other: Object = found["collider"]
			if other == _player or other is Settler:
				return other
	return null


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
	cost = _player.pay(cost)
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


## You or a settler, if either would be inside a placed piece put at `where` (moving a plot,
## building a ghost), or null. Overlapping anything else is fine.
func piece_blocked(piece: BuildPiece, where: Transform3D, _skip: Array[RID] = []) -> Object:
	return person_inside(piece.buildable.shape, where)


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
	dot.radius = MARKER_RADIUS
	dot.height = MARKER_RADIUS * 2.0
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


# Dots on the snap points this piece could attach to, as the Snap points setting says (see
# GameSettings.snap_points): "nearby" (the default) shows those within MARKER_REACH of the
# crosshair as small faint dots, "all" those within MARKER_REACH_ALL, "hidden" none. The one it's
# snapped to always shows, as a small brighter dot.
func _update_markers(end: Vector3) -> void:
	var used := 0
	# The target snap point (what the piece is attached to) as a bigger bright dot, always shown
	var active := _target_at if _target else Vector3.INF
	if active != Vector3.INF:
		_show_marker(used, active, true)
		used += 1
	var reach := 0.0
	match GameSettings.snap_points:
		"nearby":
			reach = MARKER_REACH
		"all":
			reach = MARKER_REACH_ALL
	if reach > 0.0:
		var wanted := PieceShapes.targets_for(_own_sockets())
		for piece in registry.pieces_near(end, maxf(reach, SNAP_SEARCH)):
			for socket in piece.world_sockets():
				if used >= MAX_MARKERS or not wanted.has(socket["type"]):
					continue
				var spot: Vector3 = socket["position"]
				if spot.distance_to(end) > reach or spot.distance_to(active) < 0.01:
					continue
				_show_marker(used, spot, false)
				used += 1
	for i in range(used, _markers.size()):
		_markers[i].visible = false


func _show_marker(index: int, spot: Vector3, active: bool) -> void:
	var marker := _markers[index]
	marker.global_position = spot
	marker.scale = Vector3.ONE * (ACTIVE_MARKER_SCALE if active else 1.0)
	marker.material_override = _active_material if active else _marker_material
	marker.visible = true


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
