extends Node
## The snapping regression test: run headless after any change to building, snapping or placement
## code (CLAUDE.md), and fix any failure before reporting:
##
##     godot --headless --path . res://tests/snap_regression.tscn --quit-after 40000
##
## It opens the world (a fresh one: nothing is loaded or saved), finds flat open ground, puts down
## what each case needs, and places pieces through the real placer (ValheimPlacer) the way a player
## does: the camera pointed at the spot (the real crosshair, followed by the placer's own physics
## frames) and real input events sent through the input system (the mouse wheel, and Shift held
## down). It never sets the turn or an aim point itself: to turn the piece it sends wheel notches.
## Each check prints "SNAPTEST PASS" or "SNAPTEST FAIL" with what it measured; the last line is the
## summary, and the exit code is the number of failures (0: all passed).

const WORLD := "res://world/world.tscn"
## How close counts as exactly there (m), and as exactly that angle (degrees)
const EXACT := 0.01
const EXACT_TURN := 0.5
## The controls row while placing a building piece, and furniture (or a workbench, chest...), exactly
const CONTROL_KEYS := ["LMB", "Wheel", "PgUp/PgDn", "Hold Shift", "MMB", "RMB"]
const FURNITURE_KEYS := ["LMB", "Wheel", "Hold Shift", "MMB", "RMB"]

var player: Node
var pp: ValheimPlacer
var bp: BuildPlacer
var registry: PieceRegistry
var O := Vector3.ZERO
# One storey, as measured (see _case_storey)
var storey := PieceShapes.STOREY
var passed := 0
var failed := 0


## The user's bug snapshots (F9) at their raised floor: each one's exact camera is tested on every
## run (see _case_user_snapshots)
const SNAPSHOTS := ["res://tests/fixtures/stairs_snapshots/snap_2026-11-10_20-22-44.json", "res://tests/fixtures/stairs_snapshots/snap_2026-11-10_20-25-14.json"]

# A camera held exactly somewhere (a snapshot's), every frame, before the placer reads it
var _hold_camera := false
var _camera_at := Transform3D.IDENTITY


func _ready() -> void:
	# (before the placer's own physics step, which reads the camera)
	process_physics_priority = -100000
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if _hold_camera and player and is_instance_valid(player):
		player.camera.global_transform = _camera_at


func _process(_delta: float) -> void:
	if _hold_camera and player and is_instance_valid(player):
		player.camera.global_transform = _camera_at


func _run() -> void:
	var world: Node = load(WORLD).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for i in 3000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player:
			break
	await _frames(30)
	DevCheats.freebuild = true
	player.set_physics_process(false)
	player._on_held_changed("Hammer")
	bp = player._placer
	pp = bp._pieces
	registry = bp.registry
	if not _find_spot():
		_check("found flat open ground", false, "none near the start")
		_finish()
		return
	# (-- --stairs-grid-shots, in a window: only the stairs grid build, with its pictures)
	if "--stairs-grid-shots" in OS.get_cmdline_user_args():
		await _case_stairs_grid(DisplayServer.get_name() != "headless")
		_finish()
		return
	# (-- --grid-standard-shot, in a window: only the grid standard test build, with its picture)
	if "--grid-standard-shot" in OS.get_cmdline_user_args():
		await _grid_standard_shot()
		_finish()
		return
	# (-- --templates-grid-shot, in a window: only the built-in templates laid out, with their picture)
	if "--templates-grid-shot" in OS.get_cmdline_user_args():
		await _templates_grid_shot()
		_finish()
		return
	# (-- --template-joints: only the built-in templates' joint audit)
	if "--template-joints" in OS.get_cmdline_user_args():
		await _case_template_joints()
		_finish()
		return
	await _case_floor_beside()
	await _case_hole()
	await _case_wall_edge()
	await _case_doorway()
	await _case_roof()
	await _case_pole_and_beam()
	await _case_storey()
	await _case_stairs()
	await _case_foundation_height()
	await _case_flight_joints()
	await _case_raised_floor()
	await _case_removed_neighbour()
	await _case_stair_pairing()
	await _case_stairs_grid()
	await _case_collision_matches_look()
	await _case_grid_saves()
	await _case_template_joints()
	await _case_common_joins()
	await _case_stair_paths()
	await _case_pillar_fan()
	await _case_shift()
	await _case_floor_on_floor()
	var half := PieceShapes.HALF_HEIGHT
	await _case_turning("a half wall on top of a half wall", "structure/wall_half_2", "structure/wall_half_2", Vector3(0.6, half + 1.4, 3.2), Vector3(0.3, half, 0.0), Vector3(0, half, 0))
	await _case_turning("a wall beside a wall", "structure/wall", "structure/wall", Vector3(3.6, 1.7, 3.2), Vector3(1.9, -0.03, 0.12), Vector3(2, 0, 0))
	await _case_turning("a floor beside a floor", "structure/floor", "structure/floor", Vector3(0.3, 1.7, 5.0), Vector3(0.1, -0.03, 2.2), Vector3(0, 0, 2))
	await _case_every_buildable()
	await _audit()
	# (last: it loads the user's own game in place of the fresh world)
	await _case_user_snapshots()
	_finish()


