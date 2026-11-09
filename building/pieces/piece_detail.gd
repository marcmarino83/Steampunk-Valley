class_name PieceDetail
extends RefCounted
## The close-up look of the building pieces: weathered timber built from real parts (separate
## bevelled planks, round logs, split shakes, irregular stone blocks, rope lashings and iron straps)
## instead of textured boxes. Each piece's parts are merged into one mesh. The outer size, snap
## points and collision all still come from PieceShapes; only the look is made here.
##
## Every part records what it's made of in its second UV (x: WOOD, STONE, ROPE, IRON or DARK) and
## its own shade in its colour, for piece_detail.gdshader. Wood uses the Wood Planks Dirt maps with
## each plank fitted to one board of the texture at a random spot, so neighbours differ.
##
## The randomness comes from a seed (see PieceRegistry.detail_mesh: one of a few variants per shape,
## picked by the piece's id), so a piece always looks the same.

const WOOD := 0
const STONE := 1
const ROPE := 2
const IRON := 3
const DARK := 4

## Meters per copy of a texture, and how many boards run across the wood texture
const TEX := 2.0
const BOARDS := 8.0
## Planks: how tall wall planks are, the gaps between them, and their bevel
const PLANK_MIN := 0.17
const PLANK_MAX := 0.27
const GAP_MIN := 0.006
const GAP_MAX := 0.013
const BEVEL := 0.012
## Roofs: the boards the shakes lie on, how far each row of shakes shows, shake sizes
const DECK := 0.09
const SHAKE_EXPOSURE := 0.19
const SHAKE_LENGTH := 0.44
const SHAKE_THICK := 0.018
## Logs on wood foundations, stone courses, and how deep below a foundation's top the visible
## courses go (the rest is underground, left as the dark core)
const LOG_SIDES := 7
const STONE_DEPTH := 0.22
const SHOWN_DEPTH := 1.75
const STONE_SHOWN_DEPTH := 1.25
## Corner posts at wall joints, and the ridge log over a roof's peak
const POST_RADIUS := 0.11
const RIDGE_RADIUS := 0.1

var st := SurfaceTool.new()
var rng := RandomNumberGenerator.new()
var _count := 0


func _init(seed_value: int) -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	rng.seed = seed_value


## The look of one shape: {"mesh": ArrayMesh, "door_mesh": ArrayMesh or null}, or empty for a
## shape drawn some other way (furniture)
static func build(shape: String, seed_value: int) -> Dictionary:
	var b := PieceDetail.new(seed_value)
	var door: PieceDetail = null
	var G := PieceShapes.GRID
	var H := PieceShapes.WALL_HEIGHT
	match shape:
		"wall":
			b._wall(G, H, [])
		"doorway":
			var hole := PieceShapes.DOOR_WIDTH / 2.0
			b._wall(G, H, [Rect2(-hole, 0.0, hole * 2.0, PieceShapes.DOOR_HEIGHT)])
		"window":
			var hole := PieceShapes.WINDOW_WIDTH / 2.0
			b._wall(G, H, [Rect2(-hole, PieceShapes.WINDOW_BOTTOM, hole * 2.0, PieceShapes.WINDOW_TOP - PieceShapes.WINDOW_BOTTOM)])
		"wall_long":
			b._wall(PieceShapes.LONG_EDGE, H, [])
		"wall_short":
			b._wall(PieceShapes.SHORT_EDGE, H, [])
		"wall_1":
			b._wall(1.0, H, [])
		"wall_half_2":
			b._wall(G, PieceShapes.HALF_HEIGHT, [])
		"wall_half_1":
			b._wall(1.0, PieceShapes.HALF_HEIGHT, [])
		"wall_quarter":
			b._wall(1.0, 1.0, [])
		"curved_wall_45":
			b._curved_wall(22.5)
		"curved_wall_22":
			b._curved_wall(11.25)
		"gable_26":
			b._gable(PieceShapes.ROOF_RISE)
		"gable_45":
			b._gable(PieceShapes.ROOF_RISE_45)
		"door":
			door = PieceDetail.new(seed_value + 7)
			door._door()
		"floor":
			b._floor(_rect(G / 2.0), -PieceShapes.FLOOR_THICKNESS)
		"floor_1":
			b._floor(_rect(0.5), -PieceShapes.FLOOR_THICKNESS)
		"floor_rtri":
			b._floor(PieceShapes._right_triangle(), -PieceShapes.FLOOR_THICKNESS)
		"floor_tri45":
			b._floor(PieceShapes._triangle_45(), -PieceShapes.FLOOR_THICKNESS)
		"round_floor":
			b._floor(_wedge(22.5), -PieceShapes.FLOOR_THICKNESS)
		"round_floor_22":
			b._floor(_wedge(11.25), -PieceShapes.FLOOR_THICKNESS)
		"foundation_wood":
			b._foundation_wood(_rect(G / 2.0), _all_edges(_rect(G / 2.0)))
		"foundation_wood_rtri":
			b._foundation_wood(PieceShapes._right_triangle(), _all_edges(PieceShapes._right_triangle()))
		"foundation_wood_tri45":
			b._foundation_wood(PieceShapes._triangle_45(), _all_edges(PieceShapes._triangle_45()))
		"round_foundation_wood":
			b._foundation_wood(_wedge(22.5), _arc_edges(_wedge(22.5)))
		"round_foundation_wood_22":
			b._foundation_wood(_wedge(11.25), _arc_edges(_wedge(11.25)))
		"foundation_stone":
			b._foundation_stone(_rect(G / 2.0), _all_edges(_rect(G / 2.0)))
		"foundation_stone_rtri":
			b._foundation_stone(PieceShapes._right_triangle(), _all_edges(PieceShapes._right_triangle()))
		"foundation_stone_tri45":
			b._foundation_stone(PieceShapes._triangle_45(), _all_edges(PieceShapes._triangle_45()))
		"round_foundation_stone":
			b._foundation_stone(_wedge(22.5), _arc_edges(_wedge(22.5)))
		"round_foundation_stone_22":
			b._foundation_stone(_wedge(11.25), _arc_edges(_wedge(11.25)))
		"roof":
			b._roof_panel(PieceShapes.ROOF_RISE, -1.0, 1.0, 0.0, G, [-0.67, 0.0, 0.67])
		"roof_45":
			b._roof_panel(PieceShapes.ROOF_RISE_45, -1.0, 1.0, 0.0, G, [-0.67, 0.0, 0.67])
		"eave_26", "eave_45":
			var o := PieceShapes.OVERHANG
			b._roof_panel(_rise_of(shape), -1.0, 1.0, -o, 0.0, [-0.67, 0.0, 0.67])
			b._fascia(_rise_of(shape), -1.0, 1.0, -o, 0.0, true, false)
		"gable_overhang_26", "gable_overhang_45":
			var half := PieceShapes.OVERHANG / 2.0
			b._roof_panel(_rise_of(shape), -half, half, 0.0, G, [])
			b._fascia(_rise_of(shape), -half, half, 0.0, G, false, true)
		"eave_corner_26", "eave_corner_45":
			var half := PieceShapes.OVERHANG / 2.0
			b._roof_panel(_rise_of(shape), -half, half, -PieceShapes.OVERHANG, 0.0, [])
			b._fascia(_rise_of(shape), -half, half, -PieceShapes.OVERHANG, 0.0, true, true)
		"roof_inner_26", "roof_outer_26", "roof_inner_45", "roof_outer_45":
			b._roof_corner(_rise_of(shape), shape.contains("inner"))
		"ridge_26", "ridge_45":
			b._ridge_cap(_rise_of(shape))
		"cone_roof":
			b._cone_roof()
		"stairs":
			b._stairs()
		"pillar_wood":
			b._wood_pillar()
		"pillar_stone":
			b._stone_pillar()
		"pole_1", "pole_2":
			b._pole(1.0 if shape == "pole_1" else G)
		"beam_1", "beam_2":
			b._beam(1.0 if shape == "beam_1" else G)
		"beam_diag_26", "beam_diag_45":
			b._diagonal_beam(_rise_of(shape))
		"ladder":
			b._ladder()
		"railing_2", "railing_1":
			b._railing(G if shape == "railing_2" else 1.0)
		"fence":
			b._fence()
		_:
			return {}
	return {"mesh": b.commit(), "door_mesh": door.commit() if door else null}


