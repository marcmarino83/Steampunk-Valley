class_name SnapEdges
## Typed edges: the snapping redesign's whole-edge fit (DESIGN.md, "Snapping redesign"). Each converted
## shape has typed edges (two end points, a type, and an outward direction, in its own space); a new
## piece fits where one of its edges lies along a compatible edge of a placed piece, over the whole
## shorter edge, at a turn the table allows, slid along the longer edge in grid steps. It never meets
## anything by a single point. ValheimPlacer chooses among the fits by aim (see its _edge_fit).
##
## Converted (phases 1 and 2, by whole edges): walls of every kind in both families; floors and
## foundations; triangle walls (gables, the Tall 45° gable wall, half gables, inverse triangles,
## topper gables) and roofs (panels, gable overhangs, eaves and their corners, ridge caps, toppers and
## topper overhangs, inner and outer corners, hip ends), both pitches; flights of stairs (all four),
## doors, round floors and foundations, curved walls, the cone roof, ladders, railings and the fence.
## By typed points (see POINT_RULES): pillars, poles, beams and chimney sections and tops. Every
## building piece is converted: nothing snaps by corners any more.
##
## Edge types (built on PieceShapes' socket types and SNAP_RULES):
##   wall_base   an upright panel's bottom edge (a wall's, a gable's), on its centre plane (out: its
##               front, +Z)
##   wall_top    a wall's top edge, likewise
##   wall_end    an upright panel's upright edge (a wall's end, a gable's tall side; out: away from it)
##   flat_top    an inverse triangle's flat top (out: its front)
##   slope       a triangle panel's sloped edge (out: its front)
##   floor_edge  a floor's or foundation's top outline edge (out: away from the floor)
##   roof_low    a roof piece's lowest level edge, on its underside (a panel's eave line, a topper's
##               low edges, a hip end's foot and sides, an outer corner's two eave lines)
##   roof_high   a roof piece's highest level edge (a panel's ridge line, an eave's top edge)
##   roof_side   a roof piece's sloped edge (a panel's side, a topper's or hip end's end slopes)
##   roof_top_side  a roof panel's side edge along its top (where inverse triangles stand)
##   eave_edge   an eave's outer (lowest) edge
##   ridge_line  the line a ridge cap sits on
##   beam_top / beam_bottom   a straight beam's top and bottom middle lines
##   stairs_top / stairs_bottom   a flight's top step's outer edge and its bottom step's front
##   door_slot   a doorway's opening along its foot (the door's width, on its centre plane)
##   door_base   a door's foot, as wide (a door stands in a doorway either way round)
##   arc_edge_45 / arc_edge_22   a round floor's or foundation's curved edge, as the chord between its
##               ends (2 m for the eighth wedge, 1.02 m for the sixteenth; out: away from the middle)
##   arc_base_45 / arc_base_22, arc_top_45 / arc_top_22   a curved wall's foot and top, likewise
##   cone_low    the cone roof's low edge on the ring, as a chord; cone_side its sloped sides
##   ladder_top / ladder_foot   a ladder's back at its top and foot, 1 m wide (centred; out: its back)
## Roof pieces' "out" is level, away from the piece seen from above.

## Converted shapes
const WALLS := ["wall", "wall_1", "wall_2m", "wall_half_1", "wall_half_1_tall", "wall_half_2", "wall_half_2_tall",
	"wall_long", "wall_short", "wall_strip_1", "wall_strip_1_tall", "wall_strip_2", "wall_strip_2_tall",
	"doorway", "doorway_2m", "window", "window_2m", "window_split_1", "window_split_1_2m", "window_split_2", "window_split_2_2m"]
const FLOORS := ["floor", "floor_1", "floor_rtri", "floor_tri45", "foundation_stone", "foundation_stone_rtri",
	"foundation_stone_tri45", "foundation_wood", "foundation_wood_rtri", "foundation_wood_tri45"]
## Triangle walls: upright panels whose edges come from their edge sockets
const TRIANGLES := ["gable_26", "gable_45", "gable_wall_45", "gable_half_1_26", "gable_half_1_45", "inverse_1_26", "inverse_1_45",
	"inverse_2_26", "inverse_2_45", "topper_gable_26", "topper_gable_45"]
## Roof pieces whose edges come from their underside's outline
const ROOFS := ["roof", "roof_45", "gable_overhang_26", "gable_overhang_45", "eave_26", "eave_45", "eave_corner_26", "eave_corner_45",
	"outer_eave_corner_26", "outer_eave_corner_45", "valley_eave_corner_26", "valley_eave_corner_45", "roof_inner_26", "roof_inner_45",
	"roof_outer_26", "roof_outer_45"]
