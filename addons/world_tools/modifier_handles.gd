@tool
extends RefCounted
## The one handle a selected TerrainModifier has in the 3D view: drag its outer ring to change
## its radius (hold Shift for fine changes; right-click or Esc cancels). A press anywhere but
## on the ring goes straight through to Godot's own gizmo, which moves the marker.

## Holding Shift while dragging changes the radius at this fraction of the mouse's speed
const PRECISION := 0.25
## How close (on screen, in pixels) a press must be to grab the ring
const RING_GRAB := 12.0

var undo_redo: EditorUndoRedoManager
## Called whenever the 3D view's overlay needs redrawing
var redraw: Callable
## The modifier being edited
var target: Node3D

var _dragging := false
var _hover := false
var _radius_before := 0.0
var _moved := false
var _last_hit = null
var _mouse := Vector2.ZERO
# For spotting a release that happened outside the 3D view
var _seen_down := false
var _up_frames := 0


## True while the ring is being dragged (changes of selection wait until it's over)
func is_dragging() -> bool:
	return _dragging


## Chooses the modifier to edit
func set_target(node: Node3D) -> void:
	if _dragging:
		return
	target = node
	_hover = false


## Catches the button being let go anywhere, even outside the 3D view. It only trusts Godot's
## input state after seeing the button down, and waits for a few frames of "up" to be sure.
func poll(_valley) -> void:
	if not _dragging:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_seen_down = true
		_up_frames = 0
	elif _seen_down:
		_up_frames += 1
		if _up_frames >= 3:
			_finish()
			redraw.call()


## Handles a mouse or key event in the 3D view. Returns true only if it's the ring's: anything
## else carries on to Godot's gizmo.
func handle_input(camera: Camera3D, event: InputEvent, valley) -> bool:
	if target == null or not is_instance_valid(target) or valley == null or not valley.has_heights():
		return false
	if event is InputEventMouse:
		_mouse = event.position
	if event is InputEventMouseMotion:
		if _dragging:
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				_finish()
				return true
			_drag_to(camera, event, valley)
			redraw.call()
			return true
		var over := _on_ring(camera, event.position, valley)
		if over != _hover:
			_hover = over
			redraw.call()
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _on_ring(camera, event.position, valley):
				return false
			_dragging = true
			_moved = false
			_seen_down = false
			_up_frames = 0
			_radius_before = target.radius
			_last_hit = _ray_to_ground(camera, event.position, valley)
			target.begin_drag()
			redraw.call()
			return true
		if _dragging:
			_finish()
			redraw.call()
			return true
		return false
	if _dragging:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			_dragging = false
			target.radius = _radius_before
			target.end_drag(true)
			redraw.call()
			return true
		# Until the button is let go, the drag owns the mouse
		if event is InputEventMouse:
			return true
	return false


# True if the mouse is on the ring itself, measured on screen at the nearest point of the ring
func _on_ring(camera: Camera3D, screen: Vector2, valley) -> bool:
	var hit = _ray_to_ground(camera, screen, valley)
	if hit == null:
		return false
	var center := Vector2(target.global_position.x, target.global_position.z)
	var spot := Vector2(hit.x, hit.z)
	if spot.distance_to(center) < 0.01:
		return false
	var edge := center + (spot - center).normalized() * float(target.radius)
	var edge_world := Vector3(edge.x, valley.get_height(edge.x, edge.y), edge.y)
	return not camera.is_position_behind(edge_world) and camera.unproject_position(edge_world).distance_to(screen) < RING_GRAB


func _drag_to(camera: Camera3D, event: InputEventMouseMotion, valley) -> void:
	var hit = _ray_to_ground(camera, event.position, valley)
	if hit == null:
		return
	var center := Vector2(target.global_position.x, target.global_position.z)
	var wanted := center.distance_to(Vector2(hit.x, hit.z))
	if event.shift_pressed and _last_hit != null:
		wanted = target.radius + (wanted - center.distance_to(Vector2(_last_hit.x, _last_hit.z))) * PRECISION
	_last_hit = hit
	target.radius = clampf(snappedf(wanted, 0.1 if event.shift_pressed else 0.5), 1.0, 300.0)
	_moved = true


# Letting go rebuilds the ground once, and records the whole drag as one step for Ctrl+Z. A
# press that never moved changes nothing.
func _finish() -> void:
	if not _dragging:
		return
	_dragging = false
	target.end_drag(_moved)
	# (no undo history when this is driven by a test, outside the editor)
	if _moved and undo_redo:
		undo_redo.create_action("Resize terrain modifier")
		undo_redo.add_do_property(target, "radius", target.radius)
		undo_redo.add_undo_property(target, "radius", _radius_before)
		undo_redo.commit_action(false)


func _ray_to_ground(camera: Camera3D, screen: Vector2, valley):
	return valley.ground_under_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


## Draws the ring, a line from the marker down to the ground with the marker's height, and the
## controls hint
func draw(overlay: Control, camera: Camera3D, valley) -> void:
	if target == null or not is_instance_valid(target) or valley == null or not valley.has_heights():
		return
	var painter = load("res://addons/world_tools/object_painter.gd")
	var color: Color = target.MODE_COLORS[target.mode]
	var hot := _dragging or _hover
	painter._ring(overlay, camera, valley, target.global_position, target.radius, Color(1.0, 0.95, 0.6) if hot else color, 4.0 if hot else 2.5)
	var p: Vector3 = target.global_position
	var ground := Vector3(p.x, valley.get_height(p.x, p.z), p.z)
	if not (camera.is_position_behind(p) or camera.is_position_behind(ground)):
		var at := camera.unproject_position(p)
		overlay.draw_line(at, camera.unproject_position(ground), Color(color, 0.8), 2.0, true)
		var text := "radius %.1f m" % target.radius if _dragging else ("height %.1f m" % p.y if target.uses_height() else "")
		if text != "":
			var font := overlay.get_theme_default_font()
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var spot := _mouse + Vector2(18, 18) if _dragging else at + Vector2(16, 6)
			overlay.draw_rect(Rect2(spot - Vector2(6, 4), text_size + Vector2(12, 8)), Color(0, 0, 0, 0.7))
			overlay.draw_string(font, spot + Vector2(0, font.get_ascent(13)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
	var lines := ["Terrain modifier"]
	if target.uses_height():
		lines.append("Move it with the gizmo: X and Z say where, Y how high")
	else:
		lines.append("Move it with the gizmo: X and Z say where it acts")
	lines.append("Drag the ring: change its radius (Shift: fine)")
	painter._hint(overlay, lines)
