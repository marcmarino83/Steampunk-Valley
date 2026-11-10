class_name IconStudio
extends Node
## Renders the build menu's icons, all staged the same way, in an off-screen viewport:
##
##   - Camera: a three-quarter view from slightly above (VIEW), orthographic. Every icon in a build
##     tab uses that tab's scale (the tab's largest piece fills about FILL of the icon), so a 1 m wall
##     really looks half as wide as a 2 m one. The piece is centred.
##   - Light: a warm key, a soft cool fill and a subtle rim from behind, so edges stand out; a soft
##     dark vignette behind, in the brass UI's browns (see vignette(): drawn by the build slot
##     behind the transparent icon).
##   - Building pieces stand solid among faint, see-through outlines of the neighbours they attach
##     to (CONTEXT): an eave on the low edge of a faint roof, a gable on a faint wall under a faint
##     roof, a door in a faint doorway... each neighbour placed by the snap rules, so it sits where it
##     really would.
##   - Furniture, the workbench, chest and campfire stand on a small faint floor patch instead.
##   - A small corner badge for size or angle where it tells pieces apart (BADGES, badge_for(): the
##     build slot draws it as text over the corner, so it stays sharp at slot size).
##   - Rendered at RENDER_SIZE, saved at SAVED_SIZE (downscaled cleanly).
##
## IconUpdater uses it to re-render icons whose piece changed. Needs a screen.

const RENDER_SIZE := 512
const SAVED_SIZE := 256
## Looking down toward the piece from the front right, a little above
const VIEW := Vector3(1.0, 0.62, 1.3)
## How much of the icon a tab's largest piece fills
const FILL := 0.75
const GHOST_SHADER := preload("res://building/icons/icon_ghost.gdshader")
const GHOST_COLOR := Color(0.93, 0.87, 0.75, 1.0)
const PATCH_COLOR := Color(0.36, 0.26, 0.17, 0.3)
## The vignette behind: warm dark brown in the middle, fading out to nothing at the edges
const VIGNETTE_MIDDLE := Color(0.25, 0.19, 0.13, 0.95)
const VIGNETTE_EDGE := Color(0.07, 0.05, 0.04, 0.0)

