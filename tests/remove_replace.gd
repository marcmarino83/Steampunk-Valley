extends Node
## Remove-and-replace: for every built-in template, each building piece is taken away and put back
## through the real placer (ValheimPlacer), the way a player would: turned with real mouse-wheel
## notches, then the crosshair aimed at the centre of where it was, from a normal player position
## (3 m away, level with it or a little below or above, with a clear view of the spot). It must
## land within 1 mm and 0.1° of where it was (its shape's symmetry allowed for). Run headless:
##
##     godot --headless --path . res://tests/remove_replace.tscn --fixed-fps 60 --quit-after 200000
##
## Each piece that doesn't come back exactly prints an "RR FAIL" line with what the placer did and
## why (worked out from the placer's own state: what the crosshair hit, whether the old spot was one
## of the snap pairs it could pick, and what beat it). When the centre aim fails, a second aim is
## tried and reported alongside: at the piece it joined, 0.3 m in from the joint (the Valheim way).
## Then "RR SUMMARY" lines per template and overall, "RR SHAPE" lines (results by shape) and
## "RR FAMILY" lines (by family: see snap_family.gd). The exit code is the number of pieces not back
## exactly by the centre aim (every family snaps by typed edges or points).

const WORLD := "res://world/world.tscn"
const EXACT := 0.001
const EXACT_TURN := 0.1
const EYE_DISTANCE := 3.0
const STEP := 22.5
## A view's line must clear other pieces by this much (m), not just graze them
const GRAZE := 0.01

var player: Node
var pp: ValheimPlacer
var bp: BuildPlacer
var registry: PieceRegistry
var O := Vector3.ZERO
var failures := 0
# shape name -> [tried, exact by the centre aim, exact by the joint aim]
var by_shape := {}
# reason -> count (the centre aim's)
var reasons := {}
# family -> [tried, exact by the centre aim] (see snap_family.gd)
var by_family := {}
var converted_misses := 0
# Point pieces standing where no rule puts one (see _point_reachable): listed, not counted
var off_grid := 0
# Pieces with no view of where they were (aimed at the piece they joined instead)
var hidden := 0
# The last aim's crosshair line (for _edge_story)
var _last_eye := Vector3.ZERO
var _last_end := Vector3.ZERO
const Family := preload("res://tests/snap_family.gd")


func _ready() -> void:
	process_physics_priority = -100000
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
		print("RR | no flat open ground found")
		get_tree().quit(1)
		return
	var total := [0, 0, 0]
	for file in DirAccess.get_files_at(BuildingTemplate.BUILT_IN_FOLDER):
		if file.ends_with(".json"):
			var counts: Array = await _template(BuildingTemplate.BUILT_IN_FOLDER.path_join(file))
			for k in 3:
				total[k] += counts[k]
	var lines := []
	for r in reasons:
		lines.append([reasons[r], r])
	lines.sort_custom(func(a, b): return a[0] > b[0])
	print("RR SUMMARY all templates: %d pieces; exact by the centre aim %d; exact by the joint aim (where the centre aim failed) %d; not back either way %d; off the grid (listed, not counted) %d; hidden (aimed at the piece they joined) %d; nothing skipped (every piece of every template tried)" % [total[0], total[1], total[2], total[0] - total[1] - total[2], off_grid, hidden])
	for l in lines:
		print("RR REASON %d × %s" % [l[0], l[1]])
	var names := by_shape.keys()
	names.sort()
	for n in names:
		var c: Array = by_shape[n]
		print("RR SHAPE %s: %d tried, centre aim exact %d, joint aim exact %d" % [n, c[0], c[1], c[2]])
	var families := by_family.keys()
	families.sort()
	for f in families:
		var c: Array = by_family[f]
		print("RR FAMILY %s: %d of %d back exactly by the centre aim (%.0f%%)" % [f, c[1], c[0], 100.0 * c[1] / maxf(c[0], 1)])
	bp.cancel()
	# (the exit code: converted pieces not back exactly by the centre aim)
	get_tree().quit(converted_misses)


# ---- Templates ----

