class_name BuildPlacer
extends Node
## Puts a chosen buildable down in the world: a see-through preview follows the crosshair along
## the ground, green where it can go and red where it can't. Nothing is spent until it's placed.
## Building pieces (floors, walls, roofs...) snap together, so they're handed to the ValheimPlacer;
## the PieceRegistry keeps track of every piece placed.

## How far ahead of the camera the crosshair picks a spot. Beyond this (or at the sky), the
## preview sits on the ground beneath that point instead.
const REACH := 8.0
const DROP_DISTANCE := 300.0
const GOOD_COLOR := Color(0.25, 1.0, 0.35, 0.45)
const BAD_COLOR := Color(1.0, 0.2, 0.15, 0.45)
## Placeable, with a warning (steep ground, water)
const WARN_COLOR := Color(1.0, 0.85, 0.2, 0.45)
## Every building keeps the grass and ferns out of its footprint, plus this much around it (m)
const CLEAR_MARGIN := 0.5
const CLEAR_ZONE_SCENE := preload("res://building/clear_zone.tscn")
# Marks a building with the buildable it was made from (its resource path)
const BUILDABLE_META := &"buildable"

## Every building piece in the world, and every plot
var registry: PieceRegistry
var plots: PlotRegistry

var _player: CharacterBody3D
var _pieces: ValheimPlacer
var _demolisher: Demolisher
var _plot_placer: PlotPlacer
# Placing a template, and building a placed template's ghosts
var _templates: TemplatePlacer
var _ghosts: GhostBuilder
# Painting dirt paths (the Paths tab's Dirt Path tool)
var _paths: PathPainter
# A ghost was taken away on the middle button's press: its release does nothing more
var _ghost_removed := false
var _buildable: Buildable
var _preview: Node3D
var _material: StandardMaterial3D
# (it's turned by the same turn as pieces, about where it stands, from a floor's facing or facing
# out of a wall: see ValheimPlacer.turn)
# The preview's box (from its meshes), for standing it flush and checking it on a floor
var _bounds := AABB()
var _on_floor := false
# Why it can't go where the preview is. Empty means it can.
var _problem := ""
# Worth knowing but not stopping it (water or steep ground under it), shown in yellow
var _warning := ""


func _ready() -> void:
	_player = get_parent()
	set_physics_process(false)
	add_to_group("saveable")
	registry = PieceRegistry.new()
	registry.world = _player.get_parent()
	add_child(registry)
	plots = PlotRegistry.new()
	plots.world = _player.get_parent()
	plots.pieces = registry
	add_child(plots)
	registry.changed.connect(plots.mark_dirty)
	_demolisher = Demolisher.new()
	_demolisher.registry = registry
	add_child(_demolisher)
	_pieces = ValheimPlacer.new()
	_pieces.registry = registry
	_pieces.plots = plots
	_pieces.demolisher = _demolisher
	add_child(_pieces)
	_plot_placer = PlotPlacer.new()
	_plot_placer.plots = plots
	_plot_placer.pieces = _pieces
	_plot_placer.builder = self
	add_child(_plot_placer)
	_templates = TemplatePlacer.new()
	_templates.registry = registry
	_templates.plots = plots
	_templates.pieces = _pieces
	_templates.builder = self
	add_child(_templates)
	_ghosts = GhostBuilder.new()
	_ghosts.registry = registry
	_ghosts.plots = plots
	_ghosts.pieces = _pieces
	_ghosts.builder = self
	add_child(_ghosts)
	_paths = PathPainter.new()
	_paths.player = _player
	add_child(_paths)


## True while placing something (or a template, or marking out, moving or resizing a plot): the
## clicks, R and Esc are ours then
func is_placing() -> bool:
	return _buildable != null or _pieces.is_placing() or _plot_placer.is_active() or _templates.is_active() or _paths.is_active()


# ---- Ghosts (a placed template's pieces still to be built; see GhostBuilder) ----

## Called every frame: `active` while the hammer is out, nothing is being placed and no menu is open
func update_ghosts(delta: float, active: bool) -> void:
	_ghosts.update(delta, active and not is_placing())


## Left-click with the hammer, nothing being placed: builds the ghost under the crosshair (and keeps
## going while held). False if there's no ghost there.
func press_ghost() -> bool:
	return _ghosts.press()


func release_ghost() -> void:
	_ghosts.release()