## Roof pieces built edge by edge (seen from above they're flat, or a line)
const TOPPERS := ["topper_26", "topper_45", "topper_overhang_26", "topper_overhang_45"]
const HIP_ENDS := ["hip_end_26", "hip_end_45"]
const RIDGES := ["ridge_26", "ridge_45"]
## Eave pieces: their lowest edges are eave edges
const EAVES := ["eave_26", "eave_45", "eave_corner_26", "eave_corner_45", "outer_eave_corner_26", "outer_eave_corner_45"]
## Straight beams (they offer top and bottom lines to whole-edge pieces), flights of stairs, the
## doorways that hold doors, and doors
const BEAMS := ["beam_2", "beam_4"]
const FLIGHTS := ["stairs", "half_stairs", "stairs_tall", "half_stairs_tall"]
const DOORWAYS := ["doorway", "doorway_2m"]
const DOORS := ["door", "door_2m"]
## Chimney pieces (by typed points: a section or top stands on the fireplace's chimney or a section's
## top)
const CHIMNEYS := ["chimney_section", "chimney_top"]
## The round family (all on the ring round its middle, their origin there): floor and foundation
## wedges (an eighth, and a sixteenth: "_22"), curved walls on their curved edges, and the cone roof's
## eighths on the curved walls' tops
const ROUND_FLOORS := ["round_floor", "round_floor_22", "round_foundation_wood", "round_foundation_stone", "round_foundation_wood_22", "round_foundation_stone_22"]
const CURVED := ["curved_wall_45", "curved_wall_22"]
const CONES := ["cone_roof"]
## Ladders, and railings and the fence (upright on a line like walls: a foot and two ends)
const LADDERS := ["ladder", "ladder_tall"]
const RAILINGS := ["railing_2", "railing_1", "fence"]
## A ladder's typed edges are this wide, centred on it (on a 2 m floor edge it goes at the 1 m points)
const LADDER_EDGE := 1.0

## Point pieces (phase 3a): pillars and poles (both families), and beams (straight, diagonal and long
## diagonal). They snap by typed points (and a beam by its whole line too), keeping the player's turn:
## see POINT_RULES and ValheimPlacer._point_fit
const POSTS := ["pillar_wood", "pillar_stone", "pillar_wood_2m", "pillar_stone_2m", "pillar_wood_half", "pillar_stone_half",
	"pillar_wood_half_tall", "pillar_stone_half_tall", "pole_1", "pole_2", "pole_4"]
const ALL_BEAMS := ["beam_2", "beam_4", "beam_diag_26", "beam_diag_45", "beam_diag_26_4", "beam_diag_45_4"]
## Point types:
##   post_foot / post_top   a pillar's or pole's foot and top (middle)
##   beam_end    a beam's end (the middle of its end's top edge)
##   beam_mid    a beam's crossing point: the middle of its end-to-end line (two diagonals spanning a
##               frame, one each way, cross there in an X)
##   edge_spot   a floor's or foundation's corners and the 1 m spots along its edges
##   floor_corner   a floor's or foundation's top corners, as a new piece's own points (a floor on
##               posts: a corner on a post top, at any wheel turn, see ValheimPlacer._point_pair_fits)
##   top_spot    a wall top's ends and the 1 m spots along it
##   chimney_foot   a chimney section's or top's bottom middle
##   chimney_spot   the top middle of the fireplace's chimney, or of a chimney section
## A new point piece's point type -> the placed points it may go on
const POINT_RULES := {
	"post_foot": ["edge_spot", "top_spot", "post_top", "beam_end"],
	"post_top": ["beam_end", "edge_spot"],
	"beam_end": ["post_top", "top_spot", "edge_spot", "beam_end", "post_foot"],
	"beam_mid": ["beam_mid"],
	"chimney_foot": ["chimney_spot"],
	"floor_corner": ["post_top"],
}
## Joins up under a piece: a new piece's edge of this type along a placed edge of these types puts it
## under the placed piece (a wall's top, an inverse triangle's flat top, fitted up under a floor's
## edge). Such a fit isn't offered while the crosshair is on that placed piece's top face: aimed at a
## floor's top, a wall goes on top of it.
const UNDER_JOINS := {"wall_top": ["floor_edge"], "flat_top": ["floor_edge"]}
## Joins that need support when slid: a join by one of these edge types, slid up or down along the
## edge from level (a wall's end on a neighbour's end, a unit higher or lower), counts only if one of
## the listed own edges also rests on a placed edge it may meet (its foot on a floor edge, its top
## under one). A level join needs nothing (walls and fences end to end, on bare ground too).
const SLID_NEEDS := {"wall_end": ["wall_base", "wall_top"]}
## A beam's line (through its two ends) lies along these edges, its whole length (a beam on a wall
## top or floor edge, a diagonal along a triangle's slope)
const LINE_RULES := ["wall_top", "floor_edge", "slope"]

static var _point_cache := {}