## Neighbours shown faintly round a piece: shape (pattern) -> [entries]. Each entry places one
## neighbour by the snap rules, its `theirs` socket meeting the piece's `mine` (whichever way round
## the rule is written): "shape" (with {p} for the piece's pitch, 26 or 45; {roof} for the roof of
## its pitch), optional "of" (place it against an earlier neighbour, by index, instead of the
## piece), and "pick" (which of the possible fits: "far", "near", "back", "straight", "left",
## "right", "first"). An entry with "place": "over_gable" instead puts a roof over a gable's slope
## (no snap rule joins them directly). ("mode" only notes which way the rule runs.)
const CONTEXT := {
	"eave_{p}": [{"shape": "{roof}", "mode": "under", "mine": "eave_base_{p}", "theirs": "eave_spot_{p}"}],
	"eave_corner_{p}": [
		{"shape": "gable_overhang_{p}", "mode": "under", "mine": "corner_top_{p}", "theirs": "overhang_low_{p}"},
		{"shape": "{roof}", "mode": "on", "of": 0, "mine": "overhang_left_{p}", "theirs": "roof_side_right_{p}"},
		{"shape": "eave_{p}", "mode": "on", "of": 1, "mine": "eave_spot_{p}", "theirs": "eave_base_{p}"},
	],
	"gable_overhang_{p}": [{"shape": "{roof}", "mode": "under", "mine": "overhang_left_{p}", "theirs": "roof_side_right_{p}"}],
	"gable_{p}": [
		{"shape": "wall", "mode": "under", "mine": "gable_base", "theirs": "wall_top"},
		{"shape": "{roof}", "place": "over_gable"},
	],
	"ridge_{p}": [
		{"shape": "{roof}", "mode": "under", "mine": "ridge_cap_{p}", "theirs": "roof_high_{p}"},
		{"shape": "{roof}", "mode": "on", "of": 0, "mine": "roof_high_{p}", "theirs": "roof_high_{p}"},
	],
	"roof_inner_{p}": [
		{"shape": "{roof}", "mode": "on", "mine": "roof_side_right_{p}", "theirs": "roof_side_left_{p}"},
		{"shape": "{roof}", "mode": "on", "mine": "roof_side_left_{p}", "theirs": "roof_side_right_{p}"},
	],
	"roof_outer_{p}": [
		{"shape": "{roof}", "mode": "on", "mine": "roof_side_right_{p}", "theirs": "roof_side_left_{p}"},
		{"shape": "{roof}", "mode": "on", "mine": "roof_side_left_{p}", "theirs": "roof_side_right_{p}"},
	],
	"valley_eave_corner_{p}": [
		{"shape": "roof_inner_{p}", "mode": "under", "mine": "valley_eave_base_{p}", "theirs": "valley_eave_spot_{p}"},
		{"shape": "{roof}", "mode": "on", "of": 0, "mine": "roof_side_right_{p}", "theirs": "roof_side_left_{p}"},
		{"shape": "{roof}", "mode": "on", "of": 0, "mine": "roof_side_left_{p}", "theirs": "roof_side_right_{p}"},
		{"shape": "eave_{p}", "mode": "on", "of": 1, "mine": "eave_spot_{p}", "theirs": "eave_base_{p}"},
		{"shape": "eave_{p}", "mode": "on", "of": 2, "mine": "eave_spot_{p}", "theirs": "eave_base_{p}"},
	],
	# A faint topper over the topper gable (its end on the gable's plane)
	"topper_gable_{p}": [{"shape": "topper_{p}", "place": "over_topper_gable"}],
	# A faint topper, the overhang carrying on past its end
	"topper_overhang_{p}": [{"shape": "topper_{p}", "mode": "under", "mine": "topper_overhang_end", "theirs": "topper_end"}],
	# Two faint roofs with the gap between them, the topper bridging it
	"topper_{p}": [
		{"shape": "{roof}", "mode": "under", "mine": "topper_low_{p}", "theirs": "roof_high_{p}", "pick": "back"},
		{"shape": "{roof}", "mode": "under", "mine": "topper_low_{p}", "theirs": "roof_high_{p}", "pick": "front"},
	],
	"outer_eave_corner_{p}": [
		{"shape": "roof_outer_{p}", "mode": "under", "mine": "outer_eave_base_{p}", "theirs": "outer_eave_spot_{p}"},
		{"shape": "eave_{p}", "mode": "on", "of": 0, "mine": "eave_spot_{p}", "theirs": "eave_base_{p}", "pick": "left"},
		{"shape": "eave_{p}", "mode": "on", "of": 0, "mine": "eave_spot_{p}", "theirs": "eave_base_{p}", "pick": "right"},
	],
	# A split-window wall with its mirrored partner, making one window
	"window_split_2": [{"shape": "window_split_2", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "opposite"}],
	"window_split_1": [{"shape": "window_split_1", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "opposite"}],
	"door": [{"shape": "doorway", "mode": "under", "mine": "door_base", "theirs": "door_slot"}],
	"stairs": [{"shape": "floor", "mode": "under", "mine": "stairs_top", "theirs": "floor_edge", "pick": "far"}],
	"pillar_wood": [{"shape": "floor", "mode": "on", "mine": "pillar_top", "theirs": "post_spot", "pick": "far"}],
	"pillar_stone": [{"shape": "floor", "mode": "on", "mine": "pillar_top", "theirs": "post_spot", "pick": "far"}],
	"pole_1": [{"shape": "floor_1", "mode": "on", "mine": "pole_top", "theirs": "post_spot", "pick": "far"}],
	"pole_2": [{"shape": "floor", "mode": "on", "mine": "pole_top", "theirs": "post_spot", "pick": "far"}],
	"beam_1": [
		{"shape": "pole_2", "mode": "under", "mine": "beam_end", "theirs": "pole_top", "pick": "left"},
		{"shape": "pole_2", "mode": "under", "mine": "beam_end", "theirs": "pole_top", "pick": "left", "mirror": true},
	],
	"beam_2": [
		{"shape": "pole_2", "mode": "under", "mine": "beam_end", "theirs": "pole_top", "pick": "left"},
		{"shape": "pole_2", "mode": "under", "mine": "beam_end", "theirs": "pole_top", "pick": "left", "mirror": true},
	],
	"ladder": [{"shape": "floor", "mode": "under", "mine": "ladder_top", "theirs": "floor_edge", "pick": "back"}],
	"railing_1": [{"shape": "floor", "mode": "under", "mine": "small_railing_base", "theirs": "half_edge", "pick": "back"}],
	"railing_2": [{"shape": "floor", "mode": "under", "mine": "railing_base", "theirs": "floor_edge", "pick": "back"}],
	"wall_1": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	"wall_half_1": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	"wall_half_2": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	"wall_quarter": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	"wall_long": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	"wall_short": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	"wall_strip_2": [{"shape": "gable_45", "mode": "on", "mine": "wall_top", "theirs": "gable_base"}],
	"wall_strip_1": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	"gable_wall_45": [{"shape": "wall", "mode": "on", "mine": "wall_end", "theirs": "wall_end", "pick": "straight"}],
	# A half gable on a faint 1 m wall, beside a faint full gable
	"gable_half_1_{p}": [
		{"shape": "wall_1", "mode": "under", "mine": "small_gable_base", "theirs": "half_top"},
		{"shape": "gable_{p}", "mode": "on", "mine": "gable_tip", "theirs": "gable_tip"},
	],
	# An inverse triangle on a faint gable's slope, under a faint beam
	"inverse_2_{p}": [
		{"shape": "gable_{p}", "mode": "under", "mine": "inverse_low_{p}", "theirs": "gable_slope_{p}", "pick": "right"},
		{"shape": "beam_2", "mode": "under", "mine": "inverse_top", "theirs": "beam_under"},
	],
	"inverse_1_{p}": [
		{"shape": "gable_{p}", "mode": "under", "mine": "inverse_low_{p}", "theirs": "gable_slope_{p}", "pick": "left"},
		{"shape": "beam_1", "mode": "under", "mine": "inverse_top_small", "theirs": "beam_under_small"},
	],
	"curved_wall_45": [{"shape": "round_floor", "mode": "under", "mine": "curve_base", "theirs": "round_edge"}],
	"curved_wall_22": [{"shape": "round_floor_22", "mode": "under", "mine": "curve22_base", "theirs": "round_edge_small"}],
	"cone_roof": [{"shape": "curved_wall_45", "mode": "under", "mine": "cone_base", "theirs": "curve_top"}],
	"chimney_section": [{"shape": "fireplace", "mode": "under", "mine": "chimney_base", "theirs": "chimney_spot"}],
	"chimney_top": [
		{"shape": "chimney_section", "mode": "under", "mine": "chimney_cap_base", "theirs": "chimney_spot"},
		{"shape": "fireplace", "mode": "under", "of": 0, "mine": "chimney_base", "theirs": "chimney_spot"},
	],
}

