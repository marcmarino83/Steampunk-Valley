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
const TERRAIN_PATH_SCRIPT := "res://world/terrain_path.gd"
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
## Holding Shift while dragging moves the point at this fraction of the mouse's speed
const PRECISION := 0.25
# During a drag: where the point started, where it is now (world), where the mouse last met
# the ground, the point's offset from that spot, and where the mouse is on screen (for the label)
var _drag_start := Vector3.ZERO
var _drag_pos := Vector3.ZERO
var _last_hit = null
var _grab_offset := Vector3.ZERO
var _mouse := Vector2.ZERO
# A change of selection that arrived mid-drag, applied once the drag ends
var _pending_edit: Object = null
var _has_pending_edit := false
# For spotting a release that happened outside the 3D view
var _seen_button_down := false
var _up_frames := 0


func _handles(object: Object) -> bool:
	return object is Node3D and object.get_script() != null and object.get_script().resource_path == TERRAIN_PATH_SCRIPT


func _edit(object: Object) -> void:
	# Godot calls this again whenever the Inspector or selection refreshes, which happens all
	# through a drag (the trail changes on every mouse move). A drag belongs to the plugin
	# until the mouse button is let go, so nothing here is allowed to interrupt it.
	if _dragging >= 0:
		_pending_edit = object
		_has_pending_edit = true
		return
	if object == _path and _path != null:
		return
	if _watched and _watched.changed.is_connected(update_overlays):
		_watched.changed.disconnect(update_overlays)
	_path = object as Node3D
	_watched = _path.curve if _path else null
	if _watched and not _watched.changed.is_connected(update_overlays):
		_watched.changed.connect(update_overlays)
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_edit(null)
	elif _dragging >= 0 and _has_pending_edit and _pending_edit == null:
		# Hidden then shown again mid-drag (an editor refresh): the trail is still selected
		_has_pending_edit = false


# Catches the button being let go anywhere (even outside the 3D view, where the release
# might never reach the plugin as an event), so a drag always ends cleanly on release.
# It only trusts Godot's input state once it has seen the button down during this drag, and
# waits for it to read "up" a few frames running, so a moment's lag can't end a drag early.
func _process(_delta: float) -> void:
	if _dragging < 0:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_seen_button_down = true
		_up_frames = 0
	elif _seen_button_down:
		_up_frames += 1
		if _up_frames >= 3:
			_finish_drag()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _path == null or not is_instance_valid(_path) or _path.curve == null:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		if _dragging >= 0:
			# A move with the left button no longer held means it was let go somewhere the
			# release didn't reach us
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				_finish_drag()
				return AFTER_GUI_INPUT_STOP
			_drag_to(camera, event.position, event.shift_pressed)
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
				_start_drag(point, camera, event.position)
				return AFTER_GUI_INPUT_STOP
			# Press on the trail between points: add a point there and drag it to bend the trail
			var offset := _trail_under_mouse(camera, event.position)
			if offset >= 0.0:
				var points_before: PackedVector3Array = _path.get_points()
				_path.begin_drag()
				var index: int = _path.insert_point_at_offset(offset)
				_start_drag(index, camera, event.position, points_before)
				return AFTER_GUI_INPUT_STOP
			return AFTER_GUI_INPUT_PASS
		elif _dragging >= 0:
			_finish_drag()
			return AFTER_GUI_INPUT_STOP

	if _dragging >= 0:
		# Right-click or Esc while dragging: put things back
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			_cancel_drag()
			return AFTER_GUI_INPUT_STOP
		# Until the button is let go, the drag owns the mouse: no other clicks or scrolls
		# reach the 3D view
		if event is InputEventMouse:
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


# While dragging, the trail only moves its handle and outline; the terrain waits for the
# mouse to be let go. `points_before` is the trail as it was before the drag (for undo).
func _start_drag(point: int, camera: Camera3D, screen: Vector2, points_before := PackedVector3Array()) -> void:
	_points_before = points_before if not points_before.is_empty() else _path.get_points()
	# (begin_drag is safe to call twice: bending the trail has already called it)
	_path.begin_drag()
	_dragging = point
	_seen_button_down = false
	_up_frames = 0
	_drag_start = _path.to_global(_path.curve.get_point_position(point))
	_drag_pos = _drag_start
	_last_hit = _ground_under_mouse(camera, screen)
	# Keep the point where it was relative to the mouse, so it doesn't jump when grabbed
	_grab_offset = _drag_start - _last_hit if _last_hit != null else Vector3.ZERO
	_mouse = screen
	update_overlays()


