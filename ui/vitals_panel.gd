class_name VitalsPanel
extends Control
## Bottom left: the brass vitals panel. Its gauge's needle shows warmth (the red zone is full
## warmth), and its two bar channels fill with hunger (gold) and warmth (orange-red), each fill
## ending in a soft edge. The words and icons are part of the art.
## Art: res://assets/ui/vitals_panel.png. Without it, plain bars are drawn in code.

## The gap to the screen's edges, in pixels at 1920 x 1080, and how big the art's pixels are drawn
const EDGE := 16.0
const ART_SCALE := 0.23
## vitals_panel.png (1016 x 742), in its pixels: the gauge's centre hole, the needle's length (it
## stays inside the scale's ticks), and the scale's ends as angles from the hole (0 = right,
## negative = up), empty to full
const HOLE := Vector2(517.9, 299.2)
const NEEDLE_LENGTH := 196.0
const NEEDLE_EMPTY := -172.0
const NEEDLE_FULL := -9.0
## The inside of each bar channel (kept clear of its pointed ends and its rim)
const HUNGER_CHANNEL := Rect2(60, 493, 897, 38)
const WARMTH_CHANNEL := Rect2(60, 663, 897, 37)
## How long a fill's soft end is, in the art's pixels
const SOFT_END := 26.0
## How fast the needle and fills catch up with a change (per second)
const EASE := 6.0
## Without the art: a plain panel this big
const PLAIN_SIZE := Vector2(200, 64)

const NEEDLE := Color(0.13, 0.1, 0.08)
const NEEDLE_SHADOW := Color(0, 0, 0, 0.35)

var _art: Texture2D
var _box: Control
# What's shown (easing towards the latest values), 0 to 100
var _hunger := 100.0
var _warmth := 100.0
var _hunger_target := 100.0
var _warmth_target := 100.0


func _ready() -> void:
	# The whole screen to place things in (the panel sits at the bottom left, see _process)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art = BrassStyle.texture("vitals_panel")
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.size = _art.get_size() * ART_SCALE if _art else PLAIN_SIZE
	_box.draw.connect(_draw_panel)
	add_child(_box)


func _process(delta: float) -> void:
	_box.position = Vector2(EDGE, get_viewport_rect().size.y - EDGE - _box.size.y)
	var step := 1.0 - exp(-EASE * delta)
	var hunger := lerpf(_hunger, _hunger_target, step)
	var warmth := lerpf(_warmth, _warmth_target, step)
	if absf(hunger - _hunger) > 0.01 or absf(warmth - _warmth) > 0.01:
		_hunger = hunger
		_warmth = warmth
		_box.queue_redraw()


## Hunger and warmth, 0 to 100
func set_values(hunger: float, warmth: float) -> void:
	_hunger_target = clampf(hunger, 0.0, 100.0)
	_warmth_target = clampf(warmth, 0.0, 100.0)


func _draw_panel() -> void:
	if _art == null:
		_box.draw_rect(Rect2(Vector2.ZERO, _box.size), BrassStyle.PANEL)
		_fill(Rect2(10, 14, 180, 12), _hunger, BrassStyle.HUNGER_FILL, 1.0)
		_fill(Rect2(10, 38, 180, 12), _warmth, BrassStyle.WARMTH_FILL, 1.0)
		return
	_box.draw_texture_rect(_art, Rect2(Vector2.ZERO, _box.size), false)
	var s := ART_SCALE
	_fill(Rect2(HUNGER_CHANNEL.position * s, HUNGER_CHANNEL.size * s), _hunger, BrassStyle.HUNGER_FILL, s)
	_fill(Rect2(WARMTH_CHANNEL.position * s, WARMTH_CHANNEL.size * s), _warmth, BrassStyle.WARMTH_FILL, s)
	_needle(HOLE * s, deg_to_rad(lerpf(NEEDLE_EMPTY, NEEDLE_FULL, _warmth / 100.0)), NEEDLE_LENGTH * s)


# A bar's fill along `channel`, `value` percent full: solid, with a lighter top and darker bottom
# so it reads as a lit tube, fading out over its last few pixels
func _fill(channel: Rect2, value: float, color: Color, s: float) -> void:
	var length := channel.size.x * value / 100.0
	if length < 0.5:
		return
	var soft := minf(SOFT_END * s, length)
	var solid := length - soft
	var top := channel.position.y
	var bottom := channel.end.y
	var left := channel.position.x
	# The solid part, shaded top to bottom
	var bands := [[0.0, 0.3, color.lightened(0.25), color], [0.3, 0.75, color, color], [0.75, 1.0, color, color.darkened(0.35)]]
	for band in bands:
		var y0: float = lerpf(top, bottom, band[0])
		var y1: float = lerpf(top, bottom, band[1])
		var c0: Color = band[2]
		var c1: Color = band[3]
		if solid > 0.0:
			_box.draw_polygon(PackedVector2Array([Vector2(left, y0), Vector2(left + solid, y0), Vector2(left + solid, y1), Vector2(left, y1)]),
					PackedColorArray([c0, c0, c1, c1]))
		# The soft end: the same shading, fading to nothing
		_box.draw_polygon(PackedVector2Array([Vector2(left + solid, y0), Vector2(left + length, y0), Vector2(left + length, y1), Vector2(left + solid, y1)]),
				PackedColorArray([c0, Color(c0, 0.0), Color(c1, 0.0), c1]))


# The gauge needle from the hole: a slim dark taper with a short tail and a shadow
func _needle(center: Vector2, angle: float, length: float) -> void:
	var width := maxf(length * 0.06, 1.6)
	var shape := PackedVector2Array([Vector2(-length * 0.14, -width * 0.6), Vector2(0, -width), Vector2(length, 0), Vector2(0, width), Vector2(-length * 0.14, width * 0.6)])
	_box.draw_set_transform(center + Vector2(1.0, 1.4), angle)
	_box.draw_colored_polygon(shape, NEEDLE_SHADOW)
	_box.draw_set_transform(center, angle)
	_box.draw_colored_polygon(shape, NEEDLE)
	_box.draw_set_transform_matrix(Transform2D.IDENTITY)
	_box.draw_circle(center, width * 1.3, BrassStyle.BRASS_DARK)
	_box.draw_circle(center - Vector2(0.3, 0.3), width * 0.7, BrassStyle.BRASS)
