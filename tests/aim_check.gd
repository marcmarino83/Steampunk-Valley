extends Node
## The aim check: random aim points over each built-in template; at each, every building piece type
## at every wheel step (16), through the real placer. Each try passes when the piece is either free
## (not snapped) or snapped next to the crosshair (its body within 0.5 m of the crosshair's line) and
## resting on whole edges, never hanging from a single point: at least two of its corners lie on
## other pieces' corners or typed edges (pillars, poles and beams, which snap by a point: one), or,
## for whole-edge pieces, one of its edges lies along a placed edge over at least EDGE_CONTACT (a 2 m
## eave along a 0.5 m edge, say).
## Run headless:
##
##     godot --headless --path . res://tests/aim_check.tscn --fixed-fps 60 --quit-after 200000
##
## Prints "AIM FAMILY" lines (per family: tries, passes, hanging from a point, too far from the
## crosshair) and "AIM FAIL" examples for the converted families. Exit code: converted families'
## failed tries. `-- --old` runs every piece the old way (corners) to compare against.

const WORLD := "res://world/world.tscn"
const Family := preload("res://tests/snap_family.gd")
## Aim points per template, and the random seed (the same points every run)
const VIEWS := 5
const SEED := 20261111
const NEAR := 0.5
const EXACT := 0.001
## A whole-edge contact shares at least this much length (the shortest edges are 0.5 m)
const EDGE_CONTACT := 0.25
## Stop early (and say so) past this many seconds, to stay inside the run's time limit
const BUDGET := 150.0

var player: Node
var pp: ValheimPlacer
var bp: BuildPlacer
var registry: PieceRegistry
var O := Vector3.ZERO
var rng := RandomNumberGenerator.new()
# family -> [tries, passed, hanging, too far]
var by_family := {}
var converted_failed := 0
var examples := 0
var started := 0


func _ready() -> void:
	process_physics_priority = -100000
	_run.call_deferred()


func _run() -> void:
	started = Time.get_ticks_msec()
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
	pp.set_physics_process(false)
	if "--old" in OS.get_cmdline_user_args():
		pp.whole_edges = false
		print("AIM | the old placer (corners only) for every piece")
	if not _find_spot():
		print("AIM | no flat open ground found")
		get_tree().quit(1)
		return
	rng.seed = SEED
	var types := _piece_types()
	var stopped := false
	for file in DirAccess.get_files_at(BuildingTemplate.BUILT_IN_FOLDER):
		if not file.ends_with(".json") or stopped:
			continue
		stopped = not await _template(BuildingTemplate.BUILT_IN_FOLDER.path_join(file), types)
	var families := by_family.keys()
	families.sort()
	for f in families:
		var c: Array = by_family[f]
		print("AIM FAMILY %s: %d of %d tries pass (%.1f%%); hanging from a point %d; too far from the crosshair %d" % [f, c[1], c[0], 100.0 * c[1] / maxf(c[0], 1), c[2], c[3]])
	print("AIM SUMMARY: %d piece types, %d views per template%s; converted families' failed tries: %d" % [types.size(), VIEWS, " (stopped early: time budget)" if stopped else "", converted_failed])
	bp.cancel()
	get_tree().quit(converted_failed)


# Every building piece type (furniture left out)
func _piece_types() -> Array:
	var found := []
	for folder in ["res://buildables/structure", "res://buildables/round"]:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".tres"):
				continue
			var b = load(folder.path_join(file))
			if b is PieceBuildable and not registry.shape_of((b as PieceBuildable).shape).get("furniture", false):
				found.append(b)
	return found


# One template: laid out, VIEWS random aim points, every type at every wheel step at each. False if
# the time budget ran out.
func _template(path: String, types: Array) -> bool:
	var template := BuildingTemplate.read(path)
	var pieces := []
	for item in template.items:
		if item["buildable"] is PieceBuildable:
			pieces.append(registry.spawn(item["buildable"], Transform3D(Basis.IDENTITY, O) * (item["relative"] as Transform3D), {}))
	await _frames(3)
	var views := []
	var tries := 0
	while views.size() < VIEWS and tries < 200:
		tries += 1
		var v := _random_view(pieces)
		if not v.is_empty():
			views.append(v)
	for view in views:
		for b in types:
			if (Time.get_ticks_msec() - started) / 1000.0 > BUDGET:
				return false
			for n in 16:
				_try(b, n, view)
	print("AIM | %s: %d views done" % [template.template_name if template else path.get_file(), views.size()])
	for p in registry.all_pieces():
		registry.remove(p)
	await _frames(2)
	return true


