class_name PieceShapes
## The exact shapes of the building pieces, all in one place: what they look like (simple wood
## shapes, one mesh per piece), what's solid, and their snap points. Everything is measured in
## meters from the piece's own origin, with +Y up and +Z its front, and the sizes are exact so
## edges line up perfectly. A piece can show a real model instead (PieceBuildable.model_scene);
## its collision and snap points still come from here.
##
## Square pieces sit on a 2 m grid. Round pieces share one circle of radius RING_RADIUS, so a 45°
## arc spans exactly 2 m and eight of them close into a circle about 5.2 m across.
##
## Snap points ("sockets") have a position, a facing (yaw, in radians, 0 = +Z) and a type. A new
## piece attaches by one of its own sockets to a nearby socket of a placed piece; SNAP_RULES says
## which types fit together, and the turns (added to facing them toward each other's yaw) that
## fit. R cycles through those.

const GRID := 2.0
const WALL_HEIGHT := 2.5
const WALL_THICKNESS := 0.2
const FLOOR_THICKNESS := 0.2
const ROOF_RISE := 1.0
const ROOF_THICKNESS := 0.15
## The doorway: wide and tall enough for the player (a body 0.8 m across and 2 m tall) to walk
## through, door open, without catching
const DOOR_WIDTH := 1.2
const DOOR_HEIGHT := 2.2
const WINDOW_WIDTH := 1.0
const WINDOW_BOTTOM := 1.1
const WINDOW_TOP := 1.9
## Split-window walls: each one's share of the joined window (wall width -> opening width), and
## the opening's height (from WINDOW_BOTTOM)
const SPLIT_WINDOWS := {2.0: 1.0, 1.0: 0.6}
const SPLIT_WINDOW_HEIGHT := 1.1
const STAIRS_RUN := 4.0
const STAIRS_STEPS := 10
## 1 / sin(22.5°): a 45° arc's ends are exactly 2 m apart
const RING_RADIUS := 2.6131259
const CONE_HEIGHT := 2.0
## Foundations: how tall the block is (its top is flush like a floor's), and how far a freely
## placed one stands above the spot it's put on, so most of it goes into the ground and covers
## uneven slopes without gaps
const FOUNDATION_DEPTH := 3.0
const FOUNDATION_LIFT := 1.0
## Logs (wood foundations) and stone courses are this tall
const COURSE := 0.25
## Width of one board, for the light/dark stripes that make the wood read as planks
const BOARD := 0.25
## Arcs are drawn in steps of this many degrees, so stripes line up from piece to piece
const ARC_STEP_DEGREES := 7.5
## The right triangle's long side (corner to corner of a 2 m square), and the 45° triangle's short
## side (the gap between two 2 m sides 45° apart): walls come in these widths too
const LONG_EDGE := 2.8284271
const SHORT_EDGE := 1.5307337
## Pillars: how thick (wood, stone) and how tall
const WOOD_PILLAR := 0.3
const STONE_PILLAR := 0.4
const PILLAR_HEIGHT := 2.5
## Every way a square thing can turn and still line up with the grid
const QUARTER_TURNS := [0.0, PI / 2.0, PI, -PI / 2.0]
## Beams (square, lying down), poles (square, standing, thinner than pillars), and how high a
## half-height wall, a ladder, a railing and a fence are
const BEAM := 0.2
const POLE := 0.15
const HALF_HEIGHT := 1.25
## The top-up strip walls: what a 45° gable (2 m) lacks of a full wall's height
const STRIP_HEIGHT := 0.5
## The ridge gap a roof topper bridges: on a building an odd number of foundation tiles across (3
## tiles, 6 m), one 2 m roof up each side leaves this much at the ridge
const TOPPER_GAP := 2.0
## How far below a roof's plain slab top its drawn shakes lie along the side edge (where inverse
## triangles stand on it)
const ROOF_EDGE_SINK := 0.025
## How far the plank infill of the small triangle walls (half gables, inverse triangles) reaches
## past their edges into their neighbours, so no hairline of light shows at a joint
const INFILL_OVERLAP := 0.02
const LADDER_HEIGHT := 2.0
const RAILING_HEIGHT := 1.0
const FENCE_HEIGHT := 1.4
## The 45° roof rises a full 2 m over its 2 m (the 26° roof, ROOF_RISE, rises 1 m)
const ROOF_RISE_45 := 2.0

const FLOOR_COLOR := Color(0.55, 0.4, 0.26)
const WALL_COLOR := Color(0.62, 0.46, 0.3)
const ROOF_COLOR := Color(0.42, 0.3, 0.2)
const DOOR_COLOR := Color(0.5, 0.34, 0.21)
const STAIRS_COLOR := Color(0.58, 0.43, 0.28)
const LOG_COLOR := Color(0.47, 0.33, 0.2)
## Weathered stone: a warm, slightly brown grey
const STONE_COLOR := Color(0.5, 0.47, 0.41)
const MORTAR_COLOR := Color(0.3, 0.27, 0.23)

## new piece's socket type -> {placed piece's socket type: [turns that fit]}
const SNAP_RULES := {
	"floor_edge": {"floor_edge": [PI], "wall_top": [0.0, PI]},
	"floor_edge_long": {"floor_edge_long": [PI]},
	"floor_edge_short": {"floor_edge_short": [PI]},
	# The 1 m points: along 2 m floor edges (and a 1 m floor's edges), and along wall tops
	"half_edge": {"half_edge": [PI]},
	# Walls and small walls also stack on any wall's top points (its ends and every 1 m)
	"wall_base": {"floor_edge": [0.0, PI], "wall_top": [0.0, PI], "top_point": [0.0, PI]},
	"small_wall_base": {"half_edge": [0.0, PI], "half_top": [0.0, PI], "top_point": [0.0, PI]},
	"long_wall_base": {"floor_edge_long": [0.0, PI], "long_wall_top": [0.0, PI]},
	"short_wall_base": {"floor_edge_short": [0.0, PI], "short_wall_top": [0.0, PI]},
	"wall_end": {"wall_end": [PI, PI / 2.0, -PI / 2.0], "pillar_top": QUARTER_TURNS, "pole_top": QUARTER_TURNS},
	# A gable on a wall's top, or on any wall's top points (a small wall's ends and middle, say), facing
	# either way
	"gable_base": {"wall_top": [0.0, PI], "top_point": [0.0, PI]},
	"door_base": {"door_slot": [0.0, PI]},
	# Roofs: any pitch goes on a wall top or carries on up from another roof's high edge; sides,
	# ridges, corners and ridge caps only meet roofs of their own pitch
	"roof_low": {"wall_top": [0.0, PI], "roof_high_26": [PI], "roof_high_45": [PI]},
	# Roofs back to back at a ridge, of either pitch
	"roof_high_26": {"roof_high_26": [PI], "roof_high_45": [PI], "topper_low_26": [PI]},
	"roof_high_45": {"roof_high_45": [PI], "roof_high_26": [PI], "topper_low_45": [PI]},
	# A roof topper's low edges on the high edges of roofs of its pitch, and toppers end to end
	"topper_low_26": {"roof_high_26": [PI]},
	"topper_low_45": {"roof_high_45": [PI]},
	"topper_end": {"topper_end": [PI]},
	# A topper overhang's end on a topper's end, carrying it on past the gable wall
	"topper_overhang_end": {"topper_end": [PI]},
	# A topper gable's bottom corner on the top of a gable's upright edge, reaching on past it
	"topper_gable_corner": {"gable_peak": [PI]},
	# Whole edges: a topper's low edge on a roof's high edge, and a roof's high edge on a topper's
	# free low edge (roofs' high edges don't meet each other this way: that stays roof_high's job)
	"edge_ridge_topper_26": {"edge_ridge_roof_26": [0.0, PI]},
	"edge_ridge_topper_45": {"edge_ridge_roof_45": [0.0, PI]},
	"edge_ridge_roof_26": {"edge_ridge_topper_26": [0.0, PI]},
	"edge_ridge_roof_45": {"edge_ridge_topper_45": [0.0, PI]},
	"roof_side_left_26": {"roof_side_right_26": [PI]},
	"roof_side_right_26": {"roof_side_left_26": [PI]},
	"roof_side_left_45": {"roof_side_right_45": [PI]},
	"roof_side_right_45": {"roof_side_left_45": [PI]},
	# Side by side by their low corners: roofs and gable overhangs of either pitch (where the
	# pitches differ, the slopes part, but the low edges line up)
	"roof_edge_corner_left": {"roof_edge_corner_right": [PI], "overhang_corner_right": [PI]},
	"roof_edge_corner_right": {"roof_edge_corner_left": [PI], "overhang_corner_left": [PI]},
	"overhang_corner_left": {"roof_edge_corner_right": [PI]},
	"overhang_corner_right": {"roof_edge_corner_left": [PI]},
	"ridge_cap_26": {"roof_high_26": [0.0], "roof_high_45": [0.0]},
	# Hip roofs: an outer (hip) corner stacked on the one below it, its foot on that one's top, the
	# hip line carrying on up; a hip end (odd widths) sitting on the end roof panel's high edge, its
	# sides along the side roofs' high edges, toppers carrying the ridge on from its far end
	"hip_foot_26": {"hip_top_26": [0.0]},
	"hip_foot_45": {"hip_top_45": [0.0]},
	"hip_end_side_26": {"roof_high_26": [PI]},
	"hip_end_side_45": {"roof_high_45": [PI]},
	"hip_end_foot_26": {"hip_top_26": QUARTER_TURNS},
	"hip_end_foot_45": {"hip_top_45": QUARTER_TURNS},
	"ridge_cap_45": {"roof_high_45": [0.0], "roof_high_26": [0.0]},
	# Overhangs: eaves on a roof's low edge (and end to end along it), gable overhangs on a roof's
	# side edge (and up the slope, and back to back at the ridge), corners under a gable overhang's
	# low end (and end to end with eaves). They meet pieces of either pitch where the snap point is
	# on an edge or corner both share (a 26° eave along a 45° roof's low edge); a gable overhang
	# meets a roof of the other pitch by their low corners (above).
	"eave_base_26": {"eave_spot_26": [PI], "eave_spot_45": [PI]},
	"eave_base_45": {"eave_spot_45": [PI], "eave_spot_26": [PI]},
	"eave_side_left_26": {"eave_side_right_26": [PI], "eave_side_right_45": [PI]},
	"eave_side_right_26": {"eave_side_left_26": [PI], "eave_side_left_45": [PI]},
	"eave_side_left_45": {"eave_side_right_45": [PI], "eave_side_right_26": [PI]},
	"eave_side_right_45": {"eave_side_left_45": [PI], "eave_side_left_26": [PI]},
	"overhang_left_26": {"roof_side_right_26": [PI]},
	"overhang_right_26": {"roof_side_left_26": [PI]},
	"overhang_left_45": {"roof_side_right_45": [PI]},
	"overhang_right_45": {"roof_side_left_45": [PI]},
	"overhang_low_26": {"overhang_high_26": [PI], "overhang_high_45": [PI]},
	"overhang_high_26": {"overhang_high_26": [PI], "overhang_low_26": [PI], "overhang_high_45": [PI], "overhang_low_45": [PI]},
	"overhang_low_45": {"overhang_high_45": [PI], "overhang_high_26": [PI]},
	"overhang_high_45": {"overhang_high_45": [PI], "overhang_low_45": [PI], "overhang_high_26": [PI], "overhang_low_26": [PI]},
	"corner_top_26": {"overhang_low_26": [PI], "overhang_low_45": [PI]},
	"corner_top_45": {"overhang_low_45": [PI], "overhang_low_26": [PI]},
	# A valley eave corner, under a valley corner's low corner (where two eaves meet inside a corner)
	"valley_eave_base_26": {"valley_eave_spot_26": [0.0], "valley_eave_spot_45": [0.0]},
	"valley_eave_base_45": {"valley_eave_spot_45": [0.0], "valley_eave_spot_26": [0.0]},
	# An outer eave corner, under an outer roof corner's low corner (and to eave ends, as an eave)
	"outer_eave_base_26": {"outer_eave_spot_26": [0.0]},
	"outer_eave_base_45": {"outer_eave_spot_45": [0.0]},
	# Gables of either pitch under a roof of either pitch (by the roof's low corner, the gable
	# rising with the roof along its side edge), and back to back at their tall edges
	"gable_corner": {"gable_under": [0.0]},
	"gable_tip": {"gable_tip": [PI]},
	# A half gable (1 m) on the 1 m points along floor edges and wall tops, and any wall's top points
	"small_gable_base": {"half_edge": [0.0, PI], "half_top": [0.0, PI], "top_point": [0.0, PI]},
	# Inverse triangles: the flat top under a beam, a roof's low edge, an eave's outer edge or a
	# wall standing above; the low corner on a gable's slope or the top of a roof's side edge of
	# the same pitch (the vertical side meets wall ends as a wall's end does)
	"inverse_top": {"beam_under": [0.0, PI], "roof_low": [0.0, PI], "eave_edge": [0.0, PI], "wall_base": [0.0, PI]},
	"inverse_top_small": {"beam_under_small": [0.0, PI], "small_wall_base": [0.0, PI]},
	"inverse_low_26": {"gable_slope_26": [0.0], "roof_top_corner_26": [0.0]},
	"inverse_low_45": {"gable_slope_45": [0.0], "roof_top_corner_45": [0.0]},
	# Triangle pieces edge to edge (see _edge_sockets and _edge_fit_ok): a sloped edge to a sloped
	# edge of the same pitch, flat to flat and upright to upright in the same plane (upright edges
	# at a corner too), and floor and foundation edges to each other
	"edge_slope_26": {"edge_slope_26": [0.0, PI]},
	"edge_slope_45": {"edge_slope_45": [0.0, PI]},
	"edge_flat": {"edge_flat": [0.0, PI]},
	"edge_vertical": {"edge_vertical": [0.0, PI, PI / 2.0, -PI / 2.0]},
	"edge_floor": {"edge_floor": [0.0, PI]},
	# Under roofs and eaves of either pitch: a 2 m wall's top under a roof's low edge or an eave's
	# outer edge, a beam likewise, and pillar and pole tops under a roof's low corners and eave edges
	"wall_top": {"roof_low": [0.0, PI], "eave_edge": [0.0, PI]},
	"beam_top": {"roof_low": [0.0, PI], "eave_edge": [0.0, PI]},
	"pillar_top": {"roof_corner": QUARTER_TURNS, "eave_edge": QUARTER_TURNS},
	"pole_top": {"roof_corner": QUARTER_TURNS, "eave_edge": QUARTER_TURNS},
	# Chimneys: a section on the fireplace's chimney or another section; the top on either too
	"chimney_base": {"chimney_spot": QUARTER_TURNS},
	"chimney_cap_base": {"chimney_spot": QUARTER_TURNS},
	"stairs_foot": {"floor_center": QUARTER_TURNS},
	# Stairs: the bottom on a floor or foundation edge, the top on one a level up, and end to end
	"stairs_bottom": {"floor_edge": [PI], "stairs_top": [PI]},
	"stairs_top": {"floor_edge": [PI], "stairs_bottom": [PI]},
	"ladder_base": {"floor_edge": [0.0, PI], "half_edge": [0.0, PI], "ladder_top": [0.0]},
	"ladder_top": {"floor_edge": [0.0, PI]},
	"railing_base": {"floor_edge": [0.0, PI], "wall_top": [0.0, PI]},
	"small_railing_base": {"half_edge": [0.0, PI], "half_top": [0.0, PI]},
	"curve_base": {"round_edge": [0.0], "curve_top": [0.0]},
	"curve22_base": {"round_edge_small": [0.0], "curve22_top": [0.0]},
	"round_edge": {"curve_base": [0.0]},
	"round_side_left": {"round_side_right": [PI]},
	"round_side_right": {"round_side_left": [PI]},
	"cone_base": {"curve_top": [0.0]},
	"cone_side_left": {"cone_side_right": [PI]},
	"cone_side_right": {"cone_side_left": [PI]},
	"foundation_base": {"foundation_top": QUARTER_TURNS},
	"round_foundation_base": {"round_foundation_top": [0.0]},
	# Pillars, poles and beams: on floor, foundation and wall-top corners and edge middles, end to
	# end, and on each other; floors, walls and roofs sit on pillar and pole tops
	"pillar_base": {"post_spot": QUARTER_TURNS, "top_spot": QUARTER_TURNS, "pillar_top": QUARTER_TURNS},
	"pole_bottom": {"post_spot": QUARTER_TURNS, "top_spot": QUARTER_TURNS, "pole_top": QUARTER_TURNS, "pillar_top": QUARTER_TURNS, "beam_end": QUARTER_TURNS},
	# (and at a post's or pillar's foot, so a diagonal brace can run from one post's foot to the top
	# of the next on bare ground)
	"beam_end": {"beam_end": [PI, PI / 2.0, -PI / 2.0], "post_spot": QUARTER_TURNS, "top_spot": QUARTER_TURNS, "pole_top": QUARTER_TURNS, "pillar_top": QUARTER_TURNS,
		"pole_bottom": QUARTER_TURNS, "pillar_base": QUARTER_TURNS},
	# A beam's centre on another beam's middle, crossing through it. It first lies exactly over the
	# other (a diagonal over a diagonal, the same way); R then turns it about its centre (see
	# PiecePlacer._slender_placements), so the first press makes an X
	"beam_mid_diag": {"beam_mid_diag": [0.0, PI], "beam_mid": [0.0, PI]},
	"beam_mid": {"beam_mid": [0.0, PI / 2.0], "beam_mid_diag": [0.0, PI]},
	"beam_under": {"wall_top": [0.0, PI]},
	"beam_under_small": {"half_top": [0.0, PI]},
	"post_spot": {"pillar_top": QUARTER_TURNS, "pole_top": QUARTER_TURNS},
	"roof_corner": {"pillar_top": QUARTER_TURNS, "pole_top": QUARTER_TURNS},
	"rtri_foundation_base": {"rtri_foundation_top": [0.0]},
	"tri45_foundation_base": {"tri45_foundation_top": [0.0]},
	"round22_foundation_base": {"round22_foundation_top": [0.0]},
}


