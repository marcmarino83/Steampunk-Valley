class_name BuildPiece
extends StaticBody3D
## One placed building piece. It builds its look, collision and snap points from its shape
## (PieceShapes) when the piece registry makes it. Doors open and close with E.
##
## Every piece has an id that stays the same across saves, and the plot that owns it (empty for
## none; see PlotRegistry). The registry lists them all.

## How far a door swings open, in degrees
const DOOR_OPEN_DEGREES := 95.0
const DOOR_SWING_SECONDS := 0.35

## Its id, unique in this world, and the plot that owns it (empty: no plot)
var piece_id := 0
var owner_plot := ""
## What it is, and what was paid for it (all of which comes back when it's taken down)
var buildable: PieceBuildable
var paid := {}
## The shape it's built as: its buildable's shape (every piece has fixed dimensions)
var shape_name := ""

var _def: Dictionary
var _door_open := false
var _door_angle := 0.0
# The door's swinging parts and how each one sits when closed
var _door_parts: Array = []
var _door_tween: Tween
# The plain textured box look, which only shows from far off once it has a close-up look
var _plain_looks: Array[MeshInstance3D] = []
# Chimney models fitted and flattened once (model path -> ArrayMesh), shared by every piece
static var _fitted_meshes := {}

## The glowing outline look a template's placement preview wears in green or red over its real
## look (see outline_glow.gdshader)
const GHOST_SHADER := preload("res://building/templates/outline_glow.gdshader")
## Ghost pieces wear their real look, solid, faded toward a pale cool grey and drained of colour
## (the pieces' shaders' ghost_fade); the ghost under the crosshair is less faded and outlined (see
## set_ghost_targeted). A model (furniture) fades through an overlay instead (PreviewLook).
const GHOST_FADE := 1.0
const GHOST_TARGET_FADE := 0.5

# A ghost (a template's piece still to be built): whether each look cast a shadow before, and the
# collision layer it had
var _ghost := false
var _ghost_targeted := false
var _ghost_saved := {}
var _solid_layer := 1

## Its looks by distance (see dress): the full close-up look within NEAR_RANGE, the simplified one
## out to MID_RANGE, the plain textured box beyond; each fading into the next over LEVEL_FADE
const NEAR_RANGE := 15.0
const MID_RANGE := 40.0
const LEVEL_FADE := 2.0
var _detail_looks: Array[MeshInstance3D] = []
var _mid_looks: Array[MeshInstance3D] = []
# Shadow-only copies of the plain box, casting its shadow while a close look shows
var _shadow_looks: Array[MeshInstance3D] = []


## Builds it from its shape. Called before it's added to the world.
func setup(piece: PieceBuildable, def: Dictionary, material: Material) -> void:
	buildable = piece
	shape_name = piece.shape
	_def = def
	name = "Piece"
	add_to_group("build_pieces")
	if piece.model_scene:
		add_child(fitted_model(piece, def))
	else:
		var look := MeshInstance3D.new()
		look.mesh = def["mesh"]
		look.material_override = material
		add_child(look)
		_plain_looks.append(look)
	if def["door_mesh"]:
		var panel := MeshInstance3D.new()
		panel.mesh = def["door_mesh"]
		panel.material_override = material
		add_child(panel)
		_door_parts.append({"node": panel, "rest": Transform3D.IDENTITY})
		_plain_looks.append(panel)
	if def.get("hearth", false):
		_make_hearth_fire()
	for part in def["collision"]:
		var solid := CollisionShape3D.new()
		solid.shape = part["shape"]
		solid.transform = part["transform"]
		add_child(solid)
		if part["door"]:
			_door_parts.append({"node": solid, "rest": part["transform"]})


## Gives it its looks at three distances (see PieceDetail):
##   - its full close-up look (separate planks, logs, split shakes, stones and rope) within
##     NEAR_RANGE,
##   - a simplified version of it (`mid`: shakes merged into rows, no rope, plain-edged planks,
##     fewer-sided logs) out to MID_RANGE,
##   - its plain textured box beyond that.
## Each fades into the next over LEVEL_FADE (Godot's visibility ranges). Neither close look casts
## shadows: a shadow-only copy of the plain box does, out to MID_RANGE, and the plain box itself
## beyond. A door's panel gets its own looks, which swing with it. Nothing changes for a shape
## without a close-up look.
func dress(detail: Dictionary, material: Material, mid: Dictionary = {}) -> void:
	_dress_looks(detail, material, mid)
	_nudge_looks()