## Pieces turned on the stage so their neighbours stand behind them and the camera sees their
## good side: shape -> turn (radians). Pieces in the Roofs tab otherwise turn half round (see turn_of).
const TURNS := {"stairs": PI, "gable_26": PI / 2.0, "gable_45": PI / 2.0}
## How far the framing leans from the piece's middle toward the middle of it and its neighbours
const LEAN := 0.35
## Pieces framed together with their neighbours (they only make sense on top of them)
const FRAME_WHOLE := ["chimney_section", "chimney_top"]

## Corner badges: shape -> text (pitches and arcs are worked out from the name, see badge_for)
const BADGES := {
	"floor": "2×2", "floor_1": "1×1", "wall": "2 m", "wall_1": "1 m", "wall_half_2": "2 m", "wall_half_1": "1 m",
	"wall_quarter": "1×1", "wall_long": "2.83 m", "wall_short": "1.53 m", "wall_strip_2": "2×½", "wall_strip_1": "1×½",
	"gable_wall_45": "2.5 m", "window_split_2": "2 m", "window_split_1": "1 m", "beam_1": "1 m", "beam_2": "2 m",
	"pole_1": "1 m", "pole_2": "2 m", "railing_1": "1 m", "railing_2": "2 m", "roof": "26°",
	"curved_wall_22": "22.5°", "curved_wall_45": "45°", "round_floor": "45°", "round_floor_22": "22.5°",
	"round_foundation_wood": "45°", "round_foundation_stone": "45°", "round_foundation_wood_22": "22.5°",
	"round_foundation_stone_22": "22.5°", "foundation_wood": "2×2", "foundation_stone": "2×2",
}