## The compatibility table: a new piece's edge type -> {a placed piece's edge type: [turns]}. The
## turn (degrees) is between the two pieces' "body directions" (the way each reaches from the edge,
## its outward direction reversed, level): 180 for side by side or carrying on (a floor beside a
## floor, a wall on from a wall's end, a roof up from a roof's high edge), ±90 for a corner, 0 or 180
## for standing on or lying along (a wall either way round, a roof along a gable's slope either side).
##
## Up under a floor: a wall's top and an inverse triangle's flat top fit along a floor's or
## foundation's edge (both lie on the level the floor's top is on, as a floor laid on them does), and
## a floor fits on an inverse triangle's flat top as on a wall's top.
## Flights: a flight's top edge hangs from a floor's edge or a round floor's curved edge (going down
## away from it), and its bottom edge stands on one at its edge (climbing over that floor); a door
## stands in a doorway.
## Round: a curved wall stands on a round floor's curved edge (or a curved wall's top) of its own
## size, bulging the same way; a round floor lies on curved walls' tops; the cone roof sits on a
## curved wall's top, its eighths side by side. Wedges go side by side by their straight edges (floor
## edges). Ladders hang from a floor's edge by their top (their back on the edge's face), stack on
## another ladder, or stand on a floor at its edge. Railings and the fence stand like walls.
const RULES := {
	"wall_base": {"floor_edge": [0.0, 180.0], "wall_top": [0.0, 180.0], "beam_top": [0.0, 180.0], "flat_top": [0.0, 180.0]},
	"wall_top": {"roof_low": [0.0, 180.0], "eave_edge": [0.0, 180.0], "floor_edge": [0.0, 180.0]},
	"wall_end": {"wall_end": [180.0, 90.0, -90.0]},
	"floor_edge": {"floor_edge": [180.0], "wall_top": [0.0, 180.0], "beam_top": [0.0, 180.0], "stairs_top": [180.0], "stairs_bottom": [180.0], "flat_top": [0.0, 180.0]},
	"flat_top": {"roof_low": [0.0, 180.0], "eave_edge": [0.0, 180.0], "beam_bottom": [0.0, 180.0], "wall_base": [0.0, 180.0], "floor_edge": [0.0, 180.0]},
	"stairs_top": {"floor_edge": [180.0], "arc_edge_45": [180.0], "arc_edge_22": [180.0]},
	"stairs_bottom": {"floor_edge": [0.0], "arc_edge_45": [0.0], "arc_edge_22": [0.0]},
	"door_base": {"door_slot": [0.0, 180.0]},
	"arc_base_45": {"arc_edge_45": [0.0], "arc_top_45": [0.0]},
	"arc_base_22": {"arc_edge_22": [0.0], "arc_top_22": [0.0]},
	"arc_edge_45": {"arc_top_45": [0.0]},
	"arc_edge_22": {"arc_top_22": [0.0]},
	"cone_low": {"arc_top_45": [0.0]},
	"cone_side": {"cone_side": [180.0]},
	"ladder_top": {"floor_edge": [180.0]},
	"ladder_foot": {"ladder_top": [0.0], "floor_edge": [0.0]},
	"slope": {"roof_side": [0.0, 180.0], "slope": [0.0, 180.0], "roof_top_side": [0.0, 180.0]},
	"roof_side": {"roof_side": [180.0], "slope": [0.0, 180.0]},
	"roof_low": {"wall_top": [0.0, 180.0], "beam_top": [0.0, 180.0], "roof_high": [180.0], "flat_top": [0.0, 180.0]},
	"roof_high": {"roof_high": [180.0], "roof_low": [180.0]},
	"ridge_line": {"roof_high": [0.0, 180.0]},
}
## Points this close are one point
const EXACT := 0.001
## The building grid: steps along level edges (and along a sloped edge's level run); up upright edges
## a piece steps by its own family's unit (PieceBuildable.vertical_unit: 1 m Standard, 1.25 m Tall)
const GRID_STEP := 1.0
## Edges are on the grid when their length (a sloped edge's level run) is a whole number of these
## (the triangles' long and short sides aren't, and take only pieces of their own length)
const GRID_FINE := 0.25

static var _cache := {}


## True for a shape placed by the redesigned snapping (whole edges, or typed points)
static func converted(shape: String) -> bool:
	return edge_shape(shape) or point_shape(shape)


## True for a shape placed by whole edges
static func edge_shape(shape: String) -> bool:
	return shape in WALLS or shape in FLOORS or shape in TRIANGLES or shape in ROOFS or shape in TOPPERS or shape in HIP_ENDS or shape in RIDGES \
		or shape in FLIGHTS or shape in DOORS or shape in ROUND_FLOORS or shape in CURVED or shape in CONES or shape in LADDERS or shape in RAILINGS


