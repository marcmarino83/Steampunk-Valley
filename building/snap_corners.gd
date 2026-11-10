class_name SnapCorners
## The snap points a building piece has when it's placed by hand (Valheim's): its corners and ends,
## nothing in between (no edge middles, no points along edges, no default points). Worked out once
## per shape from its exact solid parts (PieceShapes' collision), in the piece's own space:
##   - floors and foundations: the corners of their top (square: 4, triangles: 3, round wedges: the
##     middle of the circle and both ends of the arc)
##   - roofs, roof corners, ridges, eaves, toppers and overhangs: the corners of their underside,
##     seen from above (a roof's two low corners on the wall top it sits on, its two high corners)
##   - walls, doorways, windows and other upright panels (railings, fences, ladders, doors): their
##     four corners on their centre plane; gables, half gables and inverse triangles: their three
##   - curved walls: both ends of the arc, at the bottom and the top
##   - ridge caps: both ends of the middle line they sit on the ridge by
##   - beams, poles and pillars: both ends
##   - stairs: their four corners (the bottom edge's ends and the top edge's ends)
##   - anything else solid (chimney sections): the eight corners of its box
##   - furniture: none
## A doorway also has the door's two bottom corners where the door goes, and a fireplace or chimney
## section the next section's bottom corners where it stacks, so doors and chimneys snap in.

## Points closer than this are one point
const MERGE := 0.01
## Upright panels are no thicker than this (m)
const THIN := 0.3
## Along a curved or many-sided outline, a bend gentler than this isn't a corner
const CORNER_TURN := deg_to_rad(20.0)
## The outline edges of triangle-type wall pieces (see PieceShapes._edge_sockets)
const OUTLINE_EDGES := ["edge_flat", "edge_vertical", "edge_slope_26", "edge_slope_45", "edge_floor"]
## A doorway's door, and where a chimney stacks: the guest piece and its own point that goes there
const SLOTS := {"door_slot": ["door", "door_base"], "chimney_spot": ["chimney_section", "chimney_base"]}

static var _cache := {}


## The snap points of a shape, in its own space
static func of(shape: String, def: Dictionary) -> Array:
	if not _cache.has(shape):
		_cache[shape] = _work_out(shape, def)
	return _cache[shape]


## A placed piece's snap points, in the world
static func in_world(piece: BuildPiece) -> Array:
	var found := []
	if piece.buildable == null:
		return found
	for p in of(piece.buildable.shape, piece.shape_def()):
		found.append(piece.global_transform * (p as Vector3))
	return found


static func _work_out(shape: String, def: Dictionary) -> Array:
	var points := _own_corners(shape, def)
	# Where a door or the next chimney section goes: its own corners, put there
	for s in def["sockets"]:
		if not SLOTS.has(s["type"]):
			continue
		var guest_shape: String = SLOTS[s["type"]][0]
		var guest := PieceShapes.build(guest_shape)
		var base_spots := _socket_spots(guest["sockets"], [SLOTS[s["type"]][1]])
		if base_spots.is_empty():
			continue
		var base: Vector3 = base_spots[0]
		var at := Transform3D(Basis(Vector3.UP, float(s["yaw"])), s["position"])
		# (only the corners it stands on: its lowest)
		var corners := _own_corners(guest_shape, guest)
		var lowest := INF
		for corner in corners:
			lowest = minf(lowest, (corner as Vector3).y)
		for corner in corners:
			if (corner as Vector3).y < lowest + MERGE:
				points.append(at * ((corner as Vector3) - base))
	return _merged(points)