var registry: PieceRegistry

static var _vignette_texture: Texture2D

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _ghost: ShaderMaterial
var _patch: StandardMaterial3D
# Tab -> half the span (in the camera's view) of its largest piece
var _tab_spans := {}


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.54)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var view := VIEW.normalized()
	# Key: warm, from the upper left front
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 1.7
	_viewport.add_child(key)
	key.look_at_from_position(Vector3(-0.6, 1.4, 1.0), Vector3.ZERO, Vector3.UP)
	# Fill: soft and cool, from the right
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.8, 1.0)
	fill.light_energy = 0.45
	_viewport.add_child(fill)
	fill.look_at_from_position(Vector3(1.2, 0.3, 0.2), Vector3.ZERO, Vector3.UP)
	# Rim: from behind, toward the camera, lighting the edges
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.95, 0.88)
	rim.light_energy = 1.1
	_viewport.add_child(rim)
	rim.look_at_from_position(-view * 2.0 + Vector3.UP * 1.2, Vector3.ZERO, Vector3.UP)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	_ghost = ShaderMaterial.new()
	_ghost.shader = GHOST_SHADER
	_ghost.set_shader_parameter("color", GHOST_COLOR)
	_patch = StandardMaterial3D.new()
	_patch.albedo_color = PATCH_COLOR
	_patch.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_patch.roughness = 1.0


## Works out each tab's scale from every buildable in it (call once before rendering)
func measure(buildables: Array) -> void:
	_tab_spans.clear()
	for buildable in buildables:
		var group := scale_group(buildable)
		if group.is_empty():
			continue
		var turned := Transform3D(Basis(Vector3.UP, turn_of(buildable as PieceBuildable)), Vector3.ZERO)
		_tab_spans[group] = maxf(float(_tab_spans.get(group, 0.0)), _half_span(turned * _bounds_of(buildable)))


