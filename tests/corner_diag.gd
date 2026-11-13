extends Node
## DIAGNOSTIC: snapping at crowded corners, and the cost of placing a piece, on a real save. Run:
##
##     godot [--headless] --path . res://tests/corner_diag.tscn --quit-after 40000 -- <save.json> [lag]
##
## Loads the save through SaveGame (marked a test run: nothing is saved) and, round where its player
## stands (within REACH):
##   - every floor and foundation edge with no wall standing along it, and for each wall-type piece the
##     fits of its foot along that edge (SnapEdges.placements): whether the placer would skip it as
##     "sinking into a piece of its own kind" (PieceOverlap, as ValheimPlacer._taken), and if so, which
##     piece and which sample point of whose lies how deep inside; then, for each spot skipped, the real
##     placer aimed at it from inside, as a player would (what it snapped to, and whether it's tilted)
##     ("CORNER" lines);
##   - with "lag": the spike logger on, pieces placed one after another through the placer's own place
##     call at free spots, each placement's own time, the frames after it and every timed system's
##     share ("LAG" lines).
## Then quits.

const REACH := 30.0
## The ones sent through the placer (both families, full, half and opening walls)
const PLACER_TYPES := ["wall", "wall_2m", "wall_half_2", "wall_half_2_tall", "doorway", "window_2m"]
const WALL_TYPES := ["wall", "wall_2m", "wall_half_2", "wall_half_2_tall", "wall_1", "wall_half_1", "wall_half_1_tall", "doorway", "doorway_2m", "window", "window_2m", "wall_strip_2", "wall_strip_2_tall"]

var player: Node
var registry: PieceRegistry
var pp: ValheimPlacer
var bp: BuildPlacer


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var save: String = args[0] if not args.is_empty() else ""
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	SaveGame.load_save(save)
	for i in 4000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player and SaveGame.get("_in_world"):
			break
	if player == null:
		print("CORNER | the world didn't open")
		get_tree().quit(1)
		return
	SaveGame.set("_test_run", true)
	DevCheats.freebuild = true
	bp = player._placer
	pp = bp._pieces
	registry = bp.registry
	for i in 120:
		await get_tree().process_frame
	player.set_physics_process(false)
	player._on_held_changed("Hammer")
	var home: Vector3 = player.global_position
	print("CORNER | %s: %d pieces; the player at %s" % [save.get_file(), registry.all_pieces().size(), home.snapped(Vector3.ONE * 0.01)])
	if args.has("lag"):
		await _lag(home)
	else:
		var spots := _scan(home)
		await _through_placer(spots)
	get_tree().quit()


# ---- Crowded spots ----

# Every fit of each wall type's foot along a floor edge with no wall on it, near `home`; prints those
# the sinking check would skip, and returns them: [{shape, where, edge, against, why}]
func _scan(home: Vector3) -> Array:
	var near := registry.pieces_near(home, REACH)
	var walls := near.filter(func(p): return (p as BuildPiece).shape_name in SnapEdges.WALLS or (p as BuildPiece).shape_name in SnapEdges.TRIANGLES)
	var skipped := []
	var tried := 0
	var by_shape := {}
	for f in near:
		var floor_piece := f as BuildPiece
		if not floor_piece.is_floor():
			continue
		for e in SnapEdges.in_world(floor_piece):
			if e["type"] != "floor_edge":
				continue
			# (an edge with a wall standing along it isn't a gap)
			if walls.any(func(w): return _stands_on(w, e)):
				continue
			for shape in WALL_TYPES:
				var def := registry.shape_of(shape)
				var step: float = (load(_path(shape)) as PieceBuildable).vertical_unit
				for c in SnapEdges.placements(shape, def, step, [e]):
					if c["own"]["type"] != "wall_base":
						continue
					tried += 1
					var where: Transform3D = c["where"]
					var hits := _sinks(shape, def, where, near)
					# (crowded: the old rule, any corner point over 5 cm inside a piece of its kind,
					# would have skipped it: these go through the placer below either way)
					var crowded := _crowded(shape, def, where, near)
					if hits.is_empty() and crowded.is_empty():
						continue
					if not hits.is_empty():
						by_shape[shape] = int(by_shape.get(shape, 0)) + 1
					skipped.append({"shape": shape, "where": where, "edge": e, "against": hits if not hits.is_empty() else crowded, "skipped": not hits.is_empty()})
	print("CORNER | %d wall fits tried along %d-m-reach floor edges with no wall on them; %d crowded (the old rule skipped them); %d skipped as sinking into a piece of their own kind now: %s" % [tried, int(REACH), skipped.size(), skipped.filter(func(s): return s["skipped"]).size(), by_shape])
	var shown := {}
	for s in skipped:
		var key := "%s@%s" % [s["shape"], (s["where"] as Transform3D).origin.snapped(Vector3.ONE * 0.1)]
		if shown.has(key):
			continue
		shown[key] = true
		print("CORNER | skipped | %s at %s turned %.0f° | %s" % [s["shape"], (s["where"] as Transform3D).origin.snapped(Vector3.ONE * 0.01), rad_to_deg(_yaw((s["where"] as Transform3D).basis)), "; ".join(s["against"])])
	return skipped