## How far (meters, at most) each piece's look is nudged, so faces of overlapping pieces that
## lie in exactly the same plane don't flicker against each other
const NUDGE := 0.0025


# Every piece's look (not its collision) sits a hair off its true place, in a direction of its own
# picked from its id: overlapping pieces whose faces coincide then draw cleanly, one just in front
func _nudge_looks() -> void:
	var nudge := _nudge()
	for child in get_children():
		if child is MeshInstance3D or (child is Node3D and child.name == "Model"):
			(child as Node3D).position += nudge
	for part in _door_parts:
		if part["node"] is MeshInstance3D:
			part["rest"] = (part["rest"] as Transform3D).translated(nudge)


# How far its looks sit off its true place (see _nudge_looks): the same every time for its id.
# Flights of stairs, floors and foundations aren't nudged at all: a flight's header board meets the
# edge face it hangs from, and its footing board the top it stands on, exactly, never a hair off or
# into it. Roofs aren't either, so they sit exactly on the wall tops they rest on. (Two floors
# free-placed overlapping at the same height can flicker where their tops meet.) Every other piece's
# nudge is level, never up or down, so pieces stacked on the grid (a wall on a wall, a beam on a
# post) meet plank to plank.
func _nudge() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(piece_id * 104729 + 31)
	var nudge := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized() * NUDGE * rng.randf_range(0.4, 1.0)
	var def := shape_def()
	if def.get("stairs", false) or def.get("floor", false) or def.get("roof", false):
		return Vector3.ZERO
	return nudge


## Its close-up and middle looks made again from these: the old ones (and their shadow copies)
## taken away and the new ones put in their place, nudged and weathered as before. For when the look
## code has changed while the game runs (see PieceRegistry), so nothing keeps a look made by older
## code.
func redress(detail: Dictionary, material: Material, mid: Dictionary = {}) -> void:
	var old: Array = _detail_looks + _mid_looks + _shadow_looks
	var logs := get_node_or_null("HearthLogs")
	if logs:
		old.append(logs)
	_door_parts = _door_parts.filter(func(p): return not old.has(p["node"]))
	for node in old:
		remove_child(node)
		(node as Node).queue_free()
	_detail_looks.clear()
	_mid_looks.clear()
	_shadow_looks.clear()
	for plain in _plain_looks:
		plain.visibility_range_begin = 0.0
		plain.visibility_range_begin_margin = 0.0
	var before := get_children()
	var parts_before := _door_parts.size()
	_dress_looks(detail, material, mid)
	var nudge := _nudge()
	for child in get_children():
		if child is MeshInstance3D and not before.has(child):
			(child as MeshInstance3D).position += nudge
	# (a door's new looks swing from their nudged rest; a shadow copy's rest is the plain look's,
	# which is nudged already)
	for i in range(parts_before, _door_parts.size()):
		if not _shadow_looks.has(_door_parts[i]["node"]):
			_door_parts[i]["rest"] = (_door_parts[i]["rest"] as Transform3D).translated(nudge)
	weather()
	if not is_zero_approx(_door_angle):
		_set_door_angle(_door_angle)