## Puts a ghost workbench, chest or campfire down for a plot (placing a template, or loading a save)
func place_ghost_building(buildable: Buildable, where: Transform3D, plot_id: String) -> GhostBuilding:
	var ghost := GhostBuilding.create(buildable)
	if not plot_id.is_empty():
		ghost.set_meta(PlotRegistry.OWNER_META, plot_id)
	_player.get_parent().add_child(ghost)
	# (turned, tilted and tipped as it was placed)
	ghost.global_transform = Transform3D(where.basis.orthonormalized(), where.origin)
	return ghost


## Builds a ghost workbench, chest or campfire for real (paid for already), in its place and plot
func fill_ghost_building(ghost: GhostBuilding, _paid: Dictionary) -> Node3D:
	var built := build(ghost.buildable, ghost.global_position, ghost.global_rotation.y)
	built.global_basis = ghost.global_basis.orthonormalized()
	PeopleMover.clear_from([built])
	var plot_id := str(ghost.get_meta(PlotRegistry.OWNER_META, ""))
	if not plot_id.is_empty():
		plots.set_plot_of(built, plot_id)
	plots.remove_ghost(ghost)
	return built


## True while marking out, moving or resizing a plot
func is_plot_mode() -> bool:
	return _plot_placer.is_active()


## Starts placing something, at the turn the player last set (it stays until they change it).
## (`keep`, from switching in the build menu while placing, changes nothing now.)
func begin(buildable: Buildable, keep := false) -> void:
	cancel()
	if buildable is PathTool:
		_paths.begin(buildable)
		return
	if buildable is TemplateBuildable:
		_templates.begin(buildable)
		return
	if buildable is PlotType:
		_plot_placer.begin_new(buildable)
		return
	if buildable is PieceBuildable:
		_pieces.begin(buildable, keep)
		return
	_buildable = buildable
	_problem = "Point at the ground"
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview = _make_preview(buildable.scene)
	_preview.visible = false
	_bounds = _mesh_bounds(_preview)
	_player.get_parent().add_child(_preview)
	set_physics_process(true)


## What's being placed (a piece, a workbench, chest or campfire, or a plot being marked out), to
## come back to after the build menu; null for none (or a plot being moved or resized)
func current_buildable() -> Buildable:
	if _buildable:
		return _buildable
	if _pieces.is_placing():
		return _pieces.current()
	if _templates.is_active():
		return _templates.current()
	if _paths.is_active():
		return _paths.current()
	return _plot_placer.placing_type()


## Stops placing without spending anything
func cancel() -> void:
	if _preview:
		_preview.queue_free()
	_preview = null
	_buildable = null
	set_physics_process(false)
	_pieces.cancel()
	_plot_placer.cancel()
	_templates.cancel()
	_paths.cancel()


## Lifts a plot and everything it owns, to put down somewhere else (see PlotPlacer)
func move_plot(plot: Plot) -> void:
	cancel()
	_plot_placer.begin_move(plot)


## Plot view on or off (call every frame): every plot's outline and label show, and with nothing
## being placed, the plot edge or corner under the crosshair lights up, ready to drag
func update_plot_view(on: bool) -> void:
	plots.set_view(on)
	_plot_placer.hover(on and not is_placing())


## Left-click pressed in plot view: starts dragging the plot edge or corner under the crosshair.
## True if it did.
func try_grab_plot() -> bool:
	return _plot_placer.try_grab()


# ---- Demolishing ----
#
# With the hammer out, placing or not: the middle mouse button (the piece glows red while it's
# held, and comes down on release) or holding X. Placing carries on afterwards as it was (the
# same piece and turn). See Demolisher.

## Middle button pressed: on a ghost, takes it away at once (free); otherwise picks the piece under
## the crosshair
func press_demolish() -> void:
	# (painting paths: the middle button rubs path out instead)
	if _paths.is_active():
		_paths.set_erase_button(true)
		return
	_ghost_removed = not is_placing() and _ghosts.remove_targeted()
	if not _ghost_removed:
		_demolisher.press()


## Middle button released: takes the picked piece down, if still aimed at (`active` is false if
## the hammer was put away or a menu opened meanwhile)
func release_demolish(active: bool) -> void:
	if _paths.is_active():
		_paths.set_erase_button(false)
		return
	if _ghost_removed:
		_ghost_removed = false
		return
	_demolisher.release(active)