## True for a shape placed by typed points (pillars, poles, beams, chimney pieces)
static func point_shape(shape: String) -> bool:
	return shape in POSTS or shape in ALL_BEAMS or shape in CHIMNEYS


## A shape's typed points in its own space: [{"p", "type"}]
static func points_of(shape: String, def: Dictionary) -> Array:
	if not _point_cache.has(shape):
		var found := []
		var types := {"pillar_base": "post_foot", "pole_bottom": "post_foot", "pillar_top": "post_top", "pole_top": "post_top", "beam_end": "beam_end"}
		if shape in FLOORS:
			types = {"post_spot": "edge_spot"}
		elif shape in WALLS:
			types = {"top_spot": "top_spot"}
		elif shape in CHIMNEYS:
			types = {"chimney_base": "chimney_foot", "chimney_cap_base": "chimney_foot", "chimney_spot": "chimney_spot"}
		elif shape == "fireplace":
			types = {"chimney_spot": "chimney_spot"}
		elif not point_shape(shape):
			types = {}
		var ends := []
		for s in def["sockets"]:
			if types.has(s["type"]):
				found.append({"p": s["position"], "type": types[s["type"]]})
				if s["type"] == "beam_end":
					ends.append(s["position"])
		# (a beam's crossing point: the middle of its end-to-end line, so two diagonals spanning the
		# same frame, one each way, cross there in a true X)
		if ends.size() == 2:
			found.append({"p": ((ends[0] as Vector3) + (ends[1] as Vector3)) / 2.0, "type": "beam_mid"})
		# (a floor's or foundation's top corners, for a floor on posts)
		if shape in FLOORS:
			for c in SnapCorners.of(shape, def):
				found.append({"p": c, "type": "floor_corner"})
		_point_cache[shape] = found
	return _point_cache[shape]


## A placed piece's typed points in the world, each with its "piece"
static func points_in_world(piece: BuildPiece) -> Array:
	var found := []
	if piece == null or piece.buildable == null:
		return found
	var xf := piece.global_transform
	for p in points_of(piece.shape_name, piece.shape_def()):
		found.append({"p": xf * (p["p"] as Vector3), "type": p["type"], "piece": piece})
	return found


## A beam's line, through its two ends, in its own space: [a, b] (empty for anything else)
static func beam_line(shape: String, def: Dictionary) -> Array:
	var ends := []
	if shape in ALL_BEAMS:
		for p in points_of(shape, def):
			if p["type"] == "beam_end":
				ends.append(p["p"])
	return ends if ends.size() == 2 else []


## Where a beam of `shape`, turned `basis`, lies along the placed edge `t` over its whole length
## (the shorter of the two within the longer, in grid steps; see _offsets): [Transform3D]. None
## unless that turn makes them parallel.
static func line_placements(shape: String, def: Dictionary, basis: Basis, t: Dictionary) -> Array:
	var line := beam_line(shape, def)
	if line.is_empty():
		return []
	var placed: Vector3 = (t["b"] as Vector3) - (t["a"] as Vector3)
	var lt := placed.length()
	if lt < EXACT:
		return []
	var u := placed / lt
	var ga: Vector3 = basis * (line[0] as Vector3)
	var gb: Vector3 = basis * (line[1] as Vector3)
	var mine := gb - ga
	var lg := mine.length()
	if lg < EXACT or absf(mine.normalized().dot(u)) < 0.999:
		return []
	if mine.dot(u) < 0.0:
		ga = gb
	var level := Vector2(u.x, u.z).length()
	var scale := level if level > 0.1 and level < 0.999 else 1.0
	var found := []
	for s in _offsets(lg * scale, lt * scale, GRID_STEP):
		found.append(Transform3D(basis, (t["a"] as Vector3) + u * (float(s) / scale) - ga))
	return found


## Which kind of converted piece a shape is ("floor", "panel" (walls and triangle walls), "roof",
## "stairs", "door"), or "" for any other: a whole-edge piece's fit is passed over when it would sink
## into a piece of its own kind (a floor aimed at a floor's middle goes beside it), never into a piece
## of another kind (see ValheimPlacer._taken)
static func kind(shape: String) -> String:
	if shape in FLOORS or shape in ROUND_FLOORS:
		return "floor"
	if shape in WALLS or shape in TRIANGLES or shape in CURVED:
		return "panel"
	if shape in ROOFS or shape in TOPPERS or shape in HIP_ENDS or shape in RIDGES or shape in CONES:
		return "roof"
	if shape in FLIGHTS:
		return "stairs"
	if shape in DOORS:
		return "door"
	if shape in LADDERS:
		return "ladder"
	if shape in RAILINGS:
		return "rail"
	return ""


## A shape's typed edges in its own space: [{"a", "b", "type", "out"}]
static func of(shape: String, def: Dictionary) -> Array:
	if not _cache.has(shape):
		_cache[shape] = _work_out(shape, def)
	return _cache[shape]