func _dress_looks(detail: Dictionary, material: Material, mid: Dictionary) -> void:
	if _def.get("hearth", false):
		# Logs for the fire to burn on, in the hearth (small: no shadow)
		var logs := MeshInstance3D.new()
		logs.name = "HearthLogs"
		logs.mesh = PieceDetail.hearth_logs_mesh(piece_id)
		logs.material_override = material
		logs.position = _def.get("hearth_at", Vector3.ZERO)
		logs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(logs)
	if detail.is_empty() or detail.get("mesh") == null and detail.get("door_mesh") == null:
		return
	var has_mid := not mid.is_empty() and (mid.get("mesh") != null or mid.get("door_mesh") != null)
	var plain_from := MID_RANGE if has_mid else NEAR_RANGE
	for plain in _plain_looks.duplicate():
		# Its shadow up close, for the close looks (which cast none): from the plain box, or from the
		# simplified look where that has fewer triangles (a foundation's box goes deep underground)
		var shadow := MeshInstance3D.new()
		shadow.name = "PlainShadow"
		shadow.mesh = plain.mesh
		shadow.material_override = plain.material_override
		if has_mid and mid.get("shadow_from_mid", false) and plain.mesh == _def["mesh"]:
			shadow.mesh = mid["mesh"]
			shadow.material_override = material
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shadow.visibility_range_end = plain_from
		shadow.visibility_range_end_margin = LEVEL_FADE
		add_child(shadow)
		_shadow_looks.append(shadow)
		for part in _door_parts:
			if part["node"] == plain:
				_door_parts.append({"node": shadow, "rest": part["rest"]})
				break
		plain.visibility_range_begin = plain_from
		plain.visibility_range_begin_margin = LEVEL_FADE
		plain.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for key in ["mesh", "door_mesh"]:
		var mesh: Mesh = detail.get(key)
		if mesh == null:
			continue
		var near := MeshInstance3D.new()
		near.name = "Detail" if key == "mesh" else "DoorDetail"
		near.mesh = mesh
		near.material_override = material
		near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		near.visibility_range_end = NEAR_RANGE
		near.visibility_range_end_margin = LEVEL_FADE
		near.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(near)
		_detail_looks.append(near)
		if key == "door_mesh":
			_door_parts.append({"node": near, "rest": Transform3D.IDENTITY})
		var simple: Mesh = mid.get(key) if has_mid else null
		if simple == null:
			continue
		var middle := MeshInstance3D.new()
		middle.name = "Mid" if key == "mesh" else "DoorMid"
		middle.mesh = simple
		middle.material_override = material
		middle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		middle.visibility_range_begin = NEAR_RANGE
		middle.visibility_range_begin_margin = LEVEL_FADE
		middle.visibility_range_end = MID_RANGE
		middle.visibility_range_end_margin = LEVEL_FADE
		middle.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(middle)
		_mid_looks.append(middle)
		if key == "door_mesh":
			_door_parts.append({"node": middle, "rest": Transform3D.IDENTITY})


## Shows only its full close-up look, at any distance (a template's picture, an icon): the other
## looks hidden
func show_full_detail() -> void:
	if _detail_looks.is_empty():
		return
	for look in _detail_looks:
		look.visible = true
		look.visibility_range_end = 0.0
		look.visibility_range_end_margin = 0.0
		look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for look in _mid_looks + _plain_looks + _shadow_looks:
		look.visible = false


## Shows its simplified look up close too, never the full one (a template's placement preview, a
## ghost not under the crosshair), or back to normal
func show_simple_look(on: bool) -> void:
	if _mid_looks.is_empty():
		return
	for look in _detail_looks:
		look.visible = not on
	for look in _mid_looks:
		look.visibility_range_begin = 0.0 if on else NEAR_RANGE
		look.visibility_range_begin_margin = 0.0 if on else LEVEL_FADE


## The slight colour and brightness of its own a piece with this id wears (see weather): the same
## every time, so the placement preview can wear the one the piece will have
static func weather_tint(id: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id * 7919 + 17)
	var bright := rng.randf_range(0.92, 1.05)
	var warm := rng.randf_range(-0.035, 0.035)
	return Color(bright * (1.0 + warm), bright, bright * (1.0 - warm * 1.4))


## Gives its textured surface (see piece_surface.gdshader) this piece's own slight colour and
## brightness, picked from its id so it stays the same every time, and its box, for the grime
## toward its edges. Called once it has its id.
func weather() -> void:
	var tint := weather_tint(piece_id)
	var box := PieceShapes.bounds_of(_def)
	for child in get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is ShaderMaterial:
			var look := child as MeshInstance3D
			look.set_instance_shader_parameter("tint", tint)
			look.set_instance_shader_parameter("box_min", box.position)
			look.set_instance_shader_parameter("box_max", box.end)
			look.set_instance_shader_parameter("frame_offset", _def.get("frame_offset", 0.0))


