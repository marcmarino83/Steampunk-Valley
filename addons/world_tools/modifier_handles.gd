@tool
extends RefCounted
## Hand-editing for a selected TerrainModifier in the 3D view:
##   drag its middle        slide it across the ground (hold Shift for fine moves)
##   drag the top handle    raise or lower a Flatten's target (or Alt + drag anywhere)
##   drag the outer ring    change its radius
##   right-click or Esc     cancel the drag
## The ground only rebuilds when the mouse is let go. Presses around the middle go to these
## handles and never reach Godot's own move gizmo, so the two can't fight over a drag.

const FLATTEN := 2
## Holding Shift while dragging moves things at this fraction of the mouse's speed
const PRECISION := 0.25
## How close (on screen, in pixels) a press must be to grab each handle. The middle's reach
## covers Godot's move gizmo, which is drawn around the same spot.
const MIDDLE_GRAB := 90.0
const TOP_GRAB := 16.0
const RING_GRAB := 12.0
## How far above the middle (in pixels) the height handle sits
const TOP_OFFSET := 44.0
## A Flatten's target this far below the ground digs a pit: the label warns about it
const PIT_WARNING := 5.0

var undo_redo: EditorUndoRedoManager
## Called whenever the 3D view's overlay needs redrawing
var redraw: Callable
## The modifier being edited
var target: Node3D

# The drag in progress: "" (none), "move", "height" or "radius"
var _drag := ""
var _hover := ""
var _position_before := Vector3.ZERO
var _radius_before := 0.0
var _moved := false
# Where the mouse last met the ground, and how far the modifier's middle is from there
var _last_hit = null
var _grab_offset := Vector2.ZERO
# Where it's being slid to (x, z), kept apart from the mouse for Shift's fine moves
var _slide := Vector2.ZERO
# Flatten: how far its target is from the ground, kept as it slides
var _target_above := 0.0
var _last_screen_y := 0.0
var _mouse := Vector2.ZERO
# The ground as it is without this modifier, so its own digging or filling doesn't count
var _ground: PackedFloat32Array
var _ground_for: Node3D
# For spotting a release that happened outside the 3D view
var _seen_down := false
var _up_frames := 0


## True while a drag is going on (changes of selection wait until it's over)
func is_dragging() -> bool:
	return _drag != ""


## Chooses the modifier to edit
func set_target(node: Node3D) -> void:
	if _drag != "":
		return
	target = node
	_hover = ""
	_ground = PackedFloat32Array()
	_ground_for = null


## Catches the button being let go anywhere, even outside the 3D view. It only trusts Godot's
## input state after seeing the button down, and waits for a few frames of "up" to be sure.
func poll(_valley) -> void:
	if _drag == "":
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_seen_down = true
		_up_frames = 0
	elif _seen_down:
		_up_frames += 1
		if _up_frames >= 3:
			_finish()
			redraw.call()


## Handles a mouse or key event in the 3D view. Returns true if it used it.
func handle_input(camera: Camera3D, event: InputEvent, valley) -> bool:
	if target == null or not is_instance_valid(target) or valley == null or not valley.has_heights():
		return false
	if event is InputEventMouse:
		_mouse = event.position
	if event is InputEventMouseMotion:
		if _drag != "":
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				_finish()
				return true
			_drag_to(camera, event, valley)
			redraw.call()
			return true
		var over := _handle_under(camera, event.position, valley)
		if over != _hover:
			_hover = over
			redraw.call()
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var kind := "height" if event.alt_pressed else _handle_under(camera, event.position, valley)
			if event.alt_pressed and not _has_target_height():
				return true
			if kind == "":
				return false
			_start(kind, camera, event.position, valley)
			redraw.call()
			return true
		if _drag != "":
			_finish()
			redraw.call()
			return true
		return false
	if _drag != "":
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			_cancel()
			redraw.call()
			return true
		# Until the button is let go, the drag owns the mouse
		if event is InputEventMouse:
			return true
	return false


func _has_target_height() -> bool:
	return target.mode == FLATTEN and not target.level_to_ground