## Called every frame: the red glow on the piece that would come down, and X's hold
func update_demolish(delta: float, active: bool, holding_x: bool) -> void:
	# (painting paths: X rubs path out instead, and nothing is picked to come down)
	if _paths.is_active():
		_paths.update(active, holding_x)
		_demolisher.update(delta, false, false)
		return
	_demolisher.update(delta, active, holding_x)


## Takes the keys and clicks that mean something while placing. Returns true if it used this one.
func handle_input(event: InputEvent) -> bool:
	if _paths.is_active():
		return _paths.handle_input(event)
	if _templates.is_active():
		return _templates.handle_input(event)
	if _plot_placer.is_active():
		return _plot_placer.handle_input(event)
	if _pieces.is_placing():
		return _pieces.handle_input(event)
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		# Finish or cancel this one before putting the hammer away (Tab opens the build menu)
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			return true
	# As for pieces: the wheel turns it (the same turn) about where it stands
	if event is InputEventMouseButton and event.pressed and _pieces.turn_by_wheel(event):
		return true
	# A click while the mouse is free just grabs it again, as it does any other time
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return true
	return false


## What the on-screen controls show with the hammer out (see HudControls): {"controls":
## [[label, key], ...], "info": the piece panel, or empty}. Placing, or just holding the hammer;
## holding X shows the piece it would demolish.
func hud_state() -> Dictionary:
	if _paths.is_active():
		return _paths.hud_state()
	if _templates.is_active():
		return _templates.hud_state()
	if _plot_placer.is_active():
		return _plot_placer.hud_state()
	var state: Dictionary
	if _pieces.is_placing():
		state = _pieces.hud_state()
	elif _buildable:
		# Just the piece, its cost, and its turn when it's turned (plus why it can't go, or a warning)
		var details: PackedStringArray = []
		if not is_zero_approx(_pieces.turn):
			details.append(ValheimPlacer.turn_text(_pieces.turn))
		if not _problem.is_empty():
			details.append(_problem)
		elif not _warning.is_empty():
			details.append(_warning)
		state = {
			"controls": ValheimPlacer.FURNITURE_CONTROLS,
			"info": {
				"icon": _buildable.icon,
				"title": _buildable.display_name,
				"cost": _buildable.cost_text(),
				"cost_bad": not _buildable.can_afford(_player.inventory),
				"detail": "  ·  ".join(details),
				"detail_bad": not _problem.is_empty(),
				"detail_warn": _problem.is_empty() and not _warning.is_empty(),
			},
		}
	elif not _ghosts.info().is_empty():
		# Aimed at a ghost: its name and cost, and how to build it
		state = {
			"controls": [["Build", "LMB"], ["Keep building", "Hold LMB"], ["Remove ghost", "MMB"], ["Build menu", "Tab"], ["Plot view", "P"]],
			"info": _ghosts.info(),
		}
	else:
		var controls := [["Build menu", "Tab"], ["Demolish", "MMB / Hold X"], ["Plot view", "P"]]
		# Aimed at a plot (its ground or one of its pieces): E opens its panel, to move it (M there)
		if _player.call("_looked_at") is Plot:
			controls.push_front(["Plot: move, resize…", "E"])
		# In plot view, on a plot's edge or corner: drag to resize
		if _plot_placer.can_grab():
			controls.push_front(["Resize plot", "Drag LMB"])
		state = {"controls": controls, "info": {}}
	# Holding X: the piece it would demolish takes the panel
	var demolishing := _demolisher.info()
	if not demolishing.is_empty():
		state["info"] = demolishing
	return state


# It stands on the floor, foundation or ground under the crosshair, like furniture (see
# FurnitureSpot): on a floor's 0.5 m grid with snapping on, the workbench backing up against a wall
func _physics_process(_delta: float) -> void:
	var camera: Camera3D = _player.camera
	var far_point := camera.global_position - camera.global_basis.z * REACH
	var hit := _cast_ray(camera.global_position, far_point)
	var drop := far_point
	if hit.is_empty():
		var below := _cast_ray(far_point, far_point + Vector3.DOWN * DROP_DISTANCE)
		if not below.is_empty():
			drop = below["position"] + Vector3.UP * 0.5
	# Where it stands at its starting alignment (a floor's facing, or out of a wall it backs onto),
	# then turned about that spot as the player asked
	var spot := _pieces.furniture_spot(hit, drop, _bounds, _buildable.backs_to_wall)
	_preview.visible = not spot.is_empty()
	if spot.is_empty():
		_problem = "Point at the ground"
		return
	var start: Transform3D = spot["where"]
	_preview.global_transform = ValheimPlacer.turned(start, start.origin, _pieces.turn)
	_on_floor = spot["on_floor"]
	_problem = _check_spot(spot)
	_material.albedo_color = BAD_COLOR if not _problem.is_empty() else (WARN_COLOR if not _warning.is_empty() else GOOD_COLOR)


