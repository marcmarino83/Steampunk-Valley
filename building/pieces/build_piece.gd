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
## Ghost pieces: their full detailed look in a soft see-through grey (#9a9a9a), with slightly
## lighter grey edges (ghost_look.gdshader); the ghost under the crosshair brightens. Each surface
## is fainter than the look as a whole: a wall's planks lie over its core, so the layers together
## come to about 30% opaque.
const GHOST_LOOK_SHADER := preload("res://building/templates/ghost_look.gdshader")
const GHOST_COLOR := Color(0.604, 0.604, 0.604, 0.15)
const GHOST_EDGE_COLOR := Color(0.72, 0.72, 0.72, 0.45)
const GHOST_TARGET_COLOR := Color(0.7, 0.7, 0.7, 0.2)
const GHOST_TARGET_EDGE_COLOR := Color(0.82, 0.82, 0.82, 0.55)
static var _ghost_look: ShaderMaterial
static var _ghost_target_look: ShaderMaterial

# A ghost (a template's piece still to be built): what each look wore before, and the collision
# layer it had
var _ghost := false
var _ghost_saved := {}
var _solid_layer := 1

## Beyond this distance a piece shows its plain textured box instead of its close-up look
const DETAIL_RANGE := 60.0
const DETAIL_FADE := 4.0


## Builds it from its shape. Called before it's added to the world.
func setup(piece: PieceBuildable, def: Dictionary, material: Material) -> void:
	buildable = piece
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


## Gives it its close-up look (see PieceDetail: separate planks, logs, shakes, stones and rope),
## shown within DETAIL_RANGE; its plain textured box takes over beyond that. A door's panel gets
## its own close-up look, which swings with it. Nothing changes for a shape without one.
func dress(detail: Dictionary, material: Material) -> void:
	_dress_looks(detail, material)
	_nudge_looks()


## How far (meters, at most) each piece's look is nudged, so faces of overlapping pieces that
## lie in exactly the same plane don't flicker against each other
const NUDGE := 0.0025


# Every piece's look (not its collision) sits a hair off its true place, in a direction of its own
# picked from its id: overlapping pieces whose faces coincide then draw cleanly, one just in front
func _nudge_looks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(piece_id * 104729 + 31)
	var nudge := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * NUDGE * rng.randf_range(0.4, 1.0)
	for child in get_children():
		if child is MeshInstance3D or (child is Node3D and child.name == "Model"):
			(child as Node3D).position += nudge
	for part in _door_parts:
		if part["node"] is MeshInstance3D:
			part["rest"] = (part["rest"] as Transform3D).translated(nudge)


func _dress_looks(detail: Dictionary, material: Material) -> void:
	if _def.get("hearth", false):
		# Logs for the fire to burn on, in the hearth
		var logs := MeshInstance3D.new()
		logs.name = "HearthLogs"
		logs.mesh = PieceDetail.hearth_logs_mesh(piece_id)
		logs.material_override = material
		logs.position = _def.get("hearth_at", Vector3.ZERO)
		add_child(logs)
	if detail.is_empty() or detail.get("mesh") == null and detail.get("door_mesh") == null:
		return
	for plain in _plain_looks:
		plain.visibility_range_begin = DETAIL_RANGE
		plain.visibility_range_begin_margin = DETAIL_FADE
	for key in ["mesh", "door_mesh"]:
		var mesh: Mesh = detail.get(key)
		if mesh == null:
			continue
		var near := MeshInstance3D.new()
		near.name = "Detail" if key == "mesh" else "DoorDetail"
		near.mesh = mesh
		near.material_override = material
		near.visibility_range_end = DETAIL_RANGE
		near.visibility_range_end_margin = DETAIL_FADE
		add_child(near)
		if key == "door_mesh":
			_door_parts.append({"node": near, "rest": Transform3D.IDENTITY})


## Gives its textured surface (see piece_surface.gdshader) this piece's own slight colour and
## brightness, picked from its id so it stays the same every time, and its box, for the grime
## toward its edges. Called once it has its id.
func weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(piece_id * 7919 + 17)
	var bright := rng.randf_range(0.92, 1.05)
	var warm := rng.randf_range(-0.035, 0.035)
	var tint := Color(bright * (1.0 + warm), bright, bright * (1.0 - warm * 1.4))
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
	var box := PieceShapes.bounds_of(def)
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
	_ghost_look = null
	_ghost_target_look = null


# ---- Ghosts ----
#
# A ghost is a piece of a placed template that hasn't been built yet: its full detailed look in a
# soft see-through grey with slightly lighter edges, nothing solid (the player, settlers and every
# physics check pass through it), and it doesn't count as built for requirements, shelter or
# settlers. The hammer finds ghosts by their boxes (see GhostBuilder); filling one with materials
# turns it into the real piece.

## The grey ghost look (or the brighter one for the ghost under the crosshair)
static func ghost_material(targeted := false) -> ShaderMaterial:
	if _ghost_look == null:
		_ghost_look = ShaderMaterial.new()
		_ghost_look.shader = GHOST_LOOK_SHADER
		_ghost_look.set_shader_parameter("fill_color", GHOST_COLOR)
		_ghost_look.set_shader_parameter("edge_color", GHOST_EDGE_COLOR)
		_ghost_target_look = ShaderMaterial.new()
		_ghost_target_look.shader = GHOST_LOOK_SHADER
		_ghost_target_look.set_shader_parameter("fill_color", GHOST_TARGET_COLOR)
		_ghost_target_look.set_shader_parameter("edge_color", GHOST_TARGET_EDGE_COLOR)
	return _ghost_target_look if targeted else _ghost_look


func is_ghost() -> bool:
	return _ghost


## Turns it into a ghost, or back into the real piece
func set_ghost(on: bool) -> void:
	if on == _ghost:
		return
	_ghost = on
	if on:
		_solid_layer = collision_layer
		collision_layer = 0
		for look in find_children("*", "GeometryInstance3D", true, false):
			if look is GPUParticles3D:
				continue
			var shown := look as GeometryInstance3D
			_ghost_saved[shown] = [shown.material_override, shown.cast_shadow]
			shown.material_override = ghost_material()
			shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		collision_layer = _solid_layer
		for shown in _ghost_saved:
			if is_instance_valid(shown):
				shown.material_override = _ghost_saved[shown][0]
				shown.cast_shadow = _ghost_saved[shown][1]
		_ghost_saved.clear()
	# A ghost fireplace doesn't burn
	if _hearth_light:
		_hearth_light.visible = not on
		_hearth_flame.visible = not on
		_hearth_smoke.emitting = false
		if on:
			remove_from_group("campfires")
		else:
			add_to_group("campfires")


## The ghost under the crosshair shows brighter
func set_ghost_targeted(targeted: bool) -> void:
	if not _ghost:
		return
	for shown in _ghost_saved:
		if is_instance_valid(shown):
			shown.material_override = ghost_material(targeted)


## For a template's preview: shown only (never solid, never counted as a piece or a fire)
func make_preview_only() -> void:
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
