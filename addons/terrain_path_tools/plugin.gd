@tool
extends EditorPlugin
## Hand-editing for TerrainPath trails in the 3D view. While a trail is selected:
##   drag a point            move it across the ground
##   drag the trail itself   bend that stretch (adds a point there)
##   Ctrl + click ground     add a point at the end
##   Ctrl + Shift + click    add a point at the start
##   Alt + click a point     delete it
## Points are drawn as big round handles, and a short hint sits in the corner of the view.

## Trails are recognized by their script's path, so this plugin loads even if that script has a problem
const TERRAIN_PATH_SCRIPT := "res://terrain_path.gd"
## How close (on screen, in pixels) the mouse must be to grab a point or the trail
const POINT_GRAB := 20.0
const TRAIL_GRAB := 14.0
const HANDLE_RADIUS := 11.0

var _path: Node3D
# The curve being watched for changes (so the handles redraw as it changes)
var _watched: Curve3D
# The point being dragged (-1 = none), and the points from before the drag, for undo
var _dragging := -1
var _points_before := PackedVector3Array()
var _hover := -1


func _handles(object: Object) -> bool:
	return object is Node3D and object.get_script() != null and object.get_script().resource_path == TERRAIN_PATH_SCRIPT


func _edit(object: Object) -> void:
	if _watched and _watched.changed.is_connected(update_overlays):
		_watched.changed.disconnect(update_overlays)
	if _path and is_instance_valid(_path) and _dragging >= 0:
		_path.end_drag()
	_path = object as Node3D
	_dragging = -1
	_watched = _path.curve if _path else null
	if _watched and not _watched.changed.is_connected(update_overlays):
		_watched.changed.connect(update_overlays)
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_edit(null)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _path == null or not is_instance_valid(_path) or _path.curve == null:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		if _dragging >= 0:
			var hit = _ground_under_mouse(camera, event.position)
			if hit != null:
				_path.curve.set_point_position(_dragging, _path.to_local(hit))
			return AFTER_GUI_INPUT_STOP
		var hover := _point_under_mouse(camera, event.position)
		if hover != _hover:
			_hover = hover
			update_overlays()
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point := _point_under_mouse(camera, event.position)
			# Alt + click a point: delete it (a trail keeps at least two)
			if event.alt_pressed:
				if point >= 0 and _path.curve.point_count > 2:
					var before: PackedVector3Array = _path.get_points()
					var after := before.duplicate()
					after.remove_at(point)
					_path.apply_points_with_undo("Delete trail point", before, after)
					_hover = -1
					update_overlays()
				return AFTER_GUI_INPUT_STOP
			# Ctrl + click the ground: add a point at the end of the trail
			# (Ctrl + Shift + click: at the start instead)
			if event.ctrl_pressed or event.meta_pressed:
				var hit = _ground_under_mouse(camera, event.position)
				if hit != null:
					var before: PackedVector3Array = _path.get_points()
					var after := before.duplicate()
					if event.shift_pressed:
						after.insert(0, _path.to_local(hit))
						_path.apply_points_with_undo("Add trail point at start", before, after)
					else:
						after.append(_path.to_local(hit))
						_path.apply_points_with_undo("Add trail point", before, after)
				return AFTER_GUI_INPUT_STOP
			# Press on a point: start dragging it
			if point >= 0:
				_start_drag(point)
				return AFTER_GUI_INPUT_STOP
			# Press on the trail between points: add a point there and drag it to bend the trail
			var offset := _trail_under_mouse(camera, event.position)
			if offset >= 0.0:
				_points_before = _path.get_points()
				_path.begin_drag()
				var index: int = _path.insert_point_at_offset(offset)
				_dragging = index
				update_overlays()
				return AFTER_GUI_INPUT_STOP
			return AFTER_GUI_INPUT_PASS
		elif _dragging >= 0:
			_finish_drag()
			return AFTER_GUI_INPUT_STOP

	# Right-click or Esc while dragging: put things back
	if _dragging >= 0 and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		_dragging = -1
		_path.set_points(_points_before)
		_path.end_drag()
		update_overlays()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


