@tool
extends RefCounted
## The Sculpt Brush: shapes the ground directly in the 3D view.
##   Raise, Lower, Smooth  hold the mouse down and paint
##   Flatten               Ctrl + click samples the height under the mouse, then painting pulls
##                         the ground toward it
##   Ramp                  press at one end, drag to the other, and let go: a smooth slope
##                         between them, as wide as the brush (Strength doesn't apply)
##   Alt + drag            rubs sculpting out, back to the ground underneath
## The ground under the brush updates while painting; trails and everything standing on the
## ground catch up when the mouse is let go. Each stroke is one step for Ctrl+Z.

const MODES := ["Raise", "Lower", "Smooth", "Flatten", "Ramp"]
const FLATTEN := "Flatten"
const RAMP := "Ramp"
## How fast Raise and Lower move the ground at full Strength, in meters per second
const LIFT_SPEED := 5.0
## How quickly Smooth and Flatten close the gap at full Strength
const PULL_RATE := 8.0
## At most this often the ground under the brush is updated, in seconds
const DAB_EVERY := 0.04

var undo_redo: EditorUndoRedoManager
## Called whenever the 3D view's overlay needs redrawing
var redraw: Callable

var mode := "Raise"
var radius := 10.0
## How quickly the brush works (0-1)
var strength := 0.5
## How much of the radius fades softly to nothing at the edge (0 = hard, 1 = soft throughout)
var falloff := 0.6
## The height Flatten pulls toward; nothing until it's been sampled
var flatten_height = null
## A message for the panel
var status := ""

var _painting := false
var _erasing := false
var _cursor = null
var _alt := false
var _last_dab_at := 0
var _last_dab_spot := Vector3.ZERO
var _ramp_start = null
# For spotting a release that happened outside the 3D view
var _seen_down := false
var _up_frames := 0


## Keeps the brush working while the mouse is held still, and catches the button being let go
## anywhere, even outside the 3D view
func poll(valley) -> void:
	if not _painting:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_seen_down = true
		_up_frames = 0
	elif _seen_down:
		_up_frames += 1
		if _up_frames >= 3:
			finish_stroke(valley)
			redraw.call()
			return
	_paint_toward_cursor(valley)


## Handles a mouse or key event in the 3D view. Returns true if it used it.
func handle_input(camera: Camera3D, event: InputEvent, valley) -> bool:
	if valley == null or not valley.has_heights():
		return false
	if event is InputEventMouse:
		_alt = event.alt_pressed
		_cursor = valley.ground_under_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventMouseMotion:
		if _painting and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			finish_stroke(valley)
		elif _painting:
			_paint_toward_cursor(valley)
		redraw.call()
		return _painting
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _cursor == null:
				return true
			# Ctrl + click: sample the height to flatten to
			if mode == FLATTEN and (event.ctrl_pressed or event.meta_pressed):
				flatten_height = _cursor.y
				status = "Flatten height: %.1f m" % flatten_height
			else:
				_start_stroke(valley, event.alt_pressed)
		else:
			finish_stroke(valley)
		redraw.call()
		return true
	if _painting and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		_painting = false
		_ramp_start = null
		valley.cancel_sculpt()
		redraw.call()
		return true
	return false


func _start_stroke(valley, erase: bool) -> void:
	status = ""
	_painting = true
	_erasing = erase
	_seen_down = false
	_up_frames = 0
	if mode == RAMP and not erase:
		_ramp_start = _cursor
		return
	# Flatten with nothing sampled yet: level to wherever the stroke starts
	if mode == FLATTEN and flatten_height == null and not erase:
		flatten_height = _cursor.y
	valley.begin_sculpt()
	_last_dab_at = Time.get_ticks_msec() - int(DAB_EVERY * 1000.0)
	_last_dab_spot = _cursor
	_paint_toward_cursor(valley)


# Lays the brush down along the way from the last dab to the mouse, working for as long as the
# time since then, so a stroke does the same however fast the mouse goes
func _paint_toward_cursor(valley) -> void:
	if _ramp_start != null or _cursor == null:
		return
	var now := Time.get_ticks_msec()
	var elapsed := (now - _last_dab_at) / 1000.0
	if elapsed < DAB_EVERY:
		return
	_last_dab_at = now
	elapsed = minf(elapsed, 0.25)
	var from: Vector3 = _last_dab_spot
	var to: Vector3 = _cursor
	var steps := clampi(ceili(Vector2(to.x - from.x, to.z - from.z).length() / maxf(radius * 0.5, 1.0)), 1, 12)
	var spots: Array[Vector2] = []
	for s in steps:
		var p := from.lerp(to, float(s + 1) / steps)
		spots.append(Vector2(p.x, p.z))
	for spot in spots:
		_dab(valley, spot, elapsed / steps)
	_last_dab_spot = to


func _dab(valley, spot: Vector2, seconds: float) -> void:
	var pull := 1.0 - exp(-PULL_RATE * strength * seconds)
	if _erasing:
		valley.sculpt_dab("Erase", spot, radius, pull, falloff)
		return
	match mode:
		"Raise":
			valley.sculpt_dab("Lift", spot, radius, LIFT_SPEED * strength * seconds, falloff)
		"Lower":
			valley.sculpt_dab("Lift", spot, radius, -LIFT_SPEED * strength * seconds, falloff)
		"Smooth":
			valley.sculpt_dab("Smooth", spot, radius, pull, falloff)
		FLATTEN:
			valley.sculpt_dab("Flatten", spot, radius, pull, falloff, flatten_height)