# Lays a template out (as built pieces), takes each building piece away in turn, puts it back
# through the placer, then restores it. [pieces tried, exact by the centre aim, exact by the joint aim]
func _template(path: String) -> Array:
	var template := BuildingTemplate.read(path)
	var title: String = template.template_name if template else path.get_file()
	var pieces := []
	for item in template.items:
		if item["buildable"] is PieceBuildable:
			pieces.append(registry.spawn(item["buildable"], Transform3D(Basis.IDENTITY, O) * (item["relative"] as Transform3D), {}))
	await _frames(3)
	var tried := 0
	var centre_ok := 0
	var joint_ok := 0
	for i in pieces.size():
		var piece: BuildPiece = pieces[i]
		var def := piece.shape_def()
		if def.get("furniture", false):
			continue
		var buildable: PieceBuildable = piece.buildable
		var was := piece.global_transform
		var piece_name := piece.display_name()
		# The pieces it joined (by a corner, exactly), for the joint aim
		var joined := _joined(piece, pieces)
		registry.remove(piece)
		await _frames(2)
		# (a point piece standing where no rule puts one: off the grid in the template, after a piece
		# was resized; listed, not counted)
		if SnapEdges.point_shape(buildable.shape) and not _point_reachable(buildable, was):
			print("RR OFF GRID | %s | %s at %s turned %.1f° | where it stands, none of its points is on a point the table allows and its line is along no edge it allows (the template needs rebuilding on the current grid)" % [title, piece_name, _local(was.origin).snapped(Vector3.ONE * 0.01), _yaw(was.basis)])
			off_grid += 1
			pieces[i] = registry.spawn(buildable, was, {})
			await _frames(1)
			continue
		tried += 1
		if not by_shape.has(piece_name):
			by_shape[piece_name] = [0, 0, 0]
		by_shape[piece_name][0] += 1
		var family: String = Family.of(buildable.shape)
		if not by_family.has(family):
			by_family[family] = [0, 0]
		by_family[family][0] += 1
		var a: Dictionary = await _put_back(buildable, was, _centre_view(was, def))
		# (hidden: no view of where it was from anywhere a player could stand, under stairs and
		# inside a foundation's corner, say: aimed at the piece it joined instead, and listed)
		if a["why_short"] == "no clear view":
			a = await _put_back(buildable, was, _joint_view(was, def, joined))
			print("RR HIDDEN | %s | %s at %s | no view of where it was: aimed at the piece it joined instead: %s" % [title, piece_name, _local(was.origin).snapped(Vector3.ONE * 0.01), "exact" if a["ok"] else a["why"]])
			hidden += 1
		if a["ok"]:
			centre_ok += 1
			by_shape[piece_name][1] += 1
			by_family[family][1] += 1
		else:
			if SnapEdges.converted(buildable.shape):
				converted_misses += 1
				print("RR CONVERTED MISS | %s | %s at %s turned %.1f° | %s" % [title, piece_name, _local(was.origin).snapped(Vector3.ONE * 0.01), _yaw(was.basis), _edge_story(buildable, was)])
			reasons[a["why_short"]] = int(reasons.get(a["why_short"], 0)) + 1
			var b: Dictionary = await _put_back(buildable, was, _joint_view(was, def, joined))
			if b["ok"]:
				joint_ok += 1
				by_shape[piece_name][2] += 1
			else:
				failures += 1
			print("RR FAIL | %s | %s at %s turned %.1f° | centre aim: %s | joint aim: %s" % [title, piece_name, _local(was.origin).snapped(Vector3.ONE * 0.01), _yaw(was.basis), a["why"], "exact" if b["ok"] else b["why"]])
		bp.cancel()
		pieces[i] = registry.spawn(buildable, was, {})
		await _frames(1)
	print("RR SUMMARY %s: %d pieces; exact by the centre aim %d; by the joint aim %d; not back %d" % [title, tried, centre_ok, joint_ok, tried - centre_ok - joint_ok])
	for p in registry.all_pieces():
		registry.remove(p)
	await _frames(2)
	return [tried, centre_ok, joint_ok]