# A random spot on a random building piece's surface, and an eye 2–3 m away with a clear view of it
# (the crosshair hitting that piece there): [eye, spot]
func _random_view(pieces: Array) -> Array:
	var piece: BuildPiece = pieces[rng.randi() % pieces.size()]
	if not is_instance_valid(piece) or piece.shape_def().get("furniture", false):
		return []
	var box := PieceShapes.bounds_of(piece.shape_def())
	var p := Vector3(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y), rng.randf_range(box.position.z, box.end.z))
	var axis := rng.randi() % 3
	p[axis] = box.position[axis] if rng.randf() < 0.5 else box.end[axis]
	var spot := piece.global_transform * p
	if spot.y < Plot.ground_at(player, spot.x, spot.z) + 0.05:
		return []
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	# (shuffled with the seeded generator, so every run tries the same views)
	var order := [0, 1, 2, 3, 4, 5, 6, 7]
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	for reach in [3.0, 2.0]:
		for h in [0.0, -1.0, 1.0, 2.0]:
			for k in order:
				var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 8.0 + rng.randf_range(-0.3, 0.3))
				var eye: Vector3 = spot + dir * reach + Vector3.UP * h
				if eye.y < Plot.ground_at(player, eye.x, eye.z) + 1.0:
					continue
				var q := PhysicsPointQueryParameters3D.new()
				q.position = eye
				q.exclude = [player.get_rid()]
				if not space.intersect_point(q, 1).is_empty():
					continue
				var hit := pp._cast_ray(eye, eye + (spot - eye).normalized() * ValheimPlacer.REACH)
				if not hit.is_empty() and hit["collider"] == piece and (hit["position"] as Vector3).distance_to(spot) < 0.3:
					return [eye, hit["position"]]
	return []


# One try: the piece started afresh, turned to wheel step `n` (real wheel notches), aimed, judged
func _try(b: PieceBuildable, n: int, view: Array) -> void:
	bp.cancel()
	bp.begin(b)
	_turn_to(n)
	var eye: Vector3 = view[0]
	var at: Vector3 = view[1]
	var to := at - eye
	player.global_position = eye - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	pp._follow_crosshair()
	var family: String = Family.of(b.shape)
	if not by_family.has(family):
		by_family[family] = [0, 0, 0, 0]
	var c: Array = by_family[family]
	c[0] += 1
	if pp._pair.is_empty():
		c[1] += 1
		return
	var from: Vector3 = player.camera.global_position
	var dir: Vector3 = -player.camera.global_basis.z
	var hit := pp._cast_ray(from, from + dir * ValheimPlacer.REACH)
	var line_end: Vector3 = (hit["position"] as Vector3) + dir * 0.1 if not hit.is_empty() else from + dir * ValheimPlacer.REACH
	var def := registry.shape_of(b.shape)
	var body: float = SnapEdges.box_distance(pp._where, PieceShapes.bounds_of(def), from, line_end)
	var slender: bool = def.get("slender", false) and not def.get("ladder", false)
	var held := _held_corners(b.shape, def, pp._where)
	var far := body > NEAR + EXACT
	# (a whole-edge piece rests on an edge: one of its edges along a placed one, over at least
	# EDGE_CONTACT, even where its longer edge reaches past the shorter one's ends)
	var whole_edge: bool = pp.whole_edges and SnapEdges.edge_shape(b.shape)
	var on_points: bool = pp.whole_edges and SnapEdges.point_shape(b.shape) and _on_typed_point(b.shape, def, pp._where)
	# (a floor's corner on a post top is a fit too: porches and stilt buildings)
	var on_post: bool = whole_edge and b.shape in SnapEdges.FLOORS and _corner_on_post_top(b.shape, def, pp._where)
	var hanging: bool = held < (1 if slender else 2) and not (whole_edge and _edge_contact(b.shape, def, pp._where)) and not on_points and not on_post
	if far:
		c[3] += 1
	if hanging:
		c[2] += 1
	if not far and not hanging:
		c[1] += 1
		return
	if SnapEdges.converted(b.shape) and pp.whole_edges:
		converted_failed += 1
		if examples < 20:
			examples += 1
			print("AIM FAIL | %s at step %d (%.1f°), aimed at %s %s: body %.2f m from the crosshair, %d corner%s held" % [b.display_name, n, n * 22.5, _name(hit.get("collider")), _local(at).snapped(Vector3.ONE * 0.01), body, held, "" if held == 1 else "s"])