## A rough log post standing over a wall joint: from 0 up `height`, with rope lashings
static func post_mesh(height: float, seed_value: int) -> ArrayMesh:
	var b := PieceDetail.new(seed_value)
	var r := POST_RADIUS * b.rng.randf_range(0.95, 1.05)
	b.log_part(Vector3(0, -0.02, 0), Vector3(0, height, 0), r, 9, 0.1, b._wood_shade(0.9), WOOD)
	var ties := 2 if height < 1.6 else 3
	for i in ties:
		var y := height * (0.22 + 0.62 * float(i) / maxf(ties - 1, 1)) + b.rng.randf_range(-0.05, 0.05)
		for k in 2:
			b.rope_ring(Vector3(0, y + k * 0.03, 0), Vector3.UP, r + 0.012, 0.014)
	return b.commit()


## A log laid along a roof's peak (along X, `length` long, centred), with rope ties
static func ridge_mesh(length: float, seed_value: int) -> ArrayMesh:
	var b := PieceDetail.new(seed_value)
	var half := length / 2.0
	b.log_part(Vector3(-half, 0, 0), Vector3(half, 0, 0), RIDGE_RADIUS, 8, 0.08, b._wood_shade(0.85), WOOD)
	var spots: Array[float] = [-half * 0.6, half * 0.6]
	if length < 1.0:
		spots = [0.0]
	for x in spots:
		b.rope_ring(Vector3(x, 0, 0), Vector3.RIGHT, RIDGE_RADIUS + 0.012, 0.014)
		b.rope_ring(Vector3(x + 0.035, 0, 0), Vector3.RIGHT, RIDGE_RADIUS + 0.012, 0.014)
	return b.commit()


func commit() -> ArrayMesh:
	if _count == 0:
		return null
	st.generate_tangents()
	return st.commit()


# ---- Walls ----

# A plank wall from -width/2 to width/2, 0 to height, centred on z = 0, with holes (doorways,
# windows) given as Rect2s in (x, y). Planks run level; a dark core behind them fills the gaps.
func _wall(width: float, height: float, holes: Array) -> void:
	var t := PieceShapes.WALL_THICKNESS
	var half := width / 2.0
	var x0 := -half
	var x1 := half
	# The core, behind the gaps (with the holes cut through it)
	for band in _bands_outside(x0, x1, 0.0, height, holes, 0.002):
		var r: Rect2 = band
		box_part(Vector3(r.get_center().x, r.get_center().y, 0), Vector3(r.size.x, r.size.y, 0.06), Basis.IDENTITY, 0.0, Color(1, 1, 1), DARK, 0)
	# Course boundaries: random plank heights, broken at the holes' edges
	var breaks: Array[float] = [0.0, height]
	for h in holes:
		var hr: Rect2 = h
		breaks.append(hr.position.y)
		breaks.append(hr.end.y)
	breaks.sort()
	var course := 0
	for i in breaks.size() - 1:
		var y := breaks[i]
		var top := breaks[i + 1]
		while top - y > 0.02:
			var h := rng.randf_range(PLANK_MIN, PLANK_MAX)
			if top - (y + h) < PLANK_MIN * 0.6:
				h = top - y
			var mid := y + h / 2.0
			# Which parts of this course are wall (not hole)
			var spans: Array = [[x0, x1]]
			for hole in holes:
				var hr: Rect2 = hole
				if mid > hr.position.y and mid < hr.end.y:
					spans = _cut_spans(spans, hr.position.x, hr.end.x)
			for s in spans:
				var span: Array = s
				_wall_plank(span[0], span[1], y, y + h, t, course)
			y += h
			course += 1
	# Chunky frames round the holes
	for hole in holes:
		var hr: Rect2 = hole
		var jamb := 0.12
		var depth := t + 0.02
		var shade := _wood_shade(0.82)
		box_part(Vector3(hr.position.x - jamb / 2.0 + 0.02, hr.end.y / 2.0 + hr.position.y / 2.0, 0), Vector3(jamb, hr.size.y, depth), Basis.IDENTITY, BEVEL, shade, WOOD, 1)
		box_part(Vector3(hr.end.x + jamb / 2.0 - 0.02, hr.end.y / 2.0 + hr.position.y / 2.0, 0), Vector3(jamb, hr.size.y, depth), Basis.IDENTITY, BEVEL, shade, WOOD, 1)
		var lintel_h := minf(0.15, height - hr.end.y + 0.02)
		box_part(Vector3(hr.get_center().x, hr.end.y + lintel_h / 2.0 - 0.01, 0), Vector3(hr.size.x + jamb * 2.0 + 0.06, lintel_h, depth), Basis.IDENTITY, BEVEL, _wood_shade(0.78), WOOD, 0)
		if hr.position.y > 0.05:
			# A window: a sill sticking out a little
			box_part(Vector3(hr.get_center().x, hr.position.y - 0.035, 0), Vector3(hr.size.x + jamb * 2.0 + 0.12, 0.07, depth + 0.02), Basis.IDENTITY, BEVEL, _wood_shade(0.8), WOOD, 0)


# One level plank from x0 to x1, y0 to y1 (gaps taken off), with random thickness, tilt and ends
func _wall_plank(x0: float, x1: float, y0: float, y1: float, t: float, course: int) -> void:
	var gap := rng.randf_range(GAP_MIN, GAP_MAX)
	var a := x0 + rng.randf_range(0.0, 0.014)
	var b := x1 - rng.randf_range(0.0, 0.014)
	if b - a < 0.05:
		return
	var lo := y0 + gap / 2.0
	var hi := y1 - gap / 2.0
	var tilt := rng.randf_range(-0.006, 0.006)
	var c := Vector2((a + b) / 2.0, (lo + hi) / 2.0)
	var poly := PackedVector2Array([Vector2(a, lo), Vector2(b, lo), Vector2(b, hi), Vector2(a, hi)])
	poly = _turned(poly, c, tilt)
	var thick := rng.randf_range(t - 0.03, t)
	var shift := rng.randf_range(-0.004, 0.004)
	var shade := _wood_shade(0.86 if course == 0 else 1.0)
	prism(poly, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -thick / 2.0 + shift, thick / 2.0 + shift, BEVEL, shade, WOOD, _plank_uv(c.y, hi - lo), 0)