## The icon for one buildable, SAVED_SIZE square (after a few frames)
func render(buildable: Buildable) -> Image:
	for child in _stage.get_children():
		child.queue_free()
	await get_tree().process_frame
	var subject := Node3D.new()
	_stage.add_child(subject)
	var own_box := _bounds_of(buildable)
	var box := own_box
	# The neighbours' box too (the framing leans a little toward them, so they show)
	var around := AABB()
	var has_around := false
	if buildable is PieceBuildable:
		var piece := buildable as PieceBuildable
		var turn := turn_of(piece)
		var turned := Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO)
		subject.rotation.y = turn
		box = turned * own_box
		subject.add_child(_piece_look(piece, false))
		var context := _context_of(piece.shape)
		if context.is_empty() and tab_of(buildable) == "Furniture":
			_add_patch(subject, own_box)
		for placed in context:
			var ghost := _piece_look(load(_buildable_path(placed["shape"])) as PieceBuildable, true)
			ghost.transform = placed["where"]
			subject.add_child(ghost)
			var part: AABB = turned * ((placed["where"] as Transform3D) * PieceShapes.bounds_of(registry.shape_of(placed["shape"])))
			around = part if not has_around else around.merge(part)
			has_around = true
	else:
		subject.add_child(TemplateLook.building_look(buildable))
		_add_patch(subject, own_box)
	# The camera, centred on the piece (leaning toward its neighbours by LEAN), at its tab's scale
	var view := VIEW.normalized()
	var centre := box.get_center()
	var whole := FRAME_WHOLE.has(buildable.resource_path.get_file().get_basename()) and has_around
	if whole:
		# Framed with its neighbours (a chimney top on its stack)
		box = box.merge(around)
		centre = box.get_center()
	elif has_around:
		centre = centre.lerp(box.merge(around).get_center(), LEAN)
	_camera.global_position = centre + view * 30.0
	_camera.look_at(centre, Vector3.UP)
	_camera.far = 80.0
	var group := scale_group(buildable)
	var span: float = _tab_spans.get(group, _half_span(box)) if not group.is_empty() else _half_span(box)
	_camera.size = span * 2.0 / FILL
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var icon := _viewport.get_texture().get_image()
	icon.convert(Image.FORMAT_RGBA8)
	# Shrunk while its colours are still premultiplied by alpha (as the see-through viewport
	# leaves them), which blends edges correctly, then put back to plain alpha
	icon.resize(SAVED_SIZE, SAVED_SIZE, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(icon)
	subject.queue_free()
	return icon


## Which build tab a buildable is in
static func tab_of(buildable: Buildable) -> String:
	return buildable.section if not buildable.section.is_empty() else "Other"


## Which icons share a scale (every building piece in a tab), or empty for one framed on its own:
## furniture and the workbench, chest, campfire and lean-to fill their icon whatever their size
## (at one scale a basket would be a speck beside a bed), standing on a floor patch for scale.
static func scale_group(buildable: Buildable) -> String:
	if not buildable is PieceBuildable or tab_of(buildable) == "Furniture":
		return ""
	return tab_of(buildable)


## How a piece is turned on the stage, so the camera sees the side it's meant to be seen from
## (roofs rise away from it, so you look onto their tops)
static func turn_of(piece: PieceBuildable) -> float:
	if TURNS.has(piece.shape):
		return TURNS[piece.shape]
	return PI if piece.section == "Roofs" else 0.0


## The badge text for a buildable ("26°", "1×1", "2 m"), or empty
static func badge_for(buildable: Buildable) -> String:
	if not buildable is PieceBuildable:
		return ""
	var shape := (buildable as PieceBuildable).shape
	if BADGES.has(shape):
		return BADGES[shape]
	if shape.ends_with("_26"):
		return "26°"
	if shape.ends_with("_45") and not shape.begins_with("curved") and not shape.begins_with("round"):
		return "45°"
	return ""


# ---- Pieces and their neighbours ----

# A piece's look (solid, or as a faint outline), built like a placed piece but never solid
func _piece_look(piece: PieceBuildable, ghost: bool) -> Node3D:
	var bp: BuildPiece = piece.scene.instantiate()
	bp.setup(piece, registry.shape_of(piece.shape), registry.material_for(piece.shape))
	bp.piece_id = 3
	bp.dress(registry.detail_mesh(piece.shape, 3), registry.detail_material())
	bp.weather()
	bp.make_preview_only()
	if ghost:
		for found in bp.find_children("*", "GeometryInstance3D", true, false):
			if found is GPUParticles3D:
				found.visible = false
				continue
			(found as GeometryInstance3D).material_override = _ghost
			(found as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for light in bp.find_children("*", "Light3D", true, false):
			light.visible = false
	return bp


# Where each faint neighbour goes, relative to the piece (at the origin): [{"shape", "where"}]
func _context_of(shape_name: String) -> Array:
	var pattern := _pattern_of(shape_name)
	if not CONTEXT.has(pattern):
		return []
	var pitch := "45" if shape_name.ends_with("_45") else "26"
	var placed := []
	for entry in CONTEXT[pattern]:
		var their_shape := _fill(entry["shape"], pitch)
		var anchor_shape := shape_name
		var anchor := Transform3D.IDENTITY
		if entry.has("of"):
			var index: int = entry["of"]
			if index >= placed.size() or placed[index] == null:
				placed.append(null)
				continue
			anchor_shape = placed[index]["shape"]
			anchor = placed[index]["where"]
		if _buildable_path(their_shape).is_empty():
			placed.append(null)
			continue
		var where = null
		if entry.get("place", "") == "over_gable":
			# The roof's low edge over the gable's low end, rising with its slope toward +X, reaching
			# back behind it (away from the camera)
			where = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-PieceShapes.GRID / 2.0, 0, -PieceShapes.GRID / 2.0))
		elif entry.get("place", "") == "over_topper_gable":
			# The topper's -X end on the gable's plane, its ridge running back from it (away from
			# the camera): the gable's x is the topper's z
			where = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 0, -PieceShapes.GRID / 2.0))
		else:
			where = _attach(anchor_shape, anchor, their_shape, entry, pitch)
			# The same at the far end (a beam's second post, which the snap rules see as a repeat
			# of the first)
			if where != null and entry.get("mirror", false):
				where = Transform3D(where.basis, Vector3(-where.origin.x, where.origin.y, where.origin.z))
		placed.append({"shape": their_shape, "where": where} if where != null else null)
	return placed.filter(func(p): return p != null)


