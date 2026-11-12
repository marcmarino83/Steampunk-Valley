class_name PieceOverlap
## Whether a piece put somewhere would sink into another piece: truly inside it, not just meeting
## it. Measured on their exact solid parts (PieceShapes' collision: boxes and convex shapes). The
## placer uses it to skip snaps that would put the ghost inside a piece of its own kind: a floor aimed
## at a floor's middle goes beside it, not into it; a half wall isn't put inside a wall.
##
## The test is by volume: each piece's solid parts are filled with an even grid of points, each
## standing for its share of the part's volume, and a piece sinks into the other when more than
## SINK_SHARE of either one's volume lies inside the other. Normal joins overlap far less: walls
## meeting in an L, a T or a cross share only the square where their ends cross (half or all of a
## wall's thickness: 2 to 10% of a wall, whatever the two walls' heights), and pieces that touch, stack
## or sit side by side share none. A piece stacked into another, or half-way along it, shares 50 to 100%.
## (It used to count any corner point more than 5 cm inside: a Tall wall's end then counted a half
## wall's top corner meeting it at an L as sinking, and the right fit was skipped.)

## How deep a box's corner may sit in another piece before the pair is worth measuring (see _shrunk)
const MARGIN := 0.05
## More than this share of either piece's volume inside the other counts as sinking into it
const SINK_SHARE := 0.25
## Grid points a side, per solid part (see _info)
const GRID := 4

# shape -> {"parts": [{"xform", "planes"}], "samples": [Vector3] (in the piece's own space)}
static var _cache := {}


## True if a piece of `shape` (its shape `def`) at `where` would sink into `other`: more than
## SINK_SHARE of either one's volume inside the other (see above).
## Slender pieces (pillars, poles, beams, ladders) never count, either way: their ends are meant to
## sit into what they hold up or rest on (a floor's corner on a pillar top, a beam's end on a pole top).
static func overlaps(shape: String, def: Dictionary, where: Transform3D, other: BuildPiece) -> bool:
	if other == null or not is_instance_valid(other) or other.buildable == null:
		return false
	return share_inside(shape, def, where, other.shape_name, other.shape_def(), other.global_transform) > SINK_SHARE


## The larger of the two shares: how much of either piece's volume lies inside the other (0 to 1).
## Slender pieces: 0.
static func share_inside(shape: String, def: Dictionary, where: Transform3D, other_shape: String, other_def: Dictionary, other_at: Transform3D) -> float:
	if def.get("slender", false) or other_def.get("slender", false):
		return 0.0
	var mine_box := where * PieceShapes.bounds_of(def)
	var other_box := other_at * PieceShapes.bounds_of(other_def)
	if not _shrunk(mine_box).intersects(_shrunk(other_box)):
		return 0.0
	var mine := _info(shape, def)
	var theirs := _info(other_shape, other_def)
	return maxf(_share(mine, where, theirs["parts"], other_at), _share(theirs, other_at, mine["parts"], where))


# The share of a piece's volume (its grid, `info`, put at `at`) inside any of `parts` (of a piece put
# at `parts_at`)
static func _share(info: Dictionary, at: Transform3D, parts: Array, parts_at: Transform3D) -> float:
	var total: float = info["volume"]
	if total <= 0.0:
		return 0.0
	var to_parts := parts_at.affine_inverse() * at
	var inside := 0.0
	for g in info["grid"]:
		var point: Vector3 = g[0]
		for part in parts:
			var planes: Array = part["planes"]
			if planes.is_empty():
				continue
			var p: Vector3 = (part["inverse"] as Transform3D) * (to_parts * point)
			var within := true
			for plane in planes:
				if (plane as Plane).distance_to(p) > -0.001:
					within = false
					break
			if within:
				inside += float(g[1])
				break
	return inside / total


# A box taken in by MARGIN on every side; along a side thinner than that, down to its middle (never
# a negative size: a door is only 8 cm thick)
static func _shrunk(box: AABB) -> AABB:
	var lo := box.position
	var hi := box.end
	for axis in 3:
		var middle := (lo[axis] + hi[axis]) / 2.0
		lo[axis] = minf(lo[axis] + MARGIN, middle)
		hi[axis] = maxf(hi[axis] - MARGIN, middle)
	return AABB(lo, hi - lo)