# Puts a piece back where it was (`was`), seen from `view` ([eye, aim point] or empty): turned first
# (wheel notches against what the crosshair will hit), then placing started afresh (no sticky
# corner left from turning) and the crosshair aimed. {"ok", "why", "why_short"}
func _put_back(buildable: PieceBuildable, was: Transform3D, view: Array) -> Dictionary:
	if view.is_empty():
		_last_eye = Vector3.INF
		return {"ok": false, "why": "no clear view of the spot from a player's position", "why_short": "no clear view"}
	var eye: Vector3 = view[0]
	var at: Vector3 = view[1]
	var dir := (at - eye).normalized()
	var hit := pp._cast_ray(eye, eye + dir * ValheimPlacer.REACH)
	_last_eye = eye
	_last_end = (hit["position"] as Vector3) + dir * 0.1 if not hit.is_empty() else eye + dir * ValheimPlacer.REACH
	var aimed: BuildPiece = hit["collider"] if not hit.is_empty() and hit["collider"] is BuildPiece else null
	var symmetry: float = registry.shape_of(buildable.shape).get("symmetry", 0.0)
	var base := _yaw(aimed.global_basis) if aimed else 0.0
	# (turned while it's free: started afresh, before the placer has followed the crosshair)
	bp.cancel()
	bp.begin(buildable)
	await _turn_to(roundi(fposmod(_yaw(was.basis) - base, 360.0) / STEP) % 16)
	bp.cancel()
	bp.begin(buildable)
	await _aim(eye, at)
	# (aimed at the ground beside a building, the turn counts against the piece it snaps to: once
	# that's known, turned again, free, and aimed afresh)
	if pp._target and pp._target != aimed and not _same_turn(pp._where.basis, was.basis, symmetry):
		var against: BuildPiece = pp._target
		bp.cancel()
		bp.begin(buildable)
		await _turn_to(roundi(fposmod(_yaw(was.basis) - _yaw(against.global_basis), 360.0) / STEP) % 16)
		bp.cancel()
		bp.begin(buildable)
		await _aim(eye, at)
	var off := pp._where.origin.distance_to(was.origin)
	var turned_ok := _turn_apart(pp._where.basis, was.basis, symmetry) <= EXACT_TURN
	if pp._preview.visible and not pp._pair.is_empty() and off <= EXACT and turned_ok:
		return {"ok": true, "why": "exact", "why_short": "exact"}
	return _diagnose(buildable, was, hit, eye, dir, off, symmetry)


# True if a point piece where it was (`was`) is a fit under the rules: one of its points on a placed
# point the table allows, or its line along an edge it allows
func _point_reachable(buildable: PieceBuildable, was: Transform3D) -> bool:
	var def := registry.shape_of(buildable.shape)
	var near := registry.pieces_near(was.origin, 5.0)
	for o in SnapEdges.points_of(buildable.shape, def):
		var at: Vector3 = was * (o["p"] as Vector3)
		for p in near:
			for q in SnapEdges.points_in_world(p):
				if (q["p"] as Vector3).distance_to(at) < EXACT and q["type"] in SnapEdges.POINT_RULES.get(o["type"], []):
					return true
	var line := SnapEdges.beam_line(buildable.shape, def)
	if not line.is_empty():
		for p in near:
			for e in SnapEdges.in_world(p):
				if e["type"] in SnapEdges.LINE_RULES and SnapEdges.along(was * (line[0] as Vector3), was * (line[1] as Vector3), e["a"], e["b"]):
					return true
	return false