# Which handle is under the mouse: the height handle and the ring win over the middle
func _handle_under(camera: Camera3D, screen: Vector2, valley) -> String:
	var middle := _middle_spot(valley)
	if camera.is_position_behind(middle):
		return ""
	var at := camera.unproject_position(middle)
	if _has_target_height() and screen.distance_to(at - Vector2(0, TOP_OFFSET)) < TOP_GRAB:
		return "height"
	var hit = _ray_to_ground(camera, screen, valley)
	if hit != null:
		# How far off the ring the mouse is, measured on screen at the nearest point of the ring
		var center := Vector2(target.global_position.x, target.global_position.z)
		var spot := Vector2(hit.x, hit.z)
		if spot.distance_to(center) > 0.01:
			var edge := center + (spot - center).normalized() * float(target.radius)
			var edge_world := Vector3(edge.x, valley.get_height(edge.x, edge.y), edge.y)
			if not camera.is_position_behind(edge_world) and camera.unproject_position(edge_world).distance_to(screen) < RING_GRAB:
				return "radius"
	if screen.distance_to(at) < MIDDLE_GRAB:
		return "move"
	return ""


func _start(kind: String, camera: Camera3D, screen: Vector2, valley) -> void:
	_drag = kind
	_moved = false
	_seen_down = false
	_up_frames = 0
	_position_before = target.position
	_radius_before = target.radius
	_refresh_ground(valley)
	target.begin_drag()
	var p: Vector3 = target.global_position
	_slide = Vector2(p.x, p.z)
	_target_above = p.y - _ground_at(valley, p.x, p.z)
	_last_screen_y = screen.y
	_last_hit = _ray_to_ground(camera, screen, valley)
	_grab_offset = _slide - Vector2(_last_hit.x, _last_hit.z) if _last_hit != null else Vector2.ZERO


func _drag_to(camera: Camera3D, event: InputEventMouseMotion, valley) -> void:
	var precise: bool = event.shift_pressed
	match _drag:
		"move":
			var hit = _ray_to_ground(camera, event.position, valley)
			if hit == null:
				return
			if precise and _last_hit != null:
				_slide += Vector2(hit.x - _last_hit.x, hit.z - _last_hit.z) * PRECISION
				_grab_offset = _slide - Vector2(hit.x, hit.z)
			else:
				_slide = Vector2(hit.x, hit.z) + _grab_offset
			_last_hit = hit
			var bounds: Rect2 = valley.map_rect().grow(-1.0)
			_slide = _slide.clamp(bounds.position, bounds.end)
			# It rides on the ground; a Flatten's target stays the same height above or below it
			var y := _ground_at(valley, _slide.x, _slide.y)
			if _has_target_height():
				y += _target_above
			target.global_position = Vector3(_slide.x, y, _slide.y)
			_moved = true
		"height":
			# One pixel is as many meters as it covers at the modifier's distance from the camera
			var distance := camera.global_position.distance_to(target.global_position)
			var meters_per_pixel := 2.0 * distance * tan(deg_to_rad(camera.fov * 0.5)) / maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
			var moved := (_last_screen_y - event.position.y) * meters_per_pixel
			_last_screen_y = event.position.y
			target.global_position.y += moved * (PRECISION if precise else 1.0)
			_moved = true
		"radius":
			var hit = _ray_to_ground(camera, event.position, valley)
			if hit == null:
				return
			var center := Vector2(target.global_position.x, target.global_position.z)
			var wanted := center.distance_to(Vector2(hit.x, hit.z))
			if precise and _last_hit != null:
				wanted = target.radius + (wanted - center.distance_to(Vector2(_last_hit.x, _last_hit.z))) * PRECISION
			_last_hit = hit
			target.radius = clampf(snappedf(wanted, 0.1 if precise else 0.5), 1.0, 300.0)
			_moved = true


# Letting go rebuilds the ground once, and records the whole drag as one step for Ctrl+Z.
# A press that never moved changes nothing.
func _finish() -> void:
	if _drag == "":
		return
	var kind := _drag
	_drag = ""
	if not _moved:
		target.end_drag(false)
		return
	target.end_drag(true)
	# (no undo history when this is driven by a test, outside the editor)
	if undo_redo:
		undo_redo.create_action("Resize terrain modifier" if kind == "radius" else "Move terrain modifier")
		undo_redo.add_do_property(target, "position", target.position)
		undo_redo.add_undo_property(target, "position", _position_before)
		undo_redo.add_do_property(target, "radius", target.radius)
		undo_redo.add_undo_property(target, "radius", _radius_before)
		undo_redo.commit_action(false)


func _cancel() -> void:
	_drag = ""
	target.position = _position_before
	target.radius = _radius_before
	target.end_drag(false)


func _ray_to_ground(camera: Camera3D, screen: Vector2, valley):
	return valley.ground_under_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