## Everything about one shape: {"mesh": ArrayMesh, "door_mesh": ArrayMesh or null, "collision":
## [{"shape", "transform", "door"}], "sockets": [{"position", "yaw", "type"}], "roof": bool,
## "floor": bool, "furniture": bool, "clear_center": Vector3, "clear_radius": float (0 = leaves
## the grass)}
static func build(shape: String) -> Dictionary:
	var d := {
		"surface": _new_surface(), "door_surface": null, "collision": [], "sockets": [],
		"roof": false, "floor": false, "furniture": false, "overhang": false, "clear_center": Vector3.ZERO, "clear_radius": 0.0,
	}
	match shape:
		"floor":
			_planked_box(d, Vector3(GRID, FLOOR_THICKNESS, GRID), Vector3(0, -FLOOR_THICKNESS / 2.0, 0), Basis.IDENTITY, FLOOR_COLOR, 0, -GRID / 2.0)
			for i in 4:
				var out := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 2.0) * -1.0
				_socket(d, out * GRID / 2.0, _yaw(out), "floor_edge")
			_socket(d, Vector3.ZERO, 0.0, "floor_center")
			_square_post_spots(d)
			_half_edges(d, GRID)
			d["floor"] = true
			d["clear_radius"] = 1.5
		"floor_1":
			_planked_box(d, Vector3(1.0, FLOOR_THICKNESS, 1.0), Vector3(0, -FLOOR_THICKNESS / 2.0, 0), Basis.IDENTITY, FLOOR_COLOR, 0, -0.5)
			_half_edges(d, 1.0)
			for x in [-1, 0, 1]:
				for z in [-1, 0, 1]:
					if x != 0 or z != 0:
						_socket(d, Vector3(x * 0.5, 0, z * 0.5), 0.0, "post_spot")
			d["floor"] = true
			d["clear_radius"] = 0.8
		"wall", "doorway", "window":
			_wall(d, shape)
		"wall_long":
			_plain_wall(d, LONG_EDGE, WALL_HEIGHT, "long_wall_base", "long_wall_top")
		"wall_short":
			_plain_wall(d, SHORT_EDGE, WALL_HEIGHT, "short_wall_base", "short_wall_top")
		"wall_1":
			_plain_wall(d, 1.0, WALL_HEIGHT, "small_wall_base", "half_top")
		"wall_half_2":
			_plain_wall(d, GRID, HALF_HEIGHT, "wall_base", "wall_top")
		"wall_half_1":
			_plain_wall(d, 1.0, HALF_HEIGHT, "small_wall_base", "half_top")
		"wall_quarter":
			_plain_wall(d, 1.0, 1.0, "small_wall_base", "half_top")
		# Top-up strips, 0.5 m tall: under a 45° gable it makes a full wall's 2.5 m
		"wall_strip_2":
			_plain_wall(d, GRID, STRIP_HEIGHT, "wall_base", "wall_top")
		"wall_strip_1":
			_plain_wall(d, 1.0, STRIP_HEIGHT, "small_wall_base", "half_top")
		# A 45° gable on a 0.5 m strip, in one: 2 m wide, 0.5 m tall at its low end and as tall as a
		# full wall at its high end
		"gable_wall_45":
			_gable(d, ROOF_RISE_45, WALL_HEIGHT - ROOF_RISE_45)
		# Half gables: 1 m along the bottom, half a 2 m gable (the 2 m gables are the full size)
		"gable_half_1_26":
			_gable(d, ROOF_RISE / 2.0, 0.0, 1.0)
		"gable_half_1_45":
			_gable(d, ROOF_RISE_45 / 2.0, 0.0, 1.0)
		# Inverse triangles: the space above a slope, under a flat line
		"inverse_2_26", "inverse_1_26", "inverse_2_45", "inverse_1_45":
			var width := GRID if shape.begins_with("inverse_2") else 1.0
			var k := (ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45) / GRID
			_inverse_wall(d, width, width * k, shape.right(3))
		"gable_26":
			_gable(d, ROOF_RISE)
		"gable_45":
			_gable(d, ROOF_RISE_45)
		"roof_45":
			_roof(d, ROOF_RISE_45, "_45")
		"roof_inner_26", "roof_outer_26":
			_roof_corner(d, ROOF_RISE, "_26", shape.contains("inner"))
		"roof_inner_45", "roof_outer_45":
			_roof_corner(d, ROOF_RISE_45, "_45", shape.contains("inner"))
		"ridge_26":
			_ridge_cap(d, ROOF_RISE, "_26")
		"ridge_45":
			_ridge_cap(d, ROOF_RISE_45, "_45")
		"eave_26", "eave_45":
			_eave(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		"gable_overhang_26", "gable_overhang_45":
			_gable_overhang(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		"eave_corner_26", "eave_corner_45":
			_eave_corner(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		"valley_eave_corner_26", "valley_eave_corner_45":
			_valley_eave_corner(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		"topper_26", "topper_45":
			_topper(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		"hip_end_26", "hip_end_45":
			_hip_end(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		"topper_overhang_26", "topper_overhang_45":
			_topper_overhang(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		"topper_gable_26", "topper_gable_45":
			_topper_gable(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45)
		"outer_eave_corner_26", "outer_eave_corner_45":
			_outer_eave_corner(d, ROOF_RISE if shape.ends_with("26") else ROOF_RISE_45, shape.right(3))
		# Split-window walls: the window cut into the +X edge, so two side by side (one turned round)
		# make one wide window across the joint
		"window_split_2", "window_split_1":
			_split_window_wall(d, GRID if shape == "window_split_2" else 1.0)
		"beam_1", "beam_2":
			_beam(d, 1.0 if shape == "beam_1" else GRID)
		"beam_diag_26":
			_diagonal_beam(d, ROOF_RISE)
		"beam_diag_45":
			_diagonal_beam(d, ROOF_RISE_45)
		"pole_1", "pole_2":
			_pole(d, 1.0 if shape == "pole_1" else GRID)
		"ladder":
			_ladder(d)
		"railing_2", "railing_1":
			_railing(d, GRID if shape == "railing_2" else 1.0)
		"fence":
			_fence(d)
		"pillar_wood", "pillar_stone":
			_pillar(d, shape == "pillar_stone")
		"floor_rtri", "foundation_wood_rtri", "foundation_stone_rtri":
			_triangle_piece(d, _right_triangle(), ["floor_edge", "floor_edge_long", "floor_edge"], _kind_of(shape), "rtri")
		"floor_tri45", "foundation_wood_tri45", "foundation_stone_tri45":
			_triangle_piece(d, _triangle_45(), ["floor_edge", "floor_edge_short", "floor_edge"], _kind_of(shape), "tri45")
		"round_floor_22":
			_round_floor(d, 11.25)
		"round_foundation_wood_22", "round_foundation_stone_22":
			_round_foundation(d, shape.contains("stone"), 11.25)
		"door":
			_door(d)
		"roof":
			_roof(d, ROOF_RISE, "_26")
		"stairs":
			_stairs(d)
		"curved_wall_45":
			_curved_wall(d, 22.5, "curve_base", "curve_top")
		"curved_wall_22":
			_curved_wall(d, 11.25, "curve22_base", "curve22_top")
		"round_floor":
			_round_floor(d)
		"cone_roof":
			_cone_roof(d)
		"foundation_wood", "foundation_stone":
			_foundation(d, shape == "foundation_stone")
		"round_foundation_wood", "round_foundation_stone":
			_round_foundation(d, shape == "round_foundation_stone")
		"bed", "foraging_basket", "chopping_block", "tool_rack", "sorting_table", "storage_shelf", "fireplace", \
				"storehouse_storage", "firewood_rack", "stone_ore_bin", "slat_crate", "woven_crate", "woven_basket":
			_furniture(d, shape)
		"chimney_section", "chimney_top":
			_chimney(d, shape)
		_:
			push_error("PieceShapes: no shape called %s" % shape)
	# Turning a symmetric piece by this much looks the same, so those turns aren't offered twice
	d["symmetry"] = {
		"floor": PI / 2.0, "floor_1": PI / 2.0, "wall": PI, "doorway": PI, "window": PI,
		"wall_long": PI, "wall_short": PI, "wall_1": PI, "wall_half_2": PI, "wall_half_1": PI, "wall_quarter": PI,
		"wall_strip_2": PI, "wall_strip_1": PI,
		"foundation_wood": PI / 2.0, "foundation_stone": PI / 2.0,
		"pillar_wood": PI / 2.0, "pillar_stone": PI / 2.0, "pole_1": PI / 2.0, "pole_2": PI / 2.0,
		"beam_1": PI, "beam_2": PI, "ridge_26": PI, "ridge_45": PI, "topper_26": PI, "topper_45": PI, "topper_gable_26": PI, "topper_gable_45": PI, "topper_overhang_26": PI, "topper_overhang_45": PI,
		"railing_2": PI, "railing_1": PI, "fence": PI,
	}.get(shape, 0.0)
	# Pillars, poles, beams and ladders are slender: they only bump into each other, so floors,
	# walls and roofs can rest on and against them
	d["slender"] = shape.begins_with("pillar") or shape.begins_with("pole") or shape.begins_with("beam") or shape == "ladder"
	d["ladder"] = shape == "ladder"
	# How far R turns it while snapped: 45° for round and triangle pieces, 90° for the rest
	var fine_turn := shape.contains("round") or shape.contains("curved") or shape.contains("cone") or shape.contains("tri")
	d["turn_step"] = PI / 4.0 if fine_turn else PI / 2.0
	# The 45° triangle is centred on its middle, which turns it 22.5° off the grid of the squares
	# it joins: its textured planks fold back onto their grid with this (see piece_surface.gdshader)
	d["frame_offset"] = PI / 8.0 if shape.contains("tri45") else 0.0
	d["mesh"] = (d["surface"] as SurfaceTool).commit()
	d.erase("surface")
	d["door_mesh"] = (d["door_surface"] as SurfaceTool).commit() if d["door_surface"] else null
	d.erase("door_surface")
	return d


## Which of a new piece's sockets can attach to a placed socket of this type, and with which turns
static func turns_for(new_type: String, placed_type: String) -> Array:
	return SNAP_RULES.get(new_type, {}).get(placed_type, [])


## Every way a new piece (with these snap points of its own) fits a placed snap point in the
## world: each of its own snap points that may attach there, put on it and turned by each turn
## the rules allow. Returns where the new piece would go, as transforms; ways that come out the
## same (allowing for the piece's symmetry, see build()) are listed once.
static func fits(own_sockets: Array, placed: Dictionary, symmetry := 0.0) -> Array:
	var found := []
	for own in own_sockets:
		for turn in turns_for(own["type"], placed["type"]):
			var yaw: float = placed["yaw"] - own["yaw"] + turn
			var basis := Basis(Vector3.UP, yaw)
			var where := Transform3D(basis, (placed["position"] as Vector3) - basis * (own["position"] as Vector3))
			# Edge to edge: only where the whole edges meet
			if own.has("edge_dir") and not _edge_fit_ok(own, placed, where):
				continue
			var repeat := false
			for other in found:
				if other.origin.distance_to(where.origin) < 0.01 and _same_turn(other.basis, basis, symmetry):
					repeat = true
			if not repeat:
				found.append(where)
	return found


# True if two turns look the same for a piece with this symmetry
static func _same_turn(a: Basis, b: Basis, symmetry: float) -> bool:
	var difference := atan2(a.z.x, a.z.z) - atan2(b.z.x, b.z.z)
	var step := symmetry if symmetry > 0.0 else TAU
	return absf(wrapf(difference + step / 2.0, 0.0, step) - step / 2.0) < 0.01


## Every placed-socket type that some socket of a new piece with these sockets could attach to
static func targets_for(sockets: Array) -> Dictionary:
	var found := {}
	for socket in sockets:
		for placed_type in SNAP_RULES.get(socket["type"], {}):
			found[placed_type] = true
	return found


# ---- The pieces ----

# A straight wall, 2 m wide and 2.5 m high, standing on its bottom middle; the doorway and window
# walls are the same with a hole
static func _wall(d: Dictionary, shape: String) -> void:
	var half := GRID / 2.0
	var hole := DOOR_WIDTH / 2.0
	match shape:
		"wall":
			_wall_part(d, -half, half, 0.0, WALL_HEIGHT)
		"doorway":
			_wall_part(d, -half, -hole, 0.0, WALL_HEIGHT)
			_wall_part(d, hole, half, 0.0, WALL_HEIGHT)
			_wall_part(d, -hole, hole, DOOR_HEIGHT, WALL_HEIGHT)
			_socket(d, Vector3(0, 1.0, 0), 0.0, "door_slot")
		"window":
			hole = WINDOW_WIDTH / 2.0
			_wall_part(d, -half, -hole, 0.0, WALL_HEIGHT)
			_wall_part(d, hole, half, 0.0, WALL_HEIGHT)
			_wall_part(d, -hole, hole, 0.0, WINDOW_BOTTOM)
			_wall_part(d, -hole, hole, WINDOW_TOP, WALL_HEIGHT)
	_socket(d, Vector3.ZERO, 0.0, "wall_base")
	_socket(d, Vector3(0, WALL_HEIGHT, 0), 0.0, "wall_top")
	_socket(d, Vector3(half, 0, 0), PI / 2.0, "wall_end")
	_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")
	_wall_top_spots(d, GRID, WALL_HEIGHT)


# A split-window wall, `width` wide and a full wall high, with a window opening cut into its +X
# edge: SPLIT_WINDOWS[width] wide (half the joined window), from WINDOW_BOTTOM (the window wall's
# sill height) up SPLIT_WINDOW_HEIGHT. Two of them joined at their open edges (one turned round,
# which is what R does) make one window twice as wide. It snaps as a wall of its width does; its
# open end gets no corner post where it meets another open end (see JointDetails).
static func _split_window_wall(d: Dictionary, width: float) -> void:
	var half := width / 2.0
	var opening: float = SPLIT_WINDOWS[width]
	var top := WINDOW_BOTTOM + SPLIT_WINDOW_HEIGHT
	_wall_part(d, -half, half - opening, 0.0, WALL_HEIGHT)
	_wall_part(d, half - opening, half, 0.0, WINDOW_BOTTOM)
	_wall_part(d, half - opening, half, top, WALL_HEIGHT)
	var small := width < 1.5
	_socket(d, Vector3.ZERO, 0.0, "small_wall_base" if small else "wall_base")
	_socket(d, Vector3(0, WALL_HEIGHT, 0), 0.0, "half_top" if small else "wall_top")
	_socket(d, Vector3(half, 0, 0), PI / 2.0, "wall_end")
	_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")
	_wall_top_spots(d, width, WALL_HEIGHT)
	# Which of its ends (-X, +X) is open, for the corner posts
	d["open_ends"] = [false, true]


# Along the top of a wall: the 1 m points small walls and short beams snap to (on 2 m walls),
# spots at its ends and middle for poles, pillars and beams (only to snap to, so a wall never
# hangs from a pillar by its top), and its top points (both ends, and every 1 m out from its
# middle, on its centre line), where gables, walls and small walls stack
static func _wall_top_spots(d: Dictionary, width: float, height: float) -> void:
	if absf(width - GRID) < 0.01:
		for x in [-0.5, 0.5]:
			_socket(d, Vector3(x, height, 0), 0.0, "half_top")
	for x in [-width / 2.0, 0.0, width / 2.0]:
		_socket(d, Vector3(x, height, 0), 0.0, "top_spot")
	var points := [-width / 2.0, width / 2.0]
	var k := 0.0
	while k < width / 2.0 - 0.05:
		for x in ([0.0] if k == 0.0 else [-k, k]):
			points.append(x)
		k += 1.0
	for x in points:
		_socket(d, Vector3(x, height, 0), 0.0, "top_point")


# The 1 m points along a square floor's edges: two on each edge of a 2 m floor, the middle of
# each edge of a 1 m floor. 1 m floors, small walls and ladders snap to them.
static func _half_edges(d: Dictionary, size: float) -> void:
	for i in 4:
		var out := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 2.0) * -1.0
		var along := out.cross(Vector3.UP)
		var offsets := [-0.5, 0.5] if size > 1.5 else [0.0]
		for o in offsets:
			_socket(d, out * size / 2.0 + along * o, _yaw(out), "half_edge")


# One solid block of a wall, x0 to x1 across and y0 to y1 up, with horizontal boards
static func _wall_part(d: Dictionary, x0: float, x1: float, y0: float, y1: float) -> void:
	var size := Vector3(x1 - x0, y1 - y0, WALL_THICKNESS)
	_planked_box(d, size, Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, 0), Basis.IDENTITY, WALL_COLOR, 1, y0)


# A door panel that fits the doorway, hinged on its left edge. Its parts are marked "door" so the
# piece can swing them.
static func _door(d: Dictionary) -> void:
	d["door_surface"] = _new_surface()
	var size := Vector3(DOOR_WIDTH - 0.04, DOOR_HEIGHT - 0.02, 0.08)
	var center := Vector3(0, size.y / 2.0, 0)
	_planked_box(d, size, center, Basis.IDENTITY, DOOR_COLOR, 0, -size.x / 2.0, true)
	# A crossbar on each side, so it reads as a door
	for side in [-1.0, 1.0]:
		_box_mesh(d["door_surface"], Vector3(size.x - 0.1, 0.12, 0.03), Transform3D(Basis.IDENTITY, Vector3(0, 1.0, side * 0.055)), DOOR_COLOR.darkened(0.2))
	_socket(d, Vector3(0, 1.0, 0), 0.0, "door_base")


# A sloped roof section: 2 m along its low edge, rising `rise` (1 m for the 26° roof, 2 m for the
# 45°) over 2 m toward +Z. Its underside runs from the low edge up to the high edge; `pitch` ("_26"
# or "_45") names the snap points only roofs of the same pitch meet at. Both its ends are cut
# plumb (straight up and down): two roofs back to back share one upright face at the ridge and meet
# in a sharp, closed peak, and the eave end looks like a cut rafter end.
static func _roof(d: Dictionary, rise: float, pitch: String) -> void:
	_roof_slab(d, -GRID / 2.0, GRID / 2.0, 0.0, GRID, rise, ROOF_COLOR)
	_socket(d, Vector3.ZERO, PI, "roof_low")
	_socket(d, Vector3.ZERO, PI, "eave_spot" + pitch)
	_socket(d, Vector3(0, rise, GRID), 0.0, "roof_high" + pitch)
	_socket(d, Vector3(GRID / 2.0, rise / 2.0, GRID / 2.0), PI / 2.0, "roof_side_right" + pitch)
	_socket(d, Vector3(-GRID / 2.0, rise / 2.0, GRID / 2.0), -PI / 2.0, "roof_side_left" + pitch)
	# Its low corners can sit on pillar tops, for porches
	_socket(d, Vector3(GRID / 2.0, 0, 0), PI / 2.0, "roof_corner")
	_socket(d, Vector3(-GRID / 2.0, 0, 0), -PI / 2.0, "roof_corner")
	# Its low corners again, for pieces of either pitch: a gable under each side edge, gable
	# overhangs and other roofs beside it (whatever their slope, they meet it at the corner)
	for side in [-1.0, 1.0]:
		_socket(d, Vector3(side * GRID / 2.0, 0, 0), -PI / 2.0, "gable_under")
	_socket(d, Vector3(GRID / 2.0, 0, 0), PI / 2.0, "roof_edge_corner_right")
	_socket(d, Vector3(-GRID / 2.0, 0, 0), -PI / 2.0, "roof_edge_corner_left")
	# Its drawn top at each low corner: an inverse triangle of its pitch stands along the top of
	# the side edge from there. The close-up look's shakes lie lower than the plain slab's top along
	# the side edge (measured 1.9 to 4.3 cm), so the point sits ROOF_EDGE_SINK under the slab top,
	# on the shakes, and the triangle's planks reach down past its edge to cover the rest.
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	for side in [-1.0, 1.0]:
		_socket(d, Vector3(side * GRID / 2.0, lift - ROOF_EDGE_SINK, 0), -PI / 2.0, "roof_top_corner" + pitch)
	# Its high edge, whole, for a roof topper's low edge (the roof lies down the slope from it)
	_ridge_edge(d, Vector3(-GRID / 2.0, rise, GRID), Vector3.BACK * -1.0, "edge_ridge_roof" + pitch)
	d["roof"] = true


# Stairs 2 m wide and 4 m long, climbing a wall's height toward +Z (a gentle enough slope to walk
# up). They stand on the middle of their footprint; you walk on a hidden ramp along the step edges.
static func _stairs(d: Dictionary) -> void:
	var rise := WALL_HEIGHT / STAIRS_STEPS
	var run := STAIRS_RUN / STAIRS_STEPS
	var start := -STAIRS_RUN / 2.0
	for i in STAIRS_STEPS:
		var top := rise * (i + 1)
		var color := _board_color(STAIRS_COLOR, i)
		_box_mesh(d["surface"], Vector3(GRID, top, run), Transform3D(Basis.IDENTITY, Vector3(0, top / 2.0, start + run * (i + 0.5))), color)
	# The ramp runs along the front edges of the steps, from the ground to the top step
	var low := Vector3(0, 0, start - run)
	var high := Vector3(0, WALL_HEIGHT, STAIRS_RUN / 2.0 - run)
	var slope := atan2(high.y - low.y, high.z - low.z)
	var basis := Basis(Vector3.RIGHT, -slope)
	var ramp := BoxShape3D.new()
	ramp.size = Vector3(GRID, 0.2, low.distance_to(high))
	_collision(d, ramp, Transform3D(basis, (low + high) / 2.0 - basis.y * 0.1))
	var landing := BoxShape3D.new()
	landing.size = Vector3(GRID, 0.2, run)
	_collision(d, landing, Transform3D(Basis.IDENTITY, Vector3(0, WALL_HEIGHT - 0.1, STAIRS_RUN / 2.0 - run / 2.0)))
	_socket(d, Vector3(0, 0, -GRID / 2.0), PI, "stairs_foot")
	_socket(d, Vector3(0, 0, start), PI, "stairs_bottom")
	_socket(d, Vector3(0, WALL_HEIGHT, STAIRS_RUN / 2.0), 0.0, "stairs_top")
	d["clear_radius"] = 2.3


# A curved wall along the ring, centered on +Z, `half_angle` degrees each side. Its origin is the
# middle of the circle, so walls of the same ring share it.
static func _curved_wall(d: Dictionary, half_angle: float, base_type: String, top_type: String) -> void:
	var st: SurfaceTool = d["surface"]
	var half := deg_to_rad(half_angle)
	var steps := roundi(half_angle * 2.0 / ARC_STEP_DEGREES)
	var inner := RING_RADIUS - WALL_THICKNESS / 2.0
	var outer := RING_RADIUS + WALL_THICKNESS / 2.0
	var bands := roundi(WALL_HEIGHT / BOARD)
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		for b in bands:
			var y0 := b * BOARD
			var y1 := y0 + BOARD
			var color := _board_color(WALL_COLOR, b)
			_arc_quad(st, outer, a0, a1, y0, y1, color, 1.0)
			_arc_quad(st, inner, a0, a1, y0, y1, color, -1.0)
		_ring_quad(st, inner, outer, a0, a1, WALL_HEIGHT, WALL_COLOR, 1.0)
		_ring_quad(st, inner, outer, a0, a1, 0.0, WALL_COLOR, -1.0)
		# Solid as a row of short straight boxes along the arc
		var box := BoxShape3D.new()
		box.size = Vector3(2.0 * RING_RADIUS * sin((a1 - a0) / 2.0), WALL_HEIGHT, WALL_THICKNESS)
		var mid := (a0 + a1) / 2.0
		_collision(d, box, Transform3D(Basis(Vector3.UP, mid), _arc_point(RING_RADIUS * cos((a1 - a0) / 2.0), mid, WALL_HEIGHT / 2.0)))
	for side in [-1.0, 1.0]:
		var a: float = side * half
		var out: Vector3 = _tangent(a) * side
		_quad(st, _arc_point(inner, a, 0), _arc_point(outer, a, 0), _arc_point(outer, a, WALL_HEIGHT), _arc_point(inner, a, WALL_HEIGHT), out, WALL_COLOR)
		_socket(d, _arc_point(RING_RADIUS, a, 0), _yaw(out), "wall_end")
	_socket(d, Vector3(0, 0, RING_RADIUS), 0.0, base_type)
	_socket(d, Vector3(0, WALL_HEIGHT, RING_RADIUS), 0.0, top_type)


# A wedge of round floor from the middle of the circle out to the ring, `half_angle` degrees each
# side: an eighth (22.5) or a sixteenth (11.25). Its curved edge is exactly under the curved
# walls' middle line, the same way straight walls stand on floor edges.
static func _round_floor(d: Dictionary, half_angle := 22.5) -> void:
	var st: SurfaceTool = d["surface"]
	var half := deg_to_rad(half_angle)
	var steps := roundi(half_angle * 2.0 / ARC_STEP_DEGREES)
	var rings := 5
	var bottom := -FLOOR_THICKNESS
	var points := PackedVector3Array([Vector3.ZERO, Vector3(0, bottom, 0)])
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		# The top in rings of boards around the middle
		for r in rings:
			var r0 := RING_RADIUS * r / rings
			var r1 := RING_RADIUS * (r + 1) / rings
			_ring_quad(st, r0, r1, a0, a1, 0.0, _board_color(FLOOR_COLOR, r), 1.0)
		_ring_quad(st, 0.0, RING_RADIUS, a0, a1, bottom, FLOOR_COLOR, -1.0)
		_arc_quad(st, RING_RADIUS, a0, a1, bottom, 0.0, FLOOR_COLOR, 1.0)
	for i in steps + 1:
		var a := -half + 2.0 * half * i / steps
		points.append(_arc_point(RING_RADIUS, a, 0.0))
		points.append(_arc_point(RING_RADIUS, a, bottom))
	for side in [-1.0, 1.0]:
		var a: float = side * half
		var out: Vector3 = _tangent(a) * side
		_quad(st, Vector3.ZERO, _arc_point(RING_RADIUS, a, 0), _arc_point(RING_RADIUS, a, bottom), Vector3(0, bottom, 0), out, FLOOR_COLOR)
	var solid := ConvexPolygonShape3D.new()
	solid.points = points
	_collision(d, solid, Transform3D.IDENTITY)
	_round_sockets(d, half)
	d["floor"] = true
	d["clear_center"] = Vector3(0, 0, RING_RADIUS * 0.62)
	d["clear_radius"] = 1.65 if half_angle > 12.0 else 1.45


# One eighth of a cone roof: from the ring (sitting on the curved walls' tops) up to a point
# above the middle
static func _cone_roof(d: Dictionary) -> void:
	var st: SurfaceTool = d["surface"]
	var half := deg_to_rad(22.5)
	var steps := roundi(45.0 / ARC_STEP_DEGREES)
	var apex := Vector3(0, CONE_HEIGHT, 0)
	var down := Vector3(0, -ROOF_THICKNESS, 0)
	var points := PackedVector3Array([apex, apex + down])
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		var p0 := _arc_point(RING_RADIUS, a0, 0)
		var p1 := _arc_point(RING_RADIUS, a1, 0)
		var color := _board_color(ROOF_COLOR, i)
		var up := (p1 - apex).cross(p0 - apex).normalized()
		if up.y < 0.0:
			up = -up
		_triangle(st, apex, p1, p0, up, color)
		_triangle(st, apex + down, p0 + down, p1 + down, -up, color)
		_quad(st, p0 + down, p1 + down, p1, p0, _arc_point(1.0, (a0 + a1) / 2.0, 0), ROOF_COLOR)
	for i in steps + 1:
		var p := _arc_point(RING_RADIUS, -half + 2.0 * half * i / steps, 0)
		points.append(p)
		points.append(p + down)
	for side in [-1.0, 1.0]:
		var a: float = side * half
		var p := _arc_point(RING_RADIUS, a, 0)
		var out: Vector3 = _tangent(a) * side
		_quad(st, apex, p, p + down, apex + down, out, ROOF_COLOR)
		_socket(d, (apex + p) / 2.0, _yaw(out), "cone_side_right" if side > 0.0 else "cone_side_left")
	var solid := ConvexPolygonShape3D.new()
	solid.points = points
	_collision(d, solid, Transform3D.IDENTITY)
	_socket(d, Vector3(0, 0, RING_RADIUS), 0.0, "cone_base")
	d["roof"] = true


# A foundation: a solid 2 × 2 m block FOUNDATION_DEPTH tall, its top flush like a floor's (so
# floors, walls and stairs snap onto its edges the same way), built of crossing logs or of
# staggered stone blocks
static func _foundation(d: Dictionary, stone: bool) -> void:
	var st: SurfaceTool = d["surface"]
	var depth := FOUNDATION_DEPTH
	var half := GRID / 2.0
	var solid := BoxShape3D.new()
	solid.size = Vector3(GRID, depth, GRID)
	_collision(d, solid, Transform3D(Basis.IDENTITY, Vector3(0, -depth / 2.0, 0)))
	var courses := roundi(depth / COURSE)
	if stone:
		# Mortar behind, blocks in front, every other course shifted by half a block
		_box_mesh(st, Vector3(GRID - 0.06, depth - 0.03, GRID - 0.06), Transform3D(Basis.IDENTITY, Vector3(0, -depth / 2.0 - 0.015, 0)), MORTAR_COLOR)
		for k in courses:
			var y := -COURSE * (k + 0.5)
			for face in 4:
				var turn := Basis(Vector3.UP, face * PI / 2.0)
				var x := -half + (0.25 if k % 2 == 1 else 0.0)
				var edges := [-half]
				while x < half - 0.001:
					if x > -half + 0.001:
						edges.append(x)
					x += 0.5
				edges.append(half)
				for i in edges.size() - 1:
					var x0: float = edges[i]
					var x1: float = edges[i + 1]
					var shade := _board_color(STONE_COLOR, k * 31 + face * 7 + i)
					_box_mesh(st, Vector3(x1 - x0 - 0.03, COURSE - 0.03, 0.06), Transform3D(turn, turn * Vector3((x0 + x1) / 2.0, y, half - 0.03)), shade)
		# Flagstones on top
		for i in 4:
			for j in 4:
				var shade := _board_color(STONE_COLOR.lightened(0.05), i * 4 + j + 50)
				_box_mesh(st, Vector3(0.47, 0.05, 0.47), Transform3D(Basis.IDENTITY, Vector3(-0.75 + i * 0.5, -0.025, -0.75 + j * 0.5)), shade)
	else:
		# Logs crossing at the corners, each course running the other way from the one above
		_box_mesh(st, Vector3(GRID - 0.2, depth, GRID - 0.2), Transform3D(Basis.IDENTITY, Vector3(0, -depth / 2.0, 0)), LOG_COLOR.darkened(0.4))
		var r := COURSE / 2.0
		for k in courses:
			var y := -COURSE * (k + 0.5)
			var along_x := k % 2 == 0
			for side in [-1.0, 1.0]:
				var color := _board_color(LOG_COLOR, k * 2 + (1 if side > 0.0 else 0))
				if along_x:
					_log(st, Vector3(-half, y, side * (half - r)), Vector3(half, y, side * (half - r)), r, color)
				else:
					_log(st, Vector3(side * (half - r), y, -half), Vector3(side * (half - r), y, half), r, color)
			# The other pair of sides, between the ends of these logs
			for side in [-1.0, 1.0]:
				var color := _board_color(LOG_COLOR, k * 2 + 7 + (1 if side > 0.0 else 0))
				if along_x:
					_log(st, Vector3(side * (half - r), y, -half + 2.0 * r), Vector3(side * (half - r), y, half - 2.0 * r), r * 0.92, color)
				else:
					_log(st, Vector3(-half + 2.0 * r, y, side * (half - r)), Vector3(half - 2.0 * r, y, side * (half - r)), r * 0.92, color)
		_planked_box(d, Vector3(GRID - 0.02, 0.06, GRID - 0.02), Vector3(0, -0.03, 0), Basis.IDENTITY, FLOOR_COLOR, 0, -half, false, false)
	for i in 4:
		var out := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 2.0) * -1.0
		_socket(d, out * half, _yaw(out), "floor_edge")
	_socket(d, Vector3.ZERO, 0.0, "floor_center")
	_socket(d, Vector3.ZERO, 0.0, "foundation_top")
	_socket(d, Vector3(0, -depth, 0), 0.0, "foundation_base")
	_square_post_spots(d)
	_half_edges(d, GRID)
	d["floor"] = true
	d["clear_radius"] = 1.5
	d["free_lift"] = FOUNDATION_LIFT


# A wedge of round foundation: the round floor's wedge (an eighth or a sixteenth),
# FOUNDATION_DEPTH tall, with logs or stone courses round its outside
static func _round_foundation(d: Dictionary, stone: bool, half_angle := 22.5) -> void:
	var st: SurfaceTool = d["surface"]
	var depth := FOUNDATION_DEPTH
	var half := deg_to_rad(half_angle)
	var steps := roundi(half_angle * 2.0 / ARC_STEP_DEGREES)
	var courses := roundi(depth / COURSE)
	var base_color := STONE_COLOR if stone else LOG_COLOR
	var points := PackedVector3Array([Vector3.ZERO, Vector3(0, -depth, 0)])
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		# The top: rings of boards, or flagstones
		for r in 5:
			var r0 := RING_RADIUS * r / 5.0
			var r1 := RING_RADIUS * (r + 1) / 5.0
			var top := _board_color(STONE_COLOR.lightened(0.05), r * 13 + i) if stone else _board_color(FLOOR_COLOR, r)
			_ring_quad(st, r0, r1, a0, a1, 0.0, top, 1.0)
		# The outside, course by course: stone blocks two arc steps long, staggered; or logs
		for k in courses:
			var y0 := -COURSE * (k + 1)
			var y1 := -COURSE * k
			var shade: Color
			if stone:
				shade = _board_color(STONE_COLOR, k * 31 + int((i + (k % 2)) / 2.0) * 5)
				_arc_quad(st, RING_RADIUS, a0, a1, y0 + 0.015, y1 - 0.015, shade, 1.0)
				_arc_quad(st, RING_RADIUS - 0.01, a0, a1, y0, y1, MORTAR_COLOR, 1.0)
			else:
				shade = _board_color(LOG_COLOR, k)
				var mid := (y0 + y1) / 2.0
				_arc_quad(st, RING_RADIUS, a0, a1, mid - COURSE * 0.3, mid + COURSE * 0.3, shade, 1.0)
				_arc_quad(st, RING_RADIUS - 0.02, a0, a1, y0, y1, LOG_COLOR.darkened(0.4), 1.0)
	for i in steps + 1:
		var a := -half + 2.0 * half * i / steps
		points.append(_arc_point(RING_RADIUS, a, 0.0))
		points.append(_arc_point(RING_RADIUS, a, -depth))
	for side in [-1.0, 1.0]:
		var a: float = side * half
		var out: Vector3 = _tangent(a) * side
		_quad(st, Vector3.ZERO, _arc_point(RING_RADIUS, a, 0), _arc_point(RING_RADIUS, a, -depth), Vector3(0, -depth, 0), out, base_color.darkened(0.3))
	var solid := ConvexPolygonShape3D.new()
	solid.points = points
	_collision(d, solid, Transform3D.IDENTITY)
	_round_sockets(d, half)
	# Stacking: in the middle of the wedge, so each wedge of a ring has its own
	var middle := Vector3(0, 0, RING_RADIUS * 0.62)
	var family := "round_foundation" if half_angle > 12.0 else "round22_foundation"
	_socket(d, middle, 0.0, family + "_top")
	_socket(d, middle + Vector3(0, -depth, 0), 0.0, family + "_base")
	d["floor"] = true
	d["clear_center"] = middle
	d["clear_radius"] = 1.65 if half_angle > 12.0 else 1.45
	d["free_lift"] = FOUNDATION_LIFT


# The snap points every round floor or foundation wedge has: its two sides (so wedges ring round
# one middle), its curved edge for curved walls (a 45° wall on an eighth's middle, 22.5° walls on
# its two halves; a 22.5° wall on a sixteenth), and pillar spots at its corners and edge middles
static func _round_sockets(d: Dictionary, half: float) -> void:
	for side in [-1.0, 1.0]:
		var a: float = side * half
		var out: Vector3 = _tangent(a) * side
		_socket(d, _arc_point(RING_RADIUS / 2.0, a, 0), _yaw(out), "round_side_right" if side > 0.0 else "round_side_left")
		_socket(d, _arc_point(RING_RADIUS, a, 0), 0.0, "post_spot")
		_socket(d, _arc_point(RING_RADIUS / 2.0, a, 0), 0.0, "post_spot")
		if half > deg_to_rad(12.0):
			_socket(d, _arc_point(RING_RADIUS, a / 2.0, 0), a / 2.0, "round_edge_small")
	if half > deg_to_rad(12.0):
		_socket(d, Vector3(0, 0, RING_RADIUS), 0.0, "round_edge")
	else:
		_socket(d, Vector3(0, 0, RING_RADIUS), 0.0, "round_edge_small")
	_socket(d, Vector3(0, 0, RING_RADIUS), 0.0, "post_spot")
	_socket(d, Vector3.ZERO, 0.0, "post_spot")


# Pillar spots on a 2 m square: its corners and the middles of its edges
static func _square_post_spots(d: Dictionary) -> void:
	var half := GRID / 2.0
	for x in [-1, 0, 1]:
		for z in [-1, 0, 1]:
			if x != 0 or z != 0:
				_socket(d, Vector3(x * half, 0, z * half), 0.0, "post_spot")


# A plain wall of any width and height (the triangles' long and short edges, 1 m walls,
# half-height and quarter walls), with its own types of bottom and top snap points so it only
# goes where its width fits
static func _plain_wall(d: Dictionary, width: float, height: float, base_type: String, top_type: String) -> void:
	var half := width / 2.0
	_wall_part(d, -half, half, 0.0, height)
	_socket(d, Vector3.ZERO, 0.0, base_type)
	_socket(d, Vector3(0, height, 0), 0.0, top_type)
	_socket(d, Vector3(half, 0, 0), PI / 2.0, "wall_end")
	_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")
	_wall_top_spots(d, width, height)


# A gable: the triangle of wall under the end of one roof section, 2 m along the bottom and as
# tall as the roof rises. It stands on the top of the wall that runs up the slope, rising toward
# +X (the ridge end); its sloping edge follows the roof's underside. Two of them back to back
# fill the end under a ridge.
static func _gable(d: Dictionary, rise: float, base := 0.0, width := GRID) -> void:
	var st: SurfaceTool = d["surface"]
	var half := width / 2.0
	var pitch := "_26" if rise / width < 0.75 else "_45"
	# `base` > 0: a straight strip that high first, the triangle on top (the 45° gable wall)
	var outline := PackedVector2Array([Vector2(-half, 0), Vector2(half, 0), Vector2(half, base + rise)])
	if base > 0.0:
		outline.append(Vector2(-half, base))
	var middle := Vector2.ZERO
	for p in outline:
		middle += p / outline.size()
	var t := WALL_THICKNESS / 2.0
	var k := 0
	var y := 0.0
	while y < base + rise - 0.001:
		var band := _clip(outline, Vector2.UP * -1.0, y, minf(y + BOARD, base + rise))
		if band.size() >= 3:
			for side in [-1.0, 1.0]:
				_upright(st, band, side * t, Vector3.BACK * side, _board_color(WALL_COLOR, k))
		y += BOARD
		k += 1
	var points := PackedVector3Array()
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var out2 := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		if out2.dot((a + b) / 2.0 - middle) < 0.0:
			out2 = -out2
		_quad(st, Vector3(a.x, a.y, t), Vector3(b.x, b.y, t), Vector3(b.x, b.y, -t), Vector3(a.x, a.y, -t), Vector3(out2.x, out2.y, 0), WALL_COLOR)
		points.append(Vector3(a.x, a.y, t))
		points.append(Vector3(a.x, a.y, -t))
	var solid := ConvexPolygonShape3D.new()
	solid.points = points
	_collision(d, solid, Transform3D.IDENTITY)
	_edge_sockets(d, outline, false)
	if base > 0.0:
		# A gable wall stands on a floor or wall top like a wall, ends against walls, and things
		# stack on its tall end, which is as high as a full wall
		_socket(d, Vector3.ZERO, 0.0, "wall_base")
		_socket(d, Vector3(half, 0, 0), PI / 2.0, "wall_end")
		_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")
		_socket(d, Vector3(half, base + rise, 0), 0.0, "top_point")
		# How tall it is at each end (-x, +x), for the corner posts where it meets other walls
		d["end_tops"] = [base, base + rise]
		return
	_socket(d, Vector3.ZERO, 0.0, "gable_base" if width > 1.5 else "small_gable_base")
	# Under a roof's side edge, by its low corner (roofs of either pitch), and back to back with
	# another gable at its tall edge (two make a gable end under a ridge)
	_socket(d, Vector3(-half, 0, 0), 0.0, "gable_corner")
	_socket(d, Vector3(half, 0, 0), PI / 2.0, "gable_tip")
	# The top of its upright edge, facing on past it: where a topper gable's bottom corner goes
	_socket(d, Vector3(half, rise, 0), PI / 2.0, "gable_peak")
	# Along its slope, every 1 m: where an inverse triangle of the same pitch sits on it
	var x := -half
	while x < half - 0.01:
		_socket(d, Vector3(x, (x + half) * rise / width, 0), 0.0, "gable_slope" + pitch)
		x += 1.0
	if width < 1.5:
		# A half gable also stands beside walls and other gables by its ends
		_socket(d, Vector3(half, 0, 0), PI / 2.0, "wall_end")
		_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")
		d["end_tops"] = [0.0, rise]


# An inverse triangle: fills the space above a slope, under a flat line. Its sloped edge is along
# the bottom (rising toward +X at the pitch), its flat top level with the slope's high end, and its
# vertical side at the low end (-X). It hangs under a beam, a roof's low edge, an eave's outer
# edge or a wall above by its top; stands against a wall's end by its vertical side; and sits on
# a gable's slope or along the top of a roof's side edge of its own pitch by its low corner.
static func _inverse_wall(d: Dictionary, width: float, rise: float, pitch: String) -> void:
	var st: SurfaceTool = d["surface"]
	var half := width / 2.0
	var outline := PackedVector2Array([Vector2(-half, 0), Vector2(half, rise), Vector2(-half, rise)])
	var middle := (outline[0] + outline[1] + outline[2]) / 3.0
	var t := WALL_THICKNESS / 2.0
	var k := 0
	var y := 0.0
	while y < rise - 0.001:
		var band := _clip(outline, Vector2(0, 1), y, minf(y + BOARD, rise))
		if band.size() >= 3:
			for side in [-1.0, 1.0]:
				_upright(st, band, side * t, Vector3.BACK * side, _board_color(WALL_COLOR, k))
		y += BOARD
		k += 1
	var points := PackedVector3Array()
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var out2 := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		if out2.dot((a + b) / 2.0 - middle) < 0.0:
			out2 = -out2
		_quad(st, Vector3(a.x, a.y, t), Vector3(b.x, b.y, t), Vector3(b.x, b.y, -t), Vector3(a.x, a.y, -t), Vector3(out2.x, out2.y, 0), WALL_COLOR)
		points.append(Vector3(a.x, a.y, t))
		points.append(Vector3(a.x, a.y, -t))
	var solid := ConvexPolygonShape3D.new()
	solid.points = points
	_collision(d, solid, Transform3D.IDENTITY)
	_edge_sockets(d, outline, false)
	var small := width < 1.5
	_socket(d, Vector3(0, rise, 0), 0.0, "inverse_top_small" if small else "inverse_top")
	# Its top carries things like a wall top does (a beam, a wall, a half gable)
	_socket(d, Vector3(0, rise, 0), 0.0, "half_top" if small else "wall_top")
	_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")
	_socket(d, Vector3(-half, 0, 0), 0.0, "inverse_low" + pitch)
	d["end_tops"] = [rise, rise]


# A roof corner, 2 × 2 m. Outer (a hip): eaves along two sides (the front, and the right),
# rising to the back-left corner, where it meets a roof along each of its other two sides. Inner (a
# valley): the low point at the front-right corner, rising along the valley to high edges at the
# back and left, meeting roofs along its front and right sides. Its underside is where the two
# roofs it joins would cross.
static func _roof_corner(d: Dictionary, rise: float, pitch: String, inner: bool) -> void:
	var st: SurfaceTool = d["surface"]
	var half := GRID / 2.0
	var slope := atan2(rise, GRID)
	var lift := ROOF_THICKNESS / cos(slope)
	# Underside height: from the front eave (z = 0) and the right eave (x = +1), the lower of
	# the two for a hip, the higher for a valley
	var height := func(p: Vector2) -> float:
		var a := p.y * rise / GRID
		var b := (half - p.x) * rise / GRID
		return maxf(a, b) if inner else minf(a, b)
	var front_right := Vector2(half, 0)
	var back_left := Vector2(-half, GRID)
	var facets := [
		[front_right, Vector2(-half, 0), back_left],
		[front_right, Vector2(half, GRID), back_left],
	]
	for i in facets.size():
		var corners: Array = facets[i]
		var low := []
		var high := []
		for p in corners:
			var h: float = height.call(p)
			low.append(Vector3(p.x, h, p.y))
			high.append(Vector3(p.x, h + lift, p.y))
		var up: Vector3 = (high[1] - high[0]).cross(high[2] - high[0]).normalized()
		if up.y < 0.0:
			up = -up
		var color := _board_color(ROOF_COLOR, i + 3)
		_triangle(st, high[0], high[1], high[2], up, color)
		_triangle(st, low[0], low[1], low[2], -up, color)
		# The two outside edges of this facet (its third edge is the hip or valley, inside)
		for e in [[1, 2], [0, 1]] if i == 0 else [[0, 1], [1, 2]]:
			var a: Vector3 = low[e[0]]
			var b: Vector3 = low[e[1]]
			var out := Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized()
			if out.dot((a + b) / 2.0 - Vector3(0, 0, half)) < 0.0:
				out = -out
			_quad(st, a, b, high[e[1]], high[e[0]], out, ROOF_COLOR)
		var solid := ConvexPolygonShape3D.new()
		solid.points = PackedVector3Array(low + high)
		_collision(d, solid, Transform3D.IDENTITY)
	if inner:
		# Its low corner, where the two roofs' eaves meet inside the corner: a valley eave corner goes
		# there
		_socket(d, Vector3(half, 0, 0), 0.0, "valley_eave_spot" + pitch)
		_socket(d, Vector3(half, rise / 2.0, half), PI / 2.0, "roof_side_right" + pitch)
		_socket(d, Vector3(0, rise / 2.0, 0), PI, "roof_side_left" + pitch)
		_socket(d, Vector3(-half, rise, half), -PI / 2.0, "roof_high" + pitch)
		_socket(d, Vector3(0, rise, GRID), 0.0, "roof_high" + pitch)
	else:
		_socket(d, Vector3.ZERO, PI, "roof_low")
		_socket(d, Vector3(half, 0, half), PI / 2.0, "roof_low")
		# Eaves go along both its eaves, as along a roof's
		_socket(d, Vector3.ZERO, PI, "eave_spot" + pitch)
		_socket(d, Vector3(half, 0, half), PI / 2.0, "eave_spot" + pitch)
		_socket(d, Vector3(-half, rise / 2.0, half), -PI / 2.0, "roof_side_left" + pitch)
		_socket(d, Vector3(0, rise / 2.0, GRID), 0.0, "roof_side_right" + pitch)
		_socket(d, Vector3(half, 0, 0), PI / 2.0, "roof_corner")
		# Its low corner, where an outer eave corner goes under it
		_socket(d, Vector3(half, 0, 0), 0.0, "outer_eave_spot" + pitch)
		# Stacking up a wide hip end: its foot (the low corner) on the top (the high corner) of the
		# hip corner below, the same way round, so the hip line carries straight on up
		_socket(d, Vector3(half, 0, 0), 0.0, "hip_foot" + pitch)
		_socket(d, Vector3(-half, rise, GRID), 0.0, "hip_top" + pitch)
		# It fits wall tops many ways round; the right one lands on both walls and beside the end's
		# roof at once (see PiecePlacer._snap_by_anchors)
		d["anchored"] = true
	d["roof"] = true


# ---- Roof slabs and overhangs ----

## Overhangs: how far an eave reaches out (measured level), how wide a gable overhang is, and the
## fascia board along their outer edges (thickness, and how far it hangs below the underside)
const OVERHANG := 0.5
const FASCIA_THICKNESS := 0.03
const FASCIA_DROP := 0.1
const FASCIA_COLOR := Color(0.36, 0.25, 0.16)


# A piece of roof slab: x0 to x1 across, z0 to z1 along the slope (measured level), with its
# underside on the roof's plane (height z * rise / GRID, so it lines up with any roof of the same
# pitch) and its ends cut plumb. Drawn as boards along X, like a roof; solid unless told not to be.
static func _roof_slab(d: Dictionary, x0: float, x1: float, z0: float, z1: float, rise: float, color: Color, solid := true) -> void:
	var st: SurfaceTool = d["surface"]
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	var section := _slab_section(z0, z1, rise, 0.0, lift)
	var x := x0
	while x < x1 - 0.001:
		var k := floori(x / BOARD + 0.001)
		var next := minf((k + 1) * BOARD, x1)
		_prism_x(st, section, x, next, _board_color(color, k))
		x = next
	if solid:
		var points := PackedVector3Array()
		for p in section:
			points.append(Vector3(x0, p.y, p.x))
			points.append(Vector3(x1, p.y, p.x))
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		_collision(d, shape, Transform3D.IDENTITY)


# A slab's outline seen from the side, as (z, y) corners: from `below` under the roof's plane to
# `above` over it, cut plumb at z0 and z1
static func _slab_section(z0: float, z1: float, rise: float, below: float, above: float) -> PackedVector2Array:
	var k := rise / GRID
	return PackedVector2Array([Vector2(z0, z0 * k - below), Vector2(z1, z1 * k - below), Vector2(z1, z1 * k + above), Vector2(z0, z0 * k + above)])


# A straight solid with this side outline ((z, y) corners, convex), running x0 to x1 along X
static func _prism_x(st: SurfaceTool, section: PackedVector2Array, x0: float, x1: float, color: Color) -> void:
	var middle := Vector2.ZERO
	for p in section:
		middle += p
	middle /= section.size()
	for i in range(1, section.size() - 1):
		for x in [x0, x1]:
			var n := Vector3.LEFT if x == x0 else Vector3.RIGHT
			_triangle(st, Vector3(x, section[0].y, section[0].x), Vector3(x, section[i].y, section[i].x), Vector3(x, section[i + 1].y, section[i + 1].x), n, color)
	for i in section.size():
		var a := section[i]
		var b := section[(i + 1) % section.size()]
		var out := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		if out.dot((a + b) / 2.0 - middle) < 0.0:
			out = -out
		_quad(st, Vector3(x0, a.y, a.x), Vector3(x0, b.y, b.x), Vector3(x1, b.y, b.x), Vector3(x1, a.y, a.x), Vector3(0, out.y, out.x), color)


# A fascia board standing along a slab's outer end at level distance z (from x0 to x1), facing
# outward (`outward` is -1 or +1 along Z)
static func _fascia_end(d: Dictionary, x0: float, x1: float, z: float, outward: float, rise: float) -> void:
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	var y := z * rise / GRID
	# Its top flush with the slab's, level with the barge boards it meets at a corner
	var height := lift + FASCIA_DROP
	var center := Vector3((x0 + x1) / 2.0, y - FASCIA_DROP + height / 2.0, z + outward * FASCIA_THICKNESS / 2.0)
	_box_mesh(d["surface"], Vector3(x1 - x0, height, FASCIA_THICKNESS), Transform3D(Basis.IDENTITY, center), FASCIA_COLOR)


# A barge board along a slab's side at x, from z0 to z1 along the slope, on the outward side. It
# stops just under the slab's top, so where it ends up on the inner side (against the roof's edge,
# the same piece fitting either side of a roof) it hides under the roof without a lip or flicker.
static func _fascia_side(d: Dictionary, x: float, outward: float, z0: float, z1: float, rise: float) -> void:
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	var section := _slab_section(z0, z1, rise, FASCIA_DROP, lift - 0.005)
	var x_out := x + outward * FASCIA_THICKNESS
	_prism_x(d["surface"], section, minf(x, x_out), maxf(x, x_out), FASCIA_COLOR)


# An eave: carries a roof's low edge on outward and down along the same slope, 2 m wide and
# OVERHANG deep (level), with a fascia board along its outer edge. Snaps to a roof's low edge
# (by its inner edge, at its origin) and end to end with other eaves and eave corners.
static func _eave(d: Dictionary, rise: float, pitch: String) -> void:
	var half := GRID / 2.0
	_roof_slab(d, -half, half, -OVERHANG, 0.0, rise, ROOF_COLOR)
	_fascia_end(d, -half, half, -OVERHANG, -1.0, rise)
	_socket(d, Vector3.ZERO, 0.0, "eave_base" + pitch)
	# Under its outer edge: walls, beams and posts for a porch
	_socket(d, Vector3(0, -OVERHANG * rise / GRID, -OVERHANG), 0.0, "eave_edge")
	d["overhang"] = true
	var mid := Vector3(0, -OVERHANG / 2.0 * rise / GRID, -OVERHANG / 2.0)
	_socket(d, mid + Vector3(half, 0, 0), PI / 2.0, "eave_side_right" + pitch)
	_socket(d, mid - Vector3(half, 0, 0), -PI / 2.0, "eave_side_left" + pitch)


# A gable overhang: carries a roof on past its side edge (beyond the gable wall), OVERHANG wide and
# 2 m along the slope like the roof, with a barge board along each side (the inner one tucks into
# the gable wall under the roof's edge, so the same piece fits either side). Snaps to a roof's side
# edge, up the slope to another, and back to back with another at the ridge.
static func _gable_overhang(d: Dictionary, rise: float, pitch: String) -> void:
	var half := OVERHANG / 2.0
	_roof_slab(d, -half, half, 0.0, GRID, rise, ROOF_COLOR)
	_fascia_side(d, half, 1.0, 0.0, GRID, rise)
	_fascia_side(d, -half, -1.0, 0.0, GRID, rise)
	_socket(d, Vector3(-half, rise / 2.0, GRID / 2.0), -PI / 2.0, "overhang_left" + pitch)
	_socket(d, Vector3(half, rise / 2.0, GRID / 2.0), PI / 2.0, "overhang_right" + pitch)
	_socket(d, Vector3.ZERO, PI, "overhang_low" + pitch)
	_socket(d, Vector3(0, rise, GRID), 0.0, "overhang_high" + pitch)
	# Its low corners, to meet a roof of the other pitch at the corner (see roof_edge_corner)
	_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "overhang_corner_left")
	_socket(d, Vector3(half, 0, 0), PI / 2.0, "overhang_corner_right")
	d["overhang"] = true


# An eave corner: fills the square where an eave meets a gable overhang, OVERHANG × OVERHANG, on
# the eave's slope, with fascia boards round its outer edges. Snaps under a gable overhang's low
# end, and end to end with eaves.
static func _eave_corner(d: Dictionary, rise: float, pitch: String) -> void:
	var half := OVERHANG / 2.0
	_roof_slab(d, -half, half, -OVERHANG, 0.0, rise, ROOF_COLOR)
	_fascia_end(d, -half - FASCIA_THICKNESS, half + FASCIA_THICKNESS, -OVERHANG, -1.0, rise)
	_fascia_side(d, half, 1.0, -OVERHANG, 0.0, rise)
	_fascia_side(d, -half, -1.0, -OVERHANG, 0.0, rise)
	_socket(d, Vector3.ZERO, 0.0, "corner_top" + pitch)
	d["overhang"] = true
	var mid := Vector3(0, -OVERHANG / 2.0 * rise / GRID, -OVERHANG / 2.0)
	_socket(d, mid + Vector3(half, 0, 0), PI / 2.0, "eave_side_right" + pitch)
	_socket(d, mid - Vector3(half, 0, 0), -PI / 2.0, "eave_side_left" + pitch)


# A valley eave corner: where two eaves meet inside a corner (an L-shaped house's inner corner,
# under a valley corner), both reach into the same OVERHANG square, crossing. This fills that
# square cleanly: its top is the higher of the two eaves' slopes, so it folds along a valley down
# the diagonal like the roofs above, and a flat board underneath hides where the two eaves'
# fascia boards cross. In the valley corner's frame, moved to its low corner: x from 0 to
# OVERHANG (out past the first roof's low edge), z from -OVERHANG to 0 (out past the other's).
static func _valley_eave_corner(d: Dictionary, rise: float, pitch: String) -> void:
	var st: SurfaceTool = d["surface"]
	var k := rise / GRID
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	var o := OVERHANG
	# The first roof's eave falls along +x, the other's along -z; the top follows the higher
	var facets := [
		[[Vector2(0, 0), Vector2(o, 0), Vector2(o, -o)], func(p: Vector2) -> float: return p.y * k],
		[[Vector2(0, 0), Vector2(o, -o), Vector2(0, -o)], func(p: Vector2) -> float: return -p.x * k],
	]
	for i in facets.size():
		var corners: Array = facets[i][0]
		var height: Callable = facets[i][1]
		var low := []
		var high := []
		for p in corners:
			var h: float = height.call(p)
			low.append(Vector3(p.x, h, p.y))
			high.append(Vector3(p.x, h + lift, p.y))
		var up: Vector3 = (high[1] - high[0]).cross(high[2] - high[0]).normalized()
		if up.y < 0.0:
			up = -up
		var color := _board_color(ROOF_COLOR, i + 7)
		_triangle(st, high[0], high[1], high[2], up, color)
		_triangle(st, low[0], low[1], low[2], -up, color)
		for e in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = low[e[0]]
			var b: Vector3 = low[e[1]]
			var out := Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized()
			if out.dot((a + b) / 2.0 - Vector3(o / 2.0, 0, -o / 2.0)) < 0.0:
				out = -out
			_quad(st, a, b, high[e[1]], high[e[0]], out, ROOF_COLOR)
		var solid := ConvexPolygonShape3D.new()
		solid.points = PackedVector3Array(low + high)
		_collision(d, solid, Transform3D.IDENTITY)
	# The board underneath, level with the bottom of the fascia boards, hiding where they cross
	var soffit_y := -o * k - FASCIA_DROP - 0.01
	_box_mesh(st, Vector3(o, 0.02, o), _at(o / 2.0, soffit_y, -o / 2.0), FASCIA_COLOR)
	_socket(d, Vector3.ZERO, 0.0, "valley_eave_base" + pitch)
	d["overhang"] = true


# An outer eave corner: where two eaves meet round an outside corner (an outer roof corner's low
# corner, or round a building's corner), both stop short of the OVERHANG square between their
# ends. This fills it: its top is the lower of the two eaves' slopes, so it folds down along the
# diagonal like a hip, and fascia boards run along both outer edges, meeting at the corner. In the
# outer roof corner's frame, moved to its low corner: x from 0 to OVERHANG (out past the side
# edge's eave), z from -OVERHANG to 0 (out past the front edge's). Its inner edges are the two
# eaves' ends: it snaps to them (an eave's end point and facing match the whole 0.5 m end), and
# under the outer roof corner's low corner.
static func _outer_eave_corner(d: Dictionary, rise: float, pitch: String) -> void:
	var st: SurfaceTool = d["surface"]
	var k := rise / GRID
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	var o := OVERHANG
	# The front eave falls along -z, the side's along +x; the top follows the lower
	var facets := [
		[[Vector2(0, 0), Vector2(o, 0), Vector2(o, -o)], func(p: Vector2) -> float: return -p.x * k],
		[[Vector2(0, 0), Vector2(o, -o), Vector2(0, -o)], func(p: Vector2) -> float: return p.y * k],
	]
	for i in facets.size():
		var corners: Array = facets[i][0]
		var height: Callable = facets[i][1]
		var low := []
		var high := []
		for p in corners:
			var h: float = height.call(p)
			low.append(Vector3(p.x, h, p.y))
			high.append(Vector3(p.x, h + lift, p.y))
		var up: Vector3 = (high[1] - high[0]).cross(high[2] - high[0]).normalized()
		if up.y < 0.0:
			up = -up
		var color := _board_color(ROOF_COLOR, i + 11)
		_triangle(st, high[0], high[1], high[2], up, color)
		_triangle(st, low[0], low[1], low[2], -up, color)
		for e in [[0, 1], [1, 2], [2, 0]]:
			var a: Vector3 = low[e[0]]
			var b: Vector3 = low[e[1]]
			var out := Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized()
			if out.dot((a + b) / 2.0 - Vector3(o / 2.0, 0, -o / 2.0)) < 0.0:
				out = -out
			_quad(st, a, b, high[e[1]], high[e[0]], out, ROOF_COLOR)
		var solid := ConvexPolygonShape3D.new()
		solid.points = PackedVector3Array(low + high)
		_collision(d, solid, Transform3D.IDENTITY)
	# Fascia boards along both outer edges (level there, at the eaves' outer height), the front one
	# running on past the corner to cover the side one's end
	_fascia_end(d, 0.0, o + FASCIA_THICKNESS, -o, -1.0, rise)
	var board_height := lift + FASCIA_DROP
	_box_mesh(st, Vector3(FASCIA_THICKNESS, board_height, o), _at(o + FASCIA_THICKNESS / 2.0, -o * k - FASCIA_DROP + board_height / 2.0, -o / 2.0), FASCIA_COLOR)
	_socket(d, Vector3.ZERO, 0.0, "outer_eave_base" + pitch)
	# Its inner edges, as an eave's ends: the front eave's end (x = 0) and the side eave's (z = 0)
	var mid := -o / 2.0 * k
	_socket(d, Vector3(0, mid, -o / 2.0), -PI / 2.0, "eave_side_left" + pitch)
	_socket(d, Vector3(o / 2.0, mid, 0), 0.0, "eave_side_right" + pitch)
	d["overhang"] = true


# A roof topper: closes the ridge of a building an odd number of foundation tiles across, where the
# roofs from each side stop TOPPER_GAP apart. 2 m long along the ridge (X), it bridges the gap from
# one roof's high edge to the other's (z = -TOPPER_GAP/2 to +TOPPER_GAP/2), sloping up from both at
# the roofs' pitch to a sharp peak over the middle, as two short slabs back to back. Its origin is
# under the middle of its low edges, level with the roofs' high edges' underside.
#   - Each low edge snaps on its own, whole edge to whole edge, to the high edge of a roof of its
#     pitch (snap points at both ends and every 0.5 m along both; see _edge_sockets), so one roof
#     is enough, and the other side's roof then snaps to its free edge the same way.
#   - Its ends chain to other toppers along the ridge.
#   - Each end carries snap points along both its sloped undersides (in the end's plane, every 0.5 m
#     of run), where gables and half gables meet it edge to edge, never past its peak.
static func _topper(d: Dictionary, rise: float, pitch: String) -> void:
	var g := TOPPER_GAP / 2.0
	var peak := g * rise / GRID
	_topper_slabs(d, rise, GRID / 2.0)
	# Its low edges on roofs' high edges (facing out: -Z and +Z), and end to end along the ridge
	_socket(d, Vector3(0, 0, -g), PI, "topper_low" + pitch)
	_socket(d, Vector3(0, 0, g), 0.0, "topper_low" + pitch)
	_socket(d, Vector3(GRID / 2.0, peak, 0), PI / 2.0, "topper_end")
	_socket(d, Vector3(-GRID / 2.0, peak, 0), -PI / 2.0, "topper_end")
	# Its low edges, whole, for roofs' high edges (each lies along X; the topper is on its inner side)
	for side in [-1.0, 1.0]:
		_ridge_edge(d, Vector3(-GRID / 2.0, 0, side * g), Vector3(0, 0, -side), "edge_ridge_topper" + pitch)
	# Each end's two sloped undersides, as edges (see _edge_sockets) in the end's upright plane: a
	# wall piece there runs along Z (turned -90°), lying under the topper
	var kind := "edge_slope" + pitch
	for x in [-GRID / 2.0, GRID / 2.0]:
		for side in [-1.0, 1.0]:
			var a := Vector3(x, 0, side * g)
			var b := Vector3(x, peak, 0)
			var dir := (b - a).normalized()
			var inward := dir.cross(Vector3.RIGHT)
			if inward.y < 0.0:
				inward = -inward
			var length := a.distance_to(b)
			# At both ends and every 0.5 m of run; capped at the peak: a gable under it may run on
			# below its low end, never past its peak
			var spots: Array[float] = []
			var run := 0.0
			while run < g - 0.01:
				spots.append(run / g * length)
				run += EDGE_STEP
			spots.append(length)
			for t in spots:
				d["sockets"].append({"position": a + dir * t, "yaw": -PI / 2.0, "type": kind,
					"edge_dir": dir, "edge_t": t, "edge_len": length, "edge_in": inward, "edge_cap": true})
	d["roof"] = true


# A roof topper's two slabs back to back (see _topper), from -x to x along the ridge, solid
static func _topper_slabs(d: Dictionary, rise: float, x: float) -> void:
	var st: SurfaceTool = d["surface"]
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	var g := TOPPER_GAP / 2.0
	var peak := g * rise / GRID
	var halves := [
		PackedVector2Array([Vector2(-g, 0), Vector2(0, peak), Vector2(0, peak + lift), Vector2(-g, lift)]),
		PackedVector2Array([Vector2(0, peak), Vector2(g, 0), Vector2(g, lift), Vector2(0, peak + lift)]),
	]
	for section in halves:
		var at := -x
		while at < x - 0.001:
			var board := floori(at / BOARD + 0.001)
			var next := minf((board + 1) * BOARD, x)
			_prism_x(st, section, at, next, _board_color(ROOF_COLOR, board))
			at = next
		var points := PackedVector3Array()
		for p in section:
			points.append(Vector3(-x, p.y, p.x))
			points.append(Vector3(x, p.y, p.x))
		var solid := ConvexPolygonShape3D.new()
		solid.points = points
		_collision(d, solid, Transform3D.IDENTITY)


# A topper overhang: carries a roof topper's end on past the gable wall, OVERHANG long (along X,
# centred on its origin), the topper's two slabs with a barge board down both sides of each slope
# (the inner ones tuck under the topper's end, so the same piece fits either end). Its origin is
# level with the topper's, so beside it the gable overhangs on the roofs either side run on in line
# with its slopes. Snaps by either end to a topper's end.
static func _topper_overhang(d: Dictionary, rise: float, pitch: String) -> void:
	var half := OVERHANG / 2.0
	var g := TOPPER_GAP / 2.0
	var k := rise / GRID
	var peak := g * k
	_topper_slabs(d, rise, half)
	# Barge boards: a roof's barge-board section over its top TOPPER_GAP / 2, moved onto each slope
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	var section := _slab_section(GRID - g, GRID, rise, FASCIA_DROP, lift - 0.005)
	for side in [-1.0, 1.0]:
		var moved := PackedVector2Array()
		for p in section:
			moved.append(Vector2(-side * (p.x - GRID), p.y - (GRID - g) * k))
		if side > 0.0:
			moved.reverse()
		for x_side in [-1.0, 1.0]:
			var x: float = x_side * half
			var x_out: float = x + x_side * FASCIA_THICKNESS
			_prism_x(d["surface"], moved, minf(x, x_out), maxf(x, x_out), FASCIA_COLOR)
	_socket(d, Vector3(-half, peak, 0), -PI / 2.0, "topper_overhang_end")
	_socket(d, Vector3(half, peak, 0), PI / 2.0, "topper_overhang_end")
	# (like the other overhangs, not roof for shelter)
	d["overhang"] = true


# A topper gable: the triangle under a roof topper's end, TOPPER_GAP wide along the bottom (at the
# roofs' high edges' height) and peaking under the topper's peak, in a wall's upright plane. It
# meets the topper's sloped undersides edge to edge (see _edge_sockets), stands on wall tops like a
# gable, and its bottom corners snap onto the tops of the gables' upright edges below (between the
# two gables under the roofs on either side).
static func _topper_gable(d: Dictionary, rise: float) -> void:
	var g := TOPPER_GAP / 2.0
	var peak := g * rise / GRID
	var outline := PackedVector2Array([Vector2(-g, 0), Vector2(g, 0), Vector2(0, peak)])
	_outline_wall(d, outline)
	_edge_sockets(d, outline, false)
	_socket(d, Vector3.ZERO, 0.0, "gable_base")
	_socket(d, Vector3(-g, 0, 0), -PI / 2.0, "topper_gable_corner")
	_socket(d, Vector3(g, 0, 0), PI / 2.0, "topper_gable_corner")


# A hip end: closes the top of a hip roof's end on a building an odd number of tiles across (3
# tiles, 6 m: the side roofs stop TOPPER_GAP apart, as under a roof topper). It covers the 2 m
# square between the side roofs' high edges, from the high edge of the end roof panel below it
# (z = 0, its origin at the middle of that edge, at the underside) to z = 2. Its underside is the
# lower of the end's slope (rising with z) and the side roofs' slopes (rising toward the middle):
# a three-faced hip top, the two hip lines rising from its low corners (on the tops of the hip
# corners below) to its apex 1 m in, on the middle, the ridge running on from there to its far
# edge, which has a roof topper's cross-section, so toppers carry the ridge on from it. (Close up,
# hip logs run up both hip lines to the apex and the ridge log on from it; see PieceDetail.)
#   - It sits on the end roof panel's high edge (as a roof row stacks on the one below), its sides
#     along the side roofs' high edges, and toppers go on its far end (topper_end).
static func _hip_end(d: Dictionary, rise: float, pitch: String) -> void:
	var k := rise / GRID
	var lift := ROOF_THICKNESS / cos(atan2(rise, GRID))
	for facet in hip_end_facets():
		var outline: PackedVector2Array = facet
		var low := []
		var high := []
		for p in outline:
			var h := hip_end_height(p, k)
			low.append(Vector3(p.x, h, p.y))
			high.append(Vector3(p.x, h + lift, p.y))
		_slab_facet(d, low, high, _board_color(ROOF_COLOR, low.size() + 5))
	_socket(d, Vector3.ZERO, PI, "roof_low")
	for side in [-1.0, 1.0]:
		_socket(d, Vector3(side, 0, GRID / 2.0), side * PI / 2.0, "hip_end_side" + pitch)
	_socket(d, Vector3(0, k, GRID), 0.0, "topper_end")
	# Its low corners, on the tops of the hip corners below (where the hip lines carry on up)
	for side in [-1.0, 1.0]:
		_socket(d, Vector3(side, 0, 0), 0.0, "hip_end_foot" + pitch)
	d["roof"] = true
	# Its sides fit any side roof's high edge; the right place also lands it on the end roof's high
	# edge and the hip corners' tops (see PiecePlacer._snap_by_anchors)
	d["anchored"] = true


## A hip end's three faces, as outlines seen from above (x, z): the end's face, then the left and
## right side roofs' faces
static func hip_end_facets() -> Array:
	return [
		PackedVector2Array([Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]),
		PackedVector2Array([Vector2(-1, 0), Vector2(0, 1), Vector2(0, GRID), Vector2(-1, GRID)]),
		PackedVector2Array([Vector2(1, 0), Vector2(1, GRID), Vector2(0, GRID), Vector2(0, 1)]),
	]


## A hip end's underside height at (x, z): the lower of the end's slope and the side roofs'
static func hip_end_height(p: Vector2, k: float) -> float:
	return minf(p.y * k, (1.0 - absf(p.x)) * k)


# One flat face of a roof slab: its underside and top outlines (the same points, the top `lift`
# above), with the faces between them all round, solid
static func _slab_facet(d: Dictionary, low: Array, high: Array, color: Color) -> void:
	var st: SurfaceTool = d["surface"]
	var up: Vector3 = ((high[1] as Vector3) - (high[0] as Vector3)).cross((high[2] as Vector3) - (high[0] as Vector3)).normalized()
	if up.y < 0.0:
		up = -up
	for i in range(1, low.size() - 1):
		_triangle(st, high[0], high[i], high[i + 1], up, color)
		_triangle(st, low[0], low[i], low[i + 1], -up, color)
	var middle := Vector3.ZERO
	for p in low:
		middle += (p as Vector3) / low.size()
	for i in low.size():
		var j := (i + 1) % low.size()
		var a: Vector3 = low[i]
		var b: Vector3 = low[j]
		var out := Vector3(b.z - a.z, 0, -(b.x - a.x)).normalized()
		if out.dot((a + b) / 2.0 - middle) < 0.0:
			out = -out
		_quad(st, a, b, high[j], high[i], out, color)
	var solid := ConvexPolygonShape3D.new()
	solid.points = PackedVector3Array(low + high)
	_collision(d, solid, Transform3D.IDENTITY)


# An upright wall of this outline ((x, y), on its centre line), WALL_THICKNESS thick, in level
# boards, solid as its outline
static func _outline_wall(d: Dictionary, outline: PackedVector2Array) -> void:
	var st: SurfaceTool = d["surface"]
	var middle := Vector2.ZERO
	var top := 0.0
	for p in outline:
		middle += p / outline.size()
		top = maxf(top, p.y)
	var t := WALL_THICKNESS / 2.0
	var k := 0
	var y := 0.0
	while y < top - 0.001:
		var band := _clip(outline, Vector2(0, 1), y, minf(y + BOARD, top))
		if band.size() >= 3:
			for side in [-1.0, 1.0]:
				_upright(st, band, side * t, Vector3.BACK * side, _board_color(WALL_COLOR, k))
		y += BOARD
		k += 1
	var points := PackedVector3Array()
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var out2 := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		if out2.dot((a + b) / 2.0 - middle) < 0.0:
			out2 = -out2
		_quad(st, Vector3(a.x, a.y, t), Vector3(b.x, b.y, t), Vector3(b.x, b.y, -t), Vector3(a.x, a.y, -t), Vector3(out2.x, out2.y, 0), WALL_COLOR)
		points.append(Vector3(a.x, a.y, t))
		points.append(Vector3(a.x, a.y, -t))
	var solid := ConvexPolygonShape3D.new()
	solid.points = points
	_collision(d, solid, Transform3D.IDENTITY)


# A level 2 m edge along X from `start`, as edge snap points (see _edge_sockets) at both ends and
# every EDGE_STEP: a roof's high edge, or a roof topper's low edge. `inward` is the way the piece
# lies from it.
static func _ridge_edge(d: Dictionary, start: Vector3, inward: Vector3, kind: String) -> void:
	var t := 0.0
	while t < GRID + 0.01:
		d["sockets"].append({"position": start + Vector3.RIGHT * t, "yaw": PI / 2.0, "type": kind,
			"edge_dir": Vector3.RIGHT, "edge_t": t, "edge_len": GRID, "edge_in": inward})
		t += EDGE_STEP


# A ridge cap: an upside-down V of boards, 2 m long, sitting over the ridge where two roofs of
# its pitch meet at their high edges
static func _ridge_cap(d: Dictionary, rise: float, pitch: String) -> void:
	var slope := atan2(rise, GRID)
	var lift := ROOF_THICKNESS / cos(slope)
	var reach := 0.4
	var thick := 0.06
	for side in [-1.0, 1.0]:
		# Each half lies on one roof's top, sloping down away from the ridge
		var basis := Basis(Vector3.RIGHT, slope * side)
		var center := Vector3(0, lift - reach / 2.0 * tan(slope), side * reach / 2.0) + basis.y * thick / 2.0
		_planked_box(d, Vector3(GRID, thick, reach / cos(slope) + 0.04), center, basis, ROOF_COLOR.darkened(0.15), 0, -GRID / 2.0)
	_socket(d, Vector3.ZERO, 0.0, "ridge_cap" + pitch)
	d["roof"] = true


# A square beam lying along X, 1 m or 2 m long, centred on its origin: snaps end to end, at its
# ends onto corners, edge middles and pole and pillar tops, and lying along a wall's top
static func _beam(d: Dictionary, length: float) -> void:
	_solid_box(d, Vector3(length, BEAM, BEAM), Transform3D.IDENTITY, LOG_COLOR)
	for side in [-1.0, 1.0]:
		_socket(d, Vector3(side * length / 2.0, 0, 0), side * PI / 2.0, "beam_end")
	_socket(d, Vector3(0, -BEAM / 2.0, 0), 0.0, "beam_under" if length > 1.5 else "beam_under_small")
	# Its top, to go under a roof's low edge or an eave's outer edge
	_socket(d, Vector3(0, BEAM / 2.0, 0), 0.0, "beam_top")
	# Its middle, for another beam crossing through it
	_socket(d, Vector3.ZERO, 0.0, "beam_mid")


# A diagonal beam climbing `rise` over 2 m along X (the slope of the 26° or 45° roof). Its box is a
# few millimetres off-centre front to back (z from -0.098 to 0.096), so a second one crossing it
# the other way (turned half round) has its faces just in front on one side and just behind on the
# other: never in the same plane, so they don't flicker. (A straight beam crossing it keeps ±0.1.)
static func _diagonal_beam(d: Dictionary, rise: float) -> void:
	var low := Vector3(-GRID / 2.0, 0, 0)
	var high := Vector3(GRID / 2.0, rise, 0)
	var basis := Basis(Vector3.BACK, atan2(rise, GRID))
	_solid_box(d, Vector3(low.distance_to(high), BEAM, BEAM - 0.006), Transform3D(basis, (low + high) / 2.0 + Vector3(0, 0, -0.001)), LOG_COLOR)
	_socket(d, low, -PI / 2.0, "beam_end")
	_socket(d, high, PI / 2.0, "beam_end")
	# Its middle, for another beam crossing through it (a second diagonal there makes an X)
	_socket(d, (low + high) / 2.0, 0.0, "beam_mid_diag")


# A square pole standing on its bottom middle, 1 m or 2 m tall, thinner than a pillar
static func _pole(d: Dictionary, length: float) -> void:
	_box_mesh(d["surface"], Vector3(POLE, length, POLE), Transform3D(Basis.IDENTITY, Vector3(0, length / 2.0, 0)), LOG_COLOR.lightened(0.05))
	var solid := BoxShape3D.new()
	solid.size = Vector3(POLE, length, POLE)
	_collision(d, solid, Transform3D(Basis.IDENTITY, Vector3(0, length / 2.0, 0)))
	_socket(d, Vector3.ZERO, 0.0, "pole_bottom")
	_socket(d, Vector3(0, length, 0), 0.0, "pole_top")


# A ladder 2 m tall and 0.6 m wide, standing on its bottom middle with its face toward +Z: on a
# floor edge, hanging from an upper floor's edge, or on top of another ladder. Climb it with W.
static func _ladder(d: Dictionary) -> void:
	var st: SurfaceTool = d["surface"]
	var width := 0.6
	for side in [-1.0, 1.0]:
		_box_mesh(st, Vector3(0.07, LADDER_HEIGHT, 0.07), Transform3D(Basis.IDENTITY, Vector3(side * (width / 2.0 - 0.035), LADDER_HEIGHT / 2.0, 0)), LOG_COLOR)
	var rung := 0.15
	while rung < LADDER_HEIGHT - 0.05:
		_box_mesh(st, Vector3(width - 0.07, 0.04, 0.05), Transform3D(Basis.IDENTITY, Vector3(0, rung, 0)), WALL_COLOR)
		rung += 0.3
	var solid := BoxShape3D.new()
	solid.size = Vector3(width, LADDER_HEIGHT, 0.08)
	_collision(d, solid, Transform3D(Basis.IDENTITY, Vector3(0, LADDER_HEIGHT / 2.0, 0)))
	_socket(d, Vector3.ZERO, 0.0, "ladder_base")
	_socket(d, Vector3(0, LADDER_HEIGHT, 0), 0.0, "ladder_top")


# A railing, 1 m high and 2 m or 1 m long: a post at each end with a top rail and a middle rail.
# It goes along floor edges (at their 1 m points for the short one) and wall tops, and end to end.
static func _railing(d: Dictionary, length: float) -> void:
	var st: SurfaceTool = d["surface"]
	var half := length / 2.0
	for x in [-half + 0.05, half - 0.05]:
		_box_mesh(st, Vector3(0.1, RAILING_HEIGHT, 0.1), Transform3D(Basis.IDENTITY, Vector3(x, RAILING_HEIGHT / 2.0, 0)), LOG_COLOR)
	if length > 1.5:
		_box_mesh(st, Vector3(0.08, RAILING_HEIGHT - 0.1, 0.08), Transform3D(Basis.IDENTITY, Vector3(0, (RAILING_HEIGHT - 0.1) / 2.0, 0)), LOG_COLOR)
	for y in [RAILING_HEIGHT - 0.06, RAILING_HEIGHT * 0.5]:
		_box_mesh(st, Vector3(length, 0.08, 0.06), Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), WALL_COLOR)
	var solid := BoxShape3D.new()
	solid.size = Vector3(length, RAILING_HEIGHT, 0.1)
	_collision(d, solid, Transform3D(Basis.IDENTITY, Vector3(0, RAILING_HEIGHT / 2.0, 0)))
	_socket(d, Vector3.ZERO, 0.0, "railing_base" if length > 1.5 else "small_railing_base")
	_socket(d, Vector3(half, 0, 0), PI / 2.0, "wall_end")
	_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")


# A 2 m picket fence, 1.4 m high: two rails with pointed pickets, lashed with rope. It stands on
# the ground or along floor edges, and chains end to end.
static func _fence(d: Dictionary) -> void:
	var st: SurfaceTool = d["surface"]
	var half := GRID / 2.0
	for y in [0.35, FENCE_HEIGHT - 0.35]:
		_box_mesh(st, Vector3(GRID, 0.08, 0.06), Transform3D(Basis.IDENTITY, Vector3(0, y, -0.06)), LOG_COLOR)
	var x := -half + 0.1
	var k := 0
	while x < half:
		var color := _board_color(WALL_COLOR, k)
		_box_mesh(st, Vector3(0.12, FENCE_HEIGHT - 0.1, 0.04), Transform3D(Basis.IDENTITY, Vector3(x, (FENCE_HEIGHT - 0.1) / 2.0, 0)), color)
		var tip := Vector3(x, FENCE_HEIGHT - 0.1, 0)
		_triangle(st, tip + Vector3(-0.06, 0, 0.02), tip + Vector3(0.06, 0, 0.02), tip + Vector3(0, 0.1, 0.02), Vector3.BACK, color)
		_triangle(st, tip + Vector3(-0.06, 0, -0.02), tip + Vector3(0.06, 0, -0.02), tip + Vector3(0, 0.1, -0.02), Vector3.FORWARD, color)
		x += 0.2
		k += 1
	var solid := BoxShape3D.new()
	solid.size = Vector3(GRID, FENCE_HEIGHT, 0.12)
	_collision(d, solid, Transform3D(Basis.IDENTITY, Vector3(0, FENCE_HEIGHT / 2.0, -0.02)))
	_socket(d, Vector3.ZERO, 0.0, "railing_base")
	_socket(d, Vector3(half, 0, 0), PI / 2.0, "wall_end")
	_socket(d, Vector3(-half, 0, 0), -PI / 2.0, "wall_end")


# ---- Furniture ----
#
# Simple placeholder shapes standing on their bottom middle, front toward +Z. Each is solid as one
# box (its overall size), rests on the floor or ground under it (see PiecePlacer), and counts toward
# plot requirements by its name.

const BED_SIZE := Vector3(1.0, 0.6, 2.0)
const BLANKET_COLOR := Color(0.5, 0.24, 0.2)
const LINEN_COLOR := Color(0.86, 0.82, 0.7)
const WICKER_COLOR := Color(0.74, 0.6, 0.37)
const BARK_COLOR := Color(0.36, 0.25, 0.16)
const IRON_COLOR := Color(0.32, 0.32, 0.34)
const SOOT_COLOR := Color(0.08, 0.07, 0.06)


## The solid box (width, height, depth) of furniture shown as a Meshy model: each model's own
## proportions at a sensible size, standing on its bottom middle with its back at -Z
const MODEL_BOXES := {
	"chopping_block": Vector3(0.65, 0.33, 0.65),
	"tool_rack": Vector3(1.3, 0.86, 0.31),
	"storage_shelf": Vector3(1.25, 1.17, 0.44),
	"fireplace": Vector3(1.4, 1.19, 0.91),
	# The Rustic Bed at a full 2 m long (its own proportions make it 1.34 m wide), headboard at -Z
	"bed": Vector3(1.34, 0.645, 2.0),
	# The Foraging Basket filling the 0.62 m footprint across its rope handle
	"foraging_basket": Vector3(0.62, 0.335, 0.55),
	# The Storehouse's stacked chests and sack (with the pitchfork leaning on them), 1.7 m across
	"storehouse_storage": Vector3(1.7, 1.442, 1.152),
	# The Stone Sorting Table (a table with baskets and a sack round it), as wide as the placeholder
	# was (1.6 m), at its own proportions: the placeholder's 0.8 m depth would have squeezed it to a
	# 0.54 m high table
	"sorting_table": Vector3(1.6, 0.825, 1.26),
	# Decorative storage, each at its own proportions
	"firewood_rack": Vector3(1.4, 0.863, 1.06),
	"stone_ore_bin": Vector3(1.3, 0.574, 1.064),
	"slat_crate": Vector3(0.9, 0.454, 0.78),
	"woven_crate": Vector3(0.9, 0.454, 0.787),
	"woven_basket": Vector3(0.7, 0.33, 0.694),
}
## Extra models standing with a furniture piece's model, as part of it (see BuildPiece.fitted_model):
## shape -> [{"scene", "at" (its bottom middle, in the piece's space), "width" (fitted evenly to
## this), "turn", and optionally "fill" (a model sitting in it), "fill_size" (width, height: fitted
## to these, not evenly)}]. The sorting table's two woven baskets, which its Meshy model lost: herbs
## at the front right corner and plant fiber under the left end, on floor its model leaves free
## (mapped from the fitted model: its leg rails run along both ends and the front left corner is
## taken, so that basket stands just inside the left legs).
const MODEL_EXTRAS := {
	"sorting_table": [
		{"scene": "res://assets/buildables/woven_basket/woven_basket.fbx", "at": Vector3(0.48, 0, 0.42), "width": 0.38, "turn": 0.4,
			"fill": "res://assets/bushes/fern_clump.tscn", "fill_size": Vector2(0.3, 0.16)},
		{"scene": "res://assets/buildables/woven_basket/woven_basket.fbx", "at": Vector3(-0.2, 0, 0.3), "width": 0.38, "turn": -0.3,
			"fill": "res://assets/bushes/plant_fiber/plant_fiber.glb", "fill_size": Vector2(0.3, 0.13)},
	],
}
## Wall-mounted furniture: shape -> how high its bottom hangs above the wall's foot
const WALL_MOUNTS := {"tool_rack": 1.0}
## Models made facing another way, turned about their upright before fitting (radians): the bed
## model lies along X with its headboard at +X, so a quarter turn puts the headboard at -Z
const MODEL_TURNS := {
	"bed": PI / 2.0,
}
## Where the fireplace's flames burn, in its own space (inside the model's hearth)
const HEARTH_FIRE := Vector3(0, 0.2, 0.05)
## The middle of the top of the fireplace model's chimney stack, in the fireplace piece's space
## (measured from the fitted model), and the stack's width: chimney pieces are this square
const FIREPLACE_CHIMNEY := Vector3(-0.147, 1.187, -0.19)
const CHIMNEY_WIDTH := 0.41
## A chimney section's height, and the top's (the Stone Basin model scaled evenly to the width)
const CHIMNEY_SECTION_HEIGHT := 1.0
const CHIMNEY_TOP_HEIGHT := 0.402
## How each chimney model is fitted (see BuildPiece.fitted_model): its stone body's middle (x, z)
## and the range of heights kept (anything past them is flattened onto them, so the corner posts
## end flush with the stones and pieces stack without gaps), in the model's own units, and the
## scale that makes the body CHIMNEY_WIDTH square and a section CHIMNEY_SECTION_HEIGHT tall
const CHIMNEY_FITS := {
	"chimney_section": {"centre": Vector2(0.0, -0.003), "keep": Vector2(-0.476, 0.425), "scale": Vector3(0.6766, 1.1099, 0.7009)},
	"chimney_top": {"centre": Vector2(-0.006, -0.037), "keep": Vector2(-0.369, 0.358), "scale": Vector3(0.5578, 0.554, 0.5503)},
}


static func _furniture(d: Dictionary, shape: String) -> void:
	var st: SurfaceTool = d["surface"]
	var size := Vector3.ONE
	match shape:
		"bed":
			size = BED_SIZE
			_box_mesh(st, Vector3(1.0, 0.3, 2.0), _at(0, 0.15, 0), LOG_COLOR)
			_box_mesh(st, Vector3(1.0, 0.85, 0.08), _at(0, 0.425, -0.96), LOG_COLOR.darkened(0.1))
			_box_mesh(st, Vector3(0.9, 0.14, 1.88), _at(0, 0.37, 0.02), LINEN_COLOR)
			_box_mesh(st, Vector3(0.94, 0.08, 1.2), _at(0, 0.47, 0.34), BLANKET_COLOR)
			_box_mesh(st, Vector3(0.6, 0.1, 0.32), _at(0, 0.49, -0.7), LINEN_COLOR.lightened(0.1))
		"foraging_basket":
			size = Vector3(0.62, 0.5, 0.62)
			for k in 3:
				_box_mesh(st, Vector3(0.6 - k * 0.02, 0.15, 0.6 - k * 0.02), _at(0, 0.075 + k * 0.15, 0), _board_color(WICKER_COLOR, k * 5 + 1))
			_box_mesh(st, Vector3(0.64, 0.05, 0.64), _at(0, 0.475, 0), WICKER_COLOR.darkened(0.2))
			for p in [Vector3(-0.12, 0.47, 0.08), Vector3(0.1, 0.48, -0.06), Vector3(0.02, 0.5, 0.14)]:
				_box_mesh(st, Vector3(0.12, 0.08, 0.12), _at(p.x, p.y, p.z), Color(0.62, 0.12, 0.14))
		"chopping_block":
			size = Vector3(0.6, 0.55, 0.6)
			_box_mesh(st, Vector3(0.56, 0.48, 0.56), _at(0, 0.24, 0), BARK_COLOR)
			_box_mesh(st, Vector3(0.5, 0.04, 0.5), _at(0, 0.5, 0), Color(0.78, 0.64, 0.44))
			# An axe stuck in the top
			var tilt := Transform3D(Basis(Vector3.BACK, 0.5), Vector3(0.08, 0.72, 0))
			_box_mesh(st, Vector3(0.05, 0.5, 0.05), tilt, WALL_COLOR)
			_box_mesh(st, Vector3(0.18, 0.1, 0.03), tilt * Transform3D(Basis.IDENTITY, Vector3(-0.05, -0.22, 0)), IRON_COLOR)
		"tool_rack":
			size = Vector3(1.3, 1.6, 0.4)
			for x in [-0.6, 0.6]:
				_box_mesh(st, Vector3(0.08, 1.6, 0.08), _at(x, 0.8, 0), LOG_COLOR)
				_box_mesh(st, Vector3(0.1, 0.06, 0.4), _at(x, 0.03, 0), LOG_COLOR.darkened(0.15))
			for y in [0.6, 1.3]:
				_box_mesh(st, Vector3(1.3, 0.06, 0.06), _at(0, y, 0.05), WALL_COLOR)
			# Tools hanging from the top bar
			for i in 4:
				var x := -0.42 + i * 0.28
				_box_mesh(st, Vector3(0.04, 0.7, 0.04), _at(x, 0.95, 0.1), WALL_COLOR.darkened(0.1))
				_box_mesh(st, Vector3(0.16 if i % 2 == 0 else 0.08, 0.1, 0.04), _at(x, 1.25, 0.1), IRON_COLOR)
		"sorting_table":
			size = Vector3(1.6, 0.9, 0.8)
			_box_mesh(st, Vector3(1.6, 0.08, 0.8), _at(0, 0.76, 0), WALL_COLOR)
			for x in [-0.72, 0.72]:
				for z in [-0.32, 0.32]:
					_box_mesh(st, Vector3(0.08, 0.72, 0.08), _at(x, 0.36, z), LOG_COLOR)
			# Stones sorted into piles on top
			var piles := [Vector3(-0.5, 0, 0), Vector3(0.0, 0, 0.1), Vector3(0.5, 0, -0.05)]
			for i in piles.size():
				for k in 3:
					var p: Vector3 = piles[i] + Vector3((k - 1) * 0.09, 0.84 + (k % 2) * 0.03, (k % 2) * 0.08)
					var s := 0.16 - i * 0.03
					_box_mesh(st, Vector3(s, s * 0.7, s), _at(p.x, p.y, p.z), _board_color(STONE_COLOR, i * 7 + k))
		"storage_shelf":
			size = Vector3(1.25, 1.8, 0.5)
			for x in [-0.6, 0.6]:
				_box_mesh(st, Vector3(0.05, 1.8, 0.5), _at(x, 0.9, 0), LOG_COLOR)
			_box_mesh(st, Vector3(1.2, 1.8, 0.03), _at(0, 0.9, -0.235), WALL_COLOR.darkened(0.2))
			for y in [0.04, 0.62, 1.2, 1.78]:
				_box_mesh(st, Vector3(1.2, 0.04, 0.48), _at(0, y, 0), WALL_COLOR)
			# Crates and sacks on the shelves
			for y in [0.06, 0.64, 1.22]:
				_box_mesh(st, Vector3(0.36, 0.3, 0.36), _at(-0.3, y + 0.15, 0), _board_color(FLOOR_COLOR, int(y * 10)))
				_box_mesh(st, Vector3(0.3, 0.26, 0.3), _at(0.28, y + 0.13, 0.02), LINEN_COLOR.darkened(0.25))
		"fireplace":
			size = Vector3(1.4, 2.4, 0.9)
			_box_mesh(st, Vector3(1.4, 0.15, 0.9), _at(0, 0.075, 0), _board_color(STONE_COLOR, 2))
			for x in [-0.55, 0.55]:
				_box_mesh(st, Vector3(0.3, 0.9, 0.8), _at(x, 0.6, -0.05), _board_color(STONE_COLOR, 5 if x < 0.0 else 9))
			_box_mesh(st, Vector3(1.4, 0.3, 0.85), _at(0, 1.2, -0.025), _board_color(STONE_COLOR, 13))
			_box_mesh(st, Vector3(0.8, 0.9, 0.1), _at(0, 0.6, -0.4), SOOT_COLOR)
			_box_mesh(st, Vector3(0.8, 0.05, 0.6), _at(0, 0.175, -0.1), SOOT_COLOR.lightened(0.05))
			_box_mesh(st, Vector3(0.8, 1.05, 0.55), _at(0, 1.875, -0.15), _board_color(STONE_COLOR, 21))
			# A few logs in the hearth
			_box_mesh(st, Vector3(0.6, 0.1, 0.12), _at(0, 0.25, -0.05), BARK_COLOR)
			_box_mesh(st, Vector3(0.12, 0.1, 0.5), _at(0.1, 0.33, -0.08), BARK_COLOR.lightened(0.1))
		_:
			# Model-only furniture: a plain box the model's size (only seen if the model is missing)
			size = MODEL_BOXES.get(shape, size)
			_box_mesh(st, size, _at(0, size.y / 2.0, 0), _board_color(FLOOR_COLOR, 3))
	var solid := BoxShape3D.new()
	# Furniture shown as a model is solid as the model's own box, so it collides, backs up to walls
	# and fits where it looks like it does (BuildPiece fits the model into this box)
	size = MODEL_BOXES.get(shape, size)
	solid.size = size
	_collision(d, solid, _at(0, size.y / 2.0, 0))
	d["model_turn"] = MODEL_TURNS.get(shape, 0.0)
	d["model_extras"] = MODEL_EXTRAS.get(shape, [])
	d["furniture"] = true
	d["hearth_at"] = HEARTH_FIRE
	if shape == "fireplace":
		# The top of its chimney, where chimney sections and tops stack
		_socket(d, FIREPLACE_CHIMNEY, 0.0, "chimney_spot")
	# These back up flush against a wall when placed near one (their back is -Z)
	d["backs_to_wall"] = shape in ["bed", "storage_shelf", "tool_rack", "storehouse_storage", "firewood_rack"]
	# Hung on a wall rather than standing: how far up its bottom is from the wall's foot (the tool
	# rack's 0.86 m spans 1.0 to 1.86 m, its pegs about 1.2 to 1.6 m up; Page Up/Down moves it)
	d["wall_mount"] = WALL_MOUNTS.get(shape, 0.0)
	# The fireplace burns and warms like a campfire (see BuildPiece)
	d["hearth"] = shape == "fireplace"


# A chimney section or top: solid as a CHIMNEY_WIDTH square box standing on its bottom middle,
# shown as its fitted model. A section stacks on the fireplace's chimney or another section, the
# top on either. Chimneys pass through roofs (see PiecePlacer._check).
static func _chimney(d: Dictionary, shape: String) -> void:
	var top := shape == "chimney_top"
	var h := CHIMNEY_TOP_HEIGHT if top else CHIMNEY_SECTION_HEIGHT
	var solid := BoxShape3D.new()
	solid.size = Vector3(CHIMNEY_WIDTH, h, CHIMNEY_WIDTH)
	_collision(d, solid, _at(0, h / 2.0, 0))
	# A plain stone box, only shown if the model is missing
	_box_mesh(d["surface"], solid.size, _at(0, h / 2.0, 0), STONE_COLOR)
	_socket(d, Vector3.ZERO, 0.0, "chimney_cap_base" if top else "chimney_base")
	if not top:
		_socket(d, Vector3(0, h, 0), 0.0, "chimney_spot")
	d["chimney"] = true
	d["chimney_height"] = h
	d["model_fit"] = CHIMNEY_FITS[shape]


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## The box round every solid part of a shape (from build()), in the piece's own space
static func bounds_of(def: Dictionary) -> AABB:
	var box := AABB()
	var first := true
	for part in def["collision"]:
		var shape: Shape3D = part["shape"]
		var local := AABB()
		if shape is BoxShape3D:
			local = AABB(-(shape as BoxShape3D).size / 2.0, (shape as BoxShape3D).size)
		elif shape is ConvexPolygonShape3D:
			var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
			local = AABB(pts[0], Vector3.ZERO)
			for p in pts:
				local = local.expand(p)
		else:
			continue
		local = (part["transform"] as Transform3D) * local
		box = local if first else box.merge(local)
		first = false
	return box


# One solid box, drawn in a single colour, with matching collision
static func _solid_box(d: Dictionary, size: Vector3, xform: Transform3D, color: Color) -> void:
	_box_mesh(d["surface"], size, xform, color)
	var solid := BoxShape3D.new()
	solid.size = size
	_collision(d, solid, xform)


# A flat shape standing upright at depth z, given as (x, y) corners, facing `normal`
static func _upright(st: SurfaceTool, corners: PackedVector2Array, z: float, normal: Vector3, color: Color) -> void:
	for i in range(1, corners.size() - 1):
		_triangle(st, Vector3(corners[0].x, corners[0].y, z), Vector3(corners[i].x, corners[i].y, z), Vector3(corners[i + 1].x, corners[i + 1].y, z), normal, color)


# A square pillar 2.5 m tall standing on its bottom middle: a wooden post, or stacked stone blocks
static func _pillar(d: Dictionary, stone: bool) -> void:
	var st: SurfaceTool = d["surface"]
	var w := STONE_PILLAR if stone else WOOD_PILLAR
	var solid := BoxShape3D.new()
	solid.size = Vector3(w, PILLAR_HEIGHT, w)
	_collision(d, solid, Transform3D(Basis.IDENTITY, Vector3(0, PILLAR_HEIGHT / 2.0, 0)))
	if stone:
		_box_mesh(st, Vector3(w - 0.04, PILLAR_HEIGHT, w - 0.04), Transform3D(Basis.IDENTITY, Vector3(0, PILLAR_HEIGHT / 2.0, 0)), MORTAR_COLOR)
		var blocks := roundi(PILLAR_HEIGHT / COURSE)
		for k in blocks:
			var turn := Basis(Vector3.UP, (k % 2) * PI / 2.0)
			_box_mesh(st, Vector3(w, COURSE - 0.03, w), Transform3D(turn, Vector3(0, COURSE * (k + 0.5), 0)), _board_color(STONE_COLOR, k * 17 + 3))
	else:
		# A post of two boards side by side, with a slightly darker cap and foot
		for side in [-1.0, 1.0]:
			_box_mesh(st, Vector3(w / 2.0, PILLAR_HEIGHT - 0.2, w), Transform3D(Basis.IDENTITY, Vector3(side * w / 4.0, PILLAR_HEIGHT / 2.0, 0)), _board_color(WALL_COLOR, 3 if side > 0.0 else 4))
		for y in [0.05, PILLAR_HEIGHT - 0.05]:
			_box_mesh(st, Vector3(w + 0.04, 0.1, w + 0.04), Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), LOG_COLOR.darkened(0.15))
	_socket(d, Vector3.ZERO, 0.0, "pillar_base")
	_socket(d, Vector3(0, PILLAR_HEIGHT, 0), 0.0, "pillar_top")
	d["clear_radius"] = 0.6


# "floor", "wood" or "stone", from a piece's shape name
static func _kind_of(shape: String) -> String:
	if shape.begins_with("floor"):
		return "floor"
	return "stone" if shape.contains("stone") else "wood"


# Half a 2 m square, cut corner to corner: two 2 m sides at a right angle and a long side of
# LONG_EDGE. Corners in order, around the middle (its origin).
static func _right_triangle() -> PackedVector2Array:
	return _around_middle(PackedVector2Array([Vector2(0, 0), Vector2(GRID, 0), Vector2(0, GRID)]))


# Two 2 m sides meeting at 45° (and a short side of SHORT_EDGE): the gap between two squares
# turned 45° to each other. Squares and these together make an octagon.
static func _triangle_45() -> PackedVector2Array:
	var a := deg_to_rad(22.5)
	return _around_middle(PackedVector2Array([Vector2.ZERO, Vector2(GRID * sin(-a), GRID * cos(a)), Vector2(GRID * sin(a), GRID * cos(a))]))


static func _around_middle(points: PackedVector2Array) -> PackedVector2Array:
	var middle := Vector2.ZERO
	for p in points:
		middle += p
	middle /= points.size()
	var moved := PackedVector2Array()
	for p in points:
		moved.append(p - middle)
	return moved


# A triangle floor or foundation. `corners` are (x, z) around its origin; `edge_types` gives each
# edge's snap point type, edge i running from corner i to corner i + 1. `family` names its
# foundations' own stacking snap points.
static func _triangle_piece(d: Dictionary, corners: PackedVector2Array, edge_types: Array, kind: String, family: String) -> void:
	var st: SurfaceTool = d["surface"]
	var foundation := kind != "floor"
	var top := 0.0
	var bottom := -FOUNDATION_DEPTH if foundation else -FLOOR_THICKNESS
	# The top: boards in strips (or stone flags in squares), cut to the triangle
	var cells := []
	if kind == "stone":
		for i in range(-4, 4):
			for j in range(-4, 4):
				var cell := _clip(_clip(corners, Vector2.RIGHT, i * 0.5 + 0.015, (i + 1) * 0.5 - 0.015), Vector2.DOWN * -1.0, j * 0.5 + 0.015, (j + 1) * 0.5 - 0.015)
				if cell.size() >= 3:
					cells.append([cell, _board_color(STONE_COLOR.lightened(0.05), i * 8 + j + 60)])
		_flat(st, corners, top - 0.005, MORTAR_COLOR, 1.0)
	else:
		for i in range(-8, 8):
			var strip := _clip(corners, Vector2.RIGHT, i * BOARD, (i + 1) * BOARD)
			if strip.size() >= 3:
				cells.append([strip, _board_color(FLOOR_COLOR, i)])
	for cell in cells:
		_flat(st, cell[0], top, cell[1], 1.0)
	_flat(st, corners, bottom, FLOOR_COLOR if not foundation else MORTAR_COLOR, -1.0)
	# The sides, and the snap points along each edge
	var points := PackedVector3Array()
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var mid := (a + b) / 2.0
		var out2 := Vector2(b.y - a.y, -(b.x - a.x)).normalized()
		if out2.dot(mid) < 0.0:
			out2 = -out2
		var out := Vector3(out2.x, 0, out2.y)
		_triangle_side(st, a, b, out, top, bottom, kind)
		_socket(d, Vector3(mid.x, 0, mid.y), _yaw(out), edge_types[i])
		_socket(d, Vector3(a.x, 0, a.y), 0.0, "post_spot")
		_socket(d, Vector3(mid.x, 0, mid.y), 0.0, "post_spot")
		points.append(Vector3(a.x, top, a.y))
		points.append(Vector3(a.x, bottom, a.y))
	var solid := ConvexPolygonShape3D.new()
	solid.points = points
	_collision(d, solid, Transform3D.IDENTITY)
	_edge_sockets(d, corners, true)
	if foundation:
		_socket(d, Vector3.ZERO, 0.0, family + "_foundation_top")
		_socket(d, Vector3(0, bottom, 0), 0.0, family + "_foundation_base")
		d["free_lift"] = FOUNDATION_LIFT
	var reach := 0.0
	for p in corners:
		reach = maxf(reach, p.length())
	d["floor"] = true
	d["clear_radius"] = reach + 0.1


# One side of a triangle piece, from corner a to corner b: a plain floor edge, or a foundation's
# courses of logs or stone blocks
static func _triangle_side(st: SurfaceTool, a: Vector2, b: Vector2, out: Vector3, top: float, bottom: float, kind: String) -> void:
	var pa := Vector3(a.x, 0, a.y)
	var pb := Vector3(b.x, 0, b.y)
	if kind == "floor":
		_quad(st, pa + Vector3.UP * top, pb + Vector3.UP * top, pb + Vector3.UP * bottom, pa + Vector3.UP * bottom, out, FLOOR_COLOR)
		return
	var length := a.distance_to(b)
	var along := (pb - pa) / length
	_quad(st, pa + Vector3.UP * top, pb + Vector3.UP * top, pb + Vector3.UP * bottom, pa + Vector3.UP * bottom, out, MORTAR_COLOR if kind == "stone" else LOG_COLOR.darkened(0.4))
	var lift := out * 0.01
	var courses := roundi((top - bottom) / COURSE)
	for k in courses:
		var y1 := top - COURSE * k
		var y0 := y1 - COURSE
		if kind == "stone":
			# Blocks half a meter long, every other course shifted by half a block
			var x := -0.25 if k % 2 == 1 else 0.0
			var n := 0
			while x < length - 0.001:
				var x0 := maxf(x, 0.0) + 0.015
				var x1 := minf(x + 0.5, length) - 0.015
				if x1 > x0:
					var p0 := pa + along * x0 + lift
					var p1 := pa + along * x1 + lift
					_quad(st, p0 + Vector3.UP * (y1 - 0.015), p1 + Vector3.UP * (y1 - 0.015), p1 + Vector3.UP * (y0 + 0.015), p0 + Vector3.UP * (y0 + 0.015), out, _board_color(STONE_COLOR, k * 31 + n * 5))
				x += 0.5
				n += 1
		else:
			var middle := (y0 + y1) / 2.0
			_quad(st, pa + lift + Vector3.UP * (middle + COURSE * 0.3), pb + lift + Vector3.UP * (middle + COURSE * 0.3), pb + lift + Vector3.UP * (middle - COURSE * 0.3), pa + lift + Vector3.UP * (middle - COURSE * 0.3), out, _board_color(LOG_COLOR, k))


# A flat convex shape at height y, facing up (+1) or down (-1)
static func _flat(st: SurfaceTool, corners: PackedVector2Array, y: float, color: Color, facing: float) -> void:
	for i in range(1, corners.size() - 1):
		_triangle(st, Vector3(corners[0].x, y, corners[0].y), Vector3(corners[i].x, y, corners[i].y), Vector3(corners[i + 1].x, y, corners[i + 1].y), Vector3.UP * facing, color)


# The part of a convex shape between two lines across it: where `direction` · point is between
# `low` and `high`
static func _clip(corners: PackedVector2Array, direction: Vector2, low: float, high: float) -> PackedVector2Array:
	return _clip_side(_clip_side(corners, direction, low), -direction, -high)


# The part of a convex shape where `direction` · point >= `limit`
static func _clip_side(corners: PackedVector2Array, direction: Vector2, limit: float) -> PackedVector2Array:
	var kept := PackedVector2Array()
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var da := a.dot(direction) - limit
		var db := b.dot(direction) - limit
		if da >= 0.0:
			kept.append(a)
		if (da >= 0.0) != (db >= 0.0):
			kept.append(a.lerp(b, da / (da - db)))
	return kept


# ---- Building blocks ----

# A round log (an eight-sided prism) from one end point to the other, with its ends capped
static func _log(st: SurfaceTool, a: Vector3, b: Vector3, r: float, color: Color) -> void:
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along).normalized()
	var sides := 8
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var n0 := side * cos(t0) + up * sin(t0)
		var n1 := side * cos(t1) + up * sin(t1)
		_quad(st, a + n0 * r, b + n0 * r, b + n1 * r, a + n1 * r, (n0 + n1).normalized(), color)
		var end_color := color.lightened(0.25)
		_triangle(st, a, a + n0 * r, a + n1 * r, -along, end_color)
		_triangle(st, b, b + n0 * r, b + n1 * r, along, end_color)