## A piece's model, scaled evenly to fit its solid box and placed in it: standing on the box's
## floor, centred side to side, its back against the box's back (-Z). A model made facing another
## way is first turned about its upright by the shape's "model_turn" (see PieceShapes.MODEL_TURNS).
## Used for the piece itself and its placement preview.
static func fitted_model(piece: PieceBuildable, def: Dictionary) -> Node3D:
	if def.has("model_fit"):
		return _flattened_model(piece, def["model_fit"])
	var model: Node3D = piece.model_scene.instantiate()
	var box: AABB = def.get("model_box", PieceShapes.bounds_of(def))
	var turn := Basis(Vector3.UP, def.get("model_turn", 0.0))
	var own: AABB = Transform3D(turn, Vector3.ZERO) * _model_bounds(model)
	if own.size.x <= 0.0 or own.size.y <= 0.0 or own.size.z <= 0.0:
		return model
	var s := minf(minf(box.size.x / own.size.x, box.size.y / own.size.y), box.size.z / own.size.z)
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	model.basis = turn.scaled(Vector3.ONE * s)
	var centre := own.get_center() * s
	model.position = Vector3(box.get_center().x - centre.x, box.position.y - own.position.y * s, box.position.z - own.position.z * s)
	# Extra models that stand with it as part of the piece (the sorting table's baskets)
	for extra in def.get("model_extras", []):
		holder.add_child(_extra_model(extra))
	return holder


# One extra model (see PieceShapes.MODEL_EXTRAS): fitted evenly to its width, standing on the floor
# at its spot, turned; with a fill model sitting in it, fitted to the fill's width and height, its
# bottom a little under the rim so it shows above
static func _extra_model(extra: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.position = extra["at"]
	holder.rotation.y = float(extra.get("turn", 0.0))
	var model: Node3D = (load(extra["scene"]) as PackedScene).instantiate()
	var own := _model_bounds(model)
	if own.size.x <= 0.0:
		return holder
	var s: float = float(extra["width"]) / maxf(own.size.x, own.size.z)
	model.scale = Vector3.ONE * s
	model.position = Vector3(-own.get_center().x * s, -own.position.y * s, -own.get_center().z * s)
	holder.add_child(model)
	if extra.has("fill"):
		var fill: Node3D = (load(extra["fill"]) as PackedScene).instantiate()
		var fill_own := _model_bounds(fill)
		var size: Vector2 = extra["fill_size"]
		var across := size.x / maxf(fill_own.size.x, fill_own.size.z)
		var up := size.y / maxf(fill_own.size.y, 0.001)
		fill.scale = Vector3(across, up, across)
		# Its bottom 55% of the way up the basket: the rest of it heaps above the rim
		var rim := own.size.y * s
		fill.position = Vector3(-fill_own.get_center().x * across, rim * 0.55 - fill_own.position.y * up, -fill_own.get_center().z * across)
		holder.add_child(fill)
	return holder


# A model fitted exactly by the numbers in `fit` (see PieceShapes.CHIMNEY_FITS): its meshes merged
# into one, every point past the kept heights flattened onto them (so the top and bottom are flat
# and pieces stack cleanly), scaled, and placed with its body's bottom middle at the origin. Made
# once per model and shared.
static func _flattened_model(piece: PieceBuildable, fit: Dictionary) -> Node3D:
	var key := piece.model_scene.resource_path
	if not _fitted_meshes.has(key):
		var model: Node3D = piece.model_scene.instantiate()
		var keep: Vector2 = fit["keep"]
		var merged := ArrayMesh.new()
		for found in model.find_children("*", "MeshInstance3D", true, false):
			var look := found as MeshInstance3D
			var xform := Transform3D.IDENTITY
			var n: Node = look
			while n != model and n is Node3D:
				xform = (n as Node3D).transform * xform
				n = n.get_parent()
			for s in look.mesh.get_surface_count():
				var arrays := look.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in verts.size():
					var p := xform * verts[i]
					p.y = clampf(p.y, keep.x, keep.y)
					verts[i] = p
					if i < normals.size():
						normals[i] = (xform.basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_VERTEX] = verts
				if not normals.is_empty():
					arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TANGENT] = null
				merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				merged.surface_set_material(merged.get_surface_count() - 1, look.get_active_material(s))
		model.free()
		_fitted_meshes[key] = merged
	var holder := Node3D.new()
	holder.name = "Model"
	var shown := MeshInstance3D.new()
	shown.mesh = _fitted_meshes[key]
	var centre: Vector2 = fit["centre"]
	var size: Vector3 = fit["scale"]
	var keep2: Vector2 = fit["keep"]
	shown.scale = size
	shown.position = -Vector3(centre.x * size.x, keep2.x * size.y, centre.y * size.z)
	holder.add_child(shown)
	return holder