# A curved plank wall on the ring, -half_angle to half_angle degrees about +Z
func _curved_wall(half_angle: float) -> void:
	var t := PieceShapes.WALL_THICKNESS
	var R := PieceShapes.RING_RADIUS
	var half := deg_to_rad(half_angle)
	var steps := roundi(half_angle * 2.0 / PieceShapes.ARC_STEP_DEGREES)
	var height := PieceShapes.WALL_HEIGHT
	arc_band(R - 0.03, R + 0.03, -half, half, 0.0, height, steps, Color(1, 1, 1), DARK, Transform2D.IDENTITY)
	var y := 0.0
	var course := 0
	while height - y > 0.02:
		var h := rng.randf_range(PLANK_MIN, PLANK_MAX)
		if height - (y + h) < PLANK_MIN * 0.6:
			h = height - y
		var gap := rng.randf_range(GAP_MIN, GAP_MAX)
		var thick := rng.randf_range(t - 0.03, t)
		var a0 := -half + rng.randf_range(0.0, 0.006)
		var a1 := half - rng.randf_range(0.0, 0.006)
		arc_band(R - thick / 2.0, R + thick / 2.0, a0, a1, y + gap / 2.0, y + h - gap / 2.0, steps, _wood_shade(0.86 if course == 0 else 1.0), WOOD, _plank_uv(y + h / 2.0, h - gap))
		y += h
		course += 1


# A gable: level planks cut to the triangle, with a king post at its high end, a sill beam and a
# brace (two gables back to back make a gable end with a doubled post)
func _gable(rise: float) -> void:
	var half := PieceShapes.GRID / 2.0
	var t := PieceShapes.WALL_THICKNESS
	var outline := PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(half, rise)])
	prism(_inset(outline, 0.01), Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -0.03, 0.03, 0.0, Color(1, 1, 1), DARK, Transform2D.IDENTITY, 0)
	var y := 0.0
	while rise - y > 0.03:
		var h := rng.randf_range(PLANK_MIN, PLANK_MAX)
		if rise - (y + h) < PLANK_MIN * 0.5:
			h = rise - y
		var gap := rng.randf_range(GAP_MIN, GAP_MAX)
		var strip := PieceShapes._clip(outline, Vector2(0, 1), y + gap / 2.0, y + h - gap / 2.0)
		strip = PieceShapes._clip(strip, Vector2(1, 0), -half + rng.randf_range(0.0, 0.012), half - 0.12)
		if strip.size() >= 3:
			var thick := rng.randf_range(t - 0.03, t)
			prism(strip, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -thick / 2.0, thick / 2.0, BEVEL * 0.7, _wood_shade(1.0), WOOD, _plank_uv(y + h / 2.0, h - gap), 0)
		y += h
	var timber := t + 0.03
	var post := PieceShapes._clip(outline, Vector2(1, 0), half - 0.13, half - 0.005)
	prism(post, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -timber / 2.0, timber / 2.0, BEVEL, _wood_shade(0.8), WOOD, _generic_uv(), 1)
	var sill := PieceShapes._clip(outline, Vector2(0, 1), 0.0, 0.11)
	sill = PieceShapes._clip(sill, Vector2(1, 0), -half + 0.01, half - 0.13)
	prism(sill, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -timber / 2.0, timber / 2.0, BEVEL, _wood_shade(0.8), WOOD, _generic_uv(), 0)
	# The brace: from the sill up to the post, kept inside the triangle
	var from := Vector2(-half * 0.25, 0.11)
	var to := Vector2(half - 0.13, rise * 0.55)
	var dir := (to - from).normalized()
	var across := Vector2(-dir.y, dir.x) * 0.055
	var brace := PackedVector2Array([from - across, to - across, to + across, from + across])
	brace = _clip_to(brace, outline)
	if brace.size() >= 3:
		prism(brace, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -timber / 2.0 + 0.01, timber / 2.0 - 0.01, BEVEL, _wood_shade(0.78), WOOD, _generic_uv(), 0)


# The door panel (it swings, so it's a mesh of its own): vertical planks, battens behind, dark
# iron strap hinges down its hinge side, and a rope pull on each face
func _door() -> void:
	var w := PieceShapes.DOOR_WIDTH - 0.04
	var h := PieceShapes.DOOR_HEIGHT - 0.02
	var half := w / 2.0
	var boards := 5
	for i in boards:
		var a := -half + w * i / boards + 0.004
		var b := -half + w * (i + 1) / boards - 0.004
		var poly := PackedVector2Array([Vector2(a, rng.randf_range(0.0, 0.01)), Vector2(b, rng.randf_range(0.0, 0.01)), Vector2(b, h - rng.randf_range(0.0, 0.015)), Vector2(a, h - rng.randf_range(0.0, 0.015))])
		var thick := rng.randf_range(0.05, 0.06)
		prism(poly, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -thick / 2.0, thick / 2.0, 0.008, _wood_shade(0.95), WOOD, _plank_uv((a + b) / 2.0, b - a), 1)
	for y in [0.3, h - 0.3]:
		box_part(Vector3(0, y, -0.035), Vector3(w - 0.08, 0.12, 0.025), Basis.IDENTITY, 0.006, _wood_shade(0.8), WOOD, 0)
	for y in [0.32, h - 0.32]:
		box_part(Vector3(-half + 0.36, y, 0.036), Vector3(0.7, 0.055, 0.012), Basis.IDENTITY, 0.0, Color(1, 1, 1), IRON, 0)
		log_part(Vector3(-half + 0.01, y - 0.06, 0.03), Vector3(-half + 0.01, y + 0.06, 0.03), 0.022, 6, 0.0, Color(1, 1, 1), IRON)
		for k in 3:
			box_part(Vector3(-half + 0.1 + k * 0.22, y, 0.044), Vector3(0.018, 0.018, 0.006), Basis.IDENTITY, 0.0, Color(0.7, 0.7, 0.7), IRON, 0)
	for side in [1.0, -1.0]:
		rope_ring(Vector3(half - 0.12, 1.0, side * 0.06), Vector3(0, 0, 1), 0.055, 0.011)


# ---- Floors and foundations ----

# Rough floor planks along X with gaps, laid over the outline (x, z), on a dark base down to
# `bottom`. The top stays at (or a hair under) 0.
func _floor(outline: PackedVector2Array, bottom: float, plank_depth := 0.05) -> void:
	prism(_inset(outline, 0.01), Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.UP, bottom, -plank_depth + 0.002, 0.0, _wood_shade(0.55), WOOD, _generic_uv(), 0)
	var lo := INF
	var hi := -INF
	var left := INF
	var right := -INF
	for p in outline:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		left = minf(left, p.x)
		right = maxf(right, p.x)
	var z := lo
	while hi - z > 0.02:
		var w := rng.randf_range(0.16, 0.25)
		if hi - (z + w) < 0.1:
			w = hi - z
		var gap := rng.randf_range(0.007, 0.014)
		var strip := PieceShapes._clip(outline, Vector2(0, 1), z + gap / 2.0, z + w - gap / 2.0)
		if strip.size() >= 3:
			# Long strips are two planks, butted at a random spot
			var pieces: Array = [strip]
			if right - left > 1.4:
				var cut := rng.randf_range(left + 0.5, right - 0.5)
				pieces = [PieceShapes._clip(strip, Vector2(1, 0), -INF, cut - 0.006), PieceShapes._clip(strip, Vector2(1, 0), cut + 0.006, INF)]
			for piece in pieces:
				var poly: PackedVector2Array = piece
				if poly.size() < 3:
					continue
				var top := -rng.randf_range(0.0, 0.007)
				prism(poly, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.UP, -plank_depth, top, BEVEL * 0.8, _wood_shade(1.0), WOOD, _plank_uv(z + w / 2.0, w - gap), 0)
		z += w