## A placed piece's typed edges in the world, each with its "piece"
static func in_world(piece: BuildPiece) -> Array:
	var found := []
	if piece == null or piece.buildable == null:
		return found
	var xf := piece.global_transform
	for e in of(piece.shape_name, piece.shape_def()):
		found.append({"a": xf * (e["a"] as Vector3), "b": xf * (e["b"] as Vector3), "type": e["type"],
			"out": (xf.basis * (e["out"] as Vector3)).normalized(), "piece": piece})
	return found


static func _work_out(shape: String, def: Dictionary) -> Array:
	var edges := []
	var box := PieceShapes.bounds_of(def)
	if shape in WALLS:
		var z := box.get_center().z
		var x0 := box.position.x
		var x1 := box.end.x
		var y0 := box.position.y
		var y1 := box.end.y
		edges.append(_edge(Vector3(x0, y0, z), Vector3(x1, y0, z), "wall_base", Vector3.BACK))
		edges.append(_edge(Vector3(x0, y1, z), Vector3(x1, y1, z), "wall_top", Vector3.BACK))
		edges.append(_edge(Vector3(x0, y0, z), Vector3(x0, y1, z), "wall_end", Vector3.LEFT))
		edges.append(_edge(Vector3(x1, y0, z), Vector3(x1, y1, z), "wall_end", Vector3.RIGHT))
		if shape in DOORWAYS:
			var hole := PieceShapes.DOOR_WIDTH / 2.0
			edges.append(_edge(Vector3(-hole, y0, z), Vector3(hole, y0, z), "door_slot", Vector3.BACK))
	elif shape in DOORS:
		var hole := PieceShapes.DOOR_WIDTH / 2.0
		edges.append(_edge(Vector3(-hole, 0.0, 0.0), Vector3(hole, 0.0, 0.0), "door_base", Vector3.BACK))
	elif shape in RAILINGS:
		var z := box.get_center().z
		edges.append(_edge(Vector3(box.position.x, box.position.y, z), Vector3(box.end.x, box.position.y, z), "wall_base", Vector3.BACK))
		edges.append(_edge(Vector3(box.position.x, box.position.y, z), Vector3(box.position.x, box.end.y, z), "wall_end", Vector3.LEFT))
		edges.append(_edge(Vector3(box.end.x, box.position.y, z), Vector3(box.end.x, box.end.y, z), "wall_end", Vector3.RIGHT))
	elif shape in ROUND_FLOORS or shape in CURVED or shape in CONES:
		edges = _round_edges(shape)
	elif shape in LADDERS:
		var height: float = def["ladder_height"]
		var back := box.position.z
		var w := LADDER_EDGE / 2.0
		edges.append(_edge(Vector3(-w, height, back), Vector3(w, height, back), "ladder_top", Vector3.FORWARD))
		edges.append(_edge(Vector3(-w, 0.0, back), Vector3(w, 0.0, back), "ladder_foot", Vector3.FORWARD))
	elif shape in FLOORS:
		var corners: Array = SnapCorners._outline(def, true)
		for e in _outline_edges(corners):
			edges.append(_edge(e[0], e[1], "floor_edge", e[2]))
	elif shape in TRIANGLES:
		edges = _panel_edges(def)
	elif shape in ROOFS:
		edges = _roof_edges(shape, def)
	elif shape in TOPPERS:
		var h := _socket_y(def, ["topper_end", "topper_overhang_end"])
		for z in [box.position.z, box.end.z]:
			edges.append(_edge(Vector3(box.position.x, 0.0, z), Vector3(box.end.x, 0.0, z), "roof_low", Vector3(0, 0, signf(z))))
		for x in [box.position.x, box.end.x]:
			edges.append(_edge(Vector3(x, 0.0, box.position.z), Vector3(x, h, box.get_center().z), "roof_side", Vector3(signf(x), 0, 0)))
			edges.append(_edge(Vector3(x, h, box.get_center().z), Vector3(x, 0.0, box.end.z), "roof_side", Vector3(signf(x), 0, 0)))
	elif shape in HIP_ENDS:
		var h := _socket_y(def, ["topper_end"])
		var x0 := box.position.x
		var x1 := box.end.x
		var z1 := box.end.z
		edges.append(_edge(Vector3(x0, 0, 0), Vector3(x1, 0, 0), "roof_low", Vector3.FORWARD))
		edges.append(_edge(Vector3(x0, 0, 0), Vector3(x0, 0, z1), "roof_low", Vector3.LEFT))
		edges.append(_edge(Vector3(x1, 0, 0), Vector3(x1, 0, z1), "roof_low", Vector3.RIGHT))
		edges.append(_edge(Vector3(x0, 0, z1), Vector3((x0 + x1) / 2.0, h, z1), "roof_side", Vector3.BACK))
		edges.append(_edge(Vector3((x0 + x1) / 2.0, h, z1), Vector3(x1, 0, z1), "roof_side", Vector3.BACK))
	elif shape in RIDGES:
		var ends: Array = SnapCorners.of(shape, def)
		if ends.size() == 2:
			edges.append(_edge(ends[0], ends[1], "ridge_line", Vector3.BACK))
	elif shape in BEAMS:
		var c := box.get_center()
		if box.size.x >= box.size.z:
			edges.append(_edge(Vector3(box.position.x, box.end.y, c.z), Vector3(box.end.x, box.end.y, c.z), "beam_top", Vector3.BACK))
			edges.append(_edge(Vector3(box.position.x, box.position.y, c.z), Vector3(box.end.x, box.position.y, c.z), "beam_bottom", Vector3.BACK))
		else:
			edges.append(_edge(Vector3(c.x, box.end.y, box.position.z), Vector3(c.x, box.end.y, box.end.z), "beam_top", Vector3.RIGHT))
			edges.append(_edge(Vector3(c.x, box.position.y, box.position.z), Vector3(c.x, box.position.y, box.end.z), "beam_bottom", Vector3.RIGHT))
	elif shape in FLIGHTS:
		var half := PieceShapes.GRID / 2.0
		var length: float = def["stairs_length"]
		var height: float = def["stairs_height"]
		edges.append(_edge(Vector3(-half, height, length / 2.0), Vector3(half, height, length / 2.0), "stairs_top", Vector3.BACK))
		edges.append(_edge(Vector3(-half, 0.0, -length / 2.0), Vector3(half, 0.0, -length / 2.0), "stairs_bottom", Vector3.FORWARD))
	return edges