static func _new_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _socket(d: Dictionary, position: Vector3, yaw: float, type: String) -> void:
	d["sockets"].append({"position": position, "yaw": yaw, "type": type})


## How far apart edge snap points are along an edge (a sloped edge: per this much of its run)
const EDGE_STEP := 0.5


# Snap points along every edge of a triangle-type piece, so its edges meet other triangles' edges
# whole (see fits and _edge_fit_ok): at both ends of each edge and every EDGE_STEP along it (along
# a sloped edge, every EDGE_STEP of its run, so they stay on the 0.5 m grid). `outline` is the
# piece's outline: in its upright plane (x, y) on its centre line for a wall piece, or across its
# top (x, z) for a floor or foundation (`flat`). Each point knows its edge: its kind ("edge_flat",
# "edge_vertical", "edge_slope_26", "edge_slope_45", or "edge_floor"), which way it runs
# ("edge_dir"), how far along it the point is ("edge_t") and how long it is ("edge_len"), and which
# way the piece lies from it ("edge_in").
static func _edge_sockets(d: Dictionary, outline: PackedVector2Array, flat: bool) -> void:
	var middle := Vector2.ZERO
	for p in outline:
		middle += p / outline.size()
	var to3 := func(p: Vector2) -> Vector3: return Vector3(p.x, 0, p.y) if flat else Vector3(p.x, p.y, 0)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var kind := "edge_floor"
		var steps := length
		if not flat:
			var run := absf(b.x - a.x)
			if run < 0.01:
				kind = "edge_vertical"
			elif absf(b.y - a.y) < 0.01:
				kind = "edge_flat"
			else:
				kind = "edge_slope_26" if absf(b.y - a.y) / run < 0.75 else "edge_slope_45"
				steps = run
		var dir: Vector3 = (to3.call(b) - to3.call(a)).normalized()
		# Toward the piece's middle, square to the edge, in its plane
		var along := (b - a).normalized()
		var across := Vector2(-along.y, along.x)
		if across.dot(middle - a) < 0.0:
			across = -across
		var inward: Vector3 = to3.call(across)
		var yaw := atan2(dir.x, dir.z) if flat else 0.0
		var at := 0.0
		var spots: Array[float] = []
		while at < steps - 0.01:
			spots.append(at * length / steps)
			at += EDGE_STEP
		spots.append(length)
		for t in spots:
			d["sockets"].append({"position": to3.call(a.lerp(b, t / length)), "yaw": yaw, "type": kind,
				"edge_dir": dir, "edge_t": t, "edge_len": length, "edge_in": inward})