## True if a point (in a shape's own space) is in or within `reach` of one of its solid parts
static func near_solid(def: Dictionary, point: Vector3, reach: float) -> bool:
	for part in def["collision"]:
		var into: Vector3 = (part["transform"] as Transform3D).affine_inverse() * point
		var solid: Shape3D = part["shape"]
		var planes := []
		if solid is BoxShape3D:
			var half := (solid as BoxShape3D).size / 2.0
			if absf(into.x) <= half.x + reach and absf(into.y) <= half.y + reach and absf(into.z) <= half.z + reach:
				return true
			continue
		elif solid is ConvexPolygonShape3D:
			var points := []
			for p in (solid as ConvexPolygonShape3D).points:
				if not points.any(func(q): return (q as Vector3).distance_to(p) < 0.001):
					points.append(p)
			planes = _hull_planes(points)
		if not planes.is_empty() and planes.all(func(pl): return (pl as Plane).distance_to(into) <= reach):
			return true
	return false


# A shape's solid parts as planes, and its volume as an even grid of points: GRID a side through each
# part's box (the cells' middles), those inside the part kept, each standing for one cell's volume.
# ("samples": each part's corners, middle and halfway points, for diagnostics.)
static func _info(shape: String, def: Dictionary) -> Dictionary:
	if _cache.has(shape):
		return _cache[shape]
	var timing := SpikeLog.begin()
	var parts := []
	var samples := []
	var grid := []
	var volume := 0.0
	for part in def["collision"]:
		var xform: Transform3D = part["transform"]
		var solid: Shape3D = part["shape"]
		var points := []
		var planes := []
		if solid is BoxShape3D:
			var half := (solid as BoxShape3D).size / 2.0
			var box := AABB(-half, half * 2.0)
			for i in 8:
				points.append(box.get_endpoint(i))
			for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				var extent: float = absf((half * axis).length())
				planes.append(Plane(axis, extent))
				planes.append(Plane(-axis, extent))
		elif solid is ConvexPolygonShape3D:
			for p in (solid as ConvexPolygonShape3D).points:
				if not points.any(func(q): return (q as Vector3).distance_to(p) < 0.001):
					points.append(p)
			planes = _hull_planes(points)
		else:
			continue
		parts.append({"inverse": xform.affine_inverse(), "planes": planes})
		var middle := Vector3.ZERO
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for p in points:
			middle += p
			lo = lo.min(p)
			hi = hi.max(p)
		middle /= maxf(points.size(), 1)
		samples.append(xform * middle)
		for p in points:
			samples.append(xform * (p as Vector3))
			samples.append(xform * (((p as Vector3) + middle) / 2.0))
		var cell := (hi - lo) / float(GRID)
		var weight := cell.x * cell.y * cell.z
		for i in GRID:
			for j in GRID:
				for k in GRID:
					var q := lo + cell * Vector3(i + 0.5, j + 0.5, k + 0.5)
					if planes.all(func(pl): return (pl as Plane).distance_to(q) <= 0.0):
						grid.append([xform * q, weight])
						volume += weight
	_cache[shape] = {"parts": parts, "samples": samples, "grid": grid, "volume": volume}
	SpikeLog.end("overlap shape worked out (first use)", timing)
	return _cache[shape]


# The outward faces of a convex shape's corners, as planes (every plane through three corners with
# all the corners on its inner side)
static func _hull_planes(points: Array) -> Array:
	var planes := []
	var n := points.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var a: Vector3 = points[i]
				var normal := ((points[j] as Vector3) - a).cross((points[k] as Vector3) - a)
				if normal.length() < 1e-6:
					continue
				var plane := Plane(normal.normalized(), a)
				var above := false
				var below := false
				for p in points:
					var d := plane.distance_to(p)
					if d > 1e-4:
						above = true
					elif d < -1e-4:
						below = true
				if above and below:
					continue
				if above:
					plane = -plane
				if not planes.any(func(q): return (q as Plane).normal.is_equal_approx(plane.normal) and absf((q as Plane).d - plane.d) < 1e-4):
					planes.append(plane)
	return planes
