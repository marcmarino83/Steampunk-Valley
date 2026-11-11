class_name PieceOverlap
## Whether a piece put somewhere would sink into another piece by more than MARGIN (about 5 cm),
## measured on their exact solid parts (PieceShapes' collision: boxes and convex shapes). The placer
## uses it to skip snaps that would put the ghost inside the piece it's snapping to (or a piece
## touching that one): a floor aimed at a floor's middle goes beside it, not into it.
##
## The test: points spread through each piece's solid parts (every corner, each part's middle, and
## halfway from the middle to each corner) checked against the other piece's parts. A point counts
## only when it's deeper than MARGIN inside on every side of a part, so pieces that touch, stack or
## sit side by side don't count, and nor do walls meeting in an L (their ends cross by half a wall's
## thickness, but the points there lie on the bottom and top faces the two walls share).

const MARGIN := 0.05

# shape -> {"parts": [{"xform", "planes"}], "samples": [Vector3] (in the piece's own space)}
static var _cache := {}


## True if a piece of `shape` (its shape `def`) at `where` would sink into `other` by more than MARGIN
## Slender pieces (pillars, poles, beams, ladders) never count, either way: their ends are meant to
## sit into what they hold up or rest on (a floor's corner on a pillar top, a beam's end on a pole top).
static func overlaps(shape: String, def: Dictionary, where: Transform3D, other: BuildPiece) -> bool:
	if other == null or not is_instance_valid(other) or other.buildable == null:
		return false
	var other_def := other.shape_def()
	if def.get("slender", false) or other_def.get("slender", false):
		return false
	var mine_box := where * PieceShapes.bounds_of(def)
	var other_box := other.global_transform * PieceShapes.bounds_of(other_def)
	if not mine_box.grow(-MARGIN).intersects(other_box.grow(-MARGIN)):
		return false
	var mine := _info(shape, def)
	var theirs := _info(other.shape_name, other_def)
	return _any_inside(mine["samples"], where, theirs["parts"], other.global_transform) \
		or _any_inside(theirs["samples"], other.global_transform, mine["parts"], where)


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


# True if any of `samples` (in their piece's space, put at `at`) is deeper than MARGIN inside one of
# `parts` (of a piece put at `parts_at`)
static func _any_inside(samples: Array, at: Transform3D, parts: Array, parts_at: Transform3D) -> bool:
	var to_parts := parts_at.affine_inverse() * at
	for part in parts:
		var into: Transform3D = (part["inverse"] as Transform3D) * to_parts
		var planes: Array = part["planes"]
		if planes.is_empty():
			continue
		for s in samples:
			var p: Vector3 = into * (s as Vector3)
			var deep := true
			for plane in planes:
				if (plane as Plane).distance_to(p) > -MARGIN:
					deep = false
					break
			if deep:
				return true
	return false


static func _info(shape: String, def: Dictionary) -> Dictionary:
	if _cache.has(shape):
		return _cache[shape]
	var parts := []
	var samples := []
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
		for p in points:
			middle += p
		middle /= maxf(points.size(), 1)
		samples.append(xform * middle)
		for p in points:
			samples.append(xform * (p as Vector3))
			samples.append(xform * (((p as Vector3) + middle) / 2.0))
	_cache[shape] = {"parts": parts, "samples": samples}
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