# The pieces of the same kind a fit would count as sinking into (as ValheimPlacer._taken), each with
# the deepest sample point found and whose it is
func _sinks(shape: String, def: Dictionary, where: Transform3D, near: Array) -> Array:
	var found := []
	var kind := SnapEdges.kind(shape)
	for p in near:
		var other := p as BuildPiece
		if SnapEdges.kind(other.shape_name) != kind or not PieceOverlap.overlaps(shape, def, where, other):
			continue
		found.append("%s #%d at %s turned %.0f° (%s)" % [other.shape_name, other.piece_id, other.global_position.snapped(Vector3.ONE * 0.01), rad_to_deg(_yaw(other.global_basis)), _deepest(shape, def, where, other)])
	return found


# The pieces of the same kind the old rule counted a fit as sinking into (any corner, middle or
# halfway point over 5 cm inside), with the deepest point
func _crowded(shape: String, def: Dictionary, where: Transform3D, near: Array) -> Array:
	var found := []
	var kind := SnapEdges.kind(shape)
	for p in near:
		var other := p as BuildPiece
		if SnapEdges.kind(other.shape_name) != kind or def.get("slender", false) or other.shape_def().get("slender", false):
			continue
		var deepest := _deepest(shape, def, where, other)
		if deepest != "":
			found.append("%s #%d (%s; now %.0f%% of a piece inside the other)" % [other.shape_name, other.piece_id, deepest, 100.0 * PieceOverlap.share_inside(shape, def, where, other.shape_name, other.shape_def(), other.global_transform)])
	return found


# Which sample point lies inside which piece, how deep on its shallowest side
func _deepest(shape: String, def: Dictionary, where: Transform3D, other: BuildPiece) -> String:
	var best := ""
	var depth := 0.0
	for pair in [[shape, def, where, other.shape_name, other.shape_def(), other.global_transform, "the new piece's"], [other.shape_name, other.shape_def(), other.global_transform, shape, def, where, "its"]]:
		var mine := PieceOverlap._info(pair[0], pair[1])
		var theirs := PieceOverlap._info(pair[3], pair[4])
		var to_parts: Transform3D = (pair[5] as Transform3D).affine_inverse() * (pair[2] as Transform3D)
		for part in theirs["parts"]:
			var into: Transform3D = (part["inverse"] as Transform3D) * to_parts
			for s in mine["samples"]:
				var p: Vector3 = into * (s as Vector3)
				var least := INF
				for plane in part["planes"]:
					least = minf(least, -(plane as Plane).distance_to(p))
				if least > PieceOverlap.MARGIN and least > depth:
					depth = least
					best = "%s point %s (in its own space) %.3f m deep" % [pair[6], (s as Vector3).snapped(Vector3.ONE * 0.01), least]
	return best


func _stands_on(w: BuildPiece, e: Dictionary) -> bool:
	for g in SnapEdges.in_world(w):
		if g["type"] == "wall_base" and SnapEdges.along(g["a"], g["b"], e["a"], e["b"]):
			return true
	return false