# A wood foundation: stacked logs along the given outer edges, a plank deck on top, a dark core
func _foundation_wood(outline: PackedVector2Array, edges: Array) -> void:
	_floor(outline, -0.06, 0.06)
	prism(_inset(outline, 0.18), Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.UP, -PieceShapes.FOUNDATION_DEPTH, -0.06, 0.0, Color(1, 1, 1), DARK, _generic_uv(), 0)
	var course := PieceShapes.COURSE
	var centre := _centroid(outline)
	var y := -0.06 - course / 2.0
	var k := 0
	while y > -SHOWN_DEPTH:
		for e in edges:
			var edge: Array = e
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			var inward := _inward(a, b, centre)
			var r := course / 2.0 * rng.randf_range(0.9, 1.04)
			var stretch := (b - a).normalized() * (0.04 if (k % 2 == 0) else -0.02)
			var pa := a + inward * r - stretch
			var pb := b + inward * r + stretch
			log_part(Vector3(pa.x, y, pa.y), Vector3(pb.x, y, pb.y), r, LOG_SIDES, 0.07, _wood_shade(0.85), WOOD)
		y -= course
		k += 1


# A stone foundation: courses of irregular bevelled blocks along the given outer edges, flagstones
# on top, dark mortar showing between them
func _foundation_stone(outline: PackedVector2Array, edges: Array) -> void:
	prism(_inset(outline, 0.03), Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.UP, -PieceShapes.FOUNDATION_DEPTH, -0.01, 0.0, Color(1, 1, 1), DARK, _generic_uv(), 0)
	# Flagstones on top
	var cell := 0.66
	for i in range(-6, 6):
		for j in range(-6, 6):
			var x0 := i * cell + rng.randf_range(-0.04, 0.04)
			var z0 := j * cell + rng.randf_range(-0.04, 0.04)
			var flag := PieceShapes._clip(PieceShapes._clip(outline, Vector2(1, 0), x0 + 0.015, x0 + cell - 0.015), Vector2(0, 1), z0 + 0.015, z0 + cell - 0.015)
			if flag.size() >= 3 and _area(flag) > 0.01:
				prism(flag, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.UP, -0.08, -rng.randf_range(0.0, 0.008), 0.018, _stone_shade(), STONE, _stone_uv(), 0)
	var centre := _centroid(outline)
	var y := -0.08
	var row := 0
	while y > -STONE_SHOWN_DEPTH:
		var h := rng.randf_range(0.24, 0.36)
		for e in edges:
			var edge: Array = e
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			var along := b - a
			var length := along.length()
			var dir := along / length
			var inward := _inward(a, b, centre)
			var t := -rng.randf_range(0.0, 0.25) if row % 2 == 1 else 0.0
			while t < length:
				var l := rng.randf_range(0.4, 0.75)
				var t0 := maxf(t, 0.0) + 0.012
				var t1 := minf(t + l, length) - 0.012
				t += l
				if t1 - t0 < 0.08:
					continue
				var inset := rng.randf_range(0.0, 0.012)
				var depth := STONE_DEPTH * rng.randf_range(0.9, 1.1)
				var foot := PackedVector2Array([a + dir * t0 + inward * inset, a + dir * t1 + inward * inset, a + dir * t1 + inward * (inset + depth), a + dir * t0 + inward * (inset + depth)])
				foot = _turned(foot, _centroid(foot), rng.randf_range(-0.035, 0.035))
				foot = _clip_to(foot, outline)
				if foot.size() < 3:
					continue
				var y_top := y - 0.012 - rng.randf_range(0.0, 0.01)
				prism(foot, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.UP, y - h + 0.012, y_top, 0.025, _stone_shade(), STONE, _stone_uv(), 0)
		y -= h
		row += 1


# ---- Roofs ----

# A piece of roof (a panel, eave, gable overhang or eave corner): x0 to x1 across, z0 to z1 along
# the slope (level), its underside on the roof's plane, rising `rise` per 2 m. Deck boards, rafters
# under them at the given x positions (their tails poking out past the low end), and rows of split
# shakes on top, cut off at the high end so roofs back to back meet cleanly.
func _roof_panel(rise: float, x0: float, x1: float, z0: float, z1: float, rafters: Array) -> void:
	var k := rise / PieceShapes.GRID
	var s := Vector3(0, k, 1).normalized()
	var n := Vector3(0, 1, -k).normalized()
	var u := Vector3.RIGHT
	var v0 := z0 / s.z
	var v1 := z1 / s.z
	# Deck boards across the slope
	var v := v0
	while v1 - v > 0.02:
		var w := rng.randf_range(0.2, 0.3)
		if v1 - (v + w) < 0.1:
			w = v1 - v
		var poly := PackedVector2Array([Vector2(x0, v), Vector2(x1, v), Vector2(x1, v + w), Vector2(x0, v + w)])
		prism(poly, Vector3.ZERO, u, s, n, 0.0, DECK, 0.006, _wood_shade(0.7), WOOD, _plank_uv(v + w / 2.0, w), 0)
		v += w
	# Rafters, under the deck, their tails out past the low end
	for x in rafters:
		var rx: float = x
		var poly := PackedVector2Array([Vector2(rx - 0.04, v0 - 0.17), Vector2(rx + 0.04, v0 - 0.17), Vector2(rx + 0.04, v1 - 0.02), Vector2(rx - 0.04, v1 - 0.02)])
		prism(poly, Vector3.ZERO, u, s, n, -0.12, -0.001, 0.01, _wood_shade(0.75), WOOD, _generic_uv(), 1)
	_shakes(Vector3.ZERO, u, s, n, PackedVector2Array([Vector2(x0, v0 - 0.03), Vector2(x1, v0 - 0.03), Vector2(x1, v1), Vector2(x0, v1)]), 1.0)


# Fascia boards round an overhang's outer edges: along its low end (`low_end`), and barge boards
# down both its sides (`sides`; the inner one tucks under the roof beside it)
func _fascia(rise: float, x0: float, x1: float, z0: float, z1: float, low_end: bool, sides: bool) -> void:
	var k := rise / PieceShapes.GRID
	var s := Vector3(0, k, 1).normalized()
	var n := Vector3(0, 1, -k).normalized()
	var v0 := z0 / s.z
	var v1 := z1 / s.z
	var thick := 0.035
	var below := 0.11
	var above := DECK + 0.045
	if sides:
		for side in [-1.0, 1.0]:
			var x: float = x1 if side > 0.0 else x0
			var poly := PackedVector2Array([Vector2(v0 - (0.035 if low_end else 0.0), -below), Vector2(v1, -below), Vector2(v1, above), Vector2(v0 - (0.035 if low_end else 0.0), above)])
			var d0: float = x if side > 0.0 else x - thick
			prism(poly, Vector3.ZERO, s, n, Vector3.RIGHT, d0, d0 + thick, 0.006, _wood_shade(0.8), WOOD, _plank_uv(0.0, 0.2), 0)
	if low_end:
		var y := z0 * k
		var height := below + above
		var centre := Vector3((x0 + x1) / 2.0, y - below + height / 2.0 + 0.01, z0 - thick / 2.0)
		box_part(centre, Vector3(x1 - x0 + (thick * 2.0 if sides else 0.0), height, thick), Basis.IDENTITY, 0.006, _wood_shade(0.8), WOOD, 0)