# Places a neighbour against an anchor (the piece, or an earlier neighbour) by the snap rules
func _attach(anchor_shape: String, anchor: Transform3D, their_shape: String, entry: Dictionary, pitch: String):
	var mine := _fill(entry["mine"], pitch)
	var theirs := _fill(entry["theirs"], pitch)
	var anchor_def := registry.shape_of(anchor_shape)
	var their_def := registry.shape_of(their_shape)
	var options := []
	if not PieceShapes.turns_for(theirs, mine).is_empty():
		# Their socket snaps onto the anchor's
		var own: Array = their_def["sockets"].filter(func(s): return s["type"] == theirs)
		for socket in anchor_def["sockets"]:
			if socket["type"] != mine:
				continue
			var world := _socket_at(socket, anchor)
			for where in PieceShapes.fits(own, world, their_def["symmetry"]):
				options.append(where)
	elif not PieceShapes.turns_for(mine, theirs).is_empty():
		# The anchor's socket snaps onto theirs: work out where they'd be, seen from the anchor
		var own: Array = anchor_def["sockets"].filter(func(s): return s["type"] == mine)
		for socket in their_def["sockets"]:
			if socket["type"] != theirs:
				continue
			for anchor_on_them in PieceShapes.fits(own, socket, anchor_def["symmetry"]):
				options.append(anchor * (anchor_on_them as Transform3D).affine_inverse())
	if options.is_empty():
		return null
	var pick: String = entry.get("pick", "first")
	var anchor_box := PieceShapes.bounds_of(anchor_def)
	var their_box := PieceShapes.bounds_of(their_def)
	var score := func(where: Transform3D) -> float:
		var their_middle := where * their_box.get_center()
		var anchor_middle := anchor * anchor_box.get_center()
		match pick:
			"far":
				# Farthest out, and behind rather than in front where that's a tie
				return -Vector2(their_middle.x - anchor_middle.x, their_middle.z - anchor_middle.z).length() + their_middle.z * 0.1
			"near":
				return Vector2(their_middle.x - anchor_middle.x, their_middle.z - anchor_middle.z).length()
			"straight":
				# In line with it, on its right (the tall end of a gable wall) where that's a tie
				return absf(wrapf(atan2(where.basis.x.z, where.basis.x.x) - atan2(anchor.basis.x.z, anchor.basis.x.x) + PI / 2.0, 0.0, PI) - PI / 2.0) - where.origin.x * 0.002
			"back":
				return their_middle.z
			"front":
				return -their_middle.z
			"opposite":
				# In line with it, turned round, on its +X side (a split-window wall's partner)
				var turned := absf(wrapf(atan2(where.basis.z.x, where.basis.z.z) - atan2(anchor.basis.z.x, anchor.basis.z.z) - PI, -PI, PI))
				return turned - (their_middle - anchor_middle).x * 0.01
			"left":
				return where.origin.x
			"right":
				return -where.origin.x
		return 0.0
	var best: Transform3D = options[0]
	var best_score: float = score.call(best)
	for where in options:
		var s: float = score.call(where)
		if s < best_score - 0.001:
			best = where
			best_score = s
	return best