# The round family's edges (all round the ring's middle, the piece's origin): an eighth's ("_45") or
# sixteenth's ("_22") curved edge as the chord between its ends on the ring, out away from the middle;
# a wedge's straight sides as floor edges; a curved wall's foot and top chords and its two upright
# ends; the cone roof's low chord and its two sloped sides up to the point
static func _round_edges(shape: String) -> Array:
	var small := shape.ends_with("_22")
	var half := deg_to_rad(11.25 if small else 22.5)
	var size := "_22" if small else "_45"
	var r := PieceShapes.RING_RADIUS
	var a := PieceShapes._arc_point(r, -half, 0.0)
	var b := PieceShapes._arc_point(r, half, 0.0)
	var out_a: Vector3 = -PieceShapes._tangent(-half)
	var out_b: Vector3 = PieceShapes._tangent(half)
	var edges := []
	if shape in ROUND_FLOORS:
		edges.append(_edge(a, b, "arc_edge" + size, Vector3.BACK))
		edges.append(_edge(Vector3.ZERO, a, "floor_edge", out_a))
		edges.append(_edge(Vector3.ZERO, b, "floor_edge", out_b))
	elif shape in CURVED:
		var up := Vector3.UP * PieceShapes.WALL_HEIGHT
		edges.append(_edge(a, b, "arc_base" + size, Vector3.BACK))
		edges.append(_edge(a + up, b + up, "arc_top" + size, Vector3.BACK))
		edges.append(_edge(a, a + up, "wall_end", out_a))
		edges.append(_edge(b, b + up, "wall_end", out_b))
	else:
		var apex := Vector3(0, PieceShapes.CONE_HEIGHT, 0)
		edges.append(_edge(a, b, "cone_low", Vector3.BACK))
		edges.append(_edge(a, apex, "cone_side", out_a))
		edges.append(_edge(b, apex, "cone_side", out_b))
	return edges


static func _edge(a: Vector3, b: Vector3, type: String, out: Vector3) -> Dictionary:
	return {"a": a, "b": b, "type": type, "out": out}


# An outline's edges, in order round it: [a, b, out (level, away from its middle)]
static func _outline_edges(corners: Array) -> Array:
	var found := []
	var middle := Vector3.ZERO
	for c in corners:
		middle += c
	middle /= maxf(corners.size(), 1)
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var run := b - a
		var out := Vector3(run.z, 0.0, -run.x).normalized()
		var away := (a + b) / 2.0 - middle
		if out.dot(Vector3(away.x, 0.0, away.z)) < 0.0:
			out = -out
		found.append([a, b, out])
	return found