# A hip (outer) or valley (inner) corner: its two facets each decked and shaked, with a log along
# a hip
func _roof_corner(rise: float, inner: bool) -> void:
	var half := PieceShapes.GRID / 2.0
	var heights := func(p: Vector2) -> float:
		var a := p.y * rise / PieceShapes.GRID
		var b := (half - p.x) * rise / PieceShapes.GRID
		return maxf(a, b) if inner else minf(a, b)
	var front_right := Vector2(half, 0)
	var back_left := Vector2(-half, PieceShapes.GRID)
	var facets := [[front_right, Vector2(-half, 0), back_left], [front_right, Vector2(half, PieceShapes.GRID), back_left]]
	for f in facets:
		var corners: Array = f
		var pts: Array[Vector3] = []
		for c in corners:
			var p: Vector2 = c
			pts.append(Vector3(p.x, heights.call(p), p.y))
		var n := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
		if n.y < 0.0:
			n = -n
		var s := (Vector3.UP - n * n.y).normalized()
		var u := s.cross(n).normalized()
		var o := Vector3(front_right.x, 0, front_right.y)
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(Vector2((p - o).dot(u), (p - o).dot(s)))
		prism(poly, o, u, s, n, 0.0, DECK, 0.0, _wood_shade(0.7), WOOD, _generic_uv(), 1)
		_shakes(o, u, s, n, poly, 1.0)
	if not inner:
		var lift := PieceShapes.ROOF_THICKNESS / cos(atan2(rise, PieceShapes.GRID))
		log_part(Vector3(half, lift + 0.03, 0), Vector3(-half, rise + lift + 0.03, PieceShapes.GRID), 0.075, 7, 0.06, _wood_shade(0.8), WOOD)


# A ridge cap: a log along the peak with rope ties
func _ridge_cap(rise: float) -> void:
	var lift := PieceShapes.ROOF_THICKNESS / cos(atan2(rise, PieceShapes.GRID))
	var y := lift + RIDGE_RADIUS * 0.4
	log_part(Vector3(-1.0, y, 0), Vector3(1.0, y, 0), RIDGE_RADIUS, 8, 0.08, _wood_shade(0.85), WOOD)
	for x in [-0.6, 0.6]:
		rope_ring(Vector3(x, y, 0), Vector3.RIGHT, RIDGE_RADIUS + 0.012, 0.014)
		rope_ring(Vector3(x + 0.035, y, 0), Vector3.RIGHT, RIDGE_RADIUS + 0.012, 0.014)


# A cone roof wedge: each arc step its own flat facet, decked and shaked
func _cone_roof() -> void:
	var R := PieceShapes.RING_RADIUS
	var half := deg_to_rad(22.5)
	var steps := roundi(45.0 / PieceShapes.ARC_STEP_DEGREES)
	var apex := Vector3(0, PieceShapes.CONE_HEIGHT - PieceShapes.ROOF_THICKNESS, 0)
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		var p0 := PieceShapes._arc_point(R, a0, 0.0)
		var p1 := PieceShapes._arc_point(R, a1, 0.0)
		var n := (p1 - apex).cross(p0 - apex).normalized()
		if n.y < 0.0:
			n = -n
		var s := (Vector3.UP - n * n.y).normalized()
		var u := s.cross(n).normalized()
		var poly := PackedVector2Array()
		for p in [p0, p1, apex]:
			poly.append(Vector2((p - p0).dot(u), (p - p0).dot(s)))
		prism(poly, p0, u, s, n, 0.0, DECK * 0.8, 0.0, _wood_shade(0.7), WOOD, _generic_uv(), 1)
		_shakes(p0, u, s, n, poly, 1.25)


# Rows of split shakes on a flat roof facet (origin o, u across, s up the slope, n out), filling
# the polygon (in (u, s) coordinates), each row SHAKE_EXPOSURE above the one below; shakes vary in
# width, angle and shade, and a few sit out of place
func _shakes(o: Vector3, u: Vector3, s: Vector3, n: Vector3, poly: PackedVector2Array, wide: float) -> void:
	var lo := INF
	var hi := -INF
	var left := INF
	var right := -INF
	for p in poly:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		left = minf(left, p.x)
		right = maxf(right, p.x)
	var row := floori(lo / SHAKE_EXPOSURE)
	while row * SHAKE_EXPOSURE < hi - 0.02:
		var v0 := row * SHAKE_EXPOSURE
		var x := left - rng.randf_range(0.0, 0.14)
		while x < right:
			var w := rng.randf_range(0.13, 0.28) * wide
			var gap := rng.randf_range(0.008, 0.02)
			var length := SHAKE_LENGTH * rng.randf_range(0.92, 1.06)
			var yaw := rng.randf_range(-0.04, 0.04)
			var slip := 0.0
			if rng.randf() < 0.06:
				yaw = rng.randf_range(-0.16, 0.16)
				slip = rng.randf_range(-0.035, 0.02)
			var a := v0 + slip
			var rect := PackedVector2Array([Vector2(x, a), Vector2(x + w - gap, a), Vector2(x + w - gap, a + length), Vector2(x, a + length)])
			rect = _turned(rect, Vector2(x + w / 2.0, a + length / 2.0), yaw)
			rect = _clip_to(rect, poly)
			x += w
			if rect.size() < 3 or _area(rect) < 0.004:
				continue
			# Its butt end rests on the row below, so it leans down toward the slope's top
			var raise := 0.016
			var lean := -raise / length
			var base := DECK + raise + raise * a / length
			prism(rect, o, u, s, n, base, base + SHAKE_THICK, 0.0, _shake_shade(), WOOD, _plank_uv(x - w / 2.0, w - gap), 1, 2, lean)
		row += 1


# ---- Stairs, posts, beams and the rest ----

# Chunky plank treads on two log stringers
func _stairs() -> void:
	var steps := PieceShapes.STAIRS_STEPS
	var rise := PieceShapes.WALL_HEIGHT / steps
	var run := PieceShapes.STAIRS_RUN / steps
	var start := -PieceShapes.STAIRS_RUN / 2.0
	var w := PieceShapes.GRID
	for i in steps:
		var top := rise * (i + 1)
		var z0 := start + run * i - 0.02
		var z1 := start + run * (i + 1)
		var mid := z0 + (z1 - z0) * rng.randf_range(0.45, 0.55)
		for part in [[z0, mid - 0.005], [mid + 0.005, z1]]:
			var p: Array = part
			var poly := PackedVector2Array([Vector2(-w / 2.0 + 0.04, p[0]), Vector2(w / 2.0 - 0.04, p[0]), Vector2(w / 2.0 - 0.04, p[1]), Vector2(-w / 2.0 + 0.04, p[1])])
			poly = _turned(poly, _centroid(poly), rng.randf_range(-0.01, 0.01))
			prism(poly, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.UP, top - 0.075, top - rng.randf_range(0.0, 0.006), BEVEL, _wood_shade(0.95), WOOD, _plank_uv((p[0] + p[1]) / 2.0, p[1] - p[0]), 0)
	var r := 0.1
	var k := rise / run
	for side in [-1.0, 1.0]:
		var x: float = side * (w / 2.0 - 0.2)
		# Under the treads' front edges, down to the ground
		var top_z := start + run * (steps - 0.5)
		var top_y := PieceShapes.WALL_HEIGHT - 0.075 - r
		var low_y := 0.08
		var low_z := top_z - (top_y - low_y) / k
		log_part(Vector3(x, low_y, low_z), Vector3(x, top_y, top_z), r, 8, 0.06, _wood_shade(0.8), WOOD)


func _wood_pillar() -> void:
	var h := PieceShapes.PILLAR_HEIGHT
	log_part(Vector3(0, 0, 0), Vector3(0, h, 0), PieceShapes.WOOD_PILLAR / 2.0, 9, 0.08, _wood_shade(0.85), WOOD)
	rope_ring(Vector3(0, h - 0.18, 0), Vector3.UP, PieceShapes.WOOD_PILLAR / 2.0 + 0.012, 0.014)
	rope_ring(Vector3(0, h - 0.15, 0), Vector3.UP, PieceShapes.WOOD_PILLAR / 2.0 + 0.012, 0.014)