# A fit of an edge snap point onto another (see fits) is kept only if the two edges really meet
# whole: they lie along one line (either way round), the shorter lies within the longer, and the
# two pieces are on opposite sides of it (or, for upright edges, the pieces meet at a corner).
# `placed` is the placed piece's point in world space (as BuildPiece.world_sockets gives it).
static func _edge_fit_ok(own: Dictionary, placed: Dictionary, where: Transform3D) -> bool:
	if not placed.has("edge_dir"):
		return true
	var mine_dir := where.basis * (own["edge_dir"] as Vector3)
	var their_dir: Vector3 = placed["edge_dir"]
	var c := mine_dir.dot(their_dir)
	if absf(c) < 0.999:
		return false
	var s := signf(c)
	var start: float = float(placed["edge_t"]) - s * float(own["edge_t"])
	var finish: float = start + s * float(own["edge_len"])
	var lo := minf(start, finish)
	var hi := maxf(start, finish)
	var length: float = placed["edge_len"]
	var inside := (lo > -0.005 and hi < length + 0.005) or (lo < 0.005 and hi > length - 0.005)
	if not inside:
		return false
	# An edge capped at its high end (a roof topper's underside, at its peak): nothing meeting it may
	# run on past that end (it would come up through the topper's other half)
	if placed.get("edge_cap", false) and hi > length + 0.005:
		return false
	if own.get("edge_cap", false):
		var high_end := start + s * float(own["edge_len"])
		if (s > 0.0 and length > high_end + 0.005) or (s < 0.0 and high_end > 0.005):
			return false
	var sides := (where.basis * (own["edge_in"] as Vector3)).dot(placed["edge_in"])
	if own["type"] == "edge_vertical" and absf(sides) < 0.1:
		return true
	return sides < -0.5