## Lets go of the shared fitted chimney meshes (when the world closes, so nothing is reported leaked)
static func clear_fitted_cache() -> void:
	_fitted_meshes.clear()
	PreviewLook.clear_cache()


# ---- Ghosts ----
#
# A ghost is a piece of a placed template that hasn't been built yet: its real look, solid, but
# faded toward a pale cool grey and drained of colour (GHOST_FADE), so it reads clearly as not built
# yet beside built pieces; nothing solid (the player, settlers and every physics check pass through
# it), and it doesn't count as built for requirements, shelter or settlers. The hammer finds ghosts
# by their boxes (see GhostBuilder); filling one with materials turns it into the real piece.


func is_ghost() -> bool:
	return _ghost


# How faded each look shows (the pieces' shaders' ghost_fade; a model's meshes through an overlay
# instead, PreviewLook), and the outline round the one under the crosshair
func _fade_looks(fade: float, targeted: bool) -> void:
	for shown in _ghost_saved:
		if not is_instance_valid(shown):
			continue
		var g := shown as GeometryInstance3D
		var own_fade := g.material_override is ShaderMaterial and (g.material_override as ShaderMaterial).shader in [PieceRegistry.DETAIL_SHADER, PieceRegistry.SURFACE_SHADER]
		if own_fade:
			g.set_instance_shader_parameter("ghost_fade", fade)
		if targeted:
			PreviewLook.wear(g, PreviewLook.State.GHOST_TARGET)
		elif fade > 0.0 and not own_fade:
			g.material_overlay = PreviewLook.overlay(PreviewLook.State.GHOST_FADE)
		else:
			g.material_overlay = null


## Turns it into a ghost, or back into the real piece
func set_ghost(on: bool) -> void:
	if on == _ghost:
		return
	_ghost = on
	if on:
		_solid_layer = collision_layer
		collision_layer = 0
		for look in find_children("*", "GeometryInstance3D", true, false):
			if look is GPUParticles3D or _shadow_looks.has(look):
				continue
			var shown := look as GeometryInstance3D
			_ghost_saved[shown] = shown.cast_shadow
			shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fade_looks(GHOST_FADE, false)
		# No shadow, and the simplified look until it's under the crosshair
		for shadow in _shadow_looks:
			shadow.visible = false
		show_simple_look(true)
	else:
		collision_layer = _solid_layer
		_ghost_targeted = false
		_fade_looks(0.0, false)
		for shown in _ghost_saved:
			if is_instance_valid(shown):
				shown.cast_shadow = _ghost_saved[shown]
		_ghost_saved.clear()
		for shadow in _shadow_looks:
			shadow.visible = true
		show_simple_look(false)
	# A ghost fireplace doesn't burn
	if _hearth_light:
		_hearth_light.visible = not on
		_hearth_flame.visible = not on
		_hearth_smoke.emitting = false
		if on:
			remove_from_group("campfires")
		else:
			add_to_group("campfires")


## The ghost under the crosshair shows less faded, with a light outline
func set_ghost_targeted(targeted: bool) -> void:
	if not _ghost:
		return
	_ghost_targeted = targeted
	_fade_looks(GHOST_TARGET_FADE if targeted else GHOST_FADE, targeted)
	# Only the ghost under the crosshair shows its full close-up look
	show_simple_look(not targeted)