# Stacked irregular stone blocks, one or two to a course, with dark mortar between
func _stone_pillar() -> void:
	var w := PieceShapes.STONE_PILLAR
	var h := PieceShapes.PILLAR_HEIGHT
	box_part(Vector3(0, h / 2.0, 0), Vector3(w - 0.06, h, w - 0.06), Basis.IDENTITY, 0.0, Color(1, 1, 1), DARK, 0)
	var y := 0.0
	var k := 0
	while h - y > 0.03:
		var c := rng.randf_range(0.2, 0.32)
		if h - (y + c) < 0.14:
			c = h - y
		var yaw := rng.randf_range(-0.07, 0.07) + (k % 2) * PI / 2.0
		var basis := Basis(Vector3.UP, yaw)
		if rng.randf() < 0.4:
			box_part(Vector3(0, y + c / 2.0, 0), Vector3(w * rng.randf_range(0.93, 1.0), c - 0.022, w * rng.randf_range(0.93, 1.0)), basis, 0.03, _stone_shade(), STONE, 0, _stone_uv())
		else:
			var split := rng.randf_range(-0.05, 0.05)
			for side in [-1.0, 1.0]:
				var part: float = (w / 2.0 + side * split) - 0.012
				var x: float = side * (w / 2.0 - part / 2.0 - 0.006)
				box_part(Vector3(0, y + c / 2.0, 0) + basis * Vector3(x, 0, 0), Vector3(part, c - 0.022, w * rng.randf_range(0.92, 1.0)), basis, 0.025, _stone_shade(), STONE, 0, _stone_uv())
		y += c
		k += 1


func _pole(length: float) -> void:
	log_part(Vector3.ZERO, Vector3(0, length, 0), PieceShapes.POLE / 2.0, 7, 0.08, _wood_shade(0.85), WOOD)


func _beam(length: float) -> void:
	log_part(Vector3(-length / 2.0, 0, 0), Vector3(length / 2.0, 0, 0), PieceShapes.BEAM / 2.0, 8, 0.07, _wood_shade(0.85), WOOD)


func _diagonal_beam(rise: float) -> void:
	log_part(Vector3(-PieceShapes.GRID / 2.0, 0, 0), Vector3(PieceShapes.GRID / 2.0, rise, 0), PieceShapes.BEAM / 2.0, 8, 0.07, _wood_shade(0.85), WOOD)


func _ladder() -> void:
	var width := 0.6
	var h := PieceShapes.LADDER_HEIGHT
	for side in [-1.0, 1.0]:
		log_part(Vector3(side * (width / 2.0 - 0.04), 0, 0), Vector3(side * (width / 2.0 - 0.04), h, 0), 0.04, 6, 0.08, _wood_shade(0.85), WOOD)
	var y := 0.15
	while y < h - 0.05:
		log_part(Vector3(-width / 2.0 + 0.01, y, 0), Vector3(width / 2.0 - 0.01, y + rng.randf_range(-0.01, 0.01), 0), 0.025, 6, 0.1, _wood_shade(0.9), WOOD)
		y += 0.3


func _railing(length: float) -> void:
	var half := length / 2.0
	var height := PieceShapes.RAILING_HEIGHT
	var posts: Array[float] = [-half + 0.05, half - 0.05]
	if length > 1.5:
		posts.append(0.0)
	for x in posts:
		log_part(Vector3(x, 0, 0), Vector3(x, height, 0), 0.05, 7, 0.08, _wood_shade(0.85), WOOD)
	for y in [height - 0.06, height * 0.5]:
		log_part(Vector3(-half, y, 0), Vector3(half, y + rng.randf_range(-0.01, 0.01), 0), 0.035, 6, 0.08, _wood_shade(0.9), WOOD)
		for x in posts:
			rope_ring(Vector3(x, y, 0), Vector3.UP, 0.06, 0.012, 8, 4)


func _fence() -> void:
	var half := PieceShapes.GRID / 2.0
	var height := PieceShapes.FENCE_HEIGHT
	for y in [0.35, height - 0.35]:
		log_part(Vector3(-half, y, -0.06), Vector3(half, y + rng.randf_range(-0.015, 0.015), -0.06), 0.045, 6, 0.08, _wood_shade(0.85), WOOD)
	var x := -half + 0.1
	while x < half:
		var w := rng.randf_range(0.1, 0.14)
		var top := height - rng.randf_range(0.0, 0.08)
		var poly := PackedVector2Array([Vector2(x - w / 2.0, 0), Vector2(x + w / 2.0, 0), Vector2(x + w / 2.0, top - 0.1), Vector2(x, top), Vector2(x - w / 2.0, top - 0.1)])
		poly = _turned(poly, Vector2(x, top / 2.0), rng.randf_range(-0.025, 0.025))
		prism(poly, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -0.022, 0.022, 0.006, _wood_shade(1.0), WOOD, _plank_uv(x, w), 1)
		x += 0.2


# ---- Parts ----

## A straight solid with this convex outline (in (u, v) from o), from depth d0 to d1 along n, its
## caps bevelled. `grain` says which axis the wood runs along (0 u, 1 v, 2 n); `caps` is 3 for
## both caps, 2 for the top only; `lean` adds lean × v to every depth (shakes resting on a row).
func prism(poly: PackedVector2Array, o: Vector3, u: Vector3, v: Vector3, n: Vector3, d0: float, d1: float, bevel: float, color: Color, kind: int, uvx: Transform2D, grain := 0, caps := 3, lean := 0.0) -> void:
	var k := poly.size()
	if k < 3:
		return
	bevel = minf(bevel, (d1 - d0) * 0.35)
	var inner := poly
	if bevel > 0.0005:
		inner = _inset(poly, bevel)
		if inner.size() != k:
			inner = poly
			bevel = 0.0
	else:
		bevel = 0.0
	# The grain axis, the axis across the boards, and the third
	var g := u
	var c := v
	var h := n
	if grain == 1:
		g = v
		c = u
	elif grain == 2:
		g = n
		c = u
		h = v
	var middle := _centroid(poly)
	var at := func(q: Vector2, d: float) -> Vector3:
		return o + u * q.x + v * q.y + n * (d + lean * q.y)
	# The caps
	for i in range(1, k - 1):
		var a: Vector3 = at.call(inner[0], d1)
		var b: Vector3 = at.call(inner[i], d1)
		var cc: Vector3 = at.call(inner[i + 1], d1)
		_tri_flat(a, b, cc, n, color, kind, g, c, h, uvx)
		if caps & 1:
			_tri_flat(at.call(inner[0], d0), at.call(inner[i], d0), at.call(inner[i + 1], d0), -n, color, kind, g, c, h, uvx)
	for i in k:
		var p := poly[i]
		var q := poly[(i + 1) % k]
		var out2 := Vector2(q.y - p.y, -(q.x - p.x)).normalized()
		if out2.dot((p + q) / 2.0 - middle) < 0.0:
			out2 = -out2
		var out := (u * out2.x + v * out2.y).normalized()
		_quad_flat(at.call(p, d0 + bevel), at.call(q, d0 + bevel), at.call(q, d1 - bevel), at.call(p, d1 - bevel), out, color, kind, g, c, h, uvx)
		if bevel > 0.0:
			_quad_flat(at.call(p, d1 - bevel), at.call(q, d1 - bevel), at.call(inner[(i + 1) % k], d1), at.call(inner[i], d1), (out + n).normalized(), color, kind, g, c, h, uvx)
			if caps & 1:
				_quad_flat(at.call(p, d0 + bevel), at.call(q, d0 + bevel), at.call(inner[(i + 1) % k], d0), at.call(inner[i], d0), (out - n).normalized(), color, kind, g, c, h, uvx)