func _finish() -> void:
	_shift(false)
	bp.cancel()
	print("SNAPTEST SUMMARY: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)


# ---- The cases ----

# A floor aimed at the ground just past a floor's edge: in the square beside it, lined up
func _case_floor_beside() -> void:
	var first := _spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	await _begin("structure/floor")
	await _turn_to(0)
	await _aim(Vector3(0.3, 1.7, 5.0), Vector3(0.1, -0.03, 2.2))
	var off := _local(pp._where.origin).distance_to(Vector3(0, 0, 2))
	_check("floor beside a floor: in the square beside it, lined up", pp._target == first and off < EXACT and _turned_against(first) < EXACT_TURN, "target %s, %.4f m from the square's middle, turned %.1f° against it" % [_name(pp._target), off, _turned_against(first)])
	await _clear()


# A floor aimed into a 2×2 hole in a floor: fills it; turned 4 notches (90°), still fills it with its
# planks turned
func _case_hole() -> void:
	for x in [-1, 0, 1]:
		for z in [-1, 0, 1]:
			if x != 0 or z != 0:
				_spawn("structure/floor", Vector3(x * 2.0, 0, z * 2.0))
	await _frames(2)
	await _begin("structure/floor")
	await _turn_to(0)
	await _aim(Vector3(0.6, 1.7, 3.5), Vector3(0.3, -0.03, 0.25))
	var off := _local(pp._where.origin).length()
	_check("hole: a floor aimed into a 2×2 hole fills it", pp._target != null and off < EXACT, "target %s, %.4f m from the hole's middle" % [_name(pp._target), off])
	await _turn_to(4)
	await _aim(Vector3(0.6, 1.7, 3.5), Vector3(0.3, -0.03, 0.25))
	off = _local(pp._where.origin).length()
	var against := _turned_against(pp._target) if pp._target else -1.0
	_check("hole: turned 4 notches (90°), it still fills the hole, planks turned", pp._target != null and off < EXACT and absf(against - 90.0) < EXACT_TURN and _turn() == 90.0, "%.4f m from the hole's middle, turned %.1f° against the floor it's beside, panel \"%s\"" % [off, against, _panel()])
	await _turn_to(0)
	await _clear()


# A wall aimed at a foundation's edge: on it, corner to corner; the foundation is the target, its
# corners show as dots and the pair in use gets the bar; and a second one there is red
func _case_wall_edge() -> void:
	var foundation := _spawn("structure/foundation_wood", Vector3(0, 1.0, 0))
	await _frames(2)
	await _begin("structure/wall")
	await _turn_to(0)
	await _aim(Vector3(0.3, 2.8, 4.0), Vector3(0.15, 1.0, 0.88))
	var off := _local(pp._where.origin).distance_to(Vector3(0, 1.0, 1.0))
	var along := absf(wrapf(_turned_against(foundation), -90.0, 90.0))
	_check("wall on a foundation edge: on the edge, corner to corner", pp._target == foundation and off < EXACT and along < EXACT_TURN, "target %s, bottom middle %.4f m from the edge's middle, %.1f° off along it" % [_name(pp._target), off, along])
	var shown := pp.shown_markers()
	var corners := SnapCorners.in_world(foundation)
	var bar_on: bool = shown["bar"] != Vector3.INF and corners.any(func(c): return (c as Vector3).distance_to(shown["bar"]) < EXACT)
	_check("wall: the foundation's corners show as dots (only them), the bar on the pair in use", (shown["dots"] as Array).size() == corners.size() and bar_on and foundation.get_child(0) != null, "%d dots for %d corners, bar %s" % [(shown["dots"] as Array).size(), corners.size(), "on a corner" if bar_on else str(shown["bar"])])
	_check("wall: the ghost is its real look, %d%% opaque" % roundi(ValheimPlacer.GHOST_OPACITY * 100.0), not pp._looks.is_empty() and pp._looks.all(func(l): return is_equal_approx(l.transparency, 1.0 - ValheimPlacer.GHOST_OPACITY)) and not pp._red, "%d looks, red %s" % [pp._looks.size(), pp._red])
	var twin := _spawn("structure/wall", Vector3(0, 1.0, 1.0))
	await _aim(Vector3(0.3, 2.8, 4.0), Vector3(0.12, 1.0, 0.88))
	_check("wall: where an identical one stands, it snaps elsewhere instead of into it", not pp._pair.is_empty() and not pp._problem.begins_with("Already placed") and not PieceOverlap.overlaps("wall", pp._shape, pp._where, twin), "snapped %s, \"%s\", bottom middle at %s" % [not pp._pair.is_empty(), pp._problem, _local(pp._where.origin).snapped(Vector3.ONE * 0.001)])
	await _clear()


# A floor aimed at the middle of an existing floor lands beside it (on the side the crosshair is
# nearest), not on it
func _case_floor_on_floor() -> void:
	var first := _spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	await _begin("structure/floor")
	await _turn_to(0)
	await _aim(Vector3(0.3, 2.2, 3.4), Vector3(0.3, 0.0, 0.1))
	var off := _local(pp._where.origin).distance_to(Vector3(2, 0, 0))
	_check("floor aimed at a floor's middle: beside it on the nearest side (+X), not on it", pp._target == first and off < EXACT and not PieceOverlap.overlaps("floor", pp._shape, pp._where, first), "target %s, %.4f m from the square beside it on +X, at %s, \"%s\"" % [_name(pp._target), off, _local(pp._where.origin).snapped(Vector3.ONE * 0.001), pp._problem])
	await _clear()


# Turned a full 360° by wheel, one notch at a time: it stays on the same corner of the target, never
# sinks into it, and at 0° sits where it started, flush
func _case_turning(name: String, target_path: String, piece_path: String, eye: Vector3, at: Vector3, home: Vector3) -> void:
	var target := _spawn(target_path, Vector3.ZERO)
	await _frames(2)
	await _begin(piece_path)
	await _turn_to(0)
	await _aim(eye, at)
	var corner := pp._sticky_point
	var start_ok := pp._target == target and _local(pp._where.origin).distance_to(home) < EXACT and absf(wrapf(_turned_against(target), -90.0, 90.0)) < EXACT_TURN
	var moved := []
	var sank := []
	for step in 16:
		await _wheel(1)
		if pp._target != target or pp._sticky_point.distance_to(corner) > EXACT or pp._pair.is_empty():
			moved.append("%d: %s on %s" % [step + 1, _local(pp._sticky_point).snapped(Vector3.ONE * 0.01) if pp._sticky_point != Vector3.INF else "none", _name(pp._target)])
		if PieceOverlap.overlaps(pp._buildable.shape, pp._shape, pp._where, target):
			sank.append(str(step + 1))
	var back := _local(pp._where.origin).distance_to(home)
	_check("turning: %s at 0° sits flush where it should" % name, start_ok, "at %s, %.1f° against the target" % [_local(pp._where.origin).snapped(Vector3.ONE * 0.001), _turned_against(target)])
	_check("turning: %s through 360°, notch by notch, stays on the same corner and never sinks in, flush again at 0°" % name, corner != Vector3.INF and moved.is_empty() and sank.is_empty() and back < EXACT, "left the corner at notches [%s], sank in at [%s], back at 0° %.4f m off" % [", ".join(moved), ", ".join(sank), back])
	await _clear()


# A doorway aimed into a 2 m gap between two walls (on the joint between two foundations): its
# corners meet the walls' ends
func _case_doorway() -> void:
	for k in 4:
		_spawn("structure/foundation_wood", Vector3(-3.0 + 2.0 * k, 1.0, 0))
	var left := _spawn("structure/wall", Vector3(-2.0, 1.0, 1.0))
	var right := _spawn("structure/wall", Vector3(2.0, 1.0, 1.0))
	await _frames(2)
	await _begin("structure/doorway")
	await _turn_to(0)
	await _aim(Vector3(0.4, 2.8, 4.0), Vector3(0.15, 1.0, 0.88))
	var ends := SnapCorners.in_world(left) + SnapCorners.in_world(right)
	var met := 0
	for c in SnapCorners.of("doorway", pp._shape):
		var at: Vector3 = pp._where * (c as Vector3)
		if absf(_local(at).x) > 0.9 and ends.any(func(e): return (e as Vector3).distance_to(at) < EXACT):
			met += 1
	_check("doorway between two walls: its four outer corners meet the walls' ends", met == 4, "%d of 4 corners on a wall's corner, bottom middle at %s" % [met, _local(pp._where.origin).snapped(Vector3.ONE * 0.001)])
	await _clear()


# A roof aimed at a wall top, turned 8 notches (180°) to face over the room: its low corners on the
# wall top's corners, rising over the room
func _case_roof() -> void:
	_spawn("structure/foundation_wood", Vector3(0, 1.0, 0))
	var wall := _spawn("structure/wall", Vector3(0, 1.0, 1.0))
	await _frames(2)
	var top := 1.0 + PieceShapes.WALL_HEIGHT
	await _begin("structure/roof")
	await _turn_to(8)
	await _aim(Vector3(0.3, top + 1.1, 4.0), Vector3(0.15, top, 1.0))
	var low := 0
	var rising := false
	for c in SnapCorners.of("roof", pp._shape):
		var at := _local(pp._where * (c as Vector3))
		if absf(at.y - top) < EXACT and absf(at.z - 1.0) < EXACT and absf(absf(at.x) - 1.0) < EXACT:
			low += 1
		if at.y > top + 0.5:
			rising = at.z < 0.0
	_check("roof turned 180° on a wall top: low corners on the wall top's, rising over the room", pp._target == wall and low == 2 and rising and _turn() == 180.0, "target %s, %d low corners on the wall top, rising over the room %s, panel \"%s\"" % [_name(pp._target), low, rising, _panel()])
	await _turn_to(0)
	await _clear()


# A pole aimed at a floor's corner stands on it; a beam aimed at a pole's top runs from it to the
# next pole's top
func _case_pole_and_beam() -> void:
	_spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	await _begin("structure/pole_2")
	await _turn_to(0)
	await _aim(Vector3(2.6, 1.7, 3.2), Vector3(0.85, 0.0, 0.8))
	var off := _local(pp._where.origin).distance_to(Vector3(1, 0, 1))
	_check("pole on a floor corner: its foot on the corner", pp._target != null and off < EXACT, "foot %.4f m from the corner" % off)
	await _clear()
	var pole_top: float = PieceShapes.POLE_HEIGHTS["pole_2"]
	_spawn("structure/pole_2", Vector3.ZERO)
	_spawn("structure/pole_2", Vector3(2.0, 0, 0))
	await _frames(2)
	await _begin("structure/beam_2")
	await _turn_to(0)
	await _aim(Vector3(-2.5, pole_top + 1.2, 0.3), Vector3(0.02, pole_top, 0.02))
	var a := INF
	var b := INF
	for c in SnapCorners.of("beam_2", pp._shape):
		var at := _local(pp._where * (c as Vector3))
		a = minf(a, at.distance_to(Vector3(0, pole_top, 0)))
		b = minf(b, at.distance_to(Vector3(2, pole_top, 0)))
	_check("beam from pole top to pole top: an end on each", pp._target != null and a < EXACT and b < EXACT, "ends %.4f m and %.4f m from the pole tops" % [a, b])
	await _clear()


# One storey, measured through the placer: a wall aimed at a ground floor's edge, then a floor aimed
# at that wall's top; the height from the ground floor's top to the upper floor's top. Stairs are
# exactly this tall (PieceShapes.STAIRS_HEIGHT).
func _case_storey() -> void:
	var ground := _spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	await _begin("structure/wall")
	await _turn_to(0)
	await _aim(Vector3(0.3, 1.8, 4.0), Vector3(0.15, 0.0, 0.88))
	var wall_ok := pp._target == ground and not pp._pair.is_empty()
	var wall := registry.spawn(load("res://buildables/structure/wall.tres"), pp._where, {})
	await _frames(2)
	await _begin("structure/floor")
	await _turn_to(0)
	await _aim(Vector3(0.3, PieceShapes.WALL_HEIGHT + 1.7, 4.0), Vector3(0.1, PieceShapes.WALL_HEIGHT, 1.0))
	var floor_ok := pp._target == wall and not pp._pair.is_empty()
	storey = pp._where.origin.y - ground.global_position.y
	_check("one storey (ground floor's top to the top of a floor laid on walls standing on it) is %.3f m, and stairs are as tall" % storey, wall_ok and floor_ok and absf(storey - PieceShapes.STAIRS_HEIGHT) < 0.001, "wall snapped %s, upper floor snapped %s, storey %.4f m, stairs %.4f m" % [wall_ok, floor_ok, storey, PieceShapes.STAIRS_HEIGHT])
	await _clear()


# The fixed flights placed by ordinary snapping, turned with the wheel (8 notches, 180°: climbing
# toward -Z) and aimed where the flight's body goes, as a player would:
#   - Stairs down from an upper floor's 2 m opening, one storey up, aimed at the floor below: the
#     bottom corners on that floor's corners, so the top meets the opening's edge (the flight also
#     fills the opening's width);
#   - Half Stairs down from a 1.25 m ledge, the same way;
#   - Half Stairs down from a foundation's edge (1.25 m up), aimed at the ground below: the top
#     corners on the foundation's corners (the ground has none).
# Each: snapped by the end it should be, both ends exactly where they belong, the yellow bar on the
# pair in use, and once placed, the header board and the footing board each 0 mm from what they meet.
func _case_stairs() -> void:
	var top := storey
	var upper := _spawn("structure/floor", Vector3(0, top, 0))
	for x in [-2.0, 2.0]:
		for z in [0.0, 2.0, 4.0]:
			_spawn("structure/floor", Vector3(x, top, z))
	var below := _spawn("structure/floor", Vector3(0, 0, 4))
	_spawn("structure/floor", Vector3(0, 0, 6))
	await _frames(2)
	await _flight_case("Stairs down from a 2.5 m upper floor's opening, aimed at the floor below", "stairs", 8, Vector3(0.3, 1.7, 5.8), Vector3(0.1, 0.0, 3.2), "bottom", upper, below, Vector3(0, top, 1), Vector3(0, 0, 5))
	# The opening is the 2 m between the floors either side (their edges at x = ±1): the flight's
	# sides on them, and its look (the treads) as wide
	var low_x := INF
	var high_x := -INF
	for c in SnapCorners.of(pp._shape_name, pp._shape):
		var x := _local(pp._where * (c as Vector3)).x
		low_x = minf(low_x, x)
		high_x = maxf(high_x, x)
	var look: AABB = (registry.detail_mesh(pp._shape_name, 0)["mesh"] as Mesh).get_aabb()
	_check("stairs fill the 2 m opening: 0 mm gap each side, the treads as wide", absf(low_x + 1.0) < 0.001 and absf(high_x - 1.0) < 0.001 and absf(look.size.x - PieceShapes.GRID) < 0.01, "gaps %.1f mm and %.1f mm, treads %.3f m wide" % [absf(low_x + 1.0) * 1000.0, absf(high_x - 1.0) * 1000.0, look.size.x])
	await _clear()
	var half := storey / 2.0
	var ledge := _spawn("structure/floor", Vector3(0, half, 0))
	var floor_below := _spawn("structure/floor", Vector3(0, 0, 2))
	_spawn("structure/floor", Vector3(0, 0, 4))
	await _frames(2)
	await _flight_case("Half Stairs down from a 1.25 m ledge, aimed at the floor below", "half_stairs", 8, Vector3(0.3, 1.7, 4.6), Vector3(0.1, 0.0, 2.2), "bottom", ledge, floor_below, Vector3(0, half, 1), Vector3(0, 0, 3))
	await _clear()
	# (the foundation's top exactly one unit, 1.25 m, above the ground where the flight comes down)
	var foot_ground: float = (pp._cast_ray(O + Vector3(0, 5, 2), O + Vector3(0, -5, 2))["position"] as Vector3).y - O.y
	var lift := foot_ground + PieceShapes.FOUNDATION_LIFT
	var foundation := _spawn("structure/foundation_wood", Vector3(0, lift, 0))
	await _frames(2)
	await _flight_case("Half Stairs down from a 1.25 m foundation's edge, aimed at the ground below", "half_stairs", 8, Vector3(0.3, foot_ground + 1.7, 4.6), Vector3(0.1, foot_ground, 2.1), "top", foundation, null, Vector3(0, lift, 1), Vector3.INF)
	await _clear()


# ---- The building grid standard ----

## Pieces whose drawn trim may reach past their collision (the grid standard's allowances): window
## and door frames, and the roof family's overhang trim (shakes over the eaves and ends, up to 0.5 m)
const FRAME_TRIM := ["window", "window_split_1", "window_split_2", "doorway"]
const OVERHANG_TRIM := 0.5
## How far a piece's collision and its drawn look may differ (m), anywhere
const LOOK_TOLERANCE := 0.02


# Every building piece's collision stays within 2 cm of its drawn close-up look: no invisible solid
# sticking out past what's drawn (a crosshair or a placed piece would meet it in thin air), and
# nothing drawn more than 2 cm past the solid, except the standard's trim (window and door frames,
# the roof family's overhang trim up to 0.5 m). Compared box to box, along each axis. Pieces drawn
# by their plain shape (which is their collision) or by a model fitted into their solid box are
# that by construction.
func _case_collision_matches_look() -> void:
	var wrong := []
	var checked := 0
	for folder in ["res://buildables/structure", "res://buildables/round", "res://buildables/furniture"]:
		for file in DirAccess.get_files_at(folder):
			var b := load(folder.path_join(file)) as PieceBuildable if file.ends_with(".tres") else null
			if b == null:
				continue
			var def := registry.shape_of(b.shape)
			if def.get("furniture", false) or def.get("chimney", false):
				continue
			var detail := PieceDetail.build(b.shape, 1)
			if not detail.get("mesh"):
				continue
			var look: AABB = (detail["mesh"] as Mesh).get_aabb()
			if detail.get("door_mesh"):
				look = look.merge((detail["door_mesh"] as Mesh).get_aabb())
			var solid := PieceShapes.bounds_of(def)
			checked += 1
			var trim := OVERHANG_TRIM if (def.get("roof", false) or def.get("overhang", false)) else (INF if b.shape in FRAME_TRIM else LOOK_TOLERANCE)
			var off := []
			for axis in 3:
				var names := ["x", "y", "z"]
				# (collision past the look: never more than the tolerance)
				var out_low: float = look.position[axis] - solid.position[axis]
				var out_high: float = solid.end[axis] - look.end[axis]
				# (look past the collision: the tolerance, or the trim allowance)
				var in_low: float = solid.position[axis] - look.position[axis]
				var in_high: float = look.end[axis] - solid.end[axis]
				if out_low > LOOK_TOLERANCE + 0.0005 or out_high > LOOK_TOLERANCE + 0.0005:
					off.append("solid %.1f / %.1f cm past the look along %s" % [out_low * 100.0, out_high * 100.0, names[axis]])
				if in_low > trim + 0.0005 or in_high > trim + 0.0005:
					off.append("look %.1f / %.1f cm past the solid along %s" % [in_low * 100.0, in_high * 100.0, names[axis]])
			if not off.is_empty():
				wrong.append("%s: %s" % [b.shape, ", ".join(off)])
	_check("every piece's collision within 2 cm of its drawn look (window and door frames, and roofs' overhang trim, allowed past)", wrong.is_empty() and checked > 50, "%d checked%s" % [checked, ("; " + "; ".join(wrong)) if not wrong.is_empty() else ", all within"])


## Template joints: snap corners of two pieces this close are one joint (m)...
const JOINT_EXACT := 0.001
## ...and closer than this but not that close, a joint that's off (a gap, or a piece poking past)
const JOINT_NEAR := 0.3


# Every built-in template, laid out as it's read (a template from before the grid standard brought
# up to it first): written on the grid standard ("grid": 2, no pieces that are gone); every joint
# 0 mm (no two pieces' snap corners between JOINT_EXACT and JOINT_NEAR apart: each pair either
# meets exactly or is clearly apart); every building piece meeting another by at least one corner
# (nothing floating). Furniture, which has no corners, is only laid out.
func _case_template_joints() -> void:
	for file in DirAccess.get_files_at(BuildingTemplate.BUILT_IN_FOLDER):
		if not file.ends_with(".json"):
			continue
		var path := BuildingTemplate.BUILT_IN_FOLDER.path_join(file)
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		var template := BuildingTemplate.read(path)
		var wrong := []
		if not data is Dictionary or int(data.get("grid", 1)) < GridUpgrade.GRID_VERSION:
			wrong.append("not written on the grid standard (no \"grid\": %d)" % GridUpgrade.GRID_VERSION)
		var gone := 0
		for entry in (data.get("items", []) if data is Dictionary else []):
			if not ResourceLoader.exists(str(entry.get("buildable", ""))):
				gone += 1
		if gone > 0:
			wrong.append("%d pieces that are gone" % gone)
		var pieces := await _lay_out(template)
		var corners := []
		for piece in pieces:
			for c in SnapCorners.in_world(piece):
				corners.append([piece, c])
		var near := []
		var met := {}
		for i in corners.size():
			for j in range(i + 1, corners.size()):
				if corners[i][0] == corners[j][0]:
					continue
				# (a chimney joins only its fireplace and other chimney pieces: one passing a wall
				# top or a roof edge isn't a joint)
				if _stack_piece(corners[i][0]) != _stack_piece(corners[j][0]):
					continue
				var d: float = (corners[i][1] as Vector3).distance_to(corners[j][1])
				if d <= JOINT_EXACT:
					met[corners[i][0]] = true
					met[corners[j][0]] = true
				elif d < JOINT_NEAR:
					near.append("%s / %s %.0f mm at %s" % [_name(corners[i][0]), _name(corners[j][0]), d * 1000.0, _local(corners[i][1]).snapped(Vector3.ONE * 0.01)])
		var floating := []
		for piece in pieces:
			if not (piece as BuildPiece).shape_def().get("furniture", false) and not met.has(piece):
				floating.append("%s at %s" % [_name(piece), _local((piece as Node3D).global_position).snapped(Vector3.ONE * 0.01)])
		if not near.is_empty():
			wrong.append("%d joints off: %s%s" % [near.size(), ", ".join(near.slice(0, 12)), " …" if near.size() > 12 else ""])
		if not floating.is_empty():
			wrong.append("%d pieces meeting nothing: %s" % [floating.size(), ", ".join(floating.slice(0, 12))])
		_check("template %s on the grid standard, every joint 0 mm" % (template.template_name if template else file), template != null and wrong.is_empty(), "%d pieces%s" % [pieces.size(), ("; " + "; ".join(wrong)) if not wrong.is_empty() else ", every joint exact"])
		await _clear()


# True for a fireplace or chimney piece (they join only each other)
func _stack_piece(piece: BuildPiece) -> bool:
	var def := piece.shape_def()
	return def.get("furniture", false) or def.get("chimney", false)


# A template's pieces put down at O as it lays them out (furniture pieces included; the storage
# chest and other non-piece buildings left out). Returns the pieces.
func _lay_out(template: BuildingTemplate) -> Array:
	var pieces := []
	if template == null:
		return pieces
	for item in template.items:
		if item["buildable"] is PieceBuildable:
			pieces.append(registry.spawn(item["buildable"], Transform3D(Basis.IDENTITY, O) * (item["relative"] as Transform3D), {}))
	await _frames(3)
	return pieces


# A save from before the building grid standard (no grid version) loads onto it: Foundation Steps as
# Half Stairs with their top edge where it was, a Quarter Wall as a 1 m Half Wall on the same foot, a
# ladder with its top where it was, a fireplace's chimney (two sections and a top, 1 m apart from
# its old spot) laid again on the new sizes from its new spot, a pole and a beam where they were;
# every piece loads, without errors
func _case_grid_saves() -> void:
	var f := Transform3D(Basis.IDENTITY, O + Vector3(4, 0, 0))
	var old_spot := f * GridUpgrade.OLD_FIREPLACE_CHIMNEY
	var list := [
		{"id": 9101, "buildable": GridUpgrade.FOUNDATION_STEPS, "position": SaveGame.from_vector(O + Vector3(0, 0, 0)), "turn": 0.0, "paid": {}},
		{"id": 9102, "buildable": GridUpgrade.QUARTER_WALL, "position": SaveGame.from_vector(O + Vector3(0, 0, -4)), "turn": 0.0, "paid": {}},
		{"id": 9103, "buildable": GridUpgrade.LADDER, "position": SaveGame.from_vector(O + Vector3(-3, 0, 0)), "turn": 0.0, "paid": {}},
		{"id": 9104, "buildable": GridUpgrade.FIREPLACE, "position": SaveGame.from_vector(f.origin), "turn": 0.0, "paid": {}},
		{"id": 9105, "buildable": GridUpgrade.CHIMNEY_SECTION, "position": SaveGame.from_vector(old_spot), "turn": 0.0, "paid": {}},
		{"id": 9106, "buildable": GridUpgrade.CHIMNEY_SECTION, "position": SaveGame.from_vector(old_spot + Vector3.UP * 1.0), "turn": 0.0, "paid": {}},
		{"id": 9107, "buildable": GridUpgrade.CHIMNEY_TOP, "position": SaveGame.from_vector(old_spot + Vector3.UP * 2.0), "turn": 0.0, "paid": {}},
		{"id": 9108, "buildable": "res://buildables/structure/pole_2.tres", "position": SaveGame.from_vector(O + Vector3(-5, 0, 0)), "turn": 0.0, "paid": {}},
		{"id": 9109, "buildable": "res://buildables/structure/beam_2.tres", "position": SaveGame.from_vector(O + Vector3(-5, 2, 3)), "turn": 0.0, "paid": {}},
	]
	registry.load_data({"next_id": 9200, "list": list})
	await _frames(3)
	var wrong := []
	var steps := registry.find(9101)
	var top_edge := O + Vector3(0, 1.0, 1.0)
	if steps == null or steps.shape_name != "half_stairs" or (steps.global_transform * Vector3(0, PieceShapes.FLIGHTS["half_stairs"][0], 1.0)).distance_to(top_edge) > 0.001:
		wrong.append("Foundation Steps: %s" % ("%s with its top edge %.1f mm off" % [steps.shape_name, (steps.global_transform * Vector3(0, 1.25, 1.0)).distance_to(top_edge) * 1000.0] if steps else "missing"))
	var quarter := registry.find(9102)
	if quarter == null or quarter.shape_name != "wall_half_1" or quarter.global_position.distance_to(O + Vector3(0, 0, -4)) > 0.001:
		wrong.append("Quarter Wall: %s" % (quarter.shape_name if quarter else "missing"))
	var ladder := registry.find(9103)
	if ladder == null or (ladder.global_position + Vector3.UP * PieceShapes.LADDER_HEIGHT).distance_to(O + Vector3(-3, 2.0, 0)) > 0.001:
		wrong.append("ladder: top %s" % (_local(ladder.global_position + Vector3.UP * PieceShapes.LADDER_HEIGHT) if ladder else "missing"))
	var new_spot := f * PieceShapes.FIREPLACE_CHIMNEY
	var chimney := [[9105, new_spot], [9106, new_spot + Vector3.UP * PieceShapes.CHIMNEY_SECTION_HEIGHT], [9107, new_spot + Vector3.UP * PieceShapes.CHIMNEY_SECTION_HEIGHT * 2.0]]
	for c in chimney:
		var piece := registry.find(c[0])
		if piece == null or piece.global_position.distance_to(c[1]) > 0.001:
			wrong.append("chimney piece %d: foot %s, wanted %s" % [c[0], _local(piece.global_position) if piece else "missing", _local(c[1])])
	if registry.find(9108) == null or registry.find(9108).global_position.distance_to(O + Vector3(-5, 0, 0)) > 0.001:
		wrong.append("pole moved")
	if registry.find(9109) == null or registry.find(9109).global_position.distance_to(O + Vector3(-5, 2, 3)) > 0.001:
		wrong.append("beam moved")
	var count := registry.all_pieces().size()
	_check("a save from before the grid standard loads onto it: Foundation Steps as Half Stairs (top edge kept), Quarter Wall as a 1 m Half Wall, the ladder's top kept, the chimney laid again from the new fireplace spot, poles and beams where they were", wrong.is_empty() and count == list.size(), "%d of %d loaded%s" % [count, list.size(), ("; " + "; ".join(wrong)) if not wrong.is_empty() else ""])
	await _clear()


# The common joins meet at 0 mm, placed through the real placer and measured on what's drawn: a wall
# on a floor's edge (its foot on the floor's top), a floor beside a floor (edge face to edge face), a
# roof on a wall's top (its underside on the wall's top along the snap line), a beam on post tops
# (its top level with the posts' tops), a half wall on a half wall (foot on top). (The stairs' two
# joints are measured in _case_flight_joints and _case_stairs_grid.)
func _case_common_joins() -> void:
	var wrong := []
	var seen := []
	# A wall on a floor's edge
	var floor_piece := _spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	var wall := await _click_place("structure/wall", 0, Vector3(0.3, 1.7, 4.0), Vector3(0.15, 0.0, 0.88))
	var wall_gap := _gap_down(wall, floor_piece, Vector3(0, 0, 0), [Vector3(-0.8, 0, 0), Vector3(0, 0, 0), Vector3(0.8, 0, 0)]) if wall else INF
	seen.append("wall on floor %.1f mm" % (wall_gap * 1000.0))
	# A half wall on that wall's top? No: on a half wall's top
	await _clear()
	_spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	var lower := await _click_place("structure/wall_half_2", 0, Vector3(0.3, 1.7, 4.0), Vector3(0.15, 0.0, 0.88))
	var upper: BuildPiece = null
	if lower:
		upper = await _click_place("structure/wall_half_2", 0, Vector3(0.6, PieceShapes.HALF_HEIGHT + 1.4, 3.2), Vector3(0.3, PieceShapes.HALF_HEIGHT, 1.0))
	var half_gap := _gap_down(upper, lower, Vector3.ZERO, [Vector3(-0.8, 0, 0), Vector3(0, 0, 0), Vector3(0.8, 0, 0)]) if upper and lower else INF
	seen.append("half wall on half wall %.1f mm" % (half_gap * 1000.0))
	await _clear()
	# A floor beside a floor
	var first := _spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	var beside := await _click_place("structure/floor", 0, Vector3(0.3, 1.7, 5.0), Vector3(0.1, -0.03, 2.2))
	var floor_gap := INF
	if beside:
		floor_gap = 0.0
		for x in [-0.8, 0.0, 0.8]:
			# (from inside the first floor's edge plank, 5 cm in and 1 cm under its top, straight out)
			var from := first.global_transform * Vector3(x, -0.01, 0.95)
			floor_gap = maxf(floor_gap, _visible_hit(beside, from, first.global_basis.z, 0.3) - 0.05)
	seen.append("floor beside floor %.1f mm" % (floor_gap * 1000.0))
	await _clear()
	# A roof on a wall's top
	var under := _spawn("structure/wall", Vector3.ZERO)
	await _frames(2)
	var roof := await _click_place("structure/roof", 8, Vector3(0.4, 4.0, -3.0), Vector3(0.1, PieceShapes.WALL_HEIGHT, 0.0))
	var roof_gap := INF
	if roof:
		# (down from just over the roof's underside on its snap line, the wall's top centre line)
		roof_gap = 0.0
		for x in [-0.8, 0.0, 0.8]:
			var on_line := roof.global_transform * Vector3(x, 0, 0)
			roof_gap = maxf(roof_gap, absf(_visible_hit(under, on_line + Vector3.UP * 0.05, Vector3.DOWN, 0.3) - 0.05))
	seen.append("roof on wall %.1f mm" % (roof_gap * 1000.0))
	await _clear()
	# A beam on two post tops
	var tall: float = PieceShapes.POLE_HEIGHTS["pole_2"]
	var post_a := _spawn("structure/pole_2", Vector3.ZERO)
	_spawn("structure/pole_2", Vector3(2.0, 0, 0))
	await _frames(2)
	var beam := await _click_place("structure/beam_2", 0, Vector3(-2.5, tall + 1.2, 0.3), Vector3(0.02, tall, 0.02))
	var beam_gap := INF
	if beam:
		# (the beam's drawn top against the posts' drawn tops: straight down onto each from above)
		var beam_top := _visible_hit(beam, beam.global_position + Vector3(0, 1.0, 0), Vector3.DOWN, 2.0)
		var post_top := _visible_hit(post_a, post_a.global_position + Vector3(0, tall + 1.0, 0), Vector3.DOWN, 2.0)
		beam_gap = absf(beam_top - post_top)
	seen.append("beam on posts: tops %.1f mm apart" % (beam_gap * 1000.0))
	await _clear()
	for pair in [["wall on floor", wall_gap], ["half wall on half wall", half_gap], ["floor beside floor", floor_gap], ["roof on wall", roof_gap], ["beam on posts", beam_gap]]:
		if absf(pair[1]) > 0.001:
			wrong.append(pair[0])
	_check("common joins meet at 0 mm (wall on floor, half wall on half wall, floor beside floor, roof on wall, beam level with post tops)", wrong.is_empty(), ", ".join(seen) + ("" if wrong.is_empty() else " | not 0 mm: " + ", ".join(wrong)))


# How far a piece's drawn foot is from `other`'s drawn top, at points across its foot (in its own
# space, from `foot`; each just either side of its centre line, where `other` is under it): rays
# down from 0.1 m inside its foot against `other`. The largest, in m.
func _gap_down(piece: BuildPiece, other: BuildPiece, foot: Vector3, across: Array) -> float:
	var gap := 0.0
	for p in across:
		var nearest := INF
		for dz in [-0.05, 0.05]:
			var from := piece.global_transform * (foot + (p as Vector3) + Vector3(0, 0.1, dz))
			nearest = minf(nearest, absf(_visible_hit(other, from, Vector3.DOWN, 0.4) - 0.1))
		gap = maxf(gap, nearest)
	return gap


## Where the stairs-grid pictures go (see _case_stairs_grid)
const STAIRS_GRID_SHOT := "res://docs/reference/ours/stairs_grid.png"


# Stairs are grid pieces, checked on a real build through the real placer, aimed and clicked as a
# player does (free build on): for each flight (Half Stairs, Stairs), side by side,
#   - a foundation put down free on the ground (the grid's first cell, at the flight's own grid
#     origin), then foundations beside it, one under each cell the flight covers and one beyond;
#   - a floor beside the first foundation, at its near edge (the floor the flight starts on);
#   - the flight, turned with the wheel to climb away from that floor, aimed at the foundations where
#     it goes: its bottom corners on the floor's and the foundation's shared corners;
#   - a floor aimed at the flight's top tread: it snaps to the flight's top edge, one tile over and
#     the flight's height up;
#   - a half wall aimed at that upper floor's far edge.
# Measured: a floor tile's size and a half wall's height (the grid); every piece where the grid says,
# 0 mm off (the upper floor right above the last foundation, its corners on the same grid; the half
# wall right above the matching wall position on the last foundation's far edge, the flight's
# height up); the header board 0 mm from the upper floor's edge face and the footing board 0 mm on
# the floor it starts from; and the top tread and the upper floor meeting plank to plank (no gap
# between the tread's far edge and the floor's first plank, the tread's top level with the floor's).
# With -- --stairs-grid-shots in a window, also daylight pictures from the side and from above.
func _case_stairs_grid(shots := false) -> void:
	# The grid, measured from the pieces' own snap corners
	var floor_corners: Array = SnapCorners.of("floor", registry.shape_of("floor"))
	var tile := Vector2.ZERO
	for c in floor_corners:
		tile = tile.max(Vector2(absf((c as Vector3).x) * 2.0, absf((c as Vector3).z) * 2.0))
	var half_wall := 0.0
	for c in SnapCorners.of("wall_half_2", registry.shape_of("wall_half_2")):
		half_wall = maxf(half_wall, (c as Vector3).y)
	var wall := 0.0
	for c in SnapCorners.of("wall", registry.shape_of("wall")):
		wall = maxf(wall, (c as Vector3).y)
	var flights_fit := []
	for flight in PieceShapes.FLIGHTS:
		var size: AABB = PieceShapes.bounds_of(registry.shape_of(flight))
		var cells := roundi(float(PieceShapes.FLIGHTS[flight][1]) / tile.y)
		flights_fit.append("%s %.3f × %.3f m, %.3f m rise (%d cell%s)" % [flight, size.size.x, size.size.z, size.size.y, cells, "" if cells == 1 else "s"])
	_check("the grid, measured: a floor tile %.3f × %.3f m, a half wall %.3f m and a wall %.3f m tall; the flights' fixed shapes" % [tile.x, tile.y, half_wall, wall], tile.is_equal_approx(Vector2(2, 2)) and is_equal_approx(half_wall, 1.25) and is_equal_approx(wall, 2.5), "; ".join(flights_fit))
	var builds := [["half_stairs", -3.0], ["stairs", 3.0]]
	for build in builds:
		await _stairs_grid_build(build[0], build[1])
	if shots:
		await _stairs_grid_shots()
	await _clear()


# One flight's grid build (see _case_stairs_grid), its first foundation aimed at the ground `x`
# m across
func _stairs_grid_build(flight: String, x: float) -> void:
	var height: float = PieceShapes.FLIGHTS[flight][0]
	var length: float = PieceShapes.FLIGHTS[flight][1]
	var cells := roundi(length / PieceShapes.GRID)
	var name := flight.capitalize()
	var wrong := []
	# The first foundation, free on the ground: the grid's origin (G) is its top middle
	var first := await _click_place("structure/foundation_wood", 0, Vector3(x + 0.4, 1.7, 5.0), Vector3(x + 0.1, -0.03, 2.1))
	if first == null:
		_check("%s grid build: the first foundation goes down" % name, false, "nothing placed")
		return
	var g := first.global_transform
	var at := func(p: Vector3) -> Vector3: return _local(g * p)
	# Foundations beside it, one under each cell the flight covers past the first, and one beyond
	var foundations := [first]
	for k in range(1, cells + 1):
		var next := await _click_place("structure/foundation_wood", 0, at.call(Vector3(0.4, 0.7, 2.0 * k + 3.0)), at.call(Vector3(0.1, -1.0, 2.0 * k + 0.1)))
		foundations.append(next)
		if next == null or _g_off(g, next.global_position, Vector3(0, 0, 2.0 * k)) > 0.001:
			wrong.append("foundation %d at %s" % [k + 1, _g_pos(g, next.global_position) if next else "nowhere"])
	# The floor it starts on, beside the first foundation at its near edge
	var start := await _click_place("structure/floor", 0, at.call(Vector3(0.3, 1.7, -3.5)), at.call(Vector3(0.1, 0.0, -0.85)))
	if start == null or _g_off(g, start.global_position, Vector3(0, 0, -2)) > 0.001:
		wrong.append("the start floor at %s" % (_g_pos(g, start.global_position) if start else "nowhere"))
	# The flight, turned to climb away from it (+Z), aimed at the foundations where it goes
	var flight_piece := await _click_place("structure/" + flight, 0, at.call(Vector3(3.0, 1.7, length / 2.0 - 1.0)), at.call(Vector3(0.1, 0.0, length / 2.0 - 1.0 + 0.1)))
	var flight_ok := flight_piece != null and _g_off(g, flight_piece.global_transform * Vector3(0, 0, -length / 2.0), Vector3(0, 0, -1)) < 0.001 \
		and _g_off(g, flight_piece.global_transform * Vector3(0, height, length / 2.0), Vector3(0, height, length - 1.0)) < 0.001
	if not flight_ok:
		wrong.append("the flight: bottom edge middle at %s, top edge middle at %s" % [_g_pos(g, flight_piece.global_transform * Vector3(0, 0, -length / 2.0)) if flight_piece else "nowhere", _g_pos(g, flight_piece.global_transform * Vector3(0, height, length / 2.0)) if flight_piece else "-"])
	# The upper floor, aimed at the flight's top tread just in from its far edge
	var upper: BuildPiece = null
	if flight_piece:
		upper = await _click_place("structure/floor", 0, at.call(Vector3(0.4, height + 1.7, length - 3.6)), at.call(Vector3(0.1, height, length - 1.15)))
	if upper == null or _g_off(g, upper.global_position, Vector3(0, height, length)) > 0.001:
		wrong.append("the upper floor at %s (wanted %s: one tile past the flight, its height up)" % [_g_pos(g, upper.global_position) if upper else "nowhere", Vector3(0, height, length)])
	# A half wall on the upper floor's far edge
	var half_wall: BuildPiece = null
	if upper:
		half_wall = await _click_place("structure/wall_half_2", 0, at.call(Vector3(0.3, height + 1.8, length + 4.0)), at.call(Vector3(0.15, height, length + 1.0 - 0.12)))
	# Right above the matching wall position on the last foundation's far edge, the flight's height up
	var last: BuildPiece = foundations[foundations.size() - 1] if foundations[foundations.size() - 1] else first
	var below := SnapCorners.in_world(last).filter(func(c): return absf(_g_pos(g, c).z - (length + 1.0)) < 0.001)
	var wall_off := INF
	var wall_rise := 0.0
	if half_wall and below.size() == 2:
		var feet := SnapCorners.in_world(half_wall).filter(func(c): return absf(_g_pos(g, c).y - height) < 0.001)
		wall_off = 0.0
		for f in feet:
			var nearest := INF
			for b in below:
				nearest = minf(nearest, Vector2((f as Vector3).x - (b as Vector3).x, (f as Vector3).z - (b as Vector3).z).length())
			wall_off = maxf(wall_off, nearest)
		wall_rise = (feet[0] as Vector3).y - (below[0] as Vector3).y if not feet.is_empty() else 0.0
	if half_wall == null or wall_off > 0.001 or absf(wall_rise - height) > 0.001:
		wrong.append("the half wall: %s mm off the wall position below, %.3f m above it" % ["%.1f" % (wall_off * 1000.0) if wall_off != INF else "-", wall_rise])
	# The joints
	var header := _header_gaps(flight_piece, upper) if flight_piece and upper else [INF, 0, 0, 0]
	var footing := _footing_gaps(flight_piece, start) if flight_piece and start else [INF, 0, 0, 0]
	var plank := _tread_to_floor(flight_piece, upper) if flight_piece and upper else [INF, INF]
	if absf(header[0]) > 0.001 or absf(footing[0]) > 0.001 or plank[0] > 0.001 or plank[1] > 0.001:
		wrong.append("joints: header board %.1f mm, footing board %.1f mm, top tread to the floor's first plank %.1f mm apart, %.1f mm out of level" % [header[0] * 1000.0, footing[0] * 1000.0, plank[0] * 1000.0, plank[1] * 1000.0])
	_check("%s on the grid, a real build (foundations, the floor it starts on, the flight, the floor at its top, a half wall on that floor's far edge): every piece 0 mm off the grid, the half wall right above the wall position below, both joints 0 mm, plank to plank at the top" % name, wrong.is_empty(),
		"; ".join(wrong) if not wrong.is_empty() else "upper floor %.1f mm off, half wall %.1f mm off and %.3f m up; header %.1f mm, footing %.1f mm; tread to floor %.1f mm, %.1f mm out of level" % [_g_off(g, upper.global_position, Vector3(0, height, length)) * 1000.0, wall_off * 1000.0, wall_rise, header[0] * 1000.0, footing[0] * 1000.0, plank[0] * 1000.0, plank[1] * 1000.0])


# A point in the grid's frame `g` (see _stairs_grid_build), and how far a world point is from where
# the grid says
func _g_pos(g: Transform3D, p: Vector3) -> Vector3:
	return (g.affine_inverse() * p).snapped(Vector3.ONE * 0.0001)


func _g_off(g: Transform3D, p: Vector3, want: Vector3) -> float:
	return (g.affine_inverse() * p).distance_to(want)


# Places a piece the way a player does: begun as the build menu does, turned with the wheel (looking
# at open ground meanwhile), aimed from `eye` at `at`, and a real left click. The piece that went
# down, or null.
func _click_place(path: String, notches: int, eye: Vector3, at: Vector3) -> BuildPiece:
	await _begin(path)
	await _unsnap()
	await _turn_to(notches)
	await _aim(eye, at)
	var before := {}
	for p in registry.all_pieces():
		before[p] = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = get_viewport().get_visible_rect().size / 2.0
			click.global_position = click.position
			_send(click)
	else:
		# (headless, the mouse can't be captured, and a click then only grabs it: what a captured
		# click does instead)
		pp._place()
	await _frames(3)
	var problem := pp._problem
	var shown: bool = pp._preview != null and pp._preview.visible
	bp.cancel()
	for p in registry.all_pieces():
		if not before.has(p):
			return p
	print("SNAPTEST note: clicking %s placed nothing (problem \"%s\", ghost showing %s, mouse mode %d, placing %s)" % [path, problem, shown, Input.mouse_mode, bp.is_placing()])
	return null


# The top tread against the floor snapped to the flight's top edge: rays across the tread, from inside
# its far plank (5 cm in, 1 cm under its top), straight out over the edge against the floor's own
# planks: [the widest gap between the tread's far edge and the floor's first plank, how far the
# floor's top is out of level with the tread's top at the edge]
func _tread_to_floor(flight: BuildPiece, floor_piece: BuildPiece) -> Array:
	var def := flight.shape_def()
	var top: float = def["stairs_height"]
	var edge: float = float(def["stairs_length"]) / 2.0
	var t := flight.global_transform
	var out := t.basis.z.normalized()
	var widest := 0.0
	var level := 0.0
	for i in 9:
		var x := -0.8 + 0.2 * i
		var d := _visible_hit(floor_piece, t * Vector3(x, top - 0.01, edge - 0.05), out, 0.3) - 0.05
		widest = maxf(widest, d)
		# (the floor's top just past the edge, from above)
		var down := _visible_hit(floor_piece, t * Vector3(x, top + 0.2, edge + 0.03), -t.basis.y.normalized(), 0.5) - 0.2
		level = maxf(level, absf(down))
	return [widest, level]


# Daylight pictures of the grid builds, from the side and from above, side by side in one picture
func _stairs_grid_shots() -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.45
	var pictures := []
	for view in [[Vector3(14.0, 4.0, 2.0), Vector3(0.0, 1.5, 2.0)], [Vector3(0.0, 17.0, 2.5), Vector3(0.0, 0.0, 2.6)]]:
		await _aim(view[0], view[1])
		for k in 3:
			await RenderingServer.frame_post_draw
		pictures.append(get_viewport().get_texture().get_image())
	var a: Image = pictures[0]
	var b: Image = pictures[1]
	var both := Image.create_empty(a.get_width() + b.get_width(), maxi(a.get_height(), b.get_height()), false, a.get_format())
	both.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	both.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width(), 0))
	var err := both.save_png(ProjectSettings.globalize_path(STAIRS_GRID_SHOT))
	_check("the stairs grid pictures (side, and from above) saved", err == OK, STAIRS_GRID_SHOT)


