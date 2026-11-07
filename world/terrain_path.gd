@tool
extends Node3D
## A trail across the map. Edit its points in the editor with the Terrain Path Tools controls
## (drag points, drag the trail to bend it, Ctrl+click to add), and the Valley smooths the
## ground along it into a walkable path.
##
## It's a plain 3D node holding its own curve, rather than a Godot Path3D, so Godot's built-in
## path editor and its handles never react to it: only Terrain Path Tools edits trails.
## The trail rises and falls gradually so it's never steeper than Max Slope, cutting into
## the hillside or building up over dips where it has to. Only the curve's position on the
## map matters; the height of its points is ignored, since the trail follows the ground.
##
## Like terrain modifiers, trails are applied in scene order, so a trail placed after a
## Flatten marker runs smoothly into the leveled area.

## The trail's shape: its points, in this node's own space
@export var curve: Curve3D:
	set(value):
		if curve and curve.changed.is_connected(_changed):
			curve.changed.disconnect(_changed)
		curve = value
		if curve:
			curve.bake_interval = 1.0
			if not curve.changed.is_connected(_changed):
				curve.changed.connect(_changed)
		_changed()
## A spare copy of the trail's points, saved with the scene alongside the curve. If the trail
## ever loads with its curve missing or emptied (for example after a script change while the
## scene was open), it rebuilds itself from this instead of starting over.
@export_storage var saved_points := PackedVector3Array()
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

## How level the trail is from side to side: 1 = flat across (cut into the uphill side and
## built up on the downhill side, like a real hillside trail), 0 = tilts with the hillside
@export_range(0.0, 1.0, 0.01) var cross_slope := 0.8:
	set(value):
		cross_slope = value
		_changed()
## Surface the trail with gravel that frays into the ground at its edges. Untick for a
## trail that stays grassy.
@export var dirt_texture := true:
	set(value):
		dirt_texture = value
		_changed()
## How far the gravel fades out into the ground past each edge of the walkable width, in
## meters. Stones show through first and the ground fills in between them.
@export_range(0.0, 10.0, 0.1) var texture_blend_width := 2.0:
	set(value):
		texture_blend_width = value
		_changed()
## How ragged the gravel's border is: 0 = a smooth, even fade, 1 = a broken, patchy edge
@export_range(0.0, 1.0, 0.01) var edge_noise := 0.5:
	set(value):
		edge_noise = value
		_changed()
## Grass grows in tufts along the trail's edges, and in a few patches on the trail itself
@export var edge_grass := true:
	set(value):
		edge_grass = value
		_changed()

## Keep trees, resources, boulders and ferns off the trail: its width, plus Clear Margin on
## each side, and never less than the worn dirt
@export var clear_objects := true:
	set(value):
		clear_objects = value
		_changed()
## How far past each edge of the walkable width the trail stays clear, in meters
@export_range(0.0, 15.0, 0.25) var clear_margin := 1.5:
	set(value):
		clear_margin = value
		_changed()

@export_group("Editing")
## Bend the curve smoothly through its points by itself (Catmull-Rom), so moving one point
## reshapes the trail around it without any control handles. Untick to shape curves by hand.
@export var auto_smooth := true:
	set(value):
		auto_smooth = value
		_changed()
## How far beyond the last point "Add Point at End" puts the new one, in meters
@export_range(1.0, 100.0, 0.5) var new_point_distance := 8.0
## Adds a new point past the end of the trail, carrying on in the same direction
@export_tool_button("Add Point at End", "Add") var add_point_button := add_point_at_end
## Adds a new point before the start of the trail, carrying on backwards from its first stretch
@export_tool_button("Add Point at Start", "Add") var add_start_button := add_point_at_start
## Flips the trail around, so its start becomes its end (the trail itself doesn't move)
@export_tool_button("Reverse Path", "Reload") var reverse_button := reverse_path

## How far above the ground each point sits, so its handle isn't buried in a hillside
const POINT_LIFT := 0.3
const EDGE_COLOR := Color(1.0, 0.85, 0.35)