# True if one of the piece's typed edges (at `where`) lies along another piece's typed edge, the two
# sharing at least EDGE_CONTACT of their length (whole-edge pieces only: others have no typed edges)
func _edge_contact(shape: String, def: Dictionary, where: Transform3D) -> bool:
	var mine := SnapEdges.of(shape, def)
	if mine.is_empty():
		return false
	var theirs := []
	for o in registry.pieces_near(where.origin, 6.0):
		if is_instance_valid(o):
			theirs.append_array(SnapEdges.in_world(o))
	for g in mine:
		var a: Vector3 = where * (g["a"] as Vector3)
		var b: Vector3 = where * (g["b"] as Vector3)
		var u := (b - a).normalized()
		var l := a.distance_to(b)
		for t in theirs:
			var c: Vector3 = t["a"]
			var d: Vector3 = t["b"]
			if c.distance_to(d) < EXACT or absf(u.dot((d - c).normalized())) < 0.999:
				continue
			if SnapEdges.point_segment(c, a - u * 100.0, b + u * 100.0) > 2.0 * EXACT or SnapEdges.point_segment(d, a - u * 100.0, b + u * 100.0) > 2.0 * EXACT:
				continue
			var s0 := (c - a).dot(u)
			var s1 := (d - a).dot(u)
			if minf(maxf(s0, s1), l) - maxf(minf(s0, s1), 0.0) >= EDGE_CONTACT:
				return true
	return false


# True if one of a point piece's typed points (at `where`) is on another piece's typed point (a beam
# crossing another at its middle, say)
func _on_typed_point(shape: String, def: Dictionary, where: Transform3D) -> bool:
	var theirs := []
	for o in registry.pieces_near(where.origin, 6.0):
		if is_instance_valid(o):
			theirs.append_array(SnapEdges.points_in_world(o))
	for m in SnapEdges.points_of(shape, def):
		var at: Vector3 = where * (m["p"] as Vector3)
		if theirs.any(func(q): return (q["p"] as Vector3).distance_to(at) <= EXACT):
			return true
	return false


# True if one of a floor's corners (at `where`) is on a pillar's or pole's top
func _corner_on_post_top(shape: String, def: Dictionary, where: Transform3D) -> bool:
	var tops := []
	for o in registry.pieces_near(where.origin, 6.0):
		if is_instance_valid(o):
			tops.append_array(SnapEdges.points_in_world(o).filter(func(q): return q["type"] == "post_top"))
	for c in SnapCorners.of(shape, def):
		var at: Vector3 = where * (c as Vector3)
		if tops.any(func(q): return (q["p"] as Vector3).distance_to(at) <= EXACT):
			return true
	return false


# How many of the piece's corners (at `where`) lie on another piece's corner or typed edge
func _held_corners(shape: String, def: Dictionary, where: Transform3D) -> int:
	var others := registry.pieces_near(where.origin, 6.0)
	var corners := []
	var edges := []
	for o in others:
		if not is_instance_valid(o):
			continue
		corners.append_array(SnapCorners.in_world(o))
		edges.append_array(SnapEdges.in_world(o))
	var count := 0
	for own in SnapCorners.of(shape, def):
		var p: Vector3 = where * (own as Vector3)
		var held: bool = corners.any(func(q): return (q as Vector3).distance_to(p) <= EXACT)
		if not held:
			held = edges.any(func(e): return SnapEdges.point_segment(p, e["a"], e["b"]) <= EXACT)
		if held:
			count += 1
	return count


# Wheel notches (real events through the input system) until the turn is `notches` × 22.5°
func _turn_to(notches: int) -> void:
	var now := roundi(rad_to_deg(pp.turn) / 22.5)
	var diff := posmod(notches - now, 16)
	if diff > 8:
		diff -= 16
	var centre := get_viewport().get_visible_rect().size / 2.0
	for i in absi(diff):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_WHEEL_UP if diff > 0 else MOUSE_BUTTON_WHEEL_DOWN
		press.pressed = true
		press.position = centre
		press.global_position = centre
		Input.parse_input_event(press)
		Input.flush_buffered_events()
		var release: InputEventMouseButton = press.duplicate()
		release.pressed = false
		Input.parse_input_event(release)
		Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _find_spot() -> bool:
	var valley = get_tree().get_first_node_in_group("valley")
	var water: float = valley.global_position.y + valley.water_height() if valley else -INF
	var start: Vector3 = player.global_position
	for r in [10.0, 16.0, 22.0, 28.0, 34.0, 40.0, 48.0, 56.0, 64.0, 80.0]:
		for k in 16:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0) * r
			var ground := Plot.ground_at(player, c.x, c.z)
			if ground < water + 1.0:
				continue
			var ok := true
			for dx in [-9.0, -4.5, 0.0, 4.5, 9.0]:
				for dz in [-9.0, -4.5, 0.0, 4.5, 9.0]:
					var p := Vector3(c.x + dx, ground, c.z + dz)
					if absf(Plot.ground_at(player, p.x, p.z) - ground) > 0.4:
						ok = false
					var hit := pp._cast_ray(p + Vector3.UP * 40.0, p + Vector3.DOWN * 40.0)
					if hit.is_empty() or not (hit["collider"] as Node).is_in_group("terrain_ground"):
						ok = false
			if ok:
				O = Vector3(c.x, ground + 0.03, c.z)
				return true
	return false


func _name(piece) -> String:
	return (piece as BuildPiece).display_name() if piece is BuildPiece else "the ground"


func _local(p: Vector3) -> Vector3:
	return p - O