## A box (centre, size, turned by basis), its grain along one of its own axes
func box_part(centre: Vector3, size: Vector3, basis: Basis, bevel: float, color: Color, kind: int, grain := 0, uvx := Transform2D(0.0, Vector2(1.0 / TEX, 1.0 / TEX), 0.0, Vector2.ZERO)) -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var poly := PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
	prism(poly, centre, basis.x, basis.y, basis.z, -size.z / 2.0, size.z / 2.0, bevel, color, kind, uvx, grain)


## A slightly irregular log from a to b (each corner's radius wobbles a little), with end grain
func log_part(a: Vector3, b: Vector3, r: float, sides: int, wobble: float, color: Color, kind := WOOD) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.01:
		return
	axis /= length
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.1:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var spin := rng.randf() * TAU
	var ra: Array[float] = []
	var rb: Array[float] = []
	for i in sides:
		ra.append(r * (1.0 + rng.randf_range(-wobble, wobble)))
		rb.append(r * (1.0 + rng.randf_range(-wobble, wobble)))
	var off := Vector2(rng.randf(), rng.randf())
	var dirs: Array[Vector3] = []
	for i in sides + 1:
		var t := spin + TAU * i / sides
		dirs.append(side * cos(t) + up * sin(t))
	for i in sides:
		var j := (i + 1) % sides
		var pa0 := a + dirs[i] * ra[i]
		var pb0 := b + dirs[i] * rb[i]
		var pa1 := a + dirs[i + 1] * ra[j]
		var pb1 := b + dirs[i + 1] * rb[j]
		var c0 := r * TAU * i / sides / TEX * 0.5
		var c1 := r * TAU * (i + 1) / sides / TEX * 0.5
		var l1 := length / TEX
		_tri(pa0, pb0, pb1, dirs[i], dirs[i], dirs[i + 1], Vector2(c0, 0) + off, Vector2(c0, l1) + off, Vector2(c1, l1) + off, color, kind)
		_tri(pa0, pb1, pa1, dirs[i], dirs[i + 1], dirs[i + 1], Vector2(c0, 0) + off, Vector2(c1, l1) + off, Vector2(c1, 0) + off, color, kind)
	var end_color := color.lightened(0.18)
	for i in sides:
		var j := (i + 1) % sides
		for e in [[a, ra, -axis], [b, rb, axis]]:
			var centre: Vector3 = e[0]
			var radii: Array[float] = e[1]
			var normal: Vector3 = e[2]
			var p0 := centre + dirs[i] * radii[i]
			var p1 := centre + dirs[i + 1] * radii[j]
			var uv := func(p: Vector3) -> Vector2:
				return Vector2((p - centre).dot(side), (p - centre).dot(up)) / TEX * 0.6 + off
			_tri(centre, p0, p1, normal, normal, normal, uv.call(centre), uv.call(p0), uv.call(p1), end_color, kind)


## A ring of rope round an axis (radius R, rope thickness 2 × tube)
func rope_ring(centre: Vector3, axis: Vector3, R: float, tube: float, segments := 10, sides := 4) -> void:
	axis = axis.normalized()
	var x0 := axis.cross(Vector3.UP)
	if x0.length() < 0.1:
		x0 = axis.cross(Vector3.RIGHT)
	x0 = x0.normalized()
	var y0 := axis.cross(x0).normalized()
	var shade := Color(1, 1, 1) * rng.randf_range(0.85, 1.05)
	for i in segments:
		for j in sides:
			var pts: Array[Vector3] = []
			var nrm: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for di in 2:
				for dj in 2:
					var a := TAU * (i + di) / segments
					var b := TAU * (j + dj) / sides
					var ring := x0 * cos(a) + y0 * sin(a)
					var n := ring * cos(b) + axis * sin(b)
					pts.append(centre + ring * R + n * tube)
					nrm.append(n)
					uvs.append(Vector2(R * a / TEX, float(j + dj) / sides))
			_tri(pts[0], pts[2], pts[3], nrm[0], nrm[2], nrm[3], uvs[0], uvs[2], uvs[3], shade, ROPE)
			_tri(pts[0], pts[3], pts[1], nrm[0], nrm[3], nrm[1], uvs[0], uvs[3], uvs[1], shade, ROPE)


## A curved band on the ring (radius r0 to r1, angles a0 to a1 about +Z, heights y0 to y1), its
## grain running round the curve
func arc_band(r0: float, r1: float, a0: float, a1: float, y0: float, y1: float, steps: int, color: Color, kind: int, uvx: Transform2D) -> void:
	var arc := func(r: float, a: float, y: float) -> Vector3:
		return Vector3(r * sin(a), y, r * cos(a))
	var uvp := func(c: float, g: float) -> Vector2:
		return uvx * Vector2(c, g)
	var R := (r0 + r1) / 2.0
	for i in steps:
		var b0 := a0 + (a1 - a0) * i / steps
		var b1 := a0 + (a1 - a0) * (i + 1) / steps
		var n0 := Vector3(sin(b0), 0, cos(b0))
		var n1 := Vector3(sin(b1), 0, cos(b1))
		var g0 := b0 * R
		var g1 := b1 * R
		for face in [[r1, 1.0], [r0, -1.0]]:
			var r: float = face[0]
			var sgn: float = face[1]
			_tri(arc.call(r, b0, y0), arc.call(r, b1, y0), arc.call(r, b1, y1), n0 * sgn, n1 * sgn, n1 * sgn, uvp.call(y0, g0), uvp.call(y0, g1), uvp.call(y1, g1), color, kind)
			_tri(arc.call(r, b0, y0), arc.call(r, b1, y1), arc.call(r, b0, y1), n0 * sgn, n1 * sgn, n0 * sgn, uvp.call(y0, g0), uvp.call(y1, g1), uvp.call(y1, g0), color, kind)
		for face in [[y1, Vector3.UP], [y0, Vector3.DOWN]]:
			var y: float = face[0]
			var n: Vector3 = face[1]
			_tri(arc.call(r0, b0, y), arc.call(r1, b0, y), arc.call(r1, b1, y), n, n, n, uvp.call(r0, g0), uvp.call(r1, g0), uvp.call(r1, g1), color, kind)
			_tri(arc.call(r0, b0, y), arc.call(r1, b1, y), arc.call(r0, b1, y), n, n, n, uvp.call(r0, g0), uvp.call(r1, g1), uvp.call(r0, g1), color, kind)
	for e in [[a0, -1.0], [a1, 1.0]]:
		var a: float = e[0]
		var t := Vector3(cos(a), 0, -sin(a)) * float(e[1])
		_tri(arc.call(r0, a, y0), arc.call(r1, a, y0), arc.call(r1, a, y1), t, t, t, uvp.call(r0, y0), uvp.call(r1, y0), uvp.call(r1, y1), color.lightened(0.12), kind)
		_tri(arc.call(r0, a, y0), arc.call(r1, a, y1), arc.call(r0, a, y1), t, t, t, uvp.call(r0, y0), uvp.call(r1, y1), uvp.call(r0, y1), color.lightened(0.12), kind)


# ---- Building blocks ----

func _tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, color: Color, kind: int) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var p := b
		b = c
		c = p
		var n := nb
		nb = nc
		nc = n
		var t := ub
		ub = uc
		uc = t
	_vertex(a, na, ua, color, kind)
	_vertex(b, nb, ub, color, kind)
	_vertex(c, nc, uc, color, kind)
	_count += 3


func _vertex(p: Vector3, n: Vector3, uv: Vector2, color: Color, kind: int) -> void:
	st.set_normal(n)
	st.set_color(color)
	st.set_uv(uv)
	st.set_uv2(Vector2(kind, 0))
	st.add_vertex(p)