var _last_area := Rect2()
var _last_spot := Vector3.INF
var _selected := false
var _selection_check := 0.0
# True while the curve is being tidied (snapped and smoothed), so the changes it makes
# don't set off another round of tidying
var _tidying := false
# True while a point is being dragged in the editor: the terrain waits until it's let go
var _dragging := false


func _enter_tree() -> void:
	add_to_group("terrain_modifiers")
	set_notify_transform(true)


func _exit_tree() -> void:
	if Engine.is_editor_hint() and _last_area.has_area():
		var valley = _valley()
		if valley:
			valley.request_rebuild_area(_last_area)


func _ready() -> void:
	if curve == null or curve.point_count < 2:
		var start := Curve3D.new()
		if saved_points.size() >= 2:
			# The curve went missing, but the spare copy didn't: put the trail back
			for p in saved_points:
				start.add_point(p)
			push_warning("%s: its curve was missing, so it was rebuilt from its saved points (%d)." % [name, saved_points.size()])
		else:
			# A brand-new trail: a short straight stretch to start from
			start.add_point(Vector3.ZERO)
			start.add_point(Vector3(25, 0, 0))
		curve = start
	_update_saved_points()
	_last_spot = global_position
	_last_area = area()
	if Engine.is_editor_hint():
		refresh_rings()
	else:
		$Edges.hide()
		$Blend.hide()


## Adds a point `new_point_distance` meters past the last one, heading the way the trail
## was going at its end, and sets it down on the ground
func add_point_at_end() -> void:
	if curve == null:
		return
	var count := curve.point_count
	var last := curve.get_point_position(count - 1) if count > 0 else Vector3.ZERO
	var heading := Vector3.RIGHT
	if count >= 2:
		# The direction along the curve at its very end, flattened so it heads across the map
		var length := curve.get_baked_length()
		var just_before := curve.sample_baked(maxf(length - 1.0, 0.0))
		heading = last - just_before
	heading.y = 0.0
	if heading.length() < 0.001:
		heading = Vector3.RIGHT
	var spot := last + heading.normalized() * new_point_distance
	var before := get_points()
	var after := before.duplicate()
	after.append(spot)
	apply_points_with_undo("Add trail point", before, after)


## Adds a point `new_point_distance` meters before the first one, heading back the way the
## trail comes into its start, and sets it down on the ground
func add_point_at_start() -> void:
	if curve == null:
		return
	var count := curve.point_count
	var first := curve.get_point_position(0) if count > 0 else Vector3.ZERO
	var heading := Vector3.LEFT
	if count >= 2:
		# The direction along the curve at its very start, backwards, flattened across the map
		var just_after := curve.sample_baked(minf(1.0, curve.get_baked_length()))
		heading = first - just_after
	heading.y = 0.0
	if heading.length() < 0.001:
		heading = Vector3.LEFT
	var spot := first + heading.normalized() * new_point_distance
	var before := get_points()
	var after := before.duplicate()
	after.insert(0, spot)
	apply_points_with_undo("Add trail point at start", before, after)


## Flips the order of the points, so the start becomes the end. The trail stays where it is.
func reverse_path() -> void:
	var before := get_points()
	var after := before.duplicate()
	after.reverse()
	apply_points_with_undo("Reverse trail", before, after)


## The trail's points, in the path's own space
func get_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	if curve:
		for i in curve.point_count:
			points.append(curve.get_point_position(i))
	return points


## Replaces all the trail's points (then snaps and smooths them)
func set_points(points: PackedVector3Array) -> void:
	_tidying = true
	curve.clear_points()
	for p in points:
		curve.add_point(p)
	_tidying = false
	_changed()


## Changes the points in one step that Ctrl+Z can undo
func apply_points_with_undo(action: String, before: PackedVector3Array, after: PackedVector3Array) -> void:
	var undo = _undo_redo()
	if undo:
		undo.create_action(action)
		undo.add_do_method(self, "set_points", after)
		undo.add_undo_method(self, "set_points", before)
		undo.commit_action()
	else:
		set_points(after)