# For pictures of builds only: no screen overlays, nothing in the player's hands
func _hide_overlays() -> void:
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for child in player.camera.get_children():
		if child is Node3D:
			(child as Node3D).visible = false


## Where the built-in templates' picture goes (see _templates_grid_shot)
const TEMPLATES_GRID_SHOT := "res://docs/reference/ours/templates_grid.png"
## Each built-in template's view: from (eye) at (look), round where it's laid out, front three-quarter
const TEMPLATE_VIEWS := {
	"basic_house": [Vector3(-12.0, 7.0, 10.0), Vector3(1.0, 2.5, 0.5)],
	"forager_s_hut": [Vector3(10.0, 7.5, -14.0), Vector3(0.5, 2.5, 1.0)],
	"woodcutter_s_hut": [Vector3(-8.0, 5.5, -10.0), Vector3(0.4, 2.0, 1.3)],
	"storehouse": [Vector3(9.0, 7.0, -13.0), Vector3(0.0, 2.5, 1.0)],
}


# Each built-in template laid out alone in daylight and pictured from its front three-quarter view,
# the pictures tiled two by two in one picture (in TEMPLATE_VIEWS order)
func _templates_grid_shot() -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.45
	_hide_overlays()
	var pictures := []
	for slug in TEMPLATE_VIEWS:
		var template := BuildingTemplate.read(BuildingTemplate.BUILT_IN_FOLDER.path_join(slug + ".json"))
		await _lay_out(template)
		await _frames(20)
		var view: Array = TEMPLATE_VIEWS[slug]
		await _aim(view[0], view[1])
		for k in 6:
			await RenderingServer.frame_post_draw
		pictures.append(get_viewport().get_texture().get_image())
		await _clear()
	var a: Image = pictures[0]
	var w := a.get_width()
	var h := a.get_height()
	var sheet := Image.create_empty(w * 2, h * 2, false, a.get_format())
	for i in pictures.size():
		var p: Image = pictures[i]
		sheet.blit_rect(p, Rect2i(Vector2i.ZERO, p.get_size()), Vector2i((i % 2) * w, (i / 2) * h))
	var err := sheet.save_png(ProjectSettings.globalize_path(TEMPLATES_GRID_SHOT))
	_check("the built-in templates' picture saved", err == OK, TEMPLATES_GRID_SHOT)


