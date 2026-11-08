class_name BuildPlacer
extends Node
## Puts a chosen buildable down in the world: a see-through preview follows the crosshair along
## the ground, green where it can go and red where it can't. Nothing is spent until it's placed.
## Building pieces (floors, walls, roofs...) snap together, so they're handed to the PiecePlacer;
## the PieceRegistry keeps track of every piece placed.

## How far ahead of the camera the crosshair picks a spot. Beyond this (or at the sky), the
## preview sits on the ground beneath that point instead.
const REACH := 8.0
const DROP_DISTANCE := 300.0
const ROTATE_STEP := PI / 4.0
const GOOD_COLOR := Color(0.25, 1.0, 0.35, 0.45)
const BAD_COLOR := Color(1.0, 0.2, 0.15, 0.45)
const BLOCKED := "Something's in the way"
## How many things a spot's overlap check can report. Terrain chunks use up to four of them.
const MAX_OVERLAPS := 16
## Every building keeps the grass and ferns out of its footprint, plus this much around it (m)
const CLEAR_MARGIN := 0.5
const CLEAR_ZONE_SCENE := preload("res://building/clear_zone.tscn")
# Marks a building with the buildable it was made from (its resource path)
const BUILDABLE_META := &"buildable"

## Every building piece in the world, and every plot
var registry: PieceRegistry
var plots: PlotRegistry

var _player: CharacterBody3D
var _pieces: PiecePlacer
var _plot_placer: PlotPlacer
var _buildable: Buildable
var _preview: Node3D
var _material: StandardMaterial3D
var _footprint: CylinderShape3D
var _turn := 0.0
# Quarter turns from the floor's own facing, while snapped onto a floor
var _quarters := 0
# The preview's box (from its meshes), for standing it flush and checking it on a floor
var _bounds := AABB()
var _on_floor := false
var _snap_text := ""
# Why it can't go where the preview is. Empty means it can.
var _problem := ""


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
	_pieces = PiecePlacer.new()
	_pieces.registry = registry
	_pieces.plots = plots
	add_child(_pieces)
	_plot_placer = PlotPlacer.new()
	_plot_placer.plots = plots
	_plot_placer.pieces = _pieces
	_plot_placer.builder = self
	add_child(_plot_placer)


## True while placing something (or marking out, moving or resizing a plot): the clicks, R and Esc
## are ours then
func is_placing() -> bool:
	return _buildable != null or _pieces.is_placing() or _plot_placer.is_active()


## True while marking out, moving or resizing a plot
func is_plot_mode() -> bool:
	return _plot_placer.is_active()


## Starts placing something. `keep` carries the turn (and a piece's height) over from what was
## being placed before, as when switching from the build menu while placing.
func begin(buildable: Buildable, keep := false) -> void:
	cancel()
	if buildable is PlotType:
		_plot_placer.begin_new(buildable)
		return
	if buildable is PieceBuildable:
		_pieces.begin(buildable, keep)
		return
	_buildable = buildable
	if not keep:
		_turn = 0.0
		_quarters = 0
	_problem = "Point at the ground"
	_footprint = CylinderShape3D.new()
	_footprint.radius = buildable.footprint_radius
	_footprint.height = buildable.footprint_height
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
	return _plot_placer.placing_type()


## Z: snapping on or off for every piece (and the workbench, chest and campfire). Returns the
## new state.
func toggle_snapping() -> bool:
	_pieces.snapping = not _pieces.snapping
	return _pieces.snapping


func is_snapping() -> bool:
	return _pieces.snapping


## Stops placing without spending anything
func cancel() -> void:
	if _preview:
		_preview.queue_free()
	_preview = null
	_buildable = null
	set_physics_process(false)
	_pieces.cancel()
	_plot_placer.cancel()


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
# same piece, height and turn). See PiecePlacer.

## Middle button pressed: picks the piece under the crosshair
func press_demolish() -> void:
	_pieces.press_demolish()


## Middle button released: takes the picked piece down, if still aimed at (`active` is false if
## the hammer was put away or a menu opened meanwhile)
func release_demolish(active: bool) -> void:
	_pieces.release_demolish(active)


## Called every frame: the red glow on the piece that would come down, and X's hold
func update_demolish(delta: float, active: bool, holding_x: bool) -> void:
	_pieces.update_demolish(delta, active, holding_x)


## Takes the keys and clicks that mean something while placing. Returns true if it used this one.
func handle_input(event: InputEvent) -> bool:
	if _plot_placer.is_active():
		return _plot_placer.handle_input(event)
	if _pieces.is_placing():
		return _pieces.handle_input(event)
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			# Snapped, it turns a quarter at a time (squared up with a floor); free, an eighth
			if _pieces.snapping_now():
				_quarters = (_quarters + 1) % 4
			else:
				_turn = wrapf(_turn + ROTATE_STEP, 0.0, TAU)
			return true
		# Finish or cancel this one before putting the hammer away (Tab opens the build menu)
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
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
	if _plot_placer.is_active():
		return _plot_placer.hud_state()
	var state: Dictionary
	if _pieces.is_placing():
		state = _pieces.hud_state()
	elif _buildable:
		var details: PackedStringArray = []
		var plot := _plot_here()
		if plot:
			details.append("Building for: %s" % plot.plot_name)
		details.append(_snap_text if not _snap_text.is_empty() else ("Free" if _pieces.snapping_now() else "Snap off"))
		if not _problem.is_empty():
			details.append(_problem)
		state = {
			"controls": [["Place", "LMB"], ["Rotate", "R"], ["Snap", "Z"], ["Demolish", "MMB / Hold X"], ["Cancel", "RMB"]],
			"info": {
				"icon": _buildable.icon,
				"title": _buildable.display_name,
				"cost": _buildable.cost_text(),
				"cost_bad": not _buildable.can_afford(_player.inventory),
				"detail": "  ·  ".join(details),
				"detail_bad": not _problem.is_empty(),
			},
		}
	else:
		var controls := [["Build menu", "Tab"], ["Demolish", "MMB / Hold X"], ["Snap", "Z"], ["Plot view", "P"]]
		# In plot view, on a plot's edge or corner: drag to resize
		if _plot_placer.can_grab():
			controls.push_front(["Resize plot", "Drag LMB"])
		state = {"controls": controls, "info": {}}
	# Holding X: the piece it would demolish takes the panel
	var demolishing := _pieces.demolish_info()
	if not demolishing.is_empty():
		state["info"] = demolishing
	return state