# A triangle panel's edges, from its edge sockets (each edge's first socket gives its start, direction
# and length; edge_in points into the panel)
static func _panel_edges(def: Dictionary) -> Array:
	var edges := []
	for s in def["sockets"]:
		if not s.has("edge_dir") or float(s["edge_t"]) > EXACT:
			continue
		var a: Vector3 = s["position"]
		var b: Vector3 = a + (s["edge_dir"] as Vector3) * float(s["edge_len"])
		var inward: Vector3 = s["edge_in"]
		match s["type"]:
			"edge_flat":
				edges.append(_edge(a, b, "wall_base" if inward.y > 0.0 else "flat_top", Vector3.BACK))
			"edge_vertical":
				edges.append(_edge(a, b, "wall_end", Vector3(-inward.x, 0.0, -inward.z).normalized()))
			"edge_slope_26", "edge_slope_45":
				edges.append(_edge(a, b, "slope", Vector3.BACK))
	return edges


# A roof piece's edges, from its underside's outline: its lowest level edges roof_low (an eave's:
# eave_edge), its highest roof_high, sloped ones roof_side; a roof panel also has its top side edges
static func _roof_edges(shape: String, def: Dictionary) -> Array:
	var edges := []
	var corners: Array = SnapCorners._outline(def, false)
	var low := INF
	var high := -INF
	for c in corners:
		low = minf(low, (c as Vector3).y)
		high = maxf(high, (c as Vector3).y)
	for e in _outline_edges(corners):
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var type := "roof_side"
		if absf(a.y - b.y) < EXACT:
			if absf(a.y - high) < EXACT and high - low > EXACT:
				type = "roof_high"
			else:
				type = "eave_edge" if shape in EAVES else "roof_low"
		edges.append(_edge(a, b, type, e[2]))
	if shape in ["roof", "roof_45"]:
		var rise := _socket_y(def, ["roof_high_26", "roof_high_45"])
		for s in def["sockets"]:
			if (s["type"] as String).begins_with("roof_top_corner"):
				var a: Vector3 = s["position"]
				edges.append(_edge(a, a + Vector3(0.0, rise, 2.0), "roof_top_side", Vector3(signf(a.x), 0, 0)))
	return edges


static func _socket_y(def: Dictionary, types: Array) -> float:
	for s in def["sockets"]:
		if s["type"] in types:
			return (s["position"] as Vector3).y
	return 0.0


# ---- Fits ----

## Every way a new piece (`shape`) fits the placed edges `targets` (world edges, see in_world):
## [{"where": Transform3D, "piece", "own" (its edge), "at" (the placed edge)}]. `step_up` is its
## vertical grid step (its PieceBuildable.vertical_unit).
static func placements(shape: String, def: Dictionary, step_up: float, targets: Array) -> Array:
	var found := []
	var own := of(shape, def)
	for t in targets:
		for g in own:
			var rule: Dictionary = RULES.get(g["type"], {})
			if not rule.has(t["type"]):
				continue
			for theta in rule[t["type"]]:
				for where in _fit(g, t, deg_to_rad(theta), step_up):
					found.append({"where": where, "piece": t["piece"], "own": g, "at": t})
	return found


# The placements putting its edge `g` along the placed edge `t`, its body turned `theta` from the
# placed piece's
static func _fit(g: Dictionary, t: Dictionary, theta: float, step_up: float) -> Array:
	var placed: Vector3 = (t["b"] as Vector3) - (t["a"] as Vector3)
	var lt := placed.length()
	if lt < EXACT:
		return []
	var u := placed / lt
	var their_body := -(t["out"] as Vector3)
	their_body.y = 0.0
	var my_body := -(g["out"] as Vector3)
	if their_body.length() < 0.5 or my_body.length() < 0.5:
		return []
	var want := Basis(Vector3.UP, theta) * their_body.normalized()
	var yaw := atan2(want.x, want.z) - atan2(my_body.x, my_body.z)
	var basis := Basis(Vector3.UP, yaw)
	var ga: Vector3 = basis * (g["a"] as Vector3)
	var gb: Vector3 = basis * (g["b"] as Vector3)
	var mine := gb - ga
	var lg := mine.length()
	if lg < EXACT or absf(mine.normalized().dot(u)) < 0.999:
		return []
	if mine.dot(u) < 0.0:
		ga = gb
	# Grid steps along it: on a sloped edge, measured along its level run
	var level := Vector2(u.x, u.z).length()
	var step := step_up
	var scale := 1.0
	if level > 0.999:
		step = GRID_STEP
	elif level > 0.1:
		step = GRID_STEP
		scale = level
	var found := []
	for s in _offsets(lg * scale, lt * scale, step):
		found.append(Transform3D(basis, (t["a"] as Vector3) + u * (float(s) / scale) - ga))
	return found


# Where the new edge (measure `lg`) starts along the placed one (measure `lt`): the shorter lies
# within the longer, in grid steps from either end of it (only edges on the grid take a different
# length)
static func _offsets(lg: float, lt: float, step: float) -> Array:
	if absf(lg - lt) <= EXACT:
		return [0.0]
	var longer := maxf(lg, lt)
	if absf(longer / GRID_FINE - roundf(longer / GRID_FINE)) > 0.004:
		return []
	var room := longer - minf(lg, lt)
	var found := []
	var k := 0.0
	while k <= room + EXACT:
		for v in [k, room - k]:
			var s: float = v if lg < lt else -v
			if not found.any(func(f): return absf(float(f) - s) < EXACT):
				found.append(s)
		k += step
	return found