# A flat triangle, its texture laid on it along the part's axes (see _face_uv)
func _tri_flat(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color, kind: int, g: Vector3, cr: Vector3, h: Vector3, uvx: Transform2D) -> void:
	_tri(a, b, c, n, n, n, _face_uv(a, n, g, cr, h, uvx), _face_uv(b, n, g, cr, h, uvx), _face_uv(c, n, g, cr, h, uvx), color, kind)


func _quad_flat(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color, kind: int, g: Vector3, cr: Vector3, h: Vector3, uvx: Transform2D) -> void:
	_tri_flat(a, b, c, n, color, kind, g, cr, h, uvx)
	_tri_flat(a, c, d, n, color, kind, g, cr, h, uvx)


# Texture coordinates for a point on a face: (across, along the grain) where the grain lies in the
# face; on an end face, (across, depth). The part's transform then fits it to one board.
func _face_uv(p: Vector3, n: Vector3, g: Vector3, cr: Vector3, h: Vector3, uvx: Transform2D) -> Vector2:
	var on_g := absf(n.dot(g))
	var on_c := absf(n.dot(cr))
	var on_h := absf(n.dot(h))
	if on_c >= on_g and on_c >= on_h:
		return uvx * Vector2(p.dot(h), p.dot(g))
	if on_g >= on_h:
		return uvx * Vector2(p.dot(cr), p.dot(h))
	return uvx * Vector2(p.dot(cr), p.dot(g))


# Fits a plank (its middle at `centre` across the grain, `width` wide) onto one board of the wood
# texture at a random spot along it
func _plank_uv(centre: float, width: float) -> Transform2D:
	var board := float(rng.randi_range(0, int(BOARDS) - 1))
	var across := (0.82 / BOARDS) / maxf(width, 0.05)
	return Transform2D(Vector2(across, 0), Vector2(0, 1.0 / TEX), Vector2((board + 0.5) / BOARDS - centre * across, rng.randf()))


func _generic_uv() -> Transform2D:
	return Transform2D(Vector2(1.0 / TEX, 0), Vector2(0, 1.0 / TEX), Vector2(rng.randf(), rng.randf()))


# Stone blocks show a small patch of the stone texture, so each reads as one stone
func _stone_uv() -> Transform2D:
	return Transform2D(Vector2(0.22, 0), Vector2(0, 0.22), Vector2(rng.randf(), rng.randf()))


# Weathered planks each a little lighter or darker, a few warmer or cooler
func _wood_shade(base: float) -> Color:
	var b := base * rng.randf_range(0.8, 1.08)
	var warm := rng.randf_range(-0.04, 0.05)
	return Color(b * (1.0 + warm), b, b * (1.0 - warm))


func _shake_shade() -> Color:
	var c := _wood_shade(0.95)
	return c.darkened(0.25) if rng.randf() < 0.12 else c


func _stone_shade() -> Color:
	var b := rng.randf_range(0.75, 1.1)
	var t := rng.randf_range(-0.04, 0.04)
	return Color(b * (1.0 + t), b, b * (1.0 - t * 0.5))


# ---- Outlines ----

static func _rect(half: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])


# A round wedge's outline (x, z): the ring's middle and its arc
static func _wedge(half_angle: float) -> PackedVector2Array:
	var half := deg_to_rad(half_angle)
	var steps := roundi(half_angle * 2.0 / PieceShapes.ARC_STEP_DEGREES)
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in steps + 1:
		var a := -half + 2.0 * half * i / steps
		pts.append(Vector2(PieceShapes.RING_RADIUS * sin(a), PieceShapes.RING_RADIUS * cos(a)))
	return pts


static func _all_edges(poly: PackedVector2Array) -> Array:
	var edges := []
	for i in poly.size():
		edges.append([poly[i], poly[(i + 1) % poly.size()]])
	return edges


# A wedge's arc edges only (its straight sides meet its neighbours inside the circle)
static func _arc_edges(poly: PackedVector2Array) -> Array:
	var edges := []
	for i in range(1, poly.size() - 1):
		edges.append([poly[i], poly[i + 1]])
	return edges


static func _rise_of(shape: String) -> float:
	return PieceShapes.ROOF_RISE_45 if shape.ends_with("45") else PieceShapes.ROOF_RISE


# The parts of [x0, x1] spans left after cutting out a to b
static func _cut_spans(spans: Array, a: float, b: float) -> Array:
	var kept := []
	for s in spans:
		var span: Array = s
		if b <= span[0] or a >= span[1]:
			kept.append(span)
			continue
		if a > span[0]:
			kept.append([span[0], a])
		if b < span[1]:
			kept.append([b, span[1]])
	return kept


# Rectangles covering x0..x1, y0..y1 minus the holes (for a wall's core): the wall split into
# columns at the holes' sides, each column split round the holes in it
static func _bands_outside(x0: float, x1: float, y0: float, y1: float, holes: Array, shrink: float) -> Array:
	var cuts: Array[float] = [x0, x1]
	for h in holes:
		var r: Rect2 = h
		cuts.append(r.position.x)
		cuts.append(r.end.x)
	cuts.sort()
	var bands := []
	for i in cuts.size() - 1:
		var a := cuts[i]
		var b := cuts[i + 1]
		if b - a < 0.01:
			continue
		var mid := (a + b) / 2.0
		var ys: Array[float] = [y0, y1]
		for h in holes:
			var r: Rect2 = h
			if mid > r.position.x and mid < r.end.x:
				ys.append(r.position.y)
				ys.append(r.end.y)
		ys.sort()
		for j in range(0, ys.size() - 1, 2):
			if ys[j + 1] - ys[j] > 0.01:
				bands.append(Rect2(a + shrink, ys[j], b - a - shrink * 2.0, ys[j + 1] - ys[j]))
	return bands


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) / 2.0


static func _inward(a: Vector2, b: Vector2, centre: Vector2) -> Vector2:
	var n := Vector2(-(b - a).y, (b - a).x).normalized()
	return n if n.dot(centre - a) > 0.0 else -n


static func _turned(poly: PackedVector2Array, centre: Vector2, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(centre + (p - centre).rotated(angle))
	return out


# A convex polygon cut to fit inside another convex polygon
static func _clip_to(poly: PackedVector2Array, outline: PackedVector2Array) -> PackedVector2Array:
	var centre := _centroid(outline)
	var result := poly
	for i in outline.size():
		if result.size() < 3:
			return PackedVector2Array()
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var inward := _inward(a, b, centre)
		result = PieceShapes._clip_side(result, inward, inward.dot(a))
	return result


# A convex polygon shrunk by `by` on every side (empty if it would vanish)
static func _inset(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var k := poly.size()
	var centre := _centroid(poly)
	var lines := []
	for i in k:
		var a := poly[i]
		var b := poly[(i + 1) % k]
		var inward := _inward(a, b, centre)
		lines.append([a + inward * by, b - a])
	var out := PackedVector2Array()
	for i in k:
		var l0: Array = lines[(i - 1 + k) % k]
		var l1: Array = lines[i]
		var p0: Vector2 = l0[0]
		var d0: Vector2 = l0[1]
		var p1: Vector2 = l1[0]
		var d1: Vector2 = l1[1]
		var denom := d0.cross(d1)
		if absf(denom) < 1e-9:
			out.append(p1)
			continue
		var t := (p1 - p0).cross(d1) / denom
		out.append(p0 + d0 * t)
	if _area(out) < 1e-6 or _area(out) > _area(poly):
		return PackedVector2Array()
	for p in out:
		if not Geometry2D.is_point_in_polygon(p, poly):
			return PackedVector2Array()
	return out
