class_name BuildPlacer
extends Node
## Puts a chosen buildable down in the world: a see-through preview follows the crosshair along
## the ground, green where it can go and red where it can't. Nothing is spent until it's placed.

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

var _player: CharacterBody3D
var _buildable: Buildable
var _preview: Node3D
var _material: StandardMaterial3D
var _footprint: CylinderShape3D
var _turn := 0.0
# Why it can't go where the preview is. Empty means it can.
var _problem := ""


func _ready() -> void:
	_player = get_parent()
	set_physics_process(false)


func is_placing() -> bool:
	return _buildable != null


func begin(buildable: Buildable) -> void:
	cancel()
	_buildable = buildable
	_turn = 0.0
	_problem = "Point at the ground"
	_footprint = CylinderShape3D.new()
	_footprint.radius = buildable.footprint_radius
	_footprint.height = buildable.footprint_height
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview = _make_preview(buildable.scene)
	_preview.visible = false
	_player.get_parent().add_child(_preview)
	set_physics_process(true)


## Stops placing without spending anything
func cancel() -> void:
	if _preview:
		_preview.queue_free()
	_preview = null
	_buildable = null
	set_physics_process(false)


## Takes the keys and clicks that mean something while placing. Returns true if it used this one.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_turn = wrapf(_turn + ROTATE_STEP, 0.0, TAU)
			_preview.rotation.y = _turn
			return true
		# Finish or cancel this one before opening the menu or putting the hammer away
		if event.keycode == KEY_TAB or (event.keycode >= KEY_1 and event.keycode <= KEY_9):
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


## The lines for the key hints in the corner
func hints() -> PackedStringArray:
	var lines: PackedStringArray = ["Placing %s" % _buildable.display_name]
	if not _problem.is_empty():
		lines.append(_problem)
	lines.append("[Left-click] Place   [R] Rotate")
	lines.append("[Right-click] or [Esc] Cancel")
	return lines


func _physics_process(_delta: float) -> void:
	var hit := _find_spot()
	_preview.visible = not hit.is_empty()
	if hit.is_empty():
		_problem = "Point at the ground"
		return
	_preview.global_position = hit["position"]
	_preview.rotation.y = _turn
	_problem = _check_spot(hit)
	_material.albedo_color = GOOD_COLOR if _problem.is_empty() else BAD_COLOR


# What the crosshair is on, or failing that, the ground beneath the end of its reach
func _find_spot() -> Dictionary:
	var camera: Camera3D = _player.camera
	var far_point := camera.global_position - camera.global_basis.z * REACH
	var hit := _cast_ray(camera.global_position, far_point)
	if hit.is_empty():
		hit = _cast_ray(far_point, far_point + Vector3.DOWN * DROP_DISTANCE)
	return hit


func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query)


# Why this spot won't do, or an empty string if it will
func _check_spot(hit: Dictionary) -> String:
	if not hit["collider"].is_in_group("terrain_ground"):
		return BLOCKED
	var spot: Vector3 = hit["position"]
	var valley = get_tree().get_first_node_in_group("valley")
	if valley and spot.y < valley.global_position.y + valley.water_height():
		return "Can't build in water"
	if rad_to_deg(hit["normal"].angle_to(Vector3.UP)) > _buildable.max_slope_degrees:
		return "Too steep"
	if _overlaps_something(spot):
		return BLOCKED
	return ""


# Anything solid in the buildable's footprint, other than the ground. That includes you.
func _overlaps_something(spot: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _footprint
	query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * _footprint.height * 0.5)
	for found in _player.get_world_3d().direct_space_state.intersect_shape(query, MAX_OVERLAPS):
		if not found["collider"].is_in_group("terrain_ground"):
			return true
	return false


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

	var built: Node3D = _buildable.scene.instantiate()
	_player.get_parent().add_child(built)
	built.global_position = _preview.global_position
	built.rotation.y = _turn
	if not _buildable.placed_message.is_empty():
		_player.flash(_buildable.placed_message)
	var built_name := _buildable.display_name
	cancel()
	_player.report_progress("Build", built_name)


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