# Each skipped spot (one per shape and place) aimed at with the real placer from inside the room, as a
# player would: the crosshair on the floor just inside the edge's middle, from 2.5 m in and 1.7 m up
func _through_placer(spots: Array) -> void:
	var done := {}
	var right := 0
	var count := 0
	var no_view := 0
	for s in spots:
		var where: Transform3D = s["where"]
		var key := "%s@%s" % [s["shape"], where.origin.snapped(Vector3.ONE * 0.1)]
		if done.has(key) or not s["shape"] in PLACER_TYPES:
			continue
		done[key] = true
		var e: Dictionary = s["edge"]
		# (aimed 30% along the gap, not at its middle: at a T the perpendicular edge meets the gap at
		# its middle, and a crosshair there is on both edges at once)
		var mid: Vector3 = (e["a"] as Vector3).lerp(e["b"], 0.3)
		var out: Vector3 = e.get("out", Vector3.ZERO)
		if out == Vector3.ZERO:
			out = (where.basis.z).normalized()
		var inward := -Vector3(out.x, 0, out.z).normalized()
		# (a clear view: the crosshair's first hit on the floor just inside the edge's middle, from
		# inside the room or outside it, near or farther, straight on or a little to the side)
		var at := mid + inward * 0.15
		var eye := Vector3.INF
		var along: Vector3 = ((e["b"] as Vector3) - (e["a"] as Vector3)).normalized()
		for side in [inward, -inward]:
			for d in [2.0, 3.0, 1.4]:
				# (a little to the side first: straight out from the gap's middle the eye is often right
				# over a perpendicular edge meeting it there, the crosshair's line running along that
				# edge, and the wall on it is as much aimed at as the gap)
				for slant in [0.6, -0.6, 0.0]:
					var try_eye: Vector3 = mid + ((side as Vector3) + along * slant).normalized() * d + Vector3.UP * 1.7
					var aim_at: Vector3 = mid + (side as Vector3) * 0.15
					var hit := pp._cast_ray(try_eye, try_eye + (aim_at - try_eye) * 2.0)
					if eye == Vector3.INF and not hit.is_empty() and (hit["position"] as Vector3).distance_to(aim_at) < 0.12:
						eye = try_eye
						at = aim_at
		if eye == Vector3.INF:
			no_view += 1
			print("CORNER | through the placer | %s into the gap at %s: no clear view of it" % [s["shape"], where.origin.snapped(Vector3.ONE * 0.01)])
			continue
		bp.cancel()
		bp.begin(load(_path(s["shape"])))
		await _frames(2)
		_look(eye, at)
		await _frames(4)
		var landed := pp._where
		var snapped := not pp._pair.is_empty()
		var tilt := rad_to_deg(acos(clampf(landed.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)))
		var ok := snapped and landed.origin.distance_to(where.origin) < 0.01
		# (the other way round counts, a wall's two faces, but only standing on the edge by its foot:
		# not hanging under it by its top)
		if not ok and snapped:
			for p in SnapEdges.placements(s["shape"], registry.shape_of(s["shape"]), 1.0, [e]):
				if p["own"]["type"] == "wall_base" and (p["where"] as Transform3D).origin.distance_to(landed.origin) < 0.01:
					ok = true
		count += 1
		right += 1 if ok else 0
		var why := ""
		if not ok:
			var hit := pp._cast_ray(eye, eye + (at - eye) * 2.0)
			var right_one: Array = pp.last_ranking.filter(func(r): return (r["origin"] as Vector3).distance_to(where.origin) < 0.01)
			var ranked: Array = (pp.last_ranking.slice(0, 3) + right_one.slice(0, 1)).map(func(r): return "[%.2f m off, body %d, side %d, matched %d, under %d, line %.2f]" % [(r["origin"] as Vector3).distance_to(where.origin), r["body"], r.get("side", -1), r["matched"], r.get("under", -1), r["line"]])
			var listed: bool = pp.last_ranking.any(func(r): return (r["origin"] as Vector3).distance_to(where.origin) < 0.01)
			var taken: bool = pp._taken(where, pp._pieces_along(eye, at, null))
			why = " | eye %s, hit %s #%d at %s; the right fit ranked: %s, taken: %s; top fits %s" % [eye.snapped(Vector3.ONE * 0.01), (hit["collider"] as Node).name if not hit.is_empty() else "-", (hit["collider"] as BuildPiece).piece_id if not hit.is_empty() and hit["collider"] is BuildPiece else -1, (hit["position"] as Vector3).snapped(Vector3.ONE * 0.01) if not hit.is_empty() else Vector3.ZERO, listed, taken, " ".join(ranked)]
		print("CORNER | through the placer | %s into the gap at %s: %s; snapped %s to %s at %s, tilted %.1f°, %.0f mm below the edge%s%s" % [s["shape"], where.origin.snapped(Vector3.ONE * 0.01), "RIGHT" if ok else "WRONG", snapped, pp._target.shape_name if pp._target else "nothing", landed.origin.snapped(Vector3.ONE * 0.01), tilt, ((where.origin.y - landed.origin.y) * 1000.0), (" (note: %s)" % pp._note) if pp._note != "" else "", why])
	bp.cancel()
	print("CORNER | through the placer: %d of %d crowded spots placed right (%d more with no clear view of them)" % [right, count, no_view])


# ---- Placement cost ----