# It stands on the floor, foundation or ground under the crosshair, like furniture (see
# PiecePlacer.furniture_spot): on a floor's 0.5 m grid with snapping on, the workbench backing up
# against a wall
func _physics_process(_delta: float) -> void:
	var camera: Camera3D = _player.camera
	var far_point := camera.global_position - camera.global_basis.z * REACH
	var hit := _cast_ray(camera.global_position, far_point)
	var drop := far_point
	if hit.is_empty():
		var below := _cast_ray(far_point, far_point + Vector3.DOWN * DROP_DISTANCE)
		if not below.is_empty():
			drop = below["position"] + Vector3.UP * 0.5
	var spot := _pieces.furniture_spot(hit, drop, _bounds, _buildable.backs_to_wall, _quarters, _turn, [])
	_preview.visible = not spot.is_empty()
	if spot.is_empty():
		_problem = "Point at the ground"
		_snap_text = ""
		return
	_preview.global_transform = spot["where"]
	_on_floor = spot["on_floor"]
	_snap_text = spot["snap"]
	_problem = _check_spot(spot)
	_material.albedo_color = GOOD_COLOR if _problem.is_empty() else BAD_COLOR


func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query)


# Why this spot won't do, or an empty string if it will. On a floor it only mustn't overlap
# walls, furniture or anything else solid (its own box, so it can stand flush against a wall); on
# the ground it also needs dry, gentle ground and its whole footprint clear, as before.
func _check_spot(spot: Dictionary) -> String:
	var where: Transform3D = spot["where"]
	if spot["on_floor"]:
		return BLOCKED if _box_overlaps(where) else ""
	var valley = get_tree().get_first_node_in_group("valley")
	if valley and where.origin.y < valley.global_position.y + valley.water_height():
		return "Can't build in water"
	if rad_to_deg((spot["normal"] as Vector3).angle_to(Vector3.UP)) > _buildable.max_slope_degrees:
		return "Too steep"
	if _overlaps_something(where.origin):
		return BLOCKED
	return ""


# Anything solid (other than the ground and floors) inside its own box, shrunk a hair
func _box_overlaps(where: Transform3D) -> bool:
	var box := BoxShape3D.new()
	box.size = (_bounds.size - Vector3.ONE * 0.04).max(Vector3.ONE * 0.02)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = where * Transform3D(Basis.IDENTITY, _bounds.get_center() + Vector3.UP * 0.02)
	for found in _player.get_world_3d().direct_space_state.intersect_shape(query, MAX_OVERLAPS):
		if not _is_ground(found["collider"]):
			return true
	return false


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


# Anything solid in the buildable's footprint, other than the ground. That includes you.
func _overlaps_something(spot: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _footprint
	query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * _footprint.height * 0.5)
	for found in _player.get_world_3d().direct_space_state.intersect_shape(query, MAX_OVERLAPS):
		if not _is_ground(found["collider"]):
			return true
	return false


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
	for item in cost:
		_player.remove_item(item, cost[item])

	var built := build(_buildable, _preview.global_position, _preview.global_rotation.y)
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
		if built.has_method("save_data"):
			entry["state"] = built.save_data()
		if built.has_meta(PlotRegistry.OWNER_META):
			entry["plot"] = built.get_meta(PlotRegistry.OWNER_META)
		list.append(entry)
	return {"list": list, "snapping": _pieces.snapping}


func load_data(data: Dictionary) -> void:
	_pieces.snapping = bool(data.get("snapping", true))
	for built in get_tree().get_nodes_in_group("buildings"):
		built.queue_free()
	for entry in data.get("list", []):
		var buildable := load(str(entry.get("buildable", ""))) as Buildable
		if buildable == null:
			continue
		var built := build(buildable, SaveGame.to_vector(entry.get("position")), float(entry.get("turn", 0.0)))
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


## What a workbench, chest or campfire, put at `where`, would bump into in its footprint (other
## than the ground, a floor or the bodies in `skip`), or null if nothing: for moving a plot
func building_blocked(building: Node3D, where: Transform3D, skip: Array[RID]) -> Object:
	var buildable := load(str(building.get_meta(BUILDABLE_META, ""))) as Buildable
	if buildable == null:
		return null
	var footprint := CylinderShape3D.new()
	footprint.radius = buildable.footprint_radius
	footprint.height = buildable.footprint_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = footprint
	query.exclude = skip
	# Raised a little, so the ground it stands on doesn't count
	query.transform = Transform3D(Basis.IDENTITY, where.origin + Vector3.UP * (footprint.height * 0.5 + 0.1))
	for found in _player.get_world_3d().direct_space_state.intersect_shape(query, MAX_OVERLAPS):
		if not _is_ground(found["collider"]):
			return found["collider"]
	return null


## Takes down a piece, or a workbench, chest or campfire, and returns what it gives back: what a
## piece cost, or a building's (first) cost plus anything stored in it. For shrinking a plot.
func take_down(item: Node3D) -> Dictionary:
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