## Where the grid standard picture goes (see _grid_standard_shot)
const GRID_STANDARD_SHOT := "res://docs/reference/ours/grid_standard.png"


# A test build of every piece the building grid standard changed, each where the grid puts it, in
# daylight from the front right and from the back left, side by side in one picture:
#   - wood and stone foundations (top 1.25 m up), Half Stairs climbing onto the wood one, a railing
#     on the stone one's front edge, the stone triangle foundations beside them;
#   - on the foundations a wall and two half walls stacked, wall strips on the wall;
#   - posts: 1.25, 2.5 and 5 m poles, wood and stone half pillars, with 1, 2 and 4 m beams on
#     the pole tops (their tops level with the tops);
#   - a fence, a ladder, the fireplace with two chimney sections and a top;
#   - a row of walls with half gables and inverse triangles (26° and 45°) on their tops, and a
#     roof on one wall's top
func _grid_standard_shot() -> void:
	var h := PieceShapes.HALF_HEIGHT
	var w := PieceShapes.WALL_HEIGHT
	# Foundations, stairs, railing, triangles
	_spawn("structure/foundation_wood", Vector3(-4, h, 0))
	_spawn("structure/foundation_stone", Vector3(-2, h, 0))
	_spawn("structure/half_stairs", Vector3(-4, 0, 2), 180.0)
	_spawn("structure/railing_2", Vector3(-2, h, 1))
	_spawn("structure/foundation_stone_rtri", Vector3(-7, h, 0.5))
	_spawn("structure/foundation_stone_tri45", Vector3(-7, h, -3))
	# On the foundations
	_spawn("structure/wall", Vector3(-2, h, -1))
	_spawn("structure/wall_strip_2", Vector3(-2, h + w, -1))
	_spawn("structure/wall_strip_2", Vector3(-2, h + w + PieceShapes.STRIP_HEIGHT, -1))
	_spawn("structure/wall_half_2", Vector3(-4, h, -1))
	_spawn("structure/wall_half_2", Vector3(-4, h * 2.0, -1))
	# Posts and beams
	var p1: float = PieceShapes.POLE_HEIGHTS["pole_1"]
	var p2: float = PieceShapes.POLE_HEIGHTS["pole_2"]
	_spawn("structure/pole_2", Vector3(1, 0, -2))
	_spawn("structure/pole_2", Vector3(5, 0, -2))
	_spawn("structure/beam_4", Vector3(3, p2, -2))
	_spawn("structure/pole_2", Vector3(1, 0, -4))
	_spawn("structure/beam_2", Vector3(1, p2, -3), 90.0)
	_spawn("structure/pole_1", Vector3(7, 0, -2))
	_spawn("structure/pole_1", Vector3(8, 0, -2))
	_spawn("structure/beam_1", Vector3(7.5, p1, -2))
	_spawn("structure/pole_5", Vector3(9.5, 0, -2))
	_spawn("structure/pillar_wood_half", Vector3(3, 0, 0))
	_spawn("structure/pillar_stone_half", Vector3(5, 0, 0))
	# Fence, ladder, fireplace and chimney
	_spawn("structure/fence", Vector3(2, 0, 2.5))
	_spawn("structure/fence", Vector3(4, 0, 2.5))
	_spawn("structure/ladder", Vector3(7, 0, 1))
	var fireplace := Transform3D(Basis.IDENTITY, Vector3(9.5, 0, 1))
	_spawn("furniture/fireplace", fireplace.origin)
	var spot := fireplace * PieceShapes.FIREPLACE_CHIMNEY
	_spawn("furniture/chimney_section", spot)
	_spawn("furniture/chimney_section", spot + Vector3.UP * PieceShapes.CHIMNEY_SECTION_HEIGHT)
	_spawn("furniture/chimney_top", spot + Vector3.UP * PieceShapes.CHIMNEY_SECTION_HEIGHT * 2.0)
	# Walls with triangle pieces, and a roof
	for x in [-5.0, -3.0, -1.0, 1.0, 3.0]:
		_spawn("structure/wall", Vector3(x, 0, -7))
	_spawn("structure/gable_half_1_26", Vector3(-5.5, w, -7))
	_spawn("structure/gable_half_1_45", Vector3(-4.5, w, -7))
	_spawn("structure/inverse_2_26", Vector3(-3, w, -7))
	_spawn("structure/inverse_1_45", Vector3(-1.5, w, -7))
	_spawn("structure/inverse_1_26", Vector3(-0.5, w, -7))
	_spawn("structure/roof", Vector3(2, w, -7), 180.0)
	await _frames(20)
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.45
	_hide_overlays()
	var pictures := []
	for view in [[Vector3(6.5, 5.5, 9.5), Vector3(0.5, 1.2, -2.0)], [Vector3(13.0, 6.5, -11.0), Vector3(0.0, 1.5, -2.5)]]:
		await _aim(view[0], view[1])
		for k in 6:
			await RenderingServer.frame_post_draw
		pictures.append(get_viewport().get_texture().get_image())
	var a: Image = pictures[0]
	var b: Image = pictures[1]
	var both := Image.create_empty(a.get_width() + b.get_width(), maxi(a.get_height(), b.get_height()), false, a.get_format())
	both.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	both.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width(), 0))
	var err := both.save_png(ProjectSettings.globalize_path(GRID_STANDARD_SHOT))
	_check("the grid standard picture saved", err == OK, GRID_STANDARD_SHOT)


# One flight placed by ordinary snapping and checked (see _case_stairs): begun as the build menu
# does, turned `notches` with the wheel, aimed from `eye` at `at`. It must snap by its `end` ("top"
# or "bottom") corners, its top edge's middle at `top_at` and its bottom edge's middle at
# `bottom_at` (Vector3.INF: anywhere), the yellow bar on the snap point in use; then, put down
# there, its header board 0 mm from `upper`'s edge face and its footing board 0 mm from `lower`'s
# top (either null: not measured), nothing overlapping.
func _flight_case(name: String, flight: String, notches: int, eye: Vector3, at: Vector3, end: String, upper: BuildPiece, lower: BuildPiece, top_at: Vector3, bottom_at: Vector3) -> void:
	await _begin("structure/" + flight)
	await _unsnap()
	await _turn_to(notches)
	await _aim(eye, at)
	var r := await _flight_result(flight, end, upper, lower, top_at, bottom_at)
	_check("%s: snapped by its %s corners, both ends where they belong, the bar on the joint, %s" % [name, end, r["joints"]], r["ok"], r["detail"])


# What _flight_case checks, for the flight being placed: {"ok", "detail", "joints" (what's measured)}
func _flight_result(flight: String, end: String, upper: BuildPiece, lower: BuildPiece, top_at: Vector3, bottom_at: Vector3) -> Dictionary:
	var height: float = PieceShapes.FLIGHTS[flight][0]
	var tops := Vector3.ZERO
	var bottoms := Vector3.ZERO
	var by := ""
	for c in SnapCorners.of(pp._shape_name, pp._shape):
		var w: Vector3 = pp._where * (c as Vector3)
		if absf((c as Vector3).y - height) < 0.001:
			tops += w / 2.0
		else:
			bottoms += w / 2.0
		if not pp._pair.is_empty() and w.distance_to(pp._pair[1]) < 0.001:
			by = "top" if absf((c as Vector3).y - height) < 0.001 else "bottom"
	var top_off := _local(tops).distance_to(top_at)
	var bottom_off := 0.0 if bottom_at == Vector3.INF else _local(bottoms).distance_to(bottom_at)
	var bar: Vector3 = pp.shown_markers()["bar"]
	var bar_ok: bool = not pp._pair.is_empty() and bar.distance_to(pp._pair[1]) < 0.001
	var placed: BuildPiece = null
	if not pp._pair.is_empty():
		placed = registry.spawn(load("res://buildables/structure/%s.tres" % flight), pp._where, {})
		await _frames(2)
	var header := _header_gaps(placed, upper) if placed and upper else [0.0, 0.0, 0, 0]
	var footing := _footing_gaps(placed, lower) if placed and lower else [0.0, 0.0, 0, 0]
	var joints := []
	if upper:
		joints.append("header board 0 mm from the upper edge")
	if lower:
		joints.append("footing board 0 mm on the lower floor")
	var ok: bool = placed != null and by == end and top_off < 0.001 and bottom_off < 0.001 and bar_ok and pp._problem.is_empty() \
		and absf(header[0]) <= 0.001 and absf(footing[0]) <= 0.001
	var detail := "target %s, turned %.1f°, snapped by its %s corners (want %s), top edge middle at %s (%.1f mm off), bottom edge middle at %s (%.1f mm off), bar on the joint %s, problem \"%s\"" % [_name(pp._target), rad_to_deg(pp.turn), by if by != "" else "no", end, _local(tops).snapped(Vector3.ONE * 0.001), top_off * 1000.0, _local(bottoms).snapped(Vector3.ONE * 0.001), bottom_off * 1000.0, bar_ok, pp._problem]
	if upper:
		detail += "; header board: closest %.1f mm, %d of %d columns touching" % [header[0] * 1000.0, header[2], header[3]]
	if lower:
		detail += "; footing board: closest %.1f mm, %d of %d columns touching" % [footing[0] * 1000.0, footing[2], footing[3]]
	if placed:
		registry.remove(placed)
		await _frames(1)
	return {"ok": ok, "detail": detail, "joints": ", ".join(joints) if not joints.is_empty() else "nothing to measure"}