## For a template's preview: shown only (never solid, never counted as a piece or a fire), in its
## simplified look and without its shadow copy (a preview casts no shadow; see TemplatePlacer)
func make_preview_only() -> void:
	for shadow in _shadow_looks:
		shadow.visible = false
	show_simple_look(true)
	collision_layer = 0
	collision_mask = 0
	remove_from_group("build_pieces")
	remove_from_group("campfires")
	if _hearth_smoke:
		_hearth_smoke.emitting = false
		_hearth_smoke.visible = false


## A chimney section or top: passes through roofs, and carries the fireplace's smoke up
func is_chimney() -> bool:
	return _def.get("chimney", false)


## For a chimney piece: the middle of its top, in the world
func chimney_top() -> Vector3:
	return global_transform * Vector3(0, _def.get("chimney_height", 0.0), 0)


# The box round every mesh in a model, in the model's own space
static func _model_bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var look := found as MeshInstance3D
		var xform := Transform3D.IDENTITY
		var n: Node = look
		while n != model and n is Node3D:
			xform = (n as Node3D).transform * xform
			n = n.get_parent()
		var part: AABB = xform * look.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func display_name() -> String:
	return buildable.display_name if buildable else "Piece"


## Its snap points in the world: [{"position", "yaw", "type"}]
func world_sockets() -> Array:
	var found := []
	for socket in _def["sockets"]:
		var world := {
			"position": global_transform * (socket["position"] as Vector3),
			"yaw": global_rotation.y + socket["yaw"],
			"type": socket["type"],
		}
		# An edge snap point also brings its edge (see PieceShapes._edge_sockets)
		if socket.has("edge_dir"):
			world["edge_dir"] = global_basis * (socket["edge_dir"] as Vector3)
			world["edge_in"] = global_basis * (socket["edge_in"] as Vector3)
			world["edge_t"] = socket["edge_t"]
			world["edge_len"] = socket["edge_len"]
			if socket.get("edge_cap", false):
				world["edge_cap"] = true
		found.append(world)
	return found


## A roof (or cone roof) section: standing under it counts as shelter
func is_roof() -> bool:
	return _def.get("roof", false)


## A floor or round floor wedge
func is_floor() -> bool:
	return _def.get("floor", false)


## Furniture (a bed, a shelf...): counts toward a plot's requirements by its name
func is_furniture() -> bool:
	return _def.get("furniture", false)


## Furniture that backs up flush against a wall when placed near one (bed, shelves, tool rack)
func backs_to_wall() -> bool:
	return _def.get("backs_to_wall", false)


# ---- The fireplace ----
#
# It burns all the time (no fuel yet) and warms you like a campfire: it's in the "campfires"
# group, so the player's warmth and a warm night's sleep count it.

const HEARTH_HEAT_RADIUS := 6.0

## The hearth light: a soft warm amber, faint by day and brighter at night (by the sun's daylight)
const HEARTH_COLOR := Color(1.0, 0.76, 0.5)
const HEARTH_DAY_ENERGY := 0.35
const HEARTH_NIGHT_ENERGY := 1.15

## The render layers left out of the hearth light's shadow: foliage (see foliage.gd FOLIAGE_LAYER)
const HEARTH_SHADOW_SKIPS := 1 << 1

var _hearth_light: OmniLight3D
var _hearth_flame: Node3D
var _hearth_energy := HEARTH_NIGHT_ENERGY


## A fire that's burning (only the fireplace, which always is)
func is_lit() -> bool:
	return _def.get("hearth", false) and not _ghost


## How close you need to be to feel its heat
func heat_radius() -> float:
	return HEARTH_HEAT_RADIUS