func _socket_at(socket: Dictionary, at: Transform3D) -> Dictionary:
	return {
		"position": at * (socket["position"] as Vector3),
		"yaw": atan2(at.basis.z.x, at.basis.z.z) + float(socket["yaw"]),
		"type": socket["type"],
	}


# A shape name as CONTEXT lists it ("eave_26" -> "eave_{p}")
static func _pattern_of(shape_name: String) -> String:
	if shape_name.ends_with("_26") or shape_name.ends_with("_45"):
		var base := shape_name.left(shape_name.length() - 3)
		if CONTEXT.has(base + "_{p}"):
			return base + "_{p}"
	return shape_name


static func _fill(text: String, pitch: String) -> String:
	return text.replace("{roof}", "roof" if pitch == "26" else "roof_45").replace("{p}", pitch)


# The buildable file for a shape
static func _buildable_path(shape_name: String) -> String:
	for folder in ["res://buildables/structure/", "res://buildables/round/", "res://buildables/furniture/"]:
		if ResourceLoader.exists(folder + shape_name + ".tres"):
			return folder + shape_name + ".tres"
	return ""


# ---- Framing ----

# The box round a buildable's own look (no neighbours), in its own space
func _bounds_of(buildable: Buildable) -> AABB:
	if buildable is PieceBuildable:
		return PieceShapes.bounds_of(registry.shape_of((buildable as PieceBuildable).shape))
	var look := TemplateLook.building_look(buildable)
	var box := AABB()
	var first := true
	for found in look.get_children():
		if found is MeshInstance3D and found.mesh:
			var part: AABB = found.transform * found.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
	look.free()
	return box


# Half the box's span across the camera's view (the bigger of its width and height on screen)
static func _half_span(box: AABB) -> float:
	var view := VIEW.normalized()
	var right := Vector3.UP.cross(view).normalized()
	var up := view.cross(right).normalized()
	var centre := box.get_center()
	var span := 0.0
	for i in 8:
		var corner := box.get_endpoint(i) - centre
		span = maxf(span, maxf(absf(corner.dot(right)), absf(corner.dot(up))))
	return span


# A faint square of floor under furniture, so it doesn't float
func _add_patch(subject: Node3D, box: AABB) -> void:
	var slab := BoxMesh.new()
	var margin := clampf(maxf(box.size.x, box.size.z) * 0.15, 0.08, 0.3)
	slab.size = Vector3(box.size.x + margin * 2.0, 0.03, box.size.z + margin * 2.0)
	var patch := MeshInstance3D.new()
	patch.mesh = slab
	patch.material_override = _patch
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.position = Vector3(box.get_center().x, box.position.y - 0.02, box.get_center().z)
	subject.add_child(patch)


# Divides each part-clear pixel's colour by its alpha (the viewport stores colour premultiplied,
# which would otherwise make see-through parts and soft edges come out dark)
static func _unpremultiply(image: Image) -> void:
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		if a == 0 or a == 255:
			continue
		data[i] = mini(255, data[i] * 255 / a)
		data[i + 1] = mini(255, data[i + 1] * 255 / a)
		data[i + 2] = mini(255, data[i + 2] * 255 / a)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


## The soft dark vignette drawn behind every icon (by the build slot, so a locked piece's dark
## silhouette still shows its shape): a warm dark brown fading out toward the edges
static func vignette() -> Texture2D:
	if _vignette_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, VIGNETTE_MIDDLE)
		gradient.set_color(1, VIGNETTE_EDGE)
		gradient.add_point(0.55, VIGNETTE_MIDDLE.lerp(VIGNETTE_EDGE, 0.35))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 128
		texture.height = 128
		_vignette_texture = texture
	return _vignette_texture
