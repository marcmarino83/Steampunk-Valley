@tool
extends Path3D
## A trail across the map. Draw its curve in the editor (click to add points, drag the
## handles to bend it), and the Valley smooths the ground along it into a walkable path.
## The trail rises and falls gradually so it's never steeper than Max Slope, cutting into
## the hillside or building up over dips where it has to. Only the curve's position on the
## map matters; the height of its points is ignored, since the trail follows the ground.
##
## Like terrain modifiers, trails are applied in scene order, so a trail placed after a
## Flatten marker runs smoothly into the leveled area.

## How wide the walkable trail is, in meters
@export_range(0.5, 30.0, 0.1) var width := 4.0:
	set(value):
		width = value
		_changed()
## How far the trail's sides fade into the hillside, in meters
@export_range(0.0, 40.0, 0.5) var edge_blend := 6.0:
	set(value):
		edge_blend = value
		_changed()
## The steepest the trail is allowed to climb or drop, in degrees
@export_range(2.0, 45.0, 0.5) var max_slope := 20.0:
	set(value):
		max_slope = value
		_changed()
## How much the trail evens out small ups and downs along its length:
## 0 = follows every bump, 1 = long, gentle grades
@export_range(0.0, 1.0, 0.01) var smoothness := 0.5:
	set(value):
		smoothness = value
		_changed()

const EDGE_COLOR := Color(1.0, 0.85, 0.35)

var _last_area := Rect2()
var _last_spot := Vector3.INF
var _selected := false
var _selection_check := 0.0


func _enter_tree() -> void:
	add_to_group("terrain_modifiers")
	set_notify_transform(true)


func _exit_tree() -> void:
	if Engine.is_editor_hint() and _last_area.has_area():
		var valley = _valley()
		if valley:
			valley.request_rebuild_area(_last_area)


func _ready() -> void:
	if curve == null:
		# A short straight trail to start from
		curve = Curve3D.new()
		curve.add_point(Vector3.ZERO)
		curve.add_point(Vector3(25, 0, 0))
	curve.bake_interval = 1.0
	if not curve_changed.is_connected(_changed):
		curve_changed.connect(_changed)
	_last_spot = global_position
	_last_area = area()
	if Engine.is_editor_hint():
		refresh_rings()
	else:
		$Edges.hide()
		$Blend.hide()


## Points along the trail, about a meter apart, in world positions
func trail_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	if curve == null or curve.point_count < 2:
		return points
	for p in curve.get_baked_points():
		points.append(global_transform * p)
	return points


## The patch of map (x, z) the trail can change, edges and all
func area() -> Rect2:
	var points := trail_points() if is_inside_tree() else PackedVector3Array()
	if points.is_empty():
		return Rect2()
	var box := Rect2(points[0].x, points[0].z, 0.0, 0.0)
	for p in points:
		box = box.expand(Vector2(p.x, p.z))
	return box.grow(width * 0.5 + edge_blend + 1.0)


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
		if global_position.distance_to(_last_spot) > 0.01:
			_last_spot = global_position
			_ask_for_rebuild()


func _changed() -> void:
	_ask_for_rebuild()
	refresh_rings()


func _ask_for_rebuild() -> void:
	if not (Engine.is_editor_hint() and is_inside_tree()):
		return
	var valley = _valley()
	if valley:
		var now := area()
		valley.request_rebuild_area(now.merge(_last_area) if _last_area.has_area() else now)
		_last_area = now


func _valley():
	return get_tree().get_first_node_in_group("valley") if is_inside_tree() else null


func _is_selected() -> bool:
	if not Engine.has_singleton("EditorInterface"):
		return false
	var editor = Engine.get_singleton("EditorInterface")
	for node in editor.get_selection().get_selected_nodes():
		if node == self or node.is_ancestor_of(self):
			return true
	return false


## Redraws the trail's edge lines on the ground (the valley calls this after the terrain changes)
func refresh_rings() -> void:
	if not is_node_ready() or not Engine.is_editor_hint():
		return
	$Edges.mesh = _edge_mesh(width * 0.5)
	$Blend.mesh = _edge_mesh(width * 0.5 + edge_blend)
	$Edges.material_override = _glow(0.95)
	$Blend.material_override = _glow(0.35)
	_update_visibility()


func _update_visibility() -> void:
	if not is_node_ready():
		return
	var valley = _valley()
	var show_markers: bool = valley == null or valley.show_modifier_markers
	$Edges.visible = show_markers and _selected
	$Blend.visible = show_markers and _selected


# Two thin ribbons, one each side of the trail at `offset` meters out, laid on the ground
func _edge_mesh(offset: float) -> ArrayMesh:
	var valley = _valley()
	var points := trail_points()
	var mesh := ArrayMesh.new()
	if points.size() < 2:
		return mesh
	var line_width := 0.15
	var vertices := PackedVector3Array()
	var order := PackedInt32Array()
	for side in [-1.0, 1.0]:
		var first := vertices.size()
		for i in points.size():
			var ahead := points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
			var across := Vector3(-ahead.z, 0.0, ahead.x).normalized()
			for edge in [offset - line_width * 0.5, offset + line_width * 0.5]:
				var spot: Vector3 = points[i] + across * side * edge
				var ground: float = valley.get_height(spot.x, spot.z) if valley and valley.has_heights() else spot.y
				vertices.append(to_local(Vector3(spot.x, ground + 0.15, spot.z)))
		for i in points.size() - 1:
			var v := first + i * 2
			order.append_array([v, v + 1, v + 2, v + 1, v + 3, v + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = order
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _glow(alpha: float) -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, alpha)
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.no_depth_test = true
	return look