# For a converted piece that didn't come back: what the placer did, and whether the right fit exists
# among the edges round where it was (and if so, how far its body is from the crosshair's line, how
# many edges it matches, and whether it counts as taken)
func _edge_story(buildable: PieceBuildable, was: Transform3D) -> String:
	var def := registry.shape_of(buildable.shape)
	var symmetry: float = def.get("symmetry", 0.0)
	if _last_eye == Vector3.INF:
		return "no clear view of where it was from a player's position"
	var did := "free, note \"%s\"" % pp._note if pp._pair.is_empty() else "snapped %.0f mm and %.1f° off" % [pp._where.origin.distance_to(was.origin) * 1000.0, _turn_apart(pp._where.basis, was.basis, symmetry)]
	var edges := []
	var pieces := {}
	for p in registry.pieces_near(was.origin, 5.0):
		pieces[p] = true
		edges.append_array(SnapEdges.in_world(p))
	if SnapEdges.point_shape(buildable.shape):
		# (a point piece: what its own points and line touch where it was, and whether the table allows it)
		var touches := []
		for o in SnapEdges.points_of(buildable.shape, def):
			var at: Vector3 = was * (o["p"] as Vector3)
			for p in pieces:
				for q in SnapEdges.points_in_world(p):
					if (q["p"] as Vector3).distance_to(at) < EXACT:
						var allowed: bool = q["type"] in SnapEdges.POINT_RULES.get(o["type"], [])
						touches.append("%s on %s's %s (%s%s)" % [o["type"], _name(p), q["type"], "allowed" if allowed else "not in the table",
							(", point %.2f m from the line, body %.3f m, duplicate %s" % [SnapEdges.point_segment(q["p"], _last_eye, _last_end), SnapEdges.box_distance(was, PieceShapes.bounds_of(def), _last_eye, _last_end), registry.duplicate_of(buildable.shape, was) != null]) if allowed else ""])
				for c in SnapCorners.in_world(p):
					if (c as Vector3).distance_to(at) < EXACT and not touches.any(func(t): return (t as String).begins_with(o["type"]) and (t as String).contains(_name(p))):
						touches.append("%s on a corner of %s" % [o["type"], _name(p)])
				for e in SnapEdges.in_world(p):
					if SnapEdges.point_segment(at, e["a"], e["b"]) < EXACT:
						touches.append("%s on %s's %s edge" % [o["type"], _name(p), e["type"]])
		var line := SnapEdges.beam_line(buildable.shape, def)
		if not line.is_empty():
			for p in pieces:
				for e in SnapEdges.in_world(p):
					if SnapEdges.along(was * (line[0] as Vector3), was * (line[1] as Vector3), e["a"], e["b"]):
						touches.append("its line along %s's %s (%s)" % [_name(p), e["type"], "allowed" if e["type"] in SnapEdges.LINE_RULES else "not in the table"])
		var box := PieceShapes.bounds_of(def)
		var keys := func(w: Transform3D) -> String:
			var held := 0
			for o in SnapEdges.points_of(buildable.shape, def):
				var at: Vector3 = w * (o["p"] as Vector3)
				for p in pieces:
					if SnapEdges.points_in_world(p).any(func(q): return (q["p"] as Vector3).distance_to(at) < EXACT):
						held += 1
						break
			return "body %.3f, middle %.3f m from the line, %d points held" % [SnapEdges.box_distance(w, box, _last_eye, _last_end), SnapEdges.point_segment(w * box.get_center(), _last_eye, _last_end), held]
		var ranking: Array = pp.last_ranking.map(func(r): return "[%s off, body %d axis %d held %d line %.2f%s]" % [str(snappedf((r["origin"] as Vector3).distance_to(was.origin), 0.01)), r["body"], r["axis"], r["held"], r["line"], " point" if r["pivot"] else " line"])
		did += " (eye %s, line end %s, ground %.2f)" % [_local(_last_eye).snapped(Vector3.ONE * 0.01), _local(_last_end).snapped(Vector3.ONE * 0.01), Plot.ground_at(player, was.origin.x, was.origin.z) - O.y]
		# (asked again now, from the camera as it stands: what the placer finds)
		var cam: Camera3D = player.camera
		var cam_hit := pp._cast_ray(cam.global_position, cam.global_position - cam.global_basis.z * ValheimPlacer.REACH)
		var again: Dictionary = pp._point_fit(cam.global_position, (cam_hit["position"] as Vector3) + (-cam.global_basis.z) * 0.1 if not cam_hit.is_empty() else cam.global_position - cam.global_basis.z * ValheimPlacer.REACH, cam_hit["collider"] if not cam_hit.is_empty() and cam_hit["collider"] is BuildPiece else null, cam_hit["position"] if not cam_hit.is_empty() else Vector3.INF)
		did += " (asked again: camera %s, hit %s on %s; fit %s)" % [_local(cam.global_position).snapped(Vector3.ONE * 0.01), _local(cam_hit["position"]).snapped(Vector3.ONE * 0.01) if not cam_hit.is_empty() else "-", _name(cam_hit["collider"]) if not cam_hit.is_empty() and cam_hit["collider"] is BuildPiece else "not a piece", _local((again["where"] as Transform3D).origin).snapped(Vector3.ONE * 0.01) if not again.is_empty() else "none"]
		return "%s; right fit: %s; chosen: %s; placer's top fits: %s; where it was: %s" % [did, keys.call(was), keys.call(pp._where) if not pp._pair.is_empty() else "-", " ".join(ranking), "; ".join(touches.slice(0, 3)) if not touches.is_empty() else "touching no typed point, corner or edge"]
	var step: float = buildable.vertical_unit
	for c in SnapEdges.placements(buildable.shape, def, step, edges):
		var w: Transform3D = c["where"]
		if w.origin.distance_to(was.origin) <= EXACT and _turn_apart(w.basis, was.basis, symmetry) <= EXACT_TURN:
			var body: float = SnapEdges.box_distance(w, PieceShapes.bounds_of(def), _last_eye, _last_end)
			var middle := w * PieceShapes.bounds_of(def).get_center()
			var chosen := ""
			if not pp._pair.is_empty():
				var cm := pp._where * PieceShapes.bounds_of(def).get_center()
				chosen = "; chosen: body %.3f m, middle %.2f m from the line, %d edges matched" % [SnapEdges.box_distance(pp._where, PieceShapes.bounds_of(def), _last_eye, _last_end),
					SnapEdges.point_segment(cm, _last_eye, _last_end), SnapEdges.matched(buildable.shape, def, pp._where, edges)]
				# (the placer's own ranking keys, the right fit's among them: see ValheimPlacer._edge_fit)
				var keys := func(r: Dictionary) -> String: return "[%.2f m off: side %d, aim %d, body %d, matched %d, line %.2f]" % [(r["origin"] as Vector3).distance_to(was.origin), r.get("side", -1), r.get("at_hit", -1), r["body"], r["matched"], r["line"]]
				var right_one: Array = pp.last_ranking.filter(func(r): return (r["origin"] as Vector3).distance_to(was.origin) < EXACT)
				chosen += "; placer's top fits %s; the right fit %s" % [" ".join(pp.last_ranking.slice(0, 3).map(keys)), keys.call(right_one[0]) if not right_one.is_empty() else "not ranked"]
			return "%s; the right fit exists (along %s's %s, body %.3f m from the line, middle %.2f m from it, %d edges matched, taken %s)%s" % [did, _name(c["piece"]), c["at"]["type"], body,
				SnapEdges.point_segment(middle, _last_eye, _last_end), SnapEdges.matched(buildable.shape, def, w, edges), pp._taken(w, pieces), chosen]
	return "%s; no fit to where it was from the edges round it" % did