# Looks at open ground well away from any piece, so nothing is snapped (and no sticky corner held)
# while the piece is turned, as a player turning a piece they've just picked would
func _unsnap() -> void:
	await _aim(Vector3(0.0, 1.7, -14.0), Vector3(0.0, -0.03, -16.0))
	await _frames(2)


# A placed flight's footing board on `floor`: rays straight down over the board's whole foot (11
# columns across its width, each from just outside its outer face to its back, so the floor is met
# whether the flight stands on it or runs on from its edge) and over a tight grid round each of the
# flight's bottom corners that meets one of the floor's (where a flight snapped by a single corner
# touches it), each started 0.2 m up so a floor poking into the board is met too. [closest (m;
# negative = overlapping), the widest gap of a column, columns whose closest is within 1 mm, columns]
func _footing_gaps(flight: BuildPiece, floor_piece: BuildPiece) -> Array:
	const UP := 0.2
	var def := flight.shape_def()
	var start := -float(def["stairs_length"]) / 2.0
	var t := flight.global_transform
	var down := -t.basis.y.normalized()
	var closest := INF
	var widest := 0.0
	var touching := 0
	var columns := 11
	for i in columns:
		var x := -0.95 + 1.9 * i / (columns - 1)
		var column := INF
		var dz := -0.002
		while dz <= PieceDetail.HEADER_THICK:
			column = minf(column, _visible_hit(floor_piece, t * Vector3(x, UP, start + dz), down, UP + 0.3) - UP)
			dz += 0.005
		closest = minf(closest, column)
		if column != INF:
			widest = maxf(widest, column)
		if absf(column) <= 0.001:
			touching += 1
	for corner in _meeting_corners(flight, floor_piece, false):
		for gx in range(-2, 3):
			for gz in range(-2, 3):
				var p: Vector3 = (corner as Vector3) + t.basis.x.normalized() * gx * 0.002 + t.basis.z.normalized() * gz * 0.002
				closest = minf(closest, _visible_hit(floor_piece, p - down * UP, down, UP + 0.3) - UP)
	return [closest, widest, touching, columns]


# A flight's top (`top`) or bottom corners that meet one of `other`'s snap points, in the world
func _meeting_corners(flight: BuildPiece, other: BuildPiece, top: bool) -> Array:
	var height: float = flight.shape_def()["stairs_height"]
	var theirs := SnapCorners.in_world(other)
	var found := []
	for c in SnapCorners.of(flight.shape_name, flight.shape_def()):
		if (absf((c as Vector3).y - height) < 0.001) != top:
			continue
		var w: Vector3 = flight.global_transform * (c as Vector3)
		if theirs.any(func(p): return (p as Vector3).distance_to(w) < 0.001):
			found.append(w)
	return found


# The raised floor from the user's save: a floor one storey above a stone foundation pad, outdoors,
# held up by nothing but a flight on its south edge. Stairs turned with the wheel to climb toward
# its east edge (12 notches: running out east, the top toward the floor) and aimed at the
# foundations where the flight goes: the bottom corners on the foundations' corners, the top
# meeting the floor's east edge; the header board 0 mm from the floor's edge face, the footing
# board 0 mm on the foundations.
func _case_raised_floor() -> void:
	var lift := PieceShapes.FOUNDATION_LIFT
	var top := lift + storey
	var pad := {}
	for x in [0.0, 2.0, 4.0, 6.0]:
		for z in [-4.0, -2.0, 0.0]:
			pad[Vector2(x, z)] = _spawn("structure/foundation_stone", Vector3(x, lift, z))
	var floor_piece := _spawn("structure/floor", Vector3(0, top, 0))
	# (its flight on the south edge: climbing north from the pad onto the floor)
	registry.spawn(load("res://buildables/structure/stairs.tres"), Transform3D(Basis.IDENTITY, O + Vector3(0, lift, -3.0)), {})
	await _frames(2)
	await _flight_case("Stairs to a raised floor's east edge, turned with the wheel and aimed at the foundations below", "stairs", 12, Vector3(3.2, lift + 1.7, 2.4), Vector3(3.1, lift, 0.1), "bottom", floor_piece, pad[Vector2(4.0, 0.0)], Vector3(1, top, 0), Vector3(5, lift, 0))
	await _clear()


# A floor placed beside a raised floor and taken away again leaves nothing behind: none of its snap
# points, kinds of point or touching left among the raised floor's
func _case_removed_neighbour() -> void:
	var top := storey
	var floor_piece := _spawn("structure/floor", Vector3(0, top, 0))
	await _frames(2)
	await _begin("structure/stairs")
	await _aim(Vector3(3.0, top + 1.7, 0.6), Vector3(0.2, top, 0.1))
	var beside := _spawn("structure/floor", Vector3(2, top, 0))
	await _frames(2)
	# (the placer looks at both while it's there)
	await _aim(Vector3(3.0, top + 1.7, 0.6), Vector3(0.2, top, 0.1))
	var touching_then: bool = pp._pieces_round(floor_piece).has(beside)
	registry.remove(beside)
	await _frames(3)
	await _aim(Vector3(3.0, top + 1.7, 0.6), Vector3(0.2, top, 0.1))
	var leftover := pp._pieces_round(floor_piece).filter(func(p): return not is_instance_valid(p) or p.is_queued_for_deletion() or registry.find(p.piece_id) == null)
	var stale_points := pp._points_round(floor_piece).filter(func(c): return absf(_local(c).x - 3.0) < 0.01)
	var stale_kind := pp._point_kind(floor_piece, O + Vector3(3.0, top, 1.0))
	_check("a floor placed beside it and taken away leaves no snap points, kinds or target behind", touching_then and leftover.is_empty() and stale_points.is_empty() and stale_kind == 0, "touching while there %s; left behind after: %d pieces, %d snap points, kind %d at its far corner" % [touching_then, leftover.size(), stale_points.size(), stale_kind])
	await _clear()


# The user's own bug snapshots (F9) at their raised floor (floor 1015, its east edge; a leftover Half
# Stairs standing up off it): each snapshot's game loaded and its camera held exactly where it was,
# Stairs begun and turned with the wheel to 0°, 90°, 180° and 270°. By ordinary snapping, whatever
# it snaps to at each turn is a floor's or foundation's corner (never the leftover flight's, or
# anything else's), and put down there, the joint at that pair is 0 mm (its header board on the
# edge face for a top-corner snap, its footing board on the top for a bottom-corner one). The first
# snapshot is aimed at the floor's edge face: at some turn it snaps both corners onto floor 1015.
# The second is aimed into the empty gap past the edge, at nothing: it mustn't snap by a wrong
# corner (with nothing under the crosshair it's left free).
func _case_user_snapshots() -> void:
	for snapshot_path in SNAPSHOTS:
		var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(snapshot_path))
		var state := ProjectSettings.globalize_path(snapshot_path.get_base_dir().path_join(str(info["state_file"])))
		bp.cancel()
		_hold_camera = false
		SaveGame.load_save(state)
		player = null
		for i in 4000:
			await get_tree().process_frame
			SaveGame._test_run = true
			var found := get_tree().get_first_node_in_group("player")
			if found and is_instance_valid(found) and found.is_inside_tree() and i > 200:
				player = found
				break
		for i in 120:
			await get_tree().process_frame
			SaveGame._test_run = true
		if player == null:
			_check("the snapshot %s's game loads" % snapshot_path.get_file(), false, state)
			continue
		DevCheats.freebuild = true
		player.set_physics_process(false)
		player._on_held_changed("Hammer")
		bp = player._placer
		pp = bp._pieces
		registry = bp.registry
		# (measured in the world itself here, not round a spot on fresh ground)
		O = Vector3.ZERO
		var q: Array = info["camera"]["quaternion"]
		var p: Array = info["camera"]["position"]
		_camera_at = Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2]))
		_hold_camera = true
		var floor_piece := registry.find(1015)
		var first: bool = snapshot_path == SNAPSHOTS[0]
		var wrong := []
		var seen := []
		var onto_floor := false
		for notches in [0, 4, 8, 12]:
			await _begin("structure/stairs")
			await _turn_to(notches)
			await _frames(4)
			if pp._pair.is_empty():
				seen.append("%d°: free" % (notches * 22.5))
				continue
			var at: Vector3 = pp._pair[1]
			var owner := _corner_owner(at)
			var height: float = pp._shape["stairs_height"]
			var end := ""
			var meeting := 0
			for c in SnapCorners.of(pp._shape_name, pp._shape):
				var w: Vector3 = pp._where * (c as Vector3)
				if w.distance_to(at) < 0.001:
					end = "top" if absf((c as Vector3).y - height) < 0.001 else "bottom"
				if floor_piece and SnapCorners.in_world(floor_piece).any(func(p): return (p as Vector3).distance_to(w) < 0.001):
					meeting += 1
			if meeting >= 2:
				onto_floor = true
			if owner == null or not owner.shape_def().get("floor", false):
				wrong.append("%d°: snapped by its %s corner to %s's corner" % [notches * 22.5, end, _name(owner)])
				continue
			var placed := registry.spawn(load("res://buildables/structure/stairs.tres"), pp._where, {})
			await _frames(2)
			var gaps := _header_gaps(placed, owner) if end == "top" else _footing_gaps(placed, owner)
			seen.append("%d°: by its %s corners onto %s %d (%d corners on floor 1015), %s board %.1f mm" % [notches * 22.5, end, owner.shape_name, owner.piece_id, meeting, "header" if end == "top" else "footing", gaps[0] * 1000.0])
			if absf(gaps[0]) > 0.001:
				wrong.append("%d°: the %s board %.1f mm from %s %d" % [notches * 22.5, "header" if end == "top" else "footing", gaps[0] * 1000.0, owner.shape_name, owner.piece_id])
			registry.remove(placed)
			await _frames(2)
		if first and not onto_floor:
			wrong.append("at no turn did it snap both corners onto floor 1015")
		_check("the user's snapshot %s, from its exact camera, turned with the wheel: only floor or foundation corners, every joint 0 mm%s" % [snapshot_path.get_file().get_basename(), ", onto floor 1015 at some turn" if first else ""], floor_piece != null and wrong.is_empty(), "; ".join(seen) + ("" if wrong.is_empty() else " | WRONG: " + "; ".join(wrong)))
		bp.cancel()
		_hold_camera = false


# The piece whose snap point is at `p` (a floor or foundation first, when several share it), or null
func _corner_owner(p: Vector3) -> BuildPiece:
	var found: BuildPiece = null
	for piece in registry.pieces_near(p, 8.0):
		if SnapCorners.in_world(piece).any(func(c): return (c as Vector3).distance_to(p) < 0.001):
			if found == null or (piece.shape_def().get("floor", false) and not found.shape_def().get("floor", false)):
				found = piece
	return found


## Every floor and foundation type, for the stairs' pairing rule
const FLOOR_TYPES := ["structure/floor", "structure/floor_1", "structure/floor_rtri", "structure/floor_tri45", "round/round_floor", "round/round_floor_22",
	"structure/foundation_wood", "structure/foundation_wood_rtri", "structure/foundation_wood_tri45", "round/round_foundation_wood", "round/round_foundation_wood_22",
	"structure/foundation_stone", "structure/foundation_stone_rtri", "structure/foundation_stone_tri45", "round/round_foundation_stone", "round/round_foundation_stone_22"]


# Which corners a flight may meet (the rule, not any special placement):
#   - each flight, turned with the wheel to 0° and to 180°, aimed at the top of every floor and
#     foundation type just inside one of its corners: snaps, by a corner meeting one of that type's;
#   - a flight aimed at the ground right by a lone wall's foot: its corners never pair with the
#     wall's (it stays free);
#   - a flight aimed right by a lone flight's foot: never pairs with the other flight's corners;
#   - a wall aimed at a lone flight: never pairs with the flight's corners;
#   - a floor aimed at a lone flight's top tread: may pair with the flight's corners (the same
#     pairing as a flight's corner on a floor's).
func _case_stair_pairing() -> void:
	for type in FLOOR_TYPES:
		var wrong := []
		for flight in PieceShapes.FLIGHTS:
			var target := _spawn(type, Vector3(0, 0, 0))
			await _frames(2)
			var corner: Vector3 = _local(SnapCorners.in_world(target)[0])
			var middle := Vector3.ZERO
			for c in SnapCorners.in_world(target):
				middle += _local(c)
			middle /= SnapCorners.in_world(target).size()
			var inward := Vector3(middle.x - corner.x, 0.0, middle.z - corner.z).normalized()
			await _begin("structure/" + flight)
			for notches in [0, 8]:
				await _turn_to(notches)
				var at := corner + inward * 0.15
				await _aim(at - inward * 2.0 + Vector3.UP * 1.7, at)
				var anchor: Vector3 = pp._pair[1] if not pp._pair.is_empty() else Vector3.INF
				if pp._pair.is_empty() or not SnapCorners.in_world(target).any(func(p): return (p as Vector3).distance_to(anchor) < 0.001):
					wrong.append("%s at %d°: %s" % [flight, notches * 22.5, "free" if pp._pair.is_empty() else "met %s" % _local(anchor)])
			await _clear()
		_check("every flight snaps onto a %s by a corner meeting one of its corners, turned 0° and 180°" % type.get_file().replace("_", " "), wrong.is_empty(), "; ".join(wrong) if not wrong.is_empty() else "6 of 6 snapped onto its corners")
	# A flight by a lone wall's foot, and by a lone flight's foot: no pairing
	for other in ["structure/wall", "structure/stairs"]:
		var lone := _spawn(other, Vector3.ZERO)
		await _frames(2)
		var met := []
		await _begin("structure/stairs")
		for c in SnapCorners.in_world(lone):
			for notches in [0, 4, 8, 12]:
				await _turn_to(notches)
				var at: Vector3 = _local(c) + Vector3(0.05, 0.0, 0.05)
				at.y = 0.0
				await _aim(at + Vector3(0.4, 1.7, 2.5), at - Vector3(0, 0.03, 0))
				if not pp._pair.is_empty():
					met.append("%s at %d°" % [_local(pp._pair[1]), notches * 22.5])
		_check("a flight never pairs with a lone %s's corners" % _name(lone).to_lower(), met.is_empty(), "met %s" % ", ".join(met) if not met.is_empty() else "free beside it at every corner and turn")
		await _clear()
	# A wall at a lone flight: no pairing; a floor at its top tread: may pair with its corners
	var lone_flight := _spawn("structure/stairs", Vector3.ZERO)
	await _frames(2)
	await _begin("structure/wall")
	await _aim(Vector3(0.3, 4.2, 3.5), Vector3(0.1, storey, 1.85))
	var wall_met: bool = not pp._pair.is_empty()
	var wall_detail := "target %s, met %s" % [_name(pp._target), _local(pp._pair[1]) if wall_met else "nothing"]
	await _begin("structure/floor")
	await _aim(Vector3(0.3, 4.2, 3.5), Vector3(0.1, storey, 1.85))
	var floor_met: bool = not pp._pair.is_empty() and SnapCorners.in_world(lone_flight).any(func(p): return (p as Vector3).distance_to(pp._pair[1]) < 0.001)
	_check("a wall never pairs with a flight's corners; a floor may", not wall_met and floor_met, "wall: %s; floor: target %s, met %s" % [wall_detail, _name(pp._target), _local(pp._pair[1]) if not pp._pair.is_empty() else "nothing"])
	await _clear()