## Sets every point down on the ground (just above it), keeping where it is on the map
func snap_points_to_ground() -> void:
	if curve == null or not is_inside_tree():
		return
	for i in curve.point_count:
		var place := curve.get_point_position(i)
		var ground := ground_height_at(to_global(place)) + POINT_LIFT
		var on_ground := to_local(Vector3(to_global(place).x, ground, to_global(place).z))
		if absf(on_ground.y - place.y) > 0.01:
			curve.set_point_position(i, on_ground)


## Bends the curve smoothly through its points (Catmull-Rom): each point's handles point
## from the point before it toward the point after it, a sixth of the way
func apply_auto_tangents() -> void:
	if curve == null:
		return
	var count := curve.point_count
	for i in count:
		var here := curve.get_point_position(i)
		var before := curve.get_point_position(maxi(i - 1, 0))
		var after := curve.get_point_position(mini(i + 1, count - 1))
		var handle := (after - before) / 6.0
		if i == 0 or i == count - 1:
			# Ends: aim at the neighbor, half as strongly
			handle = (after - before) / 4.0
		if curve.get_point_out(i).distance_to(handle) > 0.001:
			curve.set_point_out(i, handle)
		if curve.get_point_in(i).distance_to(-handle) > 0.001:
			curve.set_point_in(i, -handle)


## The offset along the curve (meters from the start) nearest to a world position
func offset_near(spot: Vector3) -> float:
	return curve.get_closest_offset(to_local(spot))


## Adds a point at `offset` along the curve, between the two points either side of it,
## and returns its index
func insert_point_at_offset(offset: float) -> int:
	var spot := curve.sample_baked(offset)
	# It goes in before the first point that's further along the curve than it is
	var index := curve.point_count
	for i in range(1, curve.point_count):
		if curve.get_closest_offset(curve.get_point_position(i)) > offset:
			index = i
			break
	curve.add_point(spot, Vector3.ZERO, Vector3.ZERO, index)
	return index


## How high the ground is under a world position, leaving out this trail's own cut (just the
## heightmap and the other modifiers), so the trail never moves its own points. With no
## valley, it's the trail's own height.
func ground_height_at(spot: Vector3) -> float:
	var valley = _valley()
	if valley and valley.has_heights():
		return valley.ground_height_for(self, spot.x, spot.z)
	return global_position.y


## The editor calls these when a point starts and stops being dragged. During the drag only
## the handle and the outline move; the terrain is rebuilt once, when it's let go.
func begin_drag() -> void:
	_dragging = true


func end_drag() -> void:
	_dragging = false
	_ask_for_rebuild()
	refresh_rings()


## Where a line of sight (from the editor camera) first meets the ground, or null if it doesn't
func ground_under_ray(from: Vector3, direction: Vector3):
	var step := 2.0
	var previous := from
	for i in 3000:
		var here := from + direction * step * i
		if here.y <= ground_height_at(here):
			# Narrow it down between the last point above ground and this one
			var above := previous
			var below := here
			for k in 12:
				var middle := (above + below) * 0.5
				if middle.y > ground_height_at(middle):
					above = middle
				else:
					below = middle
			return below
		previous = here
	return null


func _undo_redo():
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface").get_editor_undo_redo()
	return null


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
	return box.grow(width * 0.5 + maxf(edge_blend, clear_margin) + 1.0)


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
	if _tidying:
		return
	# Whichever way a point was moved, it ends up sitting on the ground, with the curve
	# bending smoothly through it
	if curve and is_inside_tree():
		_tidying = true
		if Engine.is_editor_hint():
			snap_points_to_ground()
		if auto_smooth:
			apply_auto_tangents()
		_tidying = false
	_update_saved_points()
	if not _dragging:
		_ask_for_rebuild()
	refresh_rings()


# Keeps the spare copy of the points in step with the curve. It never copies an empty or
# one-point curve over a good copy, so a curve that goes missing can't wipe out the backup.
func _update_saved_points() -> void:
	if curve and curve.point_count >= 2:
		saved_points = get_points()


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