# Why the placer didn't put it back exactly
func _diagnose(buildable: PieceBuildable, was: Transform3D, hit: Dictionary, eye: Vector3, dir: Vector3, off: float, symmetry: float) -> Dictionary:
	var target: BuildPiece = pp._target
	var hit_text := "the crosshair hit %s" % ("nothing" if hit.is_empty() else (_name(hit["collider"]) if hit["collider"] is BuildPiece else "the ground"))
	if not hit.is_empty():
		hit_text += " at %s (normal %s, eye %s, looking %s)" % [_local(hit["position"]).snapped(Vector3.ONE * 0.01), (hit["normal"] as Vector3).snapped(Vector3.ONE * 0.01), _local(eye).snapped(Vector3.ONE * 0.01), dir.snapped(Vector3.ONE * 0.01)]
	var result := "%s; it went %.0f mm and %.1f° off%s" % [hit_text, off * 1000.0, _turn_apart(pp._where.basis, was.basis, symmetry), (", snapped to %s" % _name(target)) if not pp._pair.is_empty() else ", free (not snapped)"]
	# (why the right fit lost, by typed edges or points, is in the RR CONVERTED MISS line: _edge_story)
	var short := "free: no fit found from this aim" if pp._pair.is_empty() else "another fit ranked first from this aim"
	return {"ok": false, "why": result, "why_short": short}


# The pieces `piece` meets by an exact corner
func _joined(piece: BuildPiece, pieces: Array) -> Array:
	var found := []
	var mine := SnapCorners.in_world(piece)
	for other in pieces:
		if other == piece or not is_instance_valid(other):
			continue
		for c in SnapCorners.in_world(other):
			if mine.any(func(m): return (m as Vector3).distance_to(c) <= EXACT):
				found.append([other, c])
				break
	return found