# Where its handles are drawn: on the ground at its middle
func _middle_spot(valley) -> Vector3:
	var p: Vector3 = target.global_position
	return Vector3(p.x, valley.get_height(p.x, p.z), p.z)


func _refresh_ground(valley) -> void:
	_ground = valley.heights_without(target)
	_ground_for = target


# The ground's height at a spot without this modifier's own effect
func _ground_at(valley, x: float, z: float) -> float:
	if _ground_for != target or _ground.is_empty():
		_refresh_ground(valley)
	return valley.height_in(_ground, x, z)


## Draws the handles, the label while dragging, and the controls hint
func draw(overlay: Control, camera: Camera3D, valley) -> void:
	if target == null or not is_instance_valid(target) or valley == null or not valley.has_heights():
		return
	var painter = load("res://addons/world_tools/object_painter.gd")
	var color: Color = target.MODE_COLORS[target.mode]
	var lit := Color(1.0, 0.95, 0.6)
	# The ring
	var ring_hot := _drag == "radius" or (_drag == "" and _hover == "radius")
	painter._ring(overlay, camera, valley, target.global_position, target.radius, lit if ring_hot else color, 4.0 if ring_hot else 2.5)
	var middle := _middle_spot(valley)
	if camera.is_position_behind(middle):
		return
	var at := camera.unproject_position(middle)
	# The middle
	var middle_hot := _drag == "move" or (_drag == "" and _hover == "move")
	var size := 13.0 if middle_hot else 11.0
	overlay.draw_circle(at, size + 2.5, Color(0.1, 0.07, 0.02))
	overlay.draw_circle(at, size, lit if middle_hot else color)
	overlay.draw_circle(at, size * 0.32, Color(1, 1, 1))
	# The height handle: a small diamond above the middle
	var warning := false
	if _has_target_height():
		var hot := _drag == "height" or (_drag == "" and _hover == "height")
		var top := at - Vector2(0, TOP_OFFSET)
		overlay.draw_line(at, top, Color(1, 1, 1, 0.7), 2.0, true)
		var r := 10.0 if hot else 8.0
		var diamond := PackedVector2Array([top + Vector2(0, -r), top + Vector2(r, 0), top + Vector2(0, r), top + Vector2(-r, 0)])
		overlay.draw_colored_polygon(diamond, lit if hot else Color(0.95, 0.95, 1.0))
		warning = target.global_position.y - _ground_at(valley, target.global_position.x, target.global_position.z) < -PIT_WARNING
	# The label: what's being changed, or a Flatten's target when it's just selected
	var text := _label(valley)
	if text != "":
		var font := overlay.get_theme_default_font()
		var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var spot := (_mouse + Vector2(18, 18)) if _drag != "" else (at + Vector2(22, -TOP_OFFSET - 10.0))
		spot.x = clampf(spot.x, 6.0, overlay.size.x - text_size.x - 12.0)
		spot.y = clampf(spot.y, 6.0, overlay.size.y - text_size.y - 12.0)
		overlay.draw_rect(Rect2(spot - Vector2(6, 4), text_size + Vector2(12, 8)), Color(0, 0, 0, 0.75))
		overlay.draw_multiline_string(font, spot + Vector2(0, font.get_ascent(13)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, -1, Color(1.0, 0.45, 0.35) if warning else Color(1, 1, 1))
	var lines := ["Terrain modifier", "Drag the middle: slide it over the ground", "Drag the ring: change its radius"]
	if _has_target_height():
		lines.append("Drag the diamond, or Alt + drag: raise or lower the target")
	lines.append("Hold Shift: fine adjustment")
	lines.append("Right-click while dragging: cancel")
	painter._hint(overlay, lines)


func _label(valley) -> String:
	var p: Vector3 = target.global_position
	var lines := []
	if _drag == "radius":
		lines.append("radius %.1f m" % target.radius)
	elif _drag == "move":
		lines.append("x %.1f   z %.1f" % [p.x, p.z])
	if _has_target_height():
		var above := p.y - _ground_at(valley, p.x, p.z)
		lines.append("target %.1f m" % p.y)
		lines.append("%.1f m %s the ground under it" % [absf(above), "above" if above >= 0.0 else "below"])
		if above < -PIT_WARNING:
			lines.append("WARNING: more than %d m below ground: this digs a pit" % int(PIT_WARNING))
	elif target.mode == FLATTEN and _drag != "":
		lines.append("target: the ground's own level (Level To Ground)")
	return "\n".join(lines)