static func _collision(d: Dictionary, shape: Shape3D, xform: Transform3D, door := false) -> void:
	d["collision"].append({"shape": shape, "transform": xform, "door": door})


# A solid box drawn as boards side by side along one of its axes (0 = X, 1 = Y), each a slightly
# different shade. Board edges fall on multiples of BOARD measured from the piece's origin, so
# boards line up between neighbouring pieces. `start` is where the box begins along that axis.
static func _planked_box(d: Dictionary, size: Vector3, center: Vector3, basis: Basis, color: Color, axis: int, start: float, door := false, solid := true) -> void:
	var st: SurfaceTool = d["door_surface"] if door else d["surface"]
	var shape := BoxShape3D.new()
	shape.size = size
	if solid:
		_collision(d, shape, Transform3D(basis, center), door)
	var length: float = size[axis]
	var at := start
	while at < start + length - 0.001:
		var k := floori(at / BOARD + 0.001)
		var next := minf((k + 1) * BOARD, start + length)
		var board := size
		board[axis] = next - at
		var offset := Vector3.ZERO
		offset[axis] = (at + next) / 2.0 - (start + length / 2.0)
		_box_mesh(st, board, Transform3D(basis, center + basis * offset), _board_color(color, k))
		at = next


# A box's six faces, each with its outward normal
static func _box_mesh(st: SurfaceTool, size: Vector3, xform: Transform3D, color: Color) -> void:
	var h := size / 2.0
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for face in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		_quad(st, xform * (c - du - dv), xform * (c - du + dv), xform * (c + du + dv), xform * (c + du - dv), xform.basis * n, color)