## Ends the stroke: a ramp is made now; then the file is saved, the ground and what's on it
## catch up, and the stroke is recorded as one step for Ctrl+Z
func finish_stroke(valley) -> void:
	if not _painting:
		return
	_painting = false
	if _ramp_start != null:
		var start: Vector3 = _ramp_start
		_ramp_start = null
		if _cursor == null or Vector2(start.x - _cursor.x, start.z - _cursor.z).length() < 1.0:
			return
		valley.begin_sculpt()
		valley.sculpt_ramp(start, _cursor, radius, falloff)
	var stroke: Dictionary = valley.end_sculpt()
	if stroke.is_empty():
		return
	# (no undo history when the brush is driven by a test, outside the editor)
	if undo_redo:
		undo_redo.create_action("Sculpt: %s" % ("Erase" if _erasing else mode))
		undo_redo.add_do_method(valley, "restore_sculpt", stroke["after"], stroke["area"])
		undo_redo.add_undo_method(valley, "restore_sculpt", stroke["before"], stroke["area"])
		undo_redo.commit_action(false)


func draw(overlay: Control, camera: Camera3D, valley) -> void:
	if valley == null or not valley.has_heights():
		return
	var painter = load("res://addons/world_tools/object_painter.gd")
	var erasing: bool = _alt or (_painting and _erasing)
	var color := Color(1.0, 0.35, 0.3) if erasing else Color(1.0, 0.8, 0.35)
	if _cursor != null:
		painter._ring(overlay, camera, valley, _cursor, radius, color, 2.0)
		if falloff > 0.02 and falloff < 0.98:
			painter._ring(overlay, camera, valley, _cursor, radius * (1.0 - falloff), Color(color, 0.45), 1.5)
		if mode == FLATTEN and flatten_height != null:
			_draw_disc(overlay, camera, _cursor, flatten_height)
			_label(overlay, camera.unproject_position(_cursor) if not camera.is_position_behind(_cursor) else Vector2.ZERO, "flatten to %.1f m" % flatten_height)
	if _ramp_start != null and _cursor != null:
		_draw_ramp(overlay, camera, _ramp_start, _cursor)
	var lines := ["Sculpt Brush: %s" % mode]
	match mode:
		FLATTEN:
			lines.append("Ctrl + click: sample the height to flatten to")
			lines.append("Click / drag: pull the ground toward it")
		RAMP:
			lines.append("Press at one end, drag to the other, let go")
		_:
			lines.append("Click / drag: paint (hold to keep working)")
	lines.append("Alt + drag: rub sculpting out")
	lines.append("Right-click while painting: cancel the stroke")
	painter._hint(overlay, lines)


# The target level, as a faint flat disc floating at that height under the brush
func _draw_disc(overlay: Control, camera: Camera3D, center: Vector3, height: float) -> void:
	var points := PackedVector2Array()
	for k in 48:
		var p := Vector2(center.x, center.z) + Vector2.from_angle(TAU * k / 48.0) * radius
		var world := Vector3(p.x, height, p.y)
		if camera.is_position_behind(world):
			return
		points.append(camera.unproject_position(world))
	if not Geometry2D.triangulate_polygon(points).is_empty():
		overlay.draw_colored_polygon(points, Color(0.5, 0.85, 1.0, 0.16))
	points.append(points[0])
	overlay.draw_polyline(points, Color(0.5, 0.85, 1.0, 0.5), 1.5, true)


# Where a ramp will go: its center line, its two edges, and how steep it'll be
func _draw_ramp(overlay: Control, camera: Camera3D, a: Vector3, b: Vector3) -> void:
	if camera.is_position_behind(a) or camera.is_position_behind(b):
		return
	var along := Vector2(b.x - a.x, b.z - a.z)
	var side := Vector3(-along.y, 0.0, along.x).normalized() * radius
	var color := Color(0.5, 0.85, 1.0, 0.9)
	overlay.draw_line(camera.unproject_position(a), camera.unproject_position(b), color, 3.0, true)
	for edge in [side, -side]:
		if not (camera.is_position_behind(a + edge) or camera.is_position_behind(b + edge)):
			overlay.draw_line(camera.unproject_position(a + edge), camera.unproject_position(b + edge), Color(color, 0.5), 1.5, true)
	var slope := rad_to_deg(atan2(absf(b.y - a.y), maxf(along.length(), 0.01)))
	_label(overlay, camera.unproject_position(b), "%.1f m to %.1f m\n%.0f m long, %.0f degrees" % [a.y, b.y, along.length(), slope])


func _label(overlay: Control, at: Vector2, text: String) -> void:
	var font := overlay.get_theme_default_font()
	var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var spot := at + Vector2(18, 18)
	overlay.draw_rect(Rect2(spot - Vector2(6, 4), size + Vector2(12, 8)), Color(0, 0, 0, 0.7))
	overlay.draw_multiline_string(font, spot + Vector2(0, font.get_ascent(13)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, -1, Color(1, 1, 1))
