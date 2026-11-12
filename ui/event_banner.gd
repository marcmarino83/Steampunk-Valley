class_name EventBanner
extends Control
## The banner for an event worth stopping for: a brass plate near the top of the screen with the
## event in the banner font (Rye) and an optional line beneath in the body font, fading in, staying
## a few seconds, and fading out. Events that come while one is showing wait their turn.
##
## Used for: a visitor arriving, a building starting to work; ready for later events (an era
## unlocked, a quest done): player.show_banner("The Forge era", "New blueprints in the build menu").

## How far below the top of the screen it sits, how long it stays, and its fades (seconds)
const TOP := 118.0
const HOLD := 3.5
const FADE := 0.35
const TITLE_SIZE := 40
const LINE_SIZE := 20

var _plate: PanelContainer
var _title: Label
var _line: Label
var _queue: Array = []
var _showing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = TOP
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_plate = PanelContainer.new()
	_plate.add_theme_stylebox_override("panel", BrassStyle.frame("plate"))
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_plate)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_plate.add_child(column)
	_title = BrassStyle.label("", TITLE_SIZE, BrassStyle.TEXT)
	_title.add_theme_font_override("font", BrassStyle.banner_font())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	column.add_child(_title)
	_line = BrassStyle.label("", LINE_SIZE, BrassStyle.TEXT_DIM)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_line)
	_plate.modulate.a = 0.0
	_plate.visible = false


## Shows an event: its title, and a line beneath it (optional)
func show_event(title: String, line := "") -> void:
	_queue.append([title, line])
	if not _showing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_showing = false
		_plate.visible = false
		return
	_showing = true
	var event: Array = _queue.pop_front()
	_title.text = event[0]
	_line.text = event[1]
	_line.visible = not str(event[1]).is_empty()
	_plate.visible = true
	_plate.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_plate, "modulate:a", 1.0, FADE)
	tween.tween_interval(HOLD)
	tween.tween_property(_plate, "modulate:a", 0.0, FADE)
	tween.tween_callback(_next)
