@tool
extends RefCounted
## The Texture Brush: paints ground materials (grass, dirt, forest floor, gravel path, rock)
## onto the terrain over its automatic coloring.
##   click / drag       paint the picked material
##   Alt + click/drag   rub the painting out, back to the automatic coloring
## The materials blend by height, using their Displacement maps: paint gravel over grass and
## its stones show through first; paint grass over gravel and it fills the low spots.
## The painting is saved (to the Valley's Ground Paint Path) each time a stroke ends, and
## survives every rebuild. Each stroke is one step for Ctrl+Z.

var undo_redo: EditorUndoRedoManager
## Called whenever the 3D view's overlay needs redrawing
var redraw: Callable

## Which material to paint: an index into the Valley's PAINT_MATERIALS
var material := 0
var radius := 4.0
## How much one pass of the brush lays on (0-1)
var strength := 0.35
## How much of the radius fades softly to nothing at the edge (0 = hard, 1 = soft throughout)
var falloff := 0.6

var _painting := false
var _erasing := false
var _before: Array = []
var _last_dab := Vector3.INF
var _cursor = null
var _alt := false


func handle_input(camera: Camera3D, event: InputEvent, valley) -> bool:
	if valley == null or not valley.has_heights():
		return false
	if event is InputEventMouse:
		_alt = event.alt_pressed
		_cursor = valley.ground_under_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventMouseMotion:
		if _painting:
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				finish_stroke(valley)
			elif _cursor != null and _cursor.distance_to(_last_dab) >= maxf(radius * 0.25, 0.25):
				_dab(valley)
		redraw.call()
		return _painting
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _cursor == null:
				return true
			_painting = true
			_erasing = event.alt_pressed
			_before = valley.paint_snapshot()
			_dab(valley)
		else:
			finish_stroke(valley)
		redraw.call()
		return true
	if _painting and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		_painting = false
		valley.restore_paint(_before)
		redraw.call()
		return true
	return false


# One dab of paint under the mouse. Dabs land every quarter of the radius as the brush moves,
# so a stroke lays on about the same amount however fast the mouse goes.
func _dab(valley) -> void:
	_last_dab = _cursor
	valley.paint_ground(Vector2(_cursor.x, _cursor.z), radius, strength * 0.5, falloff, material, _erasing)


## Ends the stroke: saves the painting and records the stroke as one step for Ctrl+Z
func finish_stroke(valley) -> void:
	if not _painting:
		return
	_painting = false
	var after: Array = valley.paint_snapshot()
	valley.save_paint()
	# (no undo history when the brush is driven by a test, outside the editor)
	if undo_redo == null:
		_before = []
		return
	undo_redo.create_action("Erase ground paint" if _erasing else "Paint %s" % valley.PAINT_MATERIALS[material])
	undo_redo.add_do_method(valley, "restore_paint", after)
	undo_redo.add_undo_method(valley, "restore_paint", _before)
	undo_redo.commit_action(false)
	_before = []


func draw(overlay: Control, camera: Camera3D, valley) -> void:
	if valley == null:
		return
	if _cursor != null:
		var erasing := _alt or (_painting and _erasing)
		var color := Color(1.0, 0.35, 0.3) if erasing else Color(0.45, 0.8, 1.0)
		var painter = load("res://addons/world_tools/object_painter.gd")
		painter._ring(overlay, camera, valley, _cursor, radius, color, 2.0)
		# The soft edge starts here
		if falloff > 0.02 and falloff < 0.98:
			painter._ring(overlay, camera, valley, _cursor, radius * (1.0 - falloff), Color(color, 0.45), 1.5)
	var picked: String = valley.PAINT_MATERIALS[material] if material < valley.PAINT_MATERIALS.size() else "?"
	load("res://addons/world_tools/object_painter.gd")._hint(overlay, [
		"Texture Brush: %s" % picked,
		"Click / drag: paint",
		"Alt + click / drag: erase back to automatic",
		"Right-click while painting: cancel the stroke",
	])