# A flat four-sided face, with the normal it should have (its corners in either order)
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, e: Vector3, normal: Vector3, color: Color) -> void:
	_triangle(st, a, b, c, normal, color)
	_triangle(st, a, c, e, normal, color)


# One triangle, wound so it faces along `normal` (Godot draws clockwise faces as the front)
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var n := normal.normalized()
	if (b - a).cross(c - a).dot(n) > 0.0:
		var swap := b
		b = c
		c = swap
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(p)


# A strip of a curved surface at radius r between two angles and two heights, facing out (+1) or
# in (-1), with smooth normals
static func _arc_quad(st: SurfaceTool, r: float, a0: float, a1: float, y0: float, y1: float, color: Color, facing: float) -> void:
	var p := [_arc_point(r, a0, y0), _arc_point(r, a1, y0), _arc_point(r, a1, y1), _arc_point(r, a0, y1)]
	var n := [_arc_point(facing, a0, 0), _arc_point(facing, a1, 0), _arc_point(facing, a1, 0), _arc_point(facing, a0, 0)]
	var flip: bool = (p[1] - p[0]).cross(p[2] - p[0]).dot(n[0]) > 0.0
	for tri in ([[0, 2, 1], [0, 3, 2]] if flip else [[0, 1, 2], [0, 2, 3]]):
		for i in tri:
			st.set_normal(n[i])
			st.set_color(color)
			st.add_vertex(p[i])


# A flat curved band between radii r0 and r1 at height y, facing up (+1) or down (-1)
static func _ring_quad(st: SurfaceTool, r0: float, r1: float, a0: float, a1: float, y: float, color: Color, facing: float) -> void:
	_quad(st, _arc_point(r0, a0, y), _arc_point(r1, a0, y), _arc_point(r1, a1, y), _arc_point(r0, a1, y), Vector3.UP * facing, color)


# A point on a circle around the origin: angle 0 is +Z, turning toward +X
static func _arc_point(r: float, angle: float, y: float) -> Vector3:
	return Vector3(r * sin(angle), y, r * cos(angle))


# The direction along the circle at this angle, toward bigger angles
static func _tangent(angle: float) -> Vector3:
	return Vector3(cos(angle), 0, -sin(angle))


## The facing (yaw) of a direction: 0 is +Z, PI/2 is +X
static func _yaw(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


# A board's shade: each board a little lighter or darker, the same for the same board number
static func _board_color(base: Color, k: int) -> Color:
	var noise := fposmod(sin(k * 12.9898 + 4.1) * 43758.5453, 1.0)
	var k2 := 0.88 + 0.24 * noise
	return Color(base.r * k2, base.g * k2, base.b * k2)