func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query)


# Why this spot won't do, or an empty string if it will. Like building pieces, nothing stops it:
# it may overlap anything, and you or a settler standing there glide aside when it goes down (see
# PeopleMover). Water or steep ground under it is a warning (shown in yellow), not a block.
func _check_spot(spot: Dictionary) -> String:
	var where: Transform3D = spot["where"]
	_warning = ""
	if not spot["on_floor"]:
		var valley = get_tree().get_first_node_in_group("valley")
		if valley and where.origin.y < valley.global_position.y + valley.water_height():
			_warning = "In the water"
		elif rad_to_deg((spot["normal"] as Vector3).angle_to(Vector3.UP)) > _buildable.max_slope_degrees:
			_warning = "Steep ground"
	return ""


# The box round a preview's meshes, in its own space
func _mesh_bounds(preview: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for look in preview.get_children():
		if look is MeshInstance3D and look.mesh:
			var part: AABB = look.transform * look.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
	return box


# The ground, or a built floor: a campfire, workbench or chest can stand on either
func _is_ground(collider: Object) -> bool:
	return collider.is_in_group("terrain_ground") or (collider is BuildPiece and collider.is_floor())


func _place() -> void:
	if not _problem.is_empty():
		_player.flash(_problem)
		return
	var cost := _buildable.cost_to_pay(_player.inventory)
	if cost.is_empty():
		_player.flash("You no longer have enough for a %s" % _buildable.display_name)
		cancel()
		return
	_player.pay(cost)

	var built := build(_buildable, _preview.global_position, _preview.global_rotation.y)
	# (turned as the preview was)
	built.global_basis = _preview.global_basis.orthonormalized()
	PeopleMover.clear_from([built])
	var plot := _plot_here()
	if plot:
		plots.set_plot_of(built, plot.plot_id)
	plots.mark_dirty()
	if not _buildable.placed_message.is_empty():
		_player.flash(_buildable.placed_message)
	var built_name := _buildable.display_name
	cancel()
	_player.report_progress("Build", built_name)


## Puts a building in the world (for placing it, and when loading a save): the scene, where and
## which way it faces, and the Clear Zone under it. Every building is kept in the "buildings"
## group, and remembers which buildable it is, so the save can list them.
func build(buildable: Buildable, where: Vector3, turn: float) -> Node3D:
	var built: Node3D = buildable.scene.instantiate()
	built.set_meta(BUILDABLE_META, buildable.resource_path)
	built.add_to_group("buildings")
	_player.get_parent().add_child(built)
	built.global_position = where
	built.rotation.y = turn
	_clear_plants_under(built, buildable.footprint_radius + CLEAR_MARGIN)
	return built


func save_key() -> String:
	return "buildings"


func save_priority() -> int:
	return 30


## Every building: which buildable, where, which way, and its own state if it keeps any (a
## building with save_data() and load_data() of its own, like the campfire, adds what it needs)
func save_data() -> Dictionary:
	var list: Array = []
	for built in get_tree().get_nodes_in_group("buildings"):
		var entry := {
			"buildable": built.get_meta(BUILDABLE_META, ""),
			"position": SaveGame.from_vector(built.global_position),
			"turn": built.rotation.y,
		}
		# Tilted or tipped: its whole rotation too
		if SaveGame.is_leaning(built.global_basis):
			entry["rotation"] = SaveGame.from_rotation(built.global_basis)
		if built.has_method("save_data"):
			entry["state"] = built.save_data()
		if built.has_meta(PlotRegistry.OWNER_META):
			entry["plot"] = built.get_meta(PlotRegistry.OWNER_META)
		list.append(entry)
	# Ghost workbenches, chests and campfires (a placed template's, not built yet)
	var ghosts: Array = []
	for ghost in plots.ghost_buildings():
		var entry := {
			"buildable": ghost.get_meta(BUILDABLE_META, ""),
			"position": SaveGame.from_vector(ghost.global_position),
			"turn": ghost.global_rotation.y,
			"plot": ghost.get_meta(PlotRegistry.OWNER_META, ""),
		}
		if SaveGame.is_leaning(ghost.global_basis):
			entry["rotation"] = SaveGame.from_rotation(ghost.global_basis)
		ghosts.append(entry)
	return {"list": list, "ghosts": ghosts}


# (older saves also hold "snapping", from the snap toggle there used to be: it's ignored)
func load_data(data: Dictionary) -> void:
	for built in get_tree().get_nodes_in_group("buildings"):
		built.queue_free()
	for ghost in plots.ghost_buildings():
		ghost.remove_from_group("ghost_buildings")
		ghost.queue_free()
	for entry in data.get("ghosts", []):
		var ghost_of := load(str(entry.get("buildable", ""))) as Buildable
		if ghost_of:
			var where := Transform3D(SaveGame.to_rotation(entry), SaveGame.to_vector(entry.get("position")))
			place_ghost_building(ghost_of, where, str(entry.get("plot", "")))
	for entry in data.get("list", []):
		var buildable := load(str(entry.get("buildable", ""))) as Buildable
		if buildable == null:
			continue
		var built := build(buildable, SaveGame.to_vector(entry.get("position")), float(entry.get("turn", 0.0)))
		built.global_basis = SaveGame.to_rotation(entry)
		if built.has_method("load_data") and entry.has("state"):
			built.load_data(entry["state"])
		if not str(entry.get("plot", "")).is_empty():
			built.set_meta(PlotRegistry.OWNER_META, str(entry["plot"]))


# ---- For plots ----

# The plot the thing being placed would belong to (the preview's spot is inside), or null
func _plot_here() -> Plot:
	if _preview == null or not _preview.visible:
		return null
	return plots.find(plots.owner_for(_preview.global_position, _player.global_position))


## Takes down a piece, or a workbench, chest or campfire, and returns what it gives back: what a
## piece cost, or a building's (first) cost plus anything stored in it. For shrinking a plot.
func take_down(item: Node3D) -> Dictionary:
	if item is GhostBuilding:
		plots.remove_ghost(item)
		return {}
	if item is BuildPiece:
		var paid: Dictionary = item.paid.duplicate()
		registry.remove(item)
		return paid
	var refund := {}
	var buildable := load(str(item.get_meta(BUILDABLE_META, ""))) as Buildable
	if buildable and not buildable.costs.is_empty():
		refund = buildable.costs[0].duplicate()
	var stored = item.get("contents")
	if stored is Dictionary:
		for thing in stored:
			refund[thing] = int(refund.get(thing, 0)) + int(stored[thing])
	var valley = get_tree().get_first_node_in_group("valley")
	for zone in item.find_children("*", "Node3D", true, false):
		if zone.has_meta(&"under_building") and valley:
			valley.remove_clear_zone(zone)
	item.remove_from_group("buildings")
	item.queue_free()
	plots.mark_dirty()
	return refund


# Puts a Clear Zone under a new building that keeps grass, ferns, scattered boulders and small
# painted decorations out (trees and resources are left alone: they're solid, so they'd have
# stopped the building being placed), and has the valley clear them away. Nothing respawns in it.
func _clear_plants_under(built: Node3D, radius: float) -> void:
	var zone: Node3D = CLEAR_ZONE_SCENE.instantiate()
	zone.clear_trees = false
	zone.clear_resources = false
	zone.clear_rocks = true
	zone.clear_plants = true
	zone.set_meta(&"under_building", true)
	zone.radius = maxf(radius, 1.0)
	built.add_child(zone)
	var valley = get_tree().get_first_node_in_group("valley")
	if valley:
		valley.add_clear_zone(zone)


# Copies just the visible meshes of a scene. The scene itself is never added to the world, so
# its scripts don't run: a preview campfire mustn't count as a real one, or block itself.
func _make_preview(scene: PackedScene) -> Node3D:
	var original: Node3D = scene.instantiate()
	var preview := Node3D.new()
	_copy_meshes(original, Transform3D.IDENTITY, preview)
	original.free()
	return preview


func _copy_meshes(node: Node, parent_transform: Transform3D, preview: Node3D) -> void:
	for child in node.get_children():
		if not child is Node3D or not child.visible:
			continue
		var child_transform: Transform3D = parent_transform * child.transform
		if child is MeshInstance3D:
			var ghost := MeshInstance3D.new()
			ghost.mesh = child.mesh
			ghost.transform = child_transform
			ghost.material_override = _material
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			preview.add_child(ghost)
		_copy_meshes(child, child_transform, preview)