# Every allowed snap of each flight (Stairs, Half Stairs), by ordinary snapping
# with the wheel, leaves 0 mm at both its joints, measured on what's drawn (rays from close grids
# over each board, against the other piece's own visible triangles; see _header_gaps, _footing_gaps):
#   - climbing, by its bottom corners: turned with the wheel (180°) and aimed at a lower floor, wood
#     foundation and stone foundation (two squares at the ground), its bottom corners on their
#     corners, the top meeting an upper floor's edge its height up: the footing board 0 mm on the
#     lower top, the header board 0 mm from the upper floor's edge face;
#   - hanging, by its top corners: the same turn, aimed at the bare ground below the edge of a
#     floor, wood foundation and stone foundation its height up (the ground has no corners, so its
#     top corners take the edge's): the header board 0 mm from that edge face.
func _case_flight_joints() -> void:
	for flight in PieceShapes.FLIGHTS:
		var height: float = PieceShapes.FLIGHTS[flight][0]
		var length: float = PieceShapes.FLIGHTS[flight][1]
		var mid := 3.0 - length / 2.0
		for type in ["structure/floor", "structure/foundation_wood", "structure/foundation_stone"]:
			# Climbing: the lower squares at z 0 and 2 (the flight's foot on the far edge, z = 3), the
			# upper floor's near edge right over its top (z = 3 - length)
			_spawn(type, Vector3(0, 0, 0))
			var lower := _spawn(type, Vector3(0, 0, 2))
			var upper := _spawn("structure/floor", Vector3(0, height, 2.0 - length))
			await _frames(2)
			await _flight_case("%s climbing from a %s onto an upper floor" % [flight.capitalize(), type.get_file().replace("_", " ")], flight, 8, Vector3(0.3, 1.7, mid + 2.6), Vector3(0.1, 0.0, mid + 0.1), "bottom", upper, lower, Vector3(0, height, 3.0 - length), Vector3(0, 0, 3))
			await _clear()
		for type in ["structure/floor", "structure/foundation_wood", "structure/foundation_stone"]:
			# Hanging over bare ground from the edge at z = 1, its height up (the ground's height there
			# measured, so the flight's foot is on it)
			var ground: float = (pp._cast_ray(O + Vector3(0, 5, 1 + length / 2.0), O + Vector3(0, -5, 1 + length / 2.0))["position"] as Vector3).y - O.y
			var edge := _spawn(type, Vector3(0, ground + height, 0))
			await _frames(2)
			await _flight_case("%s hanging from a %s's edge over the ground" % [flight.capitalize(), type.get_file().replace("_", " ")], flight, 8, Vector3(0.3, ground + 1.7, 1 + length / 2.0 + 2.6), Vector3(0.1, ground, 1 + length / 2.0 + 0.1), "top", edge, null, Vector3(0, ground + height, 1), Vector3.INF)
			await _clear()


# A placed flight's header board against `edge`: rays straight out from a grid on the board's outer
# face (11 columns across its width, every 2.5 mm down its height), each started 0.2 m behind the
# face so something overlapping the board is met too. [closest (m; negative = overlapping), the
# widest gap any column has before it meets something, columns whose closest is within 1 mm, columns]
func _header_gaps(flight: BuildPiece, edge: BuildPiece) -> Array:
	const BACK := 0.2
	var def := flight.shape_def()
	var top: float = def["stairs_height"]
	var face: float = float(def["stairs_length"]) / 2.0
	var t := flight.global_transform
	var out := t.basis.z.normalized()
	var closest := INF
	var widest := 0.0
	var touching := 0
	var columns := 11
	for i in columns:
		var x := -0.95 + 1.9 * i / (columns - 1)
		var column := INF
		var y := top - PieceDetail.HEADER_TOP_DROP - 0.004
		while y > top - PieceDetail.HEADER_TOP_DROP - PieceDetail.HEADER_HEIGHT + 0.004:
			var from := t * Vector3(x, y, face) - out * BACK
			column = minf(column, _visible_hit(edge, from, out, BACK + 0.3) - BACK)
			y -= 0.0025
		closest = minf(closest, column)
		if column != INF:
			widest = maxf(widest, column)
		if absf(column) <= 0.001:
			touching += 1
	# (and round each top corner that meets one of the edge piece's, down the board's height, where a
	# flight snapped by a single corner touches its edge face)
	for corner in _meeting_corners(flight, edge, true):
		for gx in range(-2, 3):
			var y := top - PieceDetail.HEADER_TOP_DROP - 0.004
			while y > top - PieceDetail.HEADER_TOP_DROP - PieceDetail.HEADER_HEIGHT + 0.004:
				var on_face: Vector3 = (corner as Vector3) + t.basis.x.normalized() * gx * 0.002 + t.basis.y.normalized() * (y - top)
				closest = minf(closest, _visible_hit(edge, on_face - out * BACK, out, BACK + 0.3) - BACK)
				y -= 0.01
	return [closest, widest, touching, columns]


# How far along a ray (world) it first meets a piece's visible look, within `reach`, or INF
var _triangles := {}


func _visible_hit(piece: BuildPiece, from: Vector3, dir: Vector3, reach: float) -> float:
	var best := INF
	var looks: Array = piece.find_children("*", "MeshInstance3D", true, false)
	for look in piece._detail_looks:
		if not looks.has(look):
			looks.append(look)
	for look in looks:
		var mi := look as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_inside_tree() or not mi.is_visible_in_tree():
			continue
		if not _triangles.has(mi.mesh):
			_triangles[mi.mesh] = mi.mesh.generate_triangle_mesh()
		var tri: TriangleMesh = _triangles[mi.mesh]
		if tri == null:
			continue
		var inv := mi.global_transform.affine_inverse()
		var hit := tri.intersect_ray(inv * from, inv.basis * dir)
		if hit.is_empty():
			continue
		var d := (mi.global_transform * (hit["position"] as Vector3) - from).dot(dir)
		if d >= 0.0 and d <= reach:
			best = minf(best, d)
	return best


# Stairs from every path have the current look (the header board, and both stringers running under
# the treads into it and down to the ground): one laid out by a template (through the real
# laying-out, as a ghost, then built with the hammer's builder), a template's preview, Stairs saved
# and loaded back (and an old fitted flight, 1 m tall, loading as the nearest fixed one, Half Stairs), and
# every one of them again after the look code is remade mid-session (as when it changes while the
# game runs; see PieceRegistry.remake_looks).
func _case_stair_paths() -> void:
	var stairs: PieceBuildable = load("res://buildables/structure/stairs.tres")
	var plot := bp.plots.create(load("res://buildables/plots/house.tres"), Transform3D(Basis.IDENTITY, O), Vector2(6, 6))
	bp._templates._laying.append({"plot": plot, "queue": [[stairs, Transform3D(Basis.IDENTITY, O + Vector3(0, 0, 1))]]})
	bp._templates.set_process(true)
	var ghost: BuildPiece = null
	for i in 60:
		await get_tree().process_frame
		for p in registry.all_pieces():
			if p.shape_name == "stairs" and p.is_ghost():
				ghost = p
		if ghost:
			break
	var problems := []
	if ghost == null:
		problems.append("the template laid out no stairs")
	else:
		var why := _stair_look_problem(ghost)
		if why != "":
			problems.append("template ghost: " + why)
		var built := bp._ghosts.build(ghost)
		await _frames(2)
		why = _stair_look_problem(ghost) if built == "" and not ghost.is_ghost() else "not built (%s)" % built
		if why != "":
			problems.append("built from the template: " + why)
	var template := BuildingTemplate.new()
	template.plot_type = load("res://buildables/plots/house.tres")
	template.items = [{"buildable": stairs, "relative": Transform3D.IDENTITY}]
	var preview := TemplateLook.part_for(registry, template, 0) as BuildPiece
	var preview_why := _stair_look_problem(preview)
	if preview_why != "":
		problems.append("template preview: " + preview_why)
	preview.free()
	# Saved and loaded back, with an old fitted flight (1 m tall, its height saved) among them
	var data := registry.save_data()
	(data["list"] as Array).append({"id": 9001, "buildable": "res://buildables/structure/stairs.tres", "position": SaveGame.from_vector(O + Vector3(6, 0, 0)), "turn": 0.0, "paid": {}, "state": {"stairs_height": 1.0}})
	registry.load_data(data)
	await _frames(3)
	var loaded := 0
	for p in registry.all_pieces():
		if not PieceShapes.FLIGHTS.has(p.shape_name):
			continue
		loaded += 1
		var why := _stair_look_problem(p)
		if why != "":
			problems.append("loaded %s #%d: %s" % [p.shape_name, p.piece_id, why])
		if p.piece_id == 9001 and p.shape_name != "half_stairs":
			problems.append("the old 1 m fitted flight loaded as %s, not Half Stairs" % p.shape_name)
	if loaded < 2:
		problems.append("only %d flights loaded back" % loaded)
	# The look code remade mid-session
	registry.remake_looks()
	await _frames(3)
	for p in registry.all_pieces():
		if PieceShapes.FLIGHTS.has(p.shape_name):
			var why := _stair_look_problem(p)
			if why != "":
				problems.append("after the looks were remade, %s #%d: %s" % [p.shape_name, p.piece_id, why])
	_check("stairs from a template (ghost and built), its preview, a save (with an old fitted flight) and after the looks are remade: header board and full stringers", problems.is_empty(), "; ".join(problems) if not problems.is_empty() else "%d loaded flights and the template's, all current" % loaded)
	bp.plots.remove_plot(plot)
	await _clear()


# Why a flight's close-up look isn't the current one (empty if it is): it must be the look the
# current code makes for it, with the header board (points across the full width at the board's
# bottom, at the top edge) and both stringers (points where they're cut off inside the board, and
# down at the bottom step's level)
func _stair_look_problem(piece: BuildPiece) -> String:
	var detail: MeshInstance3D = null
	for child in piece.get_children():
		if child is MeshInstance3D and child.name == "Detail":
			detail = child
	if detail == null or detail.mesh == null:
		return "no close-up look"
	if detail.mesh != registry.detail_mesh(piece.shape_name, piece.piece_id).get("mesh"):
		return "its close-up look isn't the current code's"
	var height: float = PieceShapes.FLIGHTS[piece.shape_name][0]
	var edge_z: float = PieceShapes.FLIGHTS[piece.shape_name][1] / 2.0
	var board_bottom := height - 0.075 - PieceDetail.HEADER_HEIGHT
	var cut_z := edge_z - PieceDetail.HEADER_THICK + PieceDetail.HEADER_BITE
	var foot_top := height / PieceShapes.step_count(height) - PieceDetail.HEADER_TOP_DROP
	var footing := false
	var header := false
	var stringer_tops := 0
	var stringer_feet := 0
	var mesh := detail.mesh
	for s in mesh.get_surface_count():
		for v in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(v.y - board_bottom) < 0.01 and v.z > edge_z - PieceDetail.HEADER_THICK - 0.01 and absf(v.x) > 0.95:
				header = true
			# (the footing board's foot: on the floor, the flight's full width, at its bottom edge;
			# stringers don't reach that wide and the treads don't come down to the floor)
			if absf(v.y) < 0.002 and v.z < -edge_z + PieceDetail.HEADER_THICK and absf(v.x) > 0.95 and foot_top > 0.0:
				footing = true
			if absf(v.z - cut_z) < 0.002 and absf(absf(v.x) - 0.8) < 0.15 and v.y > height - 0.5:
				stringer_tops += 1
			if absf(v.y) < 0.002 and absf(absf(v.x) - 0.8) < 0.15:
				stringer_feet += 1
	var missing := []
	if not header:
		missing.append("no header board")
	if not footing:
		missing.append("no footing board")
	if stringer_tops < 8:
		missing.append("stringers don't reach the header board")
	if stringer_feet < 8:
		missing.append("stringers don't come down to the ground")
	return ", ".join(missing)


# A foundation placed free on flat ground stands with its top 1 m up; Page Up ×2 raises it to
# 1.5 m and Page Down ×6 lowers it to 0 m (flush). Then one put down at 1.25 m, and another aimed at
# the ground beside it: it snaps to it, its top at 1.25 m too.
func _case_foundation_height() -> void:
	await _begin("structure/foundation_wood")
	await _aim(Vector3(0.3, 1.7, 4.5), Vector3(0.1, -0.03, 0.1))
	var ground: float = (pp._cast_ray(O + Vector3(0.1, 2.0, 0.1), O + Vector3(0.1, -2.0, 0.1))["position"] as Vector3).y
	var start := pp._where.origin.y - ground
	await _press(KEY_PAGEUP, 2)
	var raised := pp._where.origin.y - ground
	await _press(KEY_PAGEDOWN, 7)
	var lowered := pp._where.origin.y - ground
	var controls: Array = (bp.hud_state().get("controls", []) as Array).map(func(c): return "%s [%s]" % [c[0], c[1]])
	_check("free foundation on flat ground: top 1.25 m up (one vertical unit), PgUp ×2 1.75 m, PgDn ×7 0 m; \"Raise/Lower [PgUp/PgDn]\" in the controls", pp._pair.is_empty() and absf(start - 1.25) < 0.001 and absf(raised - 1.75) < 0.001 and absf(lowered) < 0.001 and controls.has("Raise/Lower [PgUp/PgDn]"), "%.3f m, %.3f m, %.3f m up; controls %s" % [start, raised, lowered, controls])
	# (from 0 m, PgUp ×5: 1.25 m)
	await _press(KEY_PAGEUP, 5)
	var first := registry.spawn(load("res://buildables/structure/foundation_wood.tres"), pp._where, {})
	var first_top := pp._where.origin.y
	# (the crosshair on the ground beside it before the next one is picked, so nothing carries over)
	bp.cancel()
	await _aim(Vector3(0.3, 2.2, 5.0), Vector3(0.1, -0.03, 2.2))
	await _begin("structure/foundation_wood")
	await _aim(Vector3(0.3, 2.2, 5.0), Vector3(0.1, -0.03, 2.2))
	var off := pp._where.origin.distance_to(first.global_position + Vector3(0, 0, 2))
	_check("a foundation aimed at the ground beside one at 1.25 m snaps beside it at its height", pp._target == first and not pp._pair.is_empty() and off < EXACT and absf(pp._where.origin.y - first_top) < 0.001, "target %s, %.4f m from the square beside it, its top %.3f m vs %.3f m" % [_name(pp._target), off, pp._where.origin.y - ground, first_top - ground])
	await _clear()


# A floor aimed at a pillar's top, at 0°, 22.5°, 45° and 67.5°: a corner on the pillar top each time,
# turned that much against the pillar
func _case_pillar_fan() -> void:
	var pillar := _spawn("structure/pillar_wood", Vector3.ZERO)
	await _frames(2)
	var top := Vector3(0, PieceShapes.PILLAR_HEIGHT, 0)
	await _begin("structure/floor")
	for notches in [0, 1, 2, 3]:
		await _turn_to(notches)
		await _aim(top + Vector3(1.8, 1.4, 1.6), top + Vector3(0.03, 0, 0.03))
		var touch := INF
		for c in SnapCorners.of("floor", pp._shape):
			touch = minf(touch, _local(pp._where * (c as Vector3)).distance_to(top))
		var against := _turned_against(pillar)
		_check("pillar-top fan: a floor turned %s° has a corner on the pillar top" % str(notches * 22.5), pp._target == pillar and touch < EXACT and absf(against - notches * 22.5) < EXACT_TURN, "corner %.4f m from the pillar top, turned %.1f° against the pillar" % [touch, against])
	await _turn_to(0)
	await _clear()


# Holding Shift places it free (no snap) where the crosshair hits, and the wheel turns 1° a notch;
# let go, it snaps again
func _case_shift() -> void:
	var foundation := _spawn("structure/foundation_wood", Vector3(0, 1.0, 0))
	await _frames(2)
	await _begin("structure/wall")
	await _turn_to(0)
	await _shift(true)
	await _aim(Vector3(0.3, 2.8, 4.0), Vector3(0.15, 1.0, 0.88))
	var hit := _local(pp._where.origin)
	_check("Shift: placed free at the crosshair, no snap", pp._pair.is_empty() and hit.distance_to(Vector3(0, 1.0, 1.0)) > 0.05 and absf(hit.y - 1.0) < 0.02, "pair %s, bottom middle at %s" % [not pp._pair.is_empty(), hit.snapped(Vector3.ONE * 0.001)])
	await _wheel(3, true)
	_check("Shift: the wheel turns 1° a notch (×3: 3°)", is_equal_approx(_turn(), 3.0), "panel \"%s\"" % _panel())
	await _wheel(-3, true)
	await _shift(false)
	var off := _local(pp._where.origin).distance_to(Vector3(0, 1.0, 1.0))
	_check("Shift let go: it snaps onto the edge again, at 0°", pp._target == foundation and off < EXACT and is_zero_approx(_turn()), "%.4f m from the edge's middle, panel \"%s\"" % [off, _panel()])
	await _clear()