# While dragging, the trail only moves its handle and outline; the terrain waits for the
# mouse to be let go
func _start_drag(point: int) -> void:
	_points_before = _path.get_points()
	_path.begin_drag()
	_dragging = point
	update_overlays()


# Letting go rebuilds the terrain once, and records the whole drag as one step, so Ctrl+Z
# undoes it
func _finish_drag() -> void:
	var after: PackedVector3Array = _path.get_points()
	_dragging = -1
	_path.end_drag()
	var undo := get_undo_redo()
	undo.create_action("Move trail point")
	undo.add_do_method(_path, "set_points", after)
	undo.add_undo_method(_path, "set_points", _points_before)
	undo.commit_action(false)
	update_overlays()


func _ground_under_mouse(camera: Camera3D, screen: Vector2):
	return _path.ground_under_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


# The point closest to the mouse on screen, if it's close enough to grab (or -1)
func _point_under_mouse(camera: Camera3D, screen: Vector2) -> int:
	var best := -1
	var best_distance := POINT_GRAB
	for i in _path.curve.point_count:
		var world: Vector3 = _path.to_global(_path.curve.get_point_position(i))
		if camera.is_position_behind(world):
			continue
		var distance := camera.unproject_position(world).distance_to(screen)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


# How far along the trail (in meters) the mouse is, if it's over the trail (or -1)
func _trail_under_mouse(camera: Camera3D, screen: Vector2) -> float:
	var baked: PackedVector3Array = _path.curve.get_baked_points()
	var best := -1.0
	var best_distance := TRAIL_GRAB
	var travelled := 0.0
	for i in baked.size():
		if i > 0:
			travelled += baked[i].distance_to(baked[i - 1])
		var world: Vector3 = _path.to_global(baked[i])
		if camera.is_position_behind(world):
			continue
		var distance := camera.unproject_position(world).distance_to(screen)
		if distance < best_distance:
			best_distance = distance
			best = travelled
	return best


# Big round handles for the points, and the controls hint in the corner
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if _path == null or not is_instance_valid(_path) or _path.curve == null:
		return
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if camera:
		# The trail's center line (Godot's own path gizmo doesn't draw it, since a trail
		# isn't a Path3D), drawn as one line through the curve's points
		var line := PackedVector2Array()
		for p in _path.curve.get_baked_points():
			var world: Vector3 = _path.to_global(p)
			if camera.is_position_behind(world):
				if line.size() >= 2:
					overlay.draw_polyline(line, Color(1.0, 0.75, 0.25, 0.9), 2.5, true)
				line.clear()
				continue
			line.append(camera.unproject_position(world))
		if line.size() >= 2:
			overlay.draw_polyline(line, Color(1.0, 0.75, 0.25, 0.9), 2.5, true)
		for i in _path.curve.point_count:
			var world: Vector3 = _path.to_global(_path.curve.get_point_position(i))
			if camera.is_position_behind(world):
				continue
			var at := camera.unproject_position(world)
			var lit: bool = i == _dragging or i == _hover
			var size := HANDLE_RADIUS * (1.25 if lit else 1.0)
			overlay.draw_circle(at, size + 2.5, Color(0.1, 0.07, 0.02))
			overlay.draw_circle(at, size, Color(1.0, 0.85, 0.35) if lit else Color(1.0, 0.68, 0.12))
			overlay.draw_circle(at, size * 0.32, Color(1, 1, 1))

	var lines := [
		"Trail editing",
		"Drag a point: move it",
		"Drag the trail: bend it (adds a point)",
		"Ctrl + click ground: add point at end",
		"Ctrl + Shift + click: add point at start",
		"Alt + click a point: delete it",
		"Right-click while dragging: cancel",
	]
	var font := overlay.get_theme_default_font()
	var font_size := 14
	var box := Rect2(12, overlay.size.y - 18 * lines.size() - 22, 300, 18 * lines.size() + 12)
	overlay.draw_rect(box, Color(0, 0, 0, 0.55))
	for i in lines.size():
		var color := Color(1.0, 0.8, 0.4) if i == 0 else Color(0.92, 0.92, 0.92)
		overlay.draw_string(font, Vector2(box.position.x + 10, box.position.y + 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