# A normal player's view of where a piece was: 3 m away, in front, behind or to a side (then
# diagonally), level with its centre or 1 m below or above (then 2 m below), the eye above the
# ground and in open air, with nothing between it and the centre. Those whose crosshair, carrying
# on past the centre, hits a building piece come first. [eye, centre] or empty.
func _centre_view(was: Transform3D, def: Dictionary) -> Array:
	var box := PieceShapes.bounds_of(def)
	var centre := was * box.get_center()
	# (a foundation's middle is underground: the middle of the part above ground instead)
	var ground := Plot.ground_at(player, centre.x, centre.z)
	var top := (was * box.end).y
	if centre.y < ground + 0.05 and top > ground:
		centre.y = (ground + top) / 2.0
	# (a floor or foundation: also the middle of its top, seen from above)
	var aims := [centre]
	if def.get("floor", false):
		aims.append(Vector3(centre.x, top - 0.05, centre.z))
		# (covered in the middle, by stairs say: elsewhere on its top)
		for fx in [-0.3, 0.3]:
			for fz in [-0.3, 0.3]:
				aims.append(was * Vector3(box.get_center().x + box.size.x * fx, box.end.y - 0.05, box.get_center().z + box.size.z * fz))
	# (its middle hidden, inside a foundation's corner or among rafters: elsewhere within where it
	# was, above the ground and in open air; a pillar, pole or beam along its own axis first, since
	# most of a diagonal's box is empty air)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var shape_name := ""
	for s in SnapEdges.POSTS + SnapEdges.ALL_BEAMS:
		if registry.shape_of(s) == def:
			shape_name = s
	if shape_name != "":
		var ends: Array = SnapEdges.points_of(shape_name, def).filter(func(o): return o["type"] in ["beam_end", "post_foot", "post_top"])
		if ends.size() == 2:
			var down := Vector3(0, -0.1, 0) if shape_name in SnapEdges.ALL_BEAMS else Vector3.ZERO
			for t in [0.5, 0.35, 0.65, 0.2, 0.8]:
				var p: Vector3 = was * ((ends[0]["p"] as Vector3).lerp(ends[1]["p"], t) + down)
				if p.y < Plot.ground_at(player, p.x, p.z) + 0.05:
					continue
				var q := PhysicsPointQueryParameters3D.new()
				q.position = p
				q.exclude = [player.get_rid()]
				if space.intersect_point(q, 1).is_empty():
					aims.append(p)
	for fy in [0.5, 0.25, 0.75]:
		for fx in [0.5, 0.2, 0.8]:
			for fz in [0.5, 0.2, 0.8]:
				var p: Vector3 = was * (box.position + box.size * Vector3(fx, fy, fz))
				if p.y < Plot.ground_at(player, p.x, p.z) + 0.05:
					continue
				var q := PhysicsPointQueryParameters3D.new()
				q.position = p
				q.exclude = [player.get_rid()]
				if space.intersect_point(q, 1).is_empty():
					aims.append(p)
	# (a long, thin piece, a ridge cap say: views looking along it, where the crosshair runs through
	# every spot along the line at once, tried last)
	var long_axis := Vector3.ZERO
	if box.size.x > 3.0 * box.size.z:
		long_axis = (was.basis * Vector3.RIGHT).normalized()
	elif box.size.z > 3.0 * box.size.x:
		long_axis = (was.basis * Vector3.BACK).normalized()
	# (a diagonal view, at 45° to the piece, is kept only if no aim has a straight one hitting a
	# piece: looking diagonally down a corner, a wall and its twin round the corner both lie on the
	# crosshair's line, and a player facing a wall looks at it straight)
	var fallback := []
	var diagonal := []
	for aim in aims:
		var eyes := _eyes(aim, was.basis, shape_name != "")
		if long_axis != Vector3.ZERO:
			var across := eyes.filter(func(e): return absf(Vector3(e.x - aim.x, 0, e.z - aim.z).normalized().dot(long_axis)) < 0.8)
			var along := eyes.filter(func(e): return absf(Vector3(e.x - aim.x, 0, e.z - aim.z).normalized().dot(long_axis)) >= 0.8)
			eyes = across + along
		for eye in eyes:
			var to: Vector3 = aim - eye
			# (clear by a margin: a line grazing another piece's face, along a flight's side say, may
			# hit it from the camera and miss it from here)
			var side := to.cross(Vector3.UP).normalized() * GRAZE if absf(to.normalized().y) < 0.99 else Vector3.RIGHT * GRAZE
			var up := side.cross(to).normalized() * GRAZE
			var blocked := false
			for o in [Vector3.ZERO, side, -side, up, -up]:
				if not pp._cast_ray(eye + o, aim + o - to.normalized() * 0.05).is_empty():
					blocked = true
					break
			if blocked:
				continue
			var beyond := pp._cast_ray(eye, eye + to.normalized() * ValheimPlacer.REACH)
			# (the crosshair must reach the aim: one that's inside a hollow shape, under stairs say,
			# can pass the open-air test and still be hidden)
			if not beyond.is_empty() and eye.distance_to(beyond["position"]) < to.length() - 0.05:
				continue
			if not beyond.is_empty() and beyond["collider"] is BuildPiece:
				var flat := Vector3(to.x, 0, to.z).normalized()
				var straight := flat == Vector3.ZERO or absf(flat.dot(was.basis.x.normalized())) > 0.9 or absf(flat.dot(was.basis.z.normalized())) > 0.9
				if straight:
					return [eye, aim]
				if diagonal.is_empty():
					diagonal = [eye, aim]
			if fallback.is_empty():
				fallback = [eye, aim]
	return diagonal if not diagonal.is_empty() else fallback