# Every buildable: corners for every building piece (two or more), none for furniture; the wheel
# turns it 22.5° a notch; the controls row is the five controls
func _case_every_buildable() -> void:
	var count := 0
	var wrong := []
	for folder in ["res://buildables", "res://buildables/structure", "res://buildables/round", "res://buildables/furniture"]:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".tres"):
				continue
			var buildable := load(folder.path_join(file)) as Buildable
			if buildable == null or buildable is PlotType or buildable is TemplateBuildable:
				continue
			bp.begin(buildable)
			await _aim(Vector3(0.4, 2.6, 3.0), Vector3(0.1, 0.0, 0.2))
			var before := _turn()
			await _wheel(1)
			var after := _turn()
			await _wheel(-1)
			count += 1
			var problems := []
			if fposmod(after - before, 360.0) != 22.5:
				problems.append("turn %s° → %s°" % [before, after])
			if buildable is PieceBuildable:
				var def := registry.shape_of((buildable as PieceBuildable).shape)
				var corners := SnapCorners.of((buildable as PieceBuildable).shape, def)
				# (furniture has none, but where a chimney stacks on the fireplace it has the chimney's)
				var slot: bool = (def["sockets"] as Array).any(func(s): return SnapCorners.SLOTS.has(s["type"]))
				if (def.get("furniture", false) and not slot) != corners.is_empty() or (not corners.is_empty() and corners.size() < 2):
					problems.append("%d snap points" % corners.size())
			var keys: Array = (bp.hud_state().get("controls", []) as Array).map(func(c): return c[1])
			var piece_like: bool = buildable is PieceBuildable and not registry.shape_of((buildable as PieceBuildable).shape).get("furniture", false)
			if keys != (CONTROL_KEYS if piece_like else FURNITURE_KEYS):
				problems.append("controls %s" % [keys])
			if not problems.is_empty():
				wrong.append("%s (%s)" % [buildable.display_name, ", ".join(problems)])
	bp.cancel()
	_check("every buildable (%d): corners (none for furniture), wheel turns 22.5°, the controls row (with Raise/Lower for building pieces)" % count, wrong.is_empty() and count > 0, "wrong: %s" % ", ".join(wrong) if not wrong.is_empty() else "all %d" % count)


# ---- The snap audit: every buildable at its usual target ----
#
# For each building piece: its usual target is put down, where it should end up is worked out from
# the two pieces' corners (the pair of the target's corners it should meet, and which side of them it
# goes: see _expected), the piece is turned there by wheel notches and aimed at with the real
# crosshair, and the result is compared. One line per buildable: "SNAPAUDIT | name | snapped |
# corners met | right | note"; the check fails if any building piece doesn't come out right.
# Furniture (and the workbench, chest, campfire and lean-to) only has to stand on a floor.

# [shapes, target shape, where the target goes (round O), the target corners to meet, side]
const AUDIT := [
	[["floor", "floor_1"], "", Vector3.ZERO, "far_edge", "outside"],
	# (foundations stand 1 m proud, as a free one starts)
	[["foundation_wood", "foundation_stone"], "", Vector3(0, 1.0, 0), "far_edge", "outside"],
	[["floor_rtri", "floor_tri45"], "floor", Vector3.ZERO, "far_edge", "outside"],
	[["foundation_wood_rtri", "foundation_stone_rtri", "foundation_wood_tri45", "foundation_stone_tri45"], "foundation_wood", Vector3(0, 1.0, 0), "far_edge", "outside"],
	[["round_floor", "round_floor_22"], "", Vector3.ZERO, "round_side", "outside"],
	[["round_foundation_wood", "round_foundation_stone", "round_foundation_wood_22", "round_foundation_stone_22"], "", Vector3(0, 1.0, 0), "round_side", "outside"],
	[["wall", "doorway", "window", "wall_half_2", "wall_strip_2", "window_split_2", "railing_2", "fence", "gable_wall_45"], "foundation_wood", Vector3.ZERO, "far_edge", "above"],
	[["wall_1", "wall_half_1", "wall_strip_1", "window_split_1", "railing_1"], "floor_1", Vector3.ZERO, "far_edge", "above"],
	[["wall_long"], "foundation_wood_rtri", Vector3.ZERO, "width", "above"],
	[["wall_short"], "foundation_wood_tri45", Vector3.ZERO, "width", "above"],
	[["gable_26", "gable_45"], "wall", Vector3.ZERO, "top", "above"],
	[["gable_half_1_26", "gable_half_1_45"], "wall_1", Vector3.ZERO, "top", "above"],
	[["inverse_2_26"], "gable_26", Vector3.ZERO, "slope", "above"],
	[["inverse_2_45"], "gable_45", Vector3.ZERO, "slope", "above"],
	[["inverse_1_26"], "gable_half_1_26", Vector3.ZERO, "slope", "above"],
	[["inverse_1_45"], "gable_half_1_45", Vector3.ZERO, "slope", "above"],
	[["roof", "roof_outer_26"], "wall", Vector3.ZERO, "top", "behind"],
	[["roof_45", "roof_outer_45"], "wall", Vector3.ZERO, "top", "behind"],
	[["roof_inner_26"], "roof", Vector3.ZERO, "side", "outside"],
	[["roof_inner_45"], "roof_45", Vector3.ZERO, "side", "outside"],
	[["eave_26"], "roof", Vector3.ZERO, "low", "outside"],
	[["eave_45"], "roof_45", Vector3.ZERO, "low", "outside"],
	[["gable_overhang_26"], "roof", Vector3.ZERO, "side", "outside"],
	[["gable_overhang_45"], "roof_45", Vector3.ZERO, "side", "outside"],
	[["eave_corner_26", "valley_eave_corner_26", "outer_eave_corner_26"], "eave_26", Vector3.ZERO, "side", "outside"],
	[["eave_corner_45", "valley_eave_corner_45", "outer_eave_corner_45"], "eave_45", Vector3.ZERO, "side", "outside"],
	[["topper_26", "hip_end_26"], "roof", Vector3.ZERO, "high", "outside"],
	[["topper_45", "hip_end_45"], "roof_45", Vector3.ZERO, "high", "outside"],
	[["ridge_26"], "roof", Vector3.ZERO, "high", "any"],
	[["ridge_45"], "roof_45", Vector3.ZERO, "high", "any"],
	[["topper_overhang_26", "topper_gable_26"], "topper_26", Vector3.ZERO, "side", "any"],
	[["topper_overhang_45", "topper_gable_45"], "topper_45", Vector3.ZERO, "side", "any"],
	[["curved_wall_45"], "round_floor", Vector3.ZERO, "arc", "above"],
	[["curved_wall_22"], "round_floor_22", Vector3.ZERO, "arc", "above"],
	[["cone_roof"], "curved_wall_45", Vector3.ZERO, "top", "inside"],
	[["pole_1", "pole_2", "pole_5", "pillar_wood", "pillar_stone", "pillar_wood_half", "pillar_stone_half"], "floor", Vector3.ZERO, "corner", "above"],
	[["ladder"], "floor", Vector3(0, PieceShapes.LADDER_HEIGHT, 0), "corner", "below"],
	[["door"], "doorway", Vector3.ZERO, "slot", "any"],
	[["chimney_section"], "fireplace", Vector3.ZERO, "slot", "any"],
	[["chimney_top"], "chimney_section", Vector3.ZERO, "top", "above"],
]


func _audit() -> void:
	var specs := {}
	for row in AUDIT:
		for shape in row[0]:
			specs[shape] = row
	var wrong := []
	var count := 0
	for folder in ["res://buildables", "res://buildables/structure", "res://buildables/round", "res://buildables/furniture"]:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".tres"):
				continue
			var buildable := load(folder.path_join(file)) as Buildable
			if buildable == null or buildable is PlotType or buildable is TemplateBuildable:
				continue
			count += 1
			var line: Array
			if buildable is PieceBuildable and not registry.shape_of((buildable as PieceBuildable).shape).get("furniture", false):
				var shape: String = (buildable as PieceBuildable).shape
				if shape.begins_with("beam"):
					line = await _audit_beam(buildable)
				elif PieceShapes.FLIGHTS.has(shape):
					line = await _audit_stairs(buildable)
				elif specs.has(shape):
					line = await _audit_piece(buildable, specs[shape])
				else:
					line = [false, "", false, "no audit case"]
			else:
				line = await _audit_furniture(buildable)
			print("SNAPAUDIT | %s | %s | %s | %s | %s" % [buildable.display_name, "yes" if line[0] else "no", line[1], "yes" if line[2] else "NO", line[3]])
			if not line[2]:
				wrong.append(buildable.display_name)
			await _clear()
	_check("snap audit: every buildable (%d) at its usual target comes out right" % count, wrong.is_empty() and count > 0, "wrong: %s" % ", ".join(wrong) if not wrong.is_empty() else "all %d" % count)


# One building piece at its usual target: [snapped, corners met, right, note]
func _audit_piece(buildable: PieceBuildable, spec: Array) -> Array:
	var shape := buildable.shape
	var def := registry.shape_of(shape)
	var target_shape: String = spec[1] if spec[1] != "" else shape
	var target := _spawn_shape(target_shape, spec[2])
	await _frames(2)
	var pair := _target_pair(target, spec[3], def)
	if pair.is_empty():
		return [false, "", false, "no %s corners on the %s" % [spec[3], target_shape]]
	var expected := _expected(shape, def, target, pair, spec[4])
	if expected.is_empty():
		return [false, "", false, "nowhere its corners fit the %s's %s" % [target_shape, spec[3]]]
	var e: Transform3D = expected[0]
	var notches := roundi(_turn_of(e, target) / 22.5)
	if absf(_turn_of(e, target) - notches * 22.5) > EXACT_TURN:
		return [false, "", false, "it fits at %.1f°, which the wheel can't reach" % _turn_of(e, target)]
	bp.begin(buildable)
	await _frames(2)
	await _turn_to(notches)
	# Aimed where it should go (its origin), from outside the target; if the crosshair wouldn't
	# land there (it's in the air), aimed at the target just inside the corners it should meet
	var middle: Vector3 = pair[0]
	if pair.size() > 1:
		middle = ((pair[0] as Vector3) + (pair[1] as Vector3)) / 2.0
	var out := middle - target.center()
	out.y = 0.0
	out = out.normalized() if out.length() > 0.05 else e.basis.z
	var aim := e * (ValheimPlacer.hold_point(def) + Vector3(0.06, 0, 0.05))
	var eye := aim + out * 2.8 + Vector3.UP * 1.6
	var hit := pp._cast_ray(eye, eye + (aim - eye) * 1.5)
	if hit.is_empty() or (hit["position"] as Vector3).distance_to(aim) > 0.3:
		# (its hold point is in the air: aimed at the target by the corners it should meet, from
		# across the target, as a player reaching over it would)
		aim = middle + (target.center() - middle).normalized() * 0.08
		eye = aim - out * 2.8 + Vector3.UP * 1.6
	await _aim(_local(eye), _local(aim))
	var result := _judge(def, shape, target, expected, pair.size())
	if not result[2]:
		var seen := pp._cast_ray(eye, eye + (aim - eye) * 1.5)
		var probe := pp._cast_ray(target.center() + Vector3.UP * 3.0, target.center() + Vector3.DOWN * 3.0)
		result[3] += " [crosshair on %s at %s; eye %s aim %s; straight down onto the target hits %s at %s]" % [(seen["collider"] as Node).name if not seen.is_empty() else "nothing", _local(seen["position"]).snapped(Vector3.ONE * 0.01) if not seen.is_empty() else "-", _local(eye).snapped(Vector3.ONE * 0.01), _local(aim).snapped(Vector3.ONE * 0.01), (probe["collider"] as Node).name if not probe.is_empty() else "nothing", _local(probe["position"]).snapped(Vector3.ONE * 0.01) if not probe.is_empty() else "-"]
	return result


# Beams: straight ones from pole top to pole top (aimed at the near pole's top from behind it),
# diagonals from a low point (a pole top, or a floor corner) up to a taller pole's top (aimed at
# that pole's top from beyond it)
func _audit_beam(buildable: PieceBuildable) -> Array:
	var shape := buildable.shape
	var def := registry.shape_of(shape)
	var ends: Array = SnapCorners.of(shape, def)
	var span: Vector3 = (ends[1] as Vector3) - (ends[0] as Vector3)
	var length := Vector2(span.x, span.z).length()
	var rise := absf(span.y)
	var target: BuildPiece
	var low := Vector3.ZERO
	var tall: float = PieceShapes.POLE_HEIGHTS["pole_2"]
	if rise < 0.01:
		target = _spawn("structure/pole_2", Vector3.ZERO)
		_spawn("structure/pole_2", Vector3(length, 0, 0))
		low = Vector3(0, tall, 0)
	else:
		_spawn("structure/floor", Vector3(-1, 0, -1))
		# (and one under where the beam goes, to aim along it)
		_spawn("structure/floor", Vector3(1, 0, -1))
		if rise < 1.5:
			_spawn("structure/pole_1", Vector3.ZERO)
			low = Vector3(0, PieceShapes.POLE_HEIGHTS["pole_1"], 0)
		target = _spawn("structure/pole_2", Vector3(length, low.y + rise - tall, 0))
	await _frames(2)
	var high := low + Vector3(length, rise, 0)
	var expected := []
	for flip in [0.0, PI]:
		var basis := Basis(Vector3.UP, flip)
		for a in ends:
			var where := Transform3D(basis, O + low - basis * (a as Vector3))
			var other: Vector3 = where * (ends[1] if a == ends[0] else ends[0])
			if _local(other).distance_to(high) < EXACT:
				expected.append(where)
	if expected.is_empty():
		return [false, "", false, "its ends can't reach from %s to %s" % [low, high]]
	bp.begin(buildable)
	await _frames(2)
	await _unsnap()
	await _turn_to(roundi(_turn_of(expected[0], target) / 22.5))
	# (aimed at the low end's spot from behind it: a pole top, or on the floors a little way along the
	# beam's span from their shared corner; held by its middle, a beam aimed right at the corner
	# would have its low end as near the first floor's far corner as this one)
	await _aim(low + Vector3(-2.5, 1.2, 0.3), low + (Vector3(0.6, 0, -0.03) if low.y < 0.5 else Vector3(-0.03, 0, 0.02)))
	return _judge(def, shape, target, expected, 2)


# A flight of stairs (Stairs, Half Stairs), by ordinary snapping: between a floor
# exactly its height up and the floors below, turned with the wheel (180°) and aimed at the floor
# below where the flight goes: its bottom corners on the floors' seam, its top meeting the upper
# floor's edge, the header and footing boards each 0 mm from what they meet
func _audit_stairs(buildable: PieceBuildable) -> Array:
	var height: float = PieceShapes.FLIGHTS[buildable.shape][0]
	var length: float = PieceShapes.FLIGHTS[buildable.shape][1]
	var upper := _spawn("structure/floor", Vector3(0, height, 0))
	var lowers := {}
	for z in [2.0, 4.0, 6.0]:
		lowers[z] = _spawn("structure/floor", Vector3(0, 0, z))
	await _frames(2)
	bp.begin(buildable)
	await _frames(2)
	await _unsnap()
	await _turn_to(8)
	var mid := 1.0 + length / 2.0
	await _aim(Vector3(0.3, 1.7, mid + 2.6), Vector3(0.1, 0.0, mid + 0.1))
	var seen := pp._cast_ray(player.camera.global_position, player.camera.global_position - player.camera.global_basis.z * 8.0)
	var expected := Transform3D(Basis(Vector3.UP, PI), O + Vector3(0, 0, mid))
	var sinks_into := pp._pieces_round(pp._target).filter(func(p): return PieceOverlap.overlaps(pp._shape_name, pp._shape, expected, p)).map(func(p): return _name(p)) if pp._target else []
	var r := await _flight_result(buildable.shape, "bottom", upper, lowers[length], Vector3(0, height, 1), Vector3(0, 0, 1 + length))
	await _turn_to(0)
	var why := " [crosshair on %s at %s; at the expected spot it would sink into: %s]" % [(seen["collider"] as Node).name if not seen.is_empty() else "nothing", _local(seen["position"]).snapped(Vector3.ONE * 0.01) if not seen.is_empty() else "-", sinks_into]
	return [not pp._pair.is_empty(), "2 of 4 (bottom), the top on the upper edge" if r["ok"] else "", r["ok"], "" if r["ok"] else r["detail"] + why]