func _make_hearth_fire() -> void:
	add_to_group("campfires")
	_hearth_light = OmniLight3D.new()
	_hearth_light.light_color = HEARTH_COLOR
	_hearth_light.light_energy = HEARTH_NIGHT_ENERGY
	_hearth_light.omni_range = 6.0
	_hearth_light.omni_attenuation = 1.4
	_hearth_light.shadow_enabled = true
	# Its shadow leaves out grass, ferns and scattered rocks (each patch is one big object, drawn
	# whole into all six sides of its shadow), and stops once you're well away: from 20 m off a
	# small light's shadow can't be seen. The light itself fades out from 40 m.
	_hearth_light.shadow_caster_mask = 0xFFFFFFFF & ~HEARTH_SHADOW_SKIPS
	_hearth_light.distance_fade_enabled = true
	_hearth_light.distance_fade_begin = 40.0
	_hearth_light.distance_fade_shadow = 20.0
	_hearth_light.distance_fade_length = 5.0
	# Where the flames burn, inside the hearth (PieceShapes.HEARTH_FIRE); the light just in front
	var fire: Vector3 = _def.get("hearth_at", Vector3.ZERO)
	_hearth_light.position = fire + Vector3(0, 0.25, 0.4)
	add_child(_hearth_light)
	# A particle fire burning on logs in the hearth (the logs come with the close-up look, see dress)
	_hearth_flame = FireEffects.make_fire(0.85)
	_hearth_flame.position = fire + Vector3(0, 0.06, 0)
	add_child(_hearth_flame)
	_hearth_smoke = FireEffects.make_smoke()
	_hearth_smoke.name = "ChimneySmoke"
	_hearth_smoke.top_level = true
	_hearth_smoke.emitting = false
	add_child(_hearth_smoke)


# ---- Chimney smoke ----
#
# While the fireplace burns, soft grey smoke rises from the top of the chimney stacked on it: from
# a chimney top if there is one, or else from the highest section (it's never drawn from the
# fireplace's own chimney, which reads as part of the stack). Looked for again every second.

const SMOKE_CHECK := 1.0
## How close (sideways) a chimney piece's bottom must be to the top it stands on to count
const STACK_SNAP := 0.06

var _hearth_smoke: GPUParticles3D
var _smoke_check_in := 0.0


# Where the smoke comes out: the top of the chimney stack standing on this fireplace, or null if
# nothing's stacked on it
func _stack_top() -> Variant:
	var spot: Vector3 = global_transform * PieceShapes.FIREPLACE_CHIMNEY
	var found := false
	for i in 32:
		var next: BuildPiece = null
		for piece in get_tree().get_nodes_in_group("build_pieces"):
			var bp := piece as BuildPiece
			if bp == null or not bp.is_chimney() or bp.is_ghost() or bp.is_queued_for_deletion():
				continue
			var at := bp.global_position
			if Vector2(at.x - spot.x, at.z - spot.z).length() < STACK_SNAP and absf(at.y - spot.y) < STACK_SNAP:
				next = bp
				break
		if next == null:
			break
		found = true
		spot = next.chimney_top()
		if not next.buildable.shape == "chimney_section":
			break
	return spot if found else null


func _update_smoke(delta: float) -> void:
	_smoke_check_in -= delta
	if _smoke_check_in > 0.0:
		return
	_smoke_check_in = SMOKE_CHECK
	var top = _stack_top()
	var burning := is_lit() and top != null
	_hearth_smoke.emitting = burning
	if burning:
		_hearth_smoke.global_position = (top as Vector3) + Vector3.UP * 0.05


func _process(delta: float) -> void:
	if _hearth_light == null:
		set_process(false)
		return
	_update_smoke(delta)
	# Faint by day, cosy at night, easing between them; flickering either way
	var sun = get_tree().get_first_node_in_group("sun")
	var daylight: float = sun.daylight if sun else 0.0
	_hearth_energy = lerpf(_hearth_energy, lerpf(HEARTH_NIGHT_ENERGY, HEARTH_DAY_ENERGY, daylight), 1.0 - exp(-2.0 * delta))
	var t := Time.get_ticks_msec() * 0.001 + float(piece_id)
	var flicker := sin(t * 11.0) * 0.5 + sin(t * 6.7) * 0.3 + sin(t * 23.0) * 0.2
	_hearth_light.light_energy = _hearth_energy * (1.0 + flicker * 0.18)


## The middle of its solid parts, in the world: a plot owns it if this is inside the plot
func center() -> Vector3:
	return global_transform * PieceShapes.bounds_of(_def).get_center()


