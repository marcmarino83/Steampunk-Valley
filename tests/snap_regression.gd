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
## The controls row while placing, exactly
const CONTROL_KEYS := ["LMB", "Wheel", "Hold Shift", "MMB", "RMB"]

var player: Node
var pp: ValheimPlacer
var bp: BuildPlacer
var registry: PieceRegistry
var O := Vector3.ZERO
var passed := 0
var failed := 0


func _ready() -> void:
	_run.call_deferred()


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
	await _case_floor_beside()
	await _case_hole()
	await _case_wall_edge()
	await _case_doorway()
	await _case_roof()
	await _case_pole_and_beam()
	await _case_stairs()
	await _case_pillar_fan()
	await _case_shift()
	await _case_floor_on_floor()
	var half := PieceShapes.HALF_HEIGHT
	await _case_turning("a half wall on top of a half wall", "structure/wall_half_2", "structure/wall_half_2", Vector3(0.6, half + 1.4, 3.2), Vector3(0.3, half, 0.0), Vector3(0, half, 0))
	await _case_turning("a wall beside a wall", "structure/wall", "structure/wall", Vector3(3.6, 1.7, 3.2), Vector3(1.9, -0.03, 0.12), Vector3(2, 0, 0))
	await _case_turning("a floor beside a floor", "structure/floor", "structure/floor", Vector3(0.3, 1.7, 5.0), Vector3(0.1, -0.03, 2.2), Vector3(0, 0, 2))
	await _case_every_buildable()
	await _audit()
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
	_spawn("structure/pole_2", Vector3.ZERO)
	_spawn("structure/pole_2", Vector3(2.0, 0, 0))
	await _frames(2)
	await _begin("structure/beam_2")
	await _turn_to(0)
	await _aim(Vector3(-2.5, 3.2, 0.3), Vector3(0.02, 2.0, 0.02))
	var a := INF
	var b := INF
	for c in SnapCorners.of("beam_2", pp._shape):
		var at := _local(pp._where * (c as Vector3))
		a = minf(a, at.distance_to(Vector3(0, 2, 0)))
		b = minf(b, at.distance_to(Vector3(2, 2, 0)))
	_check("beam from pole top to pole top: an end on each", pp._target != null and a < EXACT and b < EXACT, "ends %.4f m and %.4f m from the pole tops" % [a, b])
	await _clear()


# Stairs aimed at a foundation's edge corner, turned 8 notches (180°): their bottom corners on the
# edge's corners, climbing over the foundation
func _case_stairs() -> void:
	_spawn("structure/foundation_wood", Vector3(0, 1.0, 0))
	await _frames(2)
	await _begin("structure/stairs")
	await _turn_to(8)
	await _aim(Vector3(1.5, 2.8, 4.0), Vector3(0.8, 1.0, 0.85))
	var on_edge := 0
	var climbing := false
	for c in SnapCorners.of("stairs", pp._shape):
		var at := _local(pp._where * (c as Vector3))
		if absf(at.y - 1.0) < EXACT and absf(at.z - 1.0) < EXACT and absf(absf(at.x) - 1.0) < EXACT:
			on_edge += 1
		if at.y > 2.0:
			climbing = at.z < 0.0
	_check("stairs turned 180° at a foundation edge: bottom corners on the edge's, climbing over it", pp._target != null and on_edge == 2 and climbing, "%d bottom corners on the edge, climbing over the foundation %s" % [on_edge, climbing])
	await _turn_to(0)
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
			if keys != CONTROL_KEYS:
				problems.append("controls %s" % [keys])
			if not problems.is_empty():
				wrong.append("%s (%s)" % [buildable.display_name, ", ".join(problems)])
	bp.cancel()
	_check("every buildable (%d): corners (none for furniture), wheel turns 22.5°, the five controls" % count, wrong.is_empty() and count > 0, "wrong: %s" % ", ".join(wrong) if not wrong.is_empty() else "all %d" % count)


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
	[["floor", "floor_1", "foundation_wood", "foundation_stone"], "", Vector3.ZERO, "far_edge", "outside"],
	[["floor_rtri", "floor_tri45"], "floor", Vector3.ZERO, "far_edge", "outside"],
	[["foundation_wood_rtri", "foundation_stone_rtri", "foundation_wood_tri45", "foundation_stone_tri45"], "foundation_wood", Vector3.ZERO, "far_edge", "outside"],
	[["round_floor", "round_floor_22", "round_foundation_wood", "round_foundation_stone", "round_foundation_wood_22", "round_foundation_stone_22"], "", Vector3.ZERO, "round_side", "outside"],
	[["wall", "doorway", "window", "wall_half_2", "wall_strip_2", "window_split_2", "railing_2", "fence", "gable_wall_45"], "foundation_wood", Vector3.ZERO, "far_edge", "above"],
	[["wall_1", "wall_half_1", "wall_quarter", "wall_strip_1", "window_split_1", "railing_1"], "floor_1", Vector3.ZERO, "far_edge", "above"],
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
	[["pole_1", "pole_2", "pillar_wood", "pillar_stone"], "floor", Vector3.ZERO, "corner", "above"],
	[["stairs"], "floor", Vector3(0, 2.5, 0), "far_edge", "down_out"],
	[["foundation_steps"], "foundation_wood", Vector3(0, 1.0, 0), "far_edge", "down_out"],
	[["ladder"], "floor", Vector3(0, 2.0, 0), "corner", "below"],
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
	if rise < 0.01:
		target = _spawn("structure/pole_2", Vector3.ZERO)
		_spawn("structure/pole_2", Vector3(length, 0, 0))
		low = Vector3(0, 2.0, 0)
	else:
		_spawn("structure/floor", Vector3(-1, 0, -1))
		if rise < 1.5:
			_spawn("structure/pole_1", Vector3.ZERO)
			low = Vector3(0, 1.0, 0)
		target = _spawn("structure/pole_2", Vector3(length, low.y + rise - 2.0, 0))
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
	await _turn_to(roundi(_turn_of(expected[0], target) / 22.5))
	# (aimed at the low end's spot from behind it: a pole top, or the floor's corner)
	await _aim(low + Vector3(-2.5, 1.2, 0.3), low + Vector3(-0.03, 0, -0.03 if low.y < 0.5 else 0.02))
	return _judge(def, shape, target, expected, 2)


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