# Furniture (and the workbench, chest, campfire and lean-to): stands on a floor, aimed at its middle
func _audit_furniture(buildable: Buildable) -> Array:
	_spawn("structure/floor", Vector3.ZERO)
	await _frames(2)
	bp.begin(buildable)
	await _frames(2)
	await _aim(Vector3(0.3, 2.2, 2.6), Vector3(0.1, 0.0, 0.1))
	var at := Vector3.INF
	if pp.is_placing() and pp._preview and pp._preview.visible:
		at = pp._where.origin
	elif bp._preview and bp._preview.visible:
		at = bp._preview.global_position
	var standing := at != Vector3.INF and absf(_local(at).y) < EXACT
	return [standing, "stands on the floor" if standing else "", standing, "" if standing else "not standing on the floor (%s)" % (_local(at).snapped(Vector3.ONE * 0.01) if at != Vector3.INF else "no preview")]


# What came out: [snapped, corners met (of the ghost's, by number), right, note]. Right: in one of
# the expected places (within EXACT and EXACT_TURN, its symmetry allowed for), not sunk into the
# target, at least `need` corners met (2, or 1 for posts and pieces put on a single corner).
func _judge(def: Dictionary, shape: String, target: BuildPiece, expected: Array, need: int) -> Array:
	var snapped := not pp._pair.is_empty()
	var where := pp._where
	var corners := []
	for piece in registry.all_pieces():
		corners.append_array(SnapCorners.in_world(piece))
	var met := []
	var own: Array = SnapCorners.of(shape, def)
	for i in own.size():
		var at: Vector3 = where * (own[i] as Vector3)
		if corners.any(func(c): return (c as Vector3).distance_to(at) < EXACT):
			met.append(str(i))
	var symmetry: float = def.get("symmetry", 0.0)
	var placed := false
	for e in expected:
		if (e as Transform3D).origin.distance_to(where.origin) < EXACT and _same_turn((e as Transform3D).basis, where.basis, symmetry):
			placed = true
	var sunk: bool = PieceOverlap.overlaps(shape, def, where, target)
	var right: bool = snapped and placed and not sunk and met.size() >= mini(need, own.size())
	var notes := []
	if not snapped:
		notes.append("didn't snap (target %s)" % _name(pp._target))
	elif not placed:
		notes.append("landed at %s, %.1f° (expected %s, %.1f°)" % [_local(where.origin).snapped(Vector3.ONE * 0.01), _turn_of(where, target), _local((expected[0] as Transform3D).origin).snapped(Vector3.ONE * 0.01), _turn_of(expected[0], target)])
	if sunk:
		notes.append("sinks into the target")
	return [snapped, "%d of %d (%s)" % [met.size(), own.size(), ",".join(met)], right, "; ".join(notes)]


# The target's corners the piece should meet: "far_edge" (the two top corners furthest along +Z),
# "top" (the two highest, furthest apart), "low" (the two lowest, furthest apart), "high" (as top),
# "side" (the two furthest along +X), "width" (the two exactly as far apart as the piece is wide),
# "slope" (the two with the biggest rise between them), "arc" (the two furthest from the target's
# origin), "round_side" (the origin's corner and the arc end on +X), "corner" (the top corner
# furthest along +X+Z), "slot" (two of the points where a door or chimney goes, the lowest)
func _target_pair(target: BuildPiece, rule: String, def: Dictionary) -> Array:
	var world := SnapCorners.in_world(target)
	var inv := target.global_transform.affine_inverse()
	var local := world.map(func(w): return inv * (w as Vector3))
	var top := -INF
	for p in local:
		top = maxf(top, (p as Vector3).y)
	var pick := func(score: Callable, filter: Callable) -> Array:
		var best := []
		var best_score := -INF
		for i in local.size():
			for j in range(i + 1, local.size()):
				var a: Vector3 = local[i]
				var b: Vector3 = local[j]
				if not filter.call(a, b):
					continue
				var s: float = score.call(a, b)
				if s > best_score + 0.001:
					best_score = s
					best = [world[i], world[j]]
		return best
	match rule:
		"far_edge":
			return pick.call(func(a, b): return a.z + b.z + a.distance_to(b) * 0.01, func(a, b): return absf(a.y - top) < 0.01 and absf(b.y - top) < 0.01 and absf(a.z - b.z) < 0.01)
		"top", "high":
			return pick.call(func(a, b): return a.y + b.y + a.distance_to(b) * 0.01, func(a, b): return absf(a.y - b.y) < 0.01)
		"low":
			return pick.call(func(a, b): return -(a.y + b.y) + a.distance_to(b) * 0.01, func(a, b): return absf(a.y - b.y) < 0.01)
		"side":
			return pick.call(func(a, b): return a.x + b.x - (a.y + b.y) * 0.001, func(a, b): return absf(a.x - b.x) < 0.01)
		"width":
			var width := PieceShapes.bounds_of(def).size.x
			return pick.call(func(a, b): return a.y + b.y, func(a, b): return absf(a.y - top) < 0.01 and absf(b.y - top) < 0.01 and absf(Vector2(a.x - b.x, a.z - b.z).length() - width) < 0.02)
		"slope":
			return pick.call(func(a, b): return absf(a.y - b.y), func(a, b): return Vector2(a.x - b.x, a.z - b.z).length() > 0.5)
		"arc":
			return pick.call(func(a, b): return Vector2(a.x, a.z).length() + Vector2(b.x, b.z).length() + a.y + b.y, func(a, b): return absf(a.y - b.y) < 0.01)
		"round_side":
			return pick.call(func(a, b): return a.x + b.x - (Vector2(a.x, a.z).length() if Vector2(a.x, a.z).length() < 0.05 else 0.0), func(a, b): return absf(a.y - top) < 0.01 and absf(b.y - top) < 0.01 and minf(Vector2(a.x, a.z).length(), Vector2(b.x, b.z).length()) < 0.05)
		"corner":
			var best := -1
			for i in local.size():
				var p: Vector3 = local[i]
				if absf(p.y - top) < 0.01 and (best < 0 or p.x + p.z > (local[best] as Vector3).x + (local[best] as Vector3).z):
					best = i
			return [world[best]] if best >= 0 else []
		"slot":
			var own_corners := SnapCorners._merged(SnapCorners._own_corners(target.buildable.shape, target.shape_def()))
			var slots := []
			for w in world:
				if not own_corners.any(func(c): return (target.global_transform * (c as Vector3)).distance_to(w) < 0.01):
					slots.append(w)
			var low := INF
			for s in slots:
				low = minf(low, (s as Vector3).y)
			var bottom := slots.filter(func(s): return absf((s as Vector3).y - low) < 0.01)
			if bottom.size() < 2:
				return []
			bottom.sort_custom(func(a, b): return (a as Vector3).x + (a as Vector3).z < (b as Vector3).x + (b as Vector3).z)
			return [bottom[0], bottom[-1]]
	return []


# Where a piece of `shape` fits with its corners on `pair` (two target corners: two of its corners
# exactly on them, turned only round the upright; one: one of its corners on it, at any 22.5° turn),
# on `side` of them ("outside": beyond them, away from the target's middle; "above"/"below": its
# middle higher/lower than them; "behind": on the target's -Z side; "inside": nearer the target's
# origin; "any"), never sunk into the target. Most wanted first (the smallest turn against the target).
func _expected(shape: String, def: Dictionary, target: BuildPiece, pair: Array, side: String) -> Array:
	var own: Array = SnapCorners.of(shape, def)
	var found := []
	if pair.size() == 1:
		for k in 16:
			var basis := Basis(Vector3.UP, deg_to_rad(_yaw(target.global_basis) + k * 22.5))
			for a in own:
				found.append(Transform3D(basis, (pair[0] as Vector3) - basis * (a as Vector3)))
	else:
		var p: Vector3 = pair[0]
		var q: Vector3 = pair[1]
		var d := q - p
		for a in own:
			for b in own:
				if a == b or absf(((b as Vector3) - (a as Vector3)).y - d.y) > 0.01:
					continue
				var hb := Vector2((b as Vector3).x - (a as Vector3).x, (b as Vector3).z - (a as Vector3).z)
				var hd := Vector2(d.x, d.z)
				if absf(hb.length() - hd.length()) > 0.01 or hd.length() < 0.01:
					continue
				var basis := Basis(Vector3.UP, atan2(hd.x, hd.y) - atan2(hb.x, hb.y))
				found.append(Transform3D(basis, p - basis * (a as Vector3)))
	var middle := ((pair[0] as Vector3) + (pair[-1] as Vector3)) / 2.0
	# (the piece's middle: the middle of its corners, which for a triangle is inside it)
	var own_middle := Vector3.ZERO
	for a in own:
		own_middle += (a as Vector3) / own.size()
	var target_middle := target.center()
	var kept := found.filter(func(w):
		var c: Vector3 = (w as Transform3D) * own_middle
		var outward := middle - target_middle
		outward.y = 0.0
		var away := c - middle
		away.y = 0.0
		var ok := true
		match side:
			"outside":
				ok = away.dot(outward) > 0.05
			"down_out":
				ok = away.dot(outward) > 0.05 and c.y < middle.y - 0.05
			"above":
				ok = c.y > middle.y + 0.05
			"below":
				ok = c.y < middle.y - 0.05
			"behind":
				ok = (target.global_transform.affine_inverse() * c).z < -0.05 and c.y > middle.y + 0.05
			"inside":
				var o := target.global_position
				ok = Vector2(c.x - o.x, c.z - o.z).length() < Vector2(middle.x - o.x, middle.z - o.z).length() - 0.05
		return ok and not PieceOverlap.overlaps(shape, def, w, target))
	kept.sort_custom(func(a, b): return absf(wrapf(_turn_of(a, target), -180.0, 180.0)) < absf(wrapf(_turn_of(b, target), -180.0, 180.0)))
	return kept


# How far `where` is turned against the target (degrees, 0 to 360)
func _turn_of(where: Transform3D, target: BuildPiece) -> float:
	var a := fposmod(_yaw(where.basis) - _yaw(target.global_basis), 360.0)
	return 0.0 if a > 359.95 else a


func _same_turn(a: Basis, b: Basis, symmetry: float) -> bool:
	var step := rad_to_deg(symmetry) if symmetry > 0.0 else 360.0
	var apart := fposmod(_yaw(a) - _yaw(b) + step / 2.0, step) - step / 2.0
	return absf(apart) < EXACT_TURN


func _spawn_shape(shape: String, local: Vector3) -> BuildPiece:
	for folder in ["structure", "round", "furniture"]:
		var path := "res://buildables/%s/%s.tres" % [folder, shape]
		if ResourceLoader.exists(path):
			return registry.spawn(load(path), Transform3D(Basis.IDENTITY, O + local), {})
	return null


# ---- Helpers ----

func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("SNAPTEST %s %s (%s)" % ["PASS" if ok else "FAIL", what, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# Flat, open, dry ground near the start, 14 m across: the cases are built round O (y: the ground)
func _find_spot() -> bool:
	var valley = get_tree().get_first_node_in_group("valley")
	var water: float = valley.global_position.y + valley.water_height() if valley else -INF
	var start: Vector3 = player.global_position
	for r in [10.0, 16.0, 22.0, 28.0, 34.0, 40.0, 48.0, 56.0, 64.0]:
		for k in 16:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0) * r
			var ground := Plot.ground_at(player, c.x, c.z)
			if ground < water + 1.0:
				continue
			var ok := true
			for dx in [-7.0, -3.5, 0.0, 3.5, 7.0]:
				for dz in [-7.0, -3.5, 0.0, 3.5, 7.0]:
					var p := Vector3(c.x + dx, ground, c.z + dz)
					if absf(Plot.ground_at(player, p.x, p.z) - ground) > 0.3:
						ok = false
					var hit := pp._cast_ray(p + Vector3.UP * 40.0, p + Vector3.DOWN * 40.0)
					if hit.is_empty() or not (hit["collider"] as Node).is_in_group("terrain_ground"):
						ok = false
			if ok:
				O = Vector3(c.x, ground + 0.03, c.z)
				return true
	return false


func _spawn(path: String, local: Vector3, yaw_degrees := 0.0) -> BuildPiece:
	var piece: PieceBuildable = load("res://buildables/%s.tres" % path)
	return registry.spawn(piece, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), O + local), {})


func _clear() -> void:
	bp.cancel()
	for p in registry.all_pieces():
		registry.remove(p)
	await _frames(2)


# Starts placing something as the build menu does
func _begin(path: String) -> void:
	bp.cancel()
	bp.begin(load("res://buildables/%s.tres" % path))
	await _frames(3)


# Points the camera from `eye` at `at` (both round O): the crosshair, followed by the placer
func _aim(eye: Vector3, at: Vector3) -> void:
	var from := O + eye
	var to := O + at - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(4)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# Real mouse wheel notches through the input system (negative: down), Shift held as the event says
func _wheel(notches: int, shift := false) -> void:
	var centre := get_viewport().get_visible_rect().size / 2.0
	for i in absi(notches):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_WHEEL_UP if notches > 0 else MOUSE_BUTTON_WHEEL_DOWN
		press.pressed = true
		press.shift_pressed = shift
		press.position = centre
		press.global_position = centre
		_send(press)
		var release: InputEventMouseButton = press.duplicate()
		release.pressed = false
		_send(release)
	await _frames(3)


# Wheel notches until the turn is `notches` × 22.5° (the turn stays from case to case, as it does
# for the player: only the wheel changes it)
func _turn_to(notches: int) -> void:
	var now := roundi(rad_to_deg(pp.turn) / 22.5)
	var diff := posmod(notches - now, 16)
	if diff > 8:
		diff -= 16
	await _wheel(diff)


# A key pressed and let go `times` times, as real key events through the input system
func _press(code: Key, times := 1) -> void:
	for i in times:
		var press := InputEventKey.new()
		press.keycode = code
		press.physical_keycode = code
		press.pressed = true
		_send(press)
		var release: InputEventKey = press.duplicate()
		release.pressed = false
		_send(release)
	await _frames(3)


# Shift pressed (held down) or let go, as a real key event through the input system
func _shift(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = down
	event.shift_pressed = down
	_send(event)
	await _frames(4)


func _panel() -> String:
	return str(bp.hud_state().get("info", {}).get("detail", ""))


# The panel's turn in degrees (no "Turn" in it: 0°)
func _turn() -> float:
	var regex := RegEx.create_from_string("Turn (-?\\d+(?:\\.\\d+)?)°")
	var found := regex.search(_panel())
	return float(found.get_string(1)) if found else 0.0


# How far the ghost is turned against a piece (degrees, 0 to 360)
func _turned_against(piece: BuildPiece) -> float:
	if piece == null:
		return -1.0
	var a := fposmod(_yaw(pp._where.basis) - _yaw(piece.global_basis), 360.0)
	return 0.0 if a > 359.5 else a


func _name(piece: BuildPiece) -> String:
	return piece.display_name() if piece else "none"


func _local(p: Vector3) -> Vector3:
	return p - O


static func _yaw(b: Basis) -> float:
	return rad_to_deg(atan2(b.z.x, b.z.z))