## How many of a new piece's edges, put at `where`, lie along a compatible placed edge
static func matched(shape: String, def: Dictionary, where: Transform3D, edges: Array) -> int:
	var count := 0
	for g in of(shape, def):
		var rule: Dictionary = RULES.get(g["type"], {})
		var a: Vector3 = where * (g["a"] as Vector3)
		var b: Vector3 = where * (g["b"] as Vector3)
		for t in edges:
			if rule.has(t["type"]) and along(a, b, t["a"], t["b"]):
				count += 1
				break
	return count


## True if segment cd lies on the line through ab and overlaps ab (by more than 5 cm)
static func along(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var u := b - a
	var l := u.length()
	if l < EXACT or c.distance_to(d) < EXACT:
		return false
	u /= l
	if absf(u.dot((d - c).normalized())) < 0.999:
		return false
	if _line_distance(c, a, u) > 2.0 * EXACT or _line_distance(d, a, u) > 2.0 * EXACT:
		return false
	var s0 := (c - a).dot(u)
	var s1 := (d - a).dot(u)
	return minf(maxf(s0, s1), l) - maxf(minf(s0, s1), 0.0) > 0.05


# ---- Geometry ----

static func _line_distance(p: Vector3, a: Vector3, u: Vector3) -> float:
	var v := p - a
	return (v - u * v.dot(u)).length()


## Distance from a point to a segment
static func point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


## Distance between two segments
static func segment_segment(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a < 1e-12 and e < 1e-12:
		return p1.distance_to(p2)
	if a < 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e < 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-12 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


## Distance from the segment `from`–`to` to a box (`box`, in the space of `where`, which only turns
## and moves: no scale)
static func box_distance(where: Transform3D, box: AABB, from: Vector3, to: Vector3) -> float:
	var inv := where.affine_inverse()
	var a := inv * from
	var b := inv * to
	if _segment_hits_box(a, b, box):
		return 0.0
	# (the distance to a box along a line rises and falls once: a ternary search finds its least; 24
	# steps narrow it to under a thousandth of the line)
	var lo := 0.0
	var hi := 1.0
	for i in 24:
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		if _point_box(a.lerp(b, m1), box) < _point_box(a.lerp(b, m2), box):
			hi = m2
		else:
			lo = m1
	return _point_box(a.lerp(b, (lo + hi) / 2.0), box)


## How far along the segment `from`–`to` (meters from `from`) it first meets the box (see
## box_distance), or, if it misses, where it passes closest
static func box_entry(where: Transform3D, box: AABB, from: Vector3, to: Vector3) -> float:
	var inv := where.affine_inverse()
	var a := inv * from
	var b := inv * to
	var length := a.distance_to(b)
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var hits := true
	for axis in 3:
		if absf(d[axis]) < 1e-9:
			if a[axis] < box.position[axis] or a[axis] > box.end[axis]:
				hits = false
			continue
		var u0 := (box.position[axis] - a[axis]) / d[axis]
		var u1 := (box.end[axis] - a[axis]) / d[axis]
		if u0 > u1:
			var tmp := u0
			u0 = u1
			u1 = tmp
		t0 = maxf(t0, u0)
		t1 = minf(t1, u1)
	if hits and t0 <= t1:
		return t0 * length
	var lo := 0.0
	var hi := 1.0
	for i in 40:
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		if _point_box(a.lerp(b, m1), box) < _point_box(a.lerp(b, m2), box):
			hi = m2
		else:
			lo = m1
	return (lo + hi) / 2.0 * length


static func _point_box(p: Vector3, box: AABB) -> float:
	var d := Vector3(maxf(maxf(box.position.x - p.x, 0.0), p.x - box.end.x), maxf(maxf(box.position.y - p.y, 0.0), p.y - box.end.y), maxf(maxf(box.position.z - p.z, 0.0), p.z - box.end.z))
	return d.length()


static func _segment_hits_box(a: Vector3, b: Vector3, box: AABB) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 3:
		var lo := box.position[axis]
		var hi := box.end[axis]
		if absf(d[axis]) < 1e-9:
			if a[axis] < lo or a[axis] > hi:
				return false
			continue
		var u0 := (lo - a[axis]) / d[axis]
		var u1 := (hi - a[axis]) / d[axis]
		if u0 > u1:
			var tmp := u0
			u0 = u1
			u1 = tmp
		t0 = maxf(t0, u0)
		t1 = minf(t1, u1)
		if t0 > t1:
			return false
	return true