# Moves the point with the mouse: straight to it normally, or at a quarter of the speed
# while Shift is held. If the mouse points somewhere with no ground under it (the sky),
# the point waits where it is and the drag carries on.
func _drag_to(camera: Camera3D, screen: Vector2, precise: bool) -> void:
	_mouse = screen
	var hit = _ground_under_mouse(camera, screen)
	if hit == null:
		update_overlays()
		return
	if precise and _last_hit != null:
		var moved: Vector3 = hit - _last_hit
		_drag_pos += Vector3(moved.x, 0.0, moved.z) * PRECISION
		# Remember the new offset, so letting go of Shift doesn't make the point jump
		_grab_offset = _drag_pos - hit
	else:
		_drag_pos = hit + _grab_offset
	_last_hit = hit
	# Stay on the map: a point dragged past the edge stops at it
	var valley = _path._valley()
	if valley and valley.has_heights():
		var bounds: Rect2 = valley.map_rect().grow(-1.0)
		_drag_pos.x = clampf(_drag_pos.x, bounds.position.x, bounds.end.x)
		_drag_pos.z = clampf(_drag_pos.z, bounds.position.y, bounds.end.y)
	_drag_pos.y = _path.ground_height_at(_drag_pos)
	_path.curve.set_point_position(_dragging, _path.to_local(_drag_pos))
	update_overlays()


# Letting go rebuilds the terrain once, and records the whole drag as one step, so Ctrl+Z
# undoes it
func _finish_drag() -> void:
	if _dragging < 0:
		return
	var after: PackedVector3Array = _path.get_points()
	_dragging = -1
	_path.end_drag()
	var undo := get_undo_redo()
	undo.create_action("Move trail point")
	undo.add_do_method(_path, "set_points", after)
	undo.add_undo_method(_path, "set_points", _points_before)
	undo.commit_action(false)
	_after_drag()


func _cancel_drag() -> void:
	_dragging = -1
	_path.set_points(_points_before)
	_path.end_drag()
	_after_drag()


# Anything that was put off until the drag ended (like a change of selection) happens now
func _after_drag() -> void:
	if _has_pending_edit:
		_has_pending_edit = false
		var next := _pending_edit
		_pending_edit = null
		if next != _path:
			_edit(next)
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

	# While dragging: where the point is, and how far it's moved, in a small label by the mouse
	if _dragging >= 0:
		var moved := Vector2(_drag_pos.x - _drag_start.x, _drag_pos.z - _drag_start.z).length()
		var precise := Input.is_key_pressed(KEY_SHIFT)
		var text := "x %.1f   z %.1f   height %.1f m\nmoved %.2f m%s" % [_drag_pos.x, _drag_pos.z, _drag_pos.y, moved, "   (fine: Shift)" if precise else ""]
		var label_font := overlay.get_theme_default_font()
		var label_size := label_font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var at := _mouse + Vector2(18, 18)
		# Keep it on screen near the edges
		at.x = minf(at.x, overlay.size.x - label_size.x - 12)
		at.y = minf(at.y, overlay.size.y - label_size.y - 12)
		overlay.draw_rect(Rect2(at - Vector2(6, 4), label_size + Vector2(12, 8)), Color(0, 0, 0, 0.7))
		overlay.draw_multiline_string(label_font, at + Vector2(0, label_font.get_ascent(13)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, -1, Color(1.0, 0.85, 0.4) if precise else Color(1, 1, 1))

	var lines := [
		"Trail editing",
		"Drag a point: move it",
		"Drag the trail: bend it (adds a point)",
		"Ctrl + click ground: add point at end",
		"Ctrl + Shift + click: add point at start",
		"Alt + click a point: delete it",
		"Hold Shift while dragging: fine adjustment",
		"Right-click while dragging: cancel",
	]
	var font := overlay.get_theme_default_font()
	var font_size := 14
	var box := Rect2(12, overlay.size.y - 18 * lines.size() - 22, 300, 18 * lines.size() + 12)
	overlay.draw_rect(box, Color(0, 0, 0, 0.55))
	for i in lines.size():
		var color := Color(1.0, 0.8, 0.4) if i == 0 else Color(0.92, 0.92, 0.92)
		overlay.draw_string(font, Vector2(box.position.x + 10, box.position.y + 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
