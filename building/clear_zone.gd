@tool
extends Node3D
## Keeps a circle of the map clear of scattered things: trees, resources, boulders and plants.
## It doesn't change the shape of the ground. Select it to see its edge drawn on the ground.

## How far it reaches, in meters
@export_range(1.0, 300.0, 0.5) var radius := 15.0:
	set(value):
		radius = value
		_changed()
## What to keep out of the circle
@export var clear_trees := true:
	set(value):
		clear_trees = value
		_changed()
## Stone, ore, fiber, sticks, mushrooms, herbs, berry bushes, and buried deposits
@export var clear_resources := true:
	set(value):
		clear_resources = value
		_changed()
## Boulders
@export var clear_rocks := true:
	set(value):
		clear_rocks = value
		_changed()
## Grass and ferns
@export var clear_plants := false:
	set(value):
		clear_plants = value
		_changed()

const RING_COLOR := Color(0.95, 0.95, 0.95)

var _last_spot := Vector3.INF
var _selected := false
var _selection_check := 0.0


func _enter_tree() -> void:
	add_to_group("clear_zones")
	set_notify_transform(true)


func _exit_tree() -> void:
	_ask_for_rebuild()


func _ready() -> void:
	_last_spot = global_position
	if Engine.is_editor_hint():
		refresh_rings()
	else:
		hide()


## True if (x, z) is inside the circle
func covers(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(Vector2(global_position.x, global_position.z)) < radius


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_selection_check -= delta
	if _selection_check <= 0.0:
		_selection_check = 0.25
		var now := _is_selected()
		if now != _selected:
			_selected = now
			_update_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and is_inside_tree():
		var flat := Vector3(global_position.x, 0.0, global_position.z)
		if flat.distance_to(_last_spot) > 0.01:
			_last_spot = flat
			_ask_for_rebuild()
			refresh_rings()


func _changed() -> void:
	_ask_for_rebuild()
	refresh_rings()


# Scattered things are only placed during a full build, so this asks for one (it waits a
# moment after the last change, so dragging the zone doesn't rebuild every frame)
func _ask_for_rebuild() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		var valley = get_tree().get_first_node_in_group("valley")
		if valley:
			valley.request_rebuild()


func _is_selected() -> bool:
	if not Engine.has_singleton("EditorInterface"):
		return false
	var editor = Engine.get_singleton("EditorInterface")
	for node in editor.get_selection().get_selected_nodes():
		if node == self or node.is_ancestor_of(self):
			return true
	return false


## Redraws the edge on the ground (the valley calls this after the terrain changes)
func refresh_rings() -> void:
	if not is_node_ready() or not Engine.is_editor_hint():
		return
	$Ring.mesh = _ring_mesh(radius)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, 0.85)
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.no_depth_test = true
	$Ring.material_override = look
	var pole := look.duplicate() as StandardMaterial3D
	pole.albedo_color.a = 0.3
	$Pole.material_override = pole
	_update_visibility()


func _update_visibility() -> void:
	if not is_node_ready():
		return
	var valley = get_tree().get_first_node_in_group("valley") if is_inside_tree() else null
	var show_markers: bool = valley == null or valley.show_modifier_markers
	$Ring.visible = show_markers and _selected
	$Pole.visible = show_markers


func _ring_mesh(ring_radius: float) -> ArrayMesh:
	var valley = get_tree().get_first_node_in_group("valley") if is_inside_tree() else null
	var width := clampf(ring_radius * 0.006, 0.12, 0.6)
	var segments := clampi(int(ring_radius * 2.0), 48, 256)
	var points := PackedVector3Array()
	var order := PackedInt32Array()
	var center := global_position
	for s in segments + 1:
		var direction := Vector2.from_angle(TAU * s / segments)
		for edge in [ring_radius - width * 0.5, ring_radius + width * 0.5]:
			var spot: Vector2 = Vector2(center.x, center.z) + direction * edge
			var ground: float = valley.get_height(spot.x, spot.y) if valley and valley.has_heights() else center.y
			points.append(to_local(Vector3(spot.x, ground + 0.15, spot.y)))
	for s in segments:
		var i := s * 2
		order.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = order
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