## Its shape's look, collision and snap points (see PieceShapes.build)
func shape_def() -> Dictionary:
	return _def


## Lays a glow over the piece (the hammer's demolish target shows red), or takes it off (null)
func set_highlight(glow: Material) -> void:
	for look in find_children("*", "GeometryInstance3D", true, false):
		(look as GeometryInstance3D).material_overlay = glow
	# (a ghost without a glow goes back to its own fade and outline)
	if glow == null and _ghost:
		_fade_looks(GHOST_TARGET_FADE if _ghost_targeted else GHOST_FADE, _ghost_targeted)


## Slender: a pillar, pole, beam or ladder (these only bump into each other)
func is_slender() -> bool:
	return _def.get("slender", false)


## An eave, gable overhang or eave corner: these only bump into each other (they tuck over wall
## tops and gables), and don't count as roof for shelter
func is_overhang() -> bool:
	return _def.get("overhang", false)


## A ladder: W climbs it while you look at it
func is_ladder() -> bool:
	return _def.get("ladder", false)


func is_door() -> bool:
	return not _door_parts.is_empty()


## True unless it's a door standing open
func is_closed() -> bool:
	return not (is_door() and _door_open)


## The circle of grass it keeps clear (radius 0 for none), from its origin
func clear_area() -> Dictionary:
	return {"center": _def.get("clear_center", Vector3.ZERO), "radius": _def.get("clear_radius", 0.0)}


# ---- Doors ----

## Doors open and close; a Storehouse's storage opens town storage (see TownStorage)
func can_interact() -> bool:
	return is_door() or _storage_plot() != null


func get_prompt() -> String:
	if is_door():
		return "Close Door" if _door_open else "Open Door"
	var plot := _storage_plot()
	if plot == null:
		return ""
	return "Open town storage" if plot.working else "Town storage (Storehouse not working)"


func interact(player) -> void:
	if is_door():
		set_open(not _door_open)
		return
	var plot := _storage_plot()
	if plot == null:
		return
	if plot.working:
		player.open_town_storage(self)
	else:
		player.flash("%s isn't working, so its town storage is closed" % plot.plot_name)


# The Storehouse (any plot holding town storage) this is the storage of, or null
func _storage_plot() -> Plot:
	if _ghost or owner_plot.is_empty() or not is_inside_tree():
		return null
	var plots := get_tree().get_first_node_in_group("plot_registry") as PlotRegistry
	var plot: Plot = plots.find(owner_plot) if plots else null
	if plot and plot.plot_type.town_storage_slots > 0 and display_name() == plot.plot_type.town_storage_item:
		return plot
	return null


## Swings the door open or shut (at once, when `instantly`, for loading a save)
func set_open(open: bool, instantly := false) -> void:
	_door_open = open
	var target := DOOR_OPEN_DEGREES if open else 0.0
	if _door_tween:
		_door_tween.kill()
	if instantly:
		_set_door_angle(target)
		return
	_door_tween = create_tween()
	_door_tween.tween_method(_set_door_angle, _door_angle, target, DOOR_SWING_SECONDS).set_trans(Tween.TRANS_SINE)


# Turns the door's parts about its hinge, down its left edge
func _set_door_angle(degrees: float) -> void:
	_door_angle = degrees
	var hinge := Vector3(-(PieceShapes.DOOR_WIDTH - 0.04) / 2.0, 0, 0)
	var swing := Transform3D(Basis.IDENTITY, hinge) * Transform3D(Basis(Vector3.UP, deg_to_rad(-degrees)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -hinge)
	for part in _door_parts:
		part["node"].transform = swing * (part["rest"] as Transform3D)


## What the save keeps of it beyond where it is (a door's open or shut, and whether it's a ghost)
func save_state() -> Dictionary:
	var state := {}
	if _door_open:
		state["open"] = true
	if _ghost:
		state["ghost"] = true
	return state


func load_state(state: Dictionary) -> void:
	if state.get("open", false):
		set_open(true, true)
	if state.get("ghost", false):
		set_ghost(true)