# A shape's own corners and ends (without what goes in its slots)
static func _own_corners(shape: String, def: Dictionary) -> Array:
	var sockets: Array = def["sockets"]
	var box := PieceShapes.bounds_of(def)
	var points := []
	if def.get("furniture", false):
		pass
	elif def.get("slender", false) and not def.get("ladder", false):
		points = _socket_spots(sockets, ["beam_end", "pole_bottom", "pole_top", "pillar_base", "pillar_top"])
	elif def.get("stairs", false):
		var half := Vector3(box.size.x / 2.0, 0, 0)
		for at in _socket_spots(sockets, ["stairs_bottom", "stairs_top"]):
			points.append((at as Vector3) - half)
			points.append((at as Vector3) + half)
	elif shape.begins_with("ridge_"):
		# A ridge cap sits on the ridge by its middle line (where the roofs' high corners are): the
		# two ends of that line
		for at in _socket_spots(sockets, ["ridge_cap_26", "ridge_cap_45"]):
			points.append((at as Vector3) - Vector3(box.size.x / 2.0, 0, 0))
			points.append((at as Vector3) + Vector3(box.size.x / 2.0, 0, 0))
	elif shape.begins_with("curved_wall"):
		for at in _socket_spots(sockets, ["wall_end"]):
			points.append(at)
			points.append((at as Vector3) + Vector3.UP * PieceShapes.WALL_HEIGHT)
	elif def.get("roof", false) or def.get("overhang", false):
		points = _outline(def, false)
	elif def.get("floor", false):
		points = _outline(def, true)
	elif sockets.any(func(s): return s.has("edge_dir") and OUTLINE_EDGES.has(s["type"])):
		for s in sockets:
			if s.has("edge_dir") and OUTLINE_EDGES.has(s["type"]) and float(s["edge_t"]) < MERGE:
				points.append(s["position"])
	elif box.size.z <= THIN:
		var z := box.get_center().z
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				points.append(Vector3(x, y, z))
	else:
		for i in 8:
			points.append(box.get_endpoint(i))
	return points


# Where a shape's typed points of these types are
static func _socket_spots(sockets: Array, types: Array) -> Array:
	var found := []
	for s in sockets:
		if types.has(s["type"]):
			found.append(s["position"])
	return found


# The corners of a flat piece's top (`top`) or a roof's underside: every corner of its solid parts,
# the highest (or lowest) at each spot seen from above, then the outline round them (a convex hull),
# keeping only the real corners (a round edge's many small bends aren't)
static func _outline(def: Dictionary, top: bool) -> Array:
	var by_spot := {}
	for p in _solid_points(def):
		var key := Vector2i(roundi(p.x / MERGE), roundi(p.z / MERGE))
		if not by_spot.has(key) or (top and p.y > (by_spot[key] as Vector3).y) or (not top and p.y < (by_spot[key] as Vector3).y):
			by_spot[key] = p
	var flat := []
	for key in by_spot:
		flat.append(Vector2((by_spot[key] as Vector3).x, (by_spot[key] as Vector3).z))
	var found := []
	for corner in _sharp(_hull(flat)):
		found.append(by_spot[Vector2i(roundi(corner.x / MERGE), roundi(corner.y / MERGE))])
	return found


# Every corner of a shape's solid parts (boxes and convex shapes), in its own space
static func _solid_points(def: Dictionary) -> Array:
	var found := []
	for part in def["collision"]:
		var xform: Transform3D = part["transform"]
		var shape: Shape3D = part["shape"]
		if shape is BoxShape3D:
			var size := (shape as BoxShape3D).size
			var box := AABB(-size / 2.0, size)
			for i in 8:
				found.append(xform * box.get_endpoint(i))
		elif shape is ConvexPolygonShape3D:
			for p in (shape as ConvexPolygonShape3D).points:
				found.append(xform * p)
	return found


# The convex hull of 2D points, in order round it (points on a straight side left out)
static func _hull(points: Array) -> Array:
	if points.size() < 3:
		return points
	var sorted := points.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y))
	var lower := []
	for p in sorted:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], p) <= 1e-7:
			lower.pop_back()
		lower.append(p)
	var upper := []
	for i in range(sorted.size() - 1, -1, -1):
		var p: Vector2 = sorted[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], p) <= 1e-7:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - o).cross(b - o)


# The points of an outline where it bends by CORNER_TURN or more
static func _sharp(outline: Array) -> Array:
	if outline.size() <= 3:
		return outline
	var found := []
	for i in outline.size():
		var before: Vector2 = outline[i] - outline[i - 1]
		var after: Vector2 = outline[(i + 1) % outline.size()] - outline[i]
		if absf(before.angle_to(after)) >= CORNER_TURN:
			found.append(outline[i])
	return found


# The points with near-repeats left out
static func _merged(points: Array) -> Array:
	var found := []
	for p in points:
		if not found.any(func(q): return (q as Vector3).distance_to(p) < MERGE):
			found.append(p)
	return found
