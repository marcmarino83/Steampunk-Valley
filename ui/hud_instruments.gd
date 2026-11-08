class_name HudInstruments
extends Control
## The brass instruments around the action bar, and the crosshair: the compass with its small
## clock (see CompassClock) sitting over the action bar's left scrollwork, drawn on top of the
## bar, and a thin brass ring in the middle of the screen.
## Art: res://assets/ui/crosshair.png (drawn at 32 px, smoothed with its mipmaps).

## The crosshair's size, and the gaps the compass keeps from slot 1 and from the controls row
const CROSSHAIR_SIZE := 32.0
const SLOT_GAP := 0.0
const ROW_GAP := 6.0
const RING_RADIUS := 9.0

var _compass: CompassClock
var _crosshair: Control
# Kept loaded for as long as the crosshair draws it (see BrassStyle.texture)
var _crosshair_art: Texture2D
var _first_slot := Rect2()
var _bar_bottom := 0.0
var _avoid := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Added after the action bar, so it draws on top of the bar's scrollwork
	_compass = CompassClock.new()
	add_child(_compass)
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.size = Vector2(CROSSHAIR_SIZE, CROSSHAIR_SIZE)
	_crosshair.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_crosshair_art = BrassStyle.texture("crosshair")
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)


## Each frame: which way you face (radians clockwise from north), the time of day (0 to 1),
## where slot 1 and the bottom of the action bar's art are on screen, and where the controls row
## is (empty if none), which the compass keeps clear of
func update_instruments(heading: float, time_of_day: float, first_slot: Rect2, bar_bottom: float, avoid: Rect2) -> void:
	_compass.heading = heading
	_compass.time_of_day = time_of_day
	_first_slot = first_slot
	_bar_bottom = bar_bottom
	_avoid = avoid


## Shows or hides the crosshair (hidden while a menu is open)
func show_crosshair(shown: bool) -> void:
	_crosshair.visible = shown


func _process(_delta: float) -> void:
	# Mounted on the bar's trimmed left end, its brass right up to slot 1's frame, level with the
	# bar's bottom (and never below the screen)
	var bottom := minf(_bar_bottom, get_viewport_rect().size.y)
	var spot := Vector2(_first_slot.position.x - SLOT_GAP - _compass.right_reach(), bottom - _compass.size.y)
	# If the controls row would overlap it, the row stays put and the compass moves left
	if _avoid.has_area() and Rect2(spot, _compass.size).intersects(_avoid.grow(ROW_GAP)):
		spot.x = minf(spot.x, _avoid.position.x - ROW_GAP - _compass.right_reach())
	_compass.position = spot
	_compass.set_clip(_first_slot.position.x - spot.x, _first_slot.position.y - spot.y)
	_crosshair.position = get_viewport_rect().size / 2.0 - _crosshair.size / 2.0


func _draw_crosshair() -> void:
	var center := _crosshair.size / 2.0
	var art := _crosshair_art
	if art:
		# A thin dark outline under it, so the semi-transparent ring shows on bright ground too
		for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_crosshair.draw_texture_rect(art, Rect2(offset, _crosshair.size), false, Color(0, 0, 0, 0.45))
		_crosshair.draw_texture_rect(art, Rect2(Vector2.ZERO, _crosshair.size), false)
		return
	# A thin brass ring with four short ticks outside it and a dot in the middle, all with a
	# dark edge so it shows on bright ground and sky
	_crosshair.draw_arc(center, RING_RADIUS, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 3.5, true)
	_crosshair.draw_arc(center, RING_RADIUS, 0.0, TAU, 40, BrassStyle.BRASS_LIGHT, 1.6, true)
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0)
		_crosshair.draw_line(center + d * (RING_RADIUS + 2.0), center + d * (RING_RADIUS + 6.0), Color(0, 0, 0, 0.6), 3.5, true)
		_crosshair.draw_line(center + d * (RING_RADIUS + 2.0), center + d * (RING_RADIUS + 6.0), BrassStyle.BRASS_LIGHT, 1.6, true)
	_crosshair.draw_circle(center, 1.6, BrassStyle.BRASS_LIGHT)