# The joint aim: at a piece it joined, 0.3 m in from the corner they shared toward that piece's
# middle, seen so the crosshair hits that piece within 0.35 m of the point
func _joint_view(was: Transform3D, def: Dictionary, joined: Array) -> Array:
	for j in joined:
		var other: BuildPiece = j[0]
		if not is_instance_valid(other):
			continue
		var middle: Vector3 = other.global_transform * PieceShapes.bounds_of(other.shape_def()).get_center()
		var at: Vector3 = (j[1] as Vector3) + ((middle - (j[1] as Vector3)).normalized() * 0.3)
		for eye in _eyes(at, was.basis):
			var hit := pp._cast_ray(eye, eye + (at - eye).normalized() * ValheimPlacer.REACH)
			if not hit.is_empty() and hit["collider"] == other and (hit["position"] as Vector3).distance_to(at) < 0.35:
				return [eye, hit["position"]]
	return []


# Eyes round a spot (see _centre_view); for a pillar, pole or beam (`slender`), from a little above or
# below first, since level with it the crosshair runs along a row of post spots or a beam's line
func _eyes(centre: Vector3, basis: Basis, slender := false) -> Array:
	var found := []
	var fwd := Vector3(basis.z.x, 0, basis.z.z).normalized()
	var side := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var dirs := [fwd, -fwd, side, -side, (fwd + side).normalized(), (fwd - side).normalized(), (-fwd + side).normalized(), (-fwd - side).normalized()]
	# (posts stand in rows along the grid: diagonal views first, so the crosshair runs through one)
	if slender:
		dirs = dirs.slice(4) + dirs.slice(0, 4)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for reach in [EYE_DISTANCE, 2.0]:
		for h in ([1.0, -1.0, 2.0, 0.0, -2.0] if slender else [0.0, -1.0, 1.0, -2.0, 2.0]):
			for d in dirs:
				var eye: Vector3 = centre + (d as Vector3) * reach + Vector3.UP * h
				if _open_eye(eye, space):
					found.append(eye)
	return found


# The eye above the ground and in open air
func _open_eye(eye: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	if eye.y < Plot.ground_at(player, eye.x, eye.z) + 1.0:
		return false
	var q := PhysicsPointQueryParameters3D.new()
	q.position = eye
	q.exclude = [player.get_rid()]
	return space.intersect_point(q, 1).is_empty()


# ---- Helpers ----

func _spawn(path: String, local: Vector3, yaw_degrees := 0.0) -> BuildPiece:
	return registry.spawn(load("res://buildables/%s.tres" % path), Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), O + local), {})


func _clear() -> void:
	bp.cancel()
	for p in registry.all_pieces():
		registry.remove(p)
	await _frames(2)


func _aim(eye: Vector3, at: Vector3) -> void:
	var to := at - eye
	player.global_position = eye - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(3)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# Wheel notches until the turn is `notches` × 22.5°, as real wheel events through the input system
func _turn_to(notches: int) -> void:
	var now := roundi(rad_to_deg(pp.turn) / STEP)
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
		_send(press)
		var release: InputEventMouseButton = press.duplicate()
		release.pressed = false
		_send(release)
	await _frames(1)


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


func _same_turn(a: Basis, b: Basis, symmetry: float) -> bool:
	return _turn_apart(a, b, symmetry) <= EXACT_TURN


func _turn_apart(a: Basis, b: Basis, symmetry: float) -> float:
	var step := rad_to_deg(symmetry) if symmetry > 0.0 else 360.0
	return absf(fposmod(_yaw(a) - _yaw(b) + step / 2.0, step) - step / 2.0)


func _name(piece) -> String:
	return (piece as BuildPiece).display_name() if piece is BuildPiece else "none"


func _local(p: Vector3) -> Vector3:
	return p - O


static func _yaw(b: Basis) -> float:
	return rad_to_deg(atan2(b.z.x, b.z.z))