# Pieces placed one after another at free floor edges near `home` (a half wall each), through the
# placer's own place call, with the spike logger on: each placement's own time, the frames after it,
# and every timed system's time over them
func _lag(home: Vector3) -> void:
	SpikeLog.enabled = true
	var near := registry.pieces_near(home, REACH)
	var walls := near.filter(func(p): return (p as BuildPiece).shape_name in SnapEdges.WALLS)
	var free := []
	for f in near:
		if not (f as BuildPiece).is_floor():
			continue
		for e in SnapEdges.in_world(f):
			if e["type"] == "floor_edge" and not walls.any(func(w): return _stands_on(w, e)):
				free.append(e)
	var buildable: PieceBuildable = load("res://buildables/structure/wall_half_2.tres")
	print("LAG | %d free floor edges near the player; placing up to 12 half walls" % free.size())
	var placed := 0
	# (picked once, as a player does, then placed at one spot after another)
	bp.cancel()
	SpikeLog._times.clear()
	SpikeLog._calls.clear()
	var t0 := Time.get_ticks_usec()
	bp.begin(buildable)
	print("LAG | picking the half wall: %.2f ms (%s)" % [(Time.get_ticks_usec() - t0) / 1000.0, _systems_text()])
	await _frames(3)
	# (standing still, as a player building does: one spot by the first free edge, then only turning to
	# aim at the free edges within reach of it, so nothing streams in round a moved player)
	var stand := Vector3.INF
	for e in free:
		if placed >= 12:
			break
		var mid: Vector3 = ((e["a"] as Vector3) + (e["b"] as Vector3)) / 2.0
		var out: Vector3 = e.get("out", Vector3.FORWARD)
		var inward := -Vector3(out.x, 0, out.z).normalized()
		if stand == Vector3.INF:
			stand = mid + inward * 2.5 + Vector3.UP * 1.7
			_look(stand, mid)
			for i in 60:
				await get_tree().process_frame
		if Vector2(mid.x - stand.x, mid.z - stand.z).length() > 6.0 or Vector2(mid.x - stand.x, mid.z - stand.z).length() < 1.0:
			continue
		_look(stand, mid + inward * 0.15 + Vector3.UP * 0.4)
		if placed == 0:
			# (the first search at a new spot, timed at once with what it set off)
			SpikeLog._times.clear()
			SpikeLog._calls.clear()
			var t1 := Time.get_ticks_usec()
			pp._follow_crosshair()
			print("LAG | the first snap search: %.2f ms (%s)" % [(Time.get_ticks_usec() - t1) / 1000.0, _systems_text()])
		await _frames(4)
		if pp._pair.is_empty() or not pp._problem.is_empty():
			continue
		SpikeLog._times.clear()
		SpikeLog._calls.clear()
		var t := Time.get_ticks_usec()
		pp._place()
		var own := (Time.get_ticks_usec() - t) / 1000.0
		var in_call := _systems_text()
		# (the work a placement sets off, each run at once and timed: the corner posts and ridge logs
		# worked out again, and the next snap search)
		t = Time.get_ticks_usec()
		registry._joints._rebuild()
		var joints := (Time.get_ticks_usec() - t) / 1000.0
		SpikeLog._times.clear()
		SpikeLog._calls.clear()
		t = Time.get_ticks_usec()
		pp._follow_crosshair()
		var search := (Time.get_ticks_usec() - t) / 1000.0
		print("LAG | placement %d at once: the place call %.2f ms, corner posts %.2f ms, the next snap search %.2f ms (%s): %.2f ms in all" % [placed + 1, own, joints, search, _systems_text(), own + joints + search])
		# The frames after it, each with the timed systems that ran in it
		var frames := []
		var worst := 0.0
		var worst_systems := ""
		var last := Time.get_ticks_usec()
		for i in 30:
			SpikeLog._times.clear()
			SpikeLog._calls.clear()
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			frames.append(snappedf(ms, 0.1))
			if ms > worst:
				worst = ms
				worst_systems = "frame %d: %s" % [i + 1, _systems_text()]
			last = now
		placed += 1
		print("LAG | placement %d: the place call %.2f ms (in it: %s) | the 30 frames after: worst %.1f ms (%s) | first frames %s" % [placed, own, in_call, worst, worst_systems, frames.slice(0, 10)])
	SpikeLog.enabled = false


# The timed systems (SpikeLog) since its times were cleared, in ms
func _systems_text() -> String:
	var parts := []
	for k in SpikeLog._times:
		parts.append("%s %.2f ms ×%d" % [k, float(SpikeLog._times[k]) / 1000.0, int(SpikeLog._calls.get(k, 1))])
	return ", ".join(parts) if not parts.is_empty() else "nothing timed"


static func _path(shape: String) -> String:
	return "res://buildables/structure/%s.tres" % shape


func _look(from: Vector3, target: Vector3) -> void:
	var to := target - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


static func _yaw(b: Basis) -> float:
	return atan2(b.z.x, b.z.z)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
