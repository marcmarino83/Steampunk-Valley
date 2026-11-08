class_name CompassClock
extends Control
## The brass compass with its small clock, left of the action bar. The compass needle (slim and
## dark, red at the north end) points north relative to the way you face; the clock's hands show
## the in-game time of day (the hour hand twice round a day, the minute hand once an hour).
## Art: res://assets/ui/compass_clock.png, its own printed clock hands painted out. Without it, a
## plain compass is drawn in code.

## compass_clock.png (864 x 892): the compass rose's middle and how long the needle is from it,
## the clock's middle and its hands' lengths, all in the art's pixels; and how big the art's
## pixels are drawn on screen
const ART_SCALE := 0.161
## Where the compass's solid body (bezel and bracket) ends on the right; past it are only loose
## scroll curls, which tuck under slot 1's frame (see set_clip)
const BODY_RIGHT := 692.0
const COMPASS_CENTER := Vector2(390, 433)
const NEEDLE_LENGTH := 150.0
const CLOCK_CENTER := Vector2(721.7, 204.3)
const HOUR_HAND := 42.0
const MINUTE_HAND := 64.0
## Without the art, the compass is this wide
const PLAIN_SIZE := 96.0

const NORTH := Color(0.78, 0.13, 0.08)
const DARK := Color(0.12, 0.1, 0.08)
const SHADOW := Color(0, 0, 0, 0.4)

## Which way you're facing: radians clockwise from north
var heading := 0.0:
	set(value):
		if absf(wrapf(value - heading, -PI, PI)) > 0.003:
			heading = value
			queue_redraw()
## The time of day, 0 to 1 (0 = midnight, 0.5 = noon)
var time_of_day := 0.0:
	set(value):
		# Redraw when the minute hand has moved a step
		if absf(value - time_of_day) * 24.0 * 60.0 >= 1.0 or absf(value - time_of_day) > 0.5:
			time_of_day = value
			queue_redraw()

# Kept loaded while it's drawn (see BrassStyle.texture)
var _art: Texture2D
# Below `_clip.y` (its own pixels), nothing is drawn right of `_clip.x`
var _clip := Vector2(INF, INF)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art = BrassStyle.texture("compass_clock")
	size = _art.get_size() * ART_SCALE if _art else Vector2(PLAIN_SIZE, PLAIN_SIZE)


## How far right of its left edge the compass's solid body reaches
func right_reach() -> float:
	return BODY_RIGHT * ART_SCALE if _art else size.x


## Hides whatever is right of `x` and below `from_y` (in its own pixels): where slot 1 is, so
## the loose scroll curls look tucked under its frame
func set_clip(x: float, from_y: float) -> void:
	var clip := Vector2(x, from_y)
	if not clip.is_equal_approx(_clip):
		_clip = clip
		queue_redraw()


func _draw() -> void:
	var compass := size / 2.0
	var needle := PLAIN_SIZE * 0.4
	if _art:
		var split := clampf(_clip.y, 0.0, size.y)
		var width := clampf(_clip.x, 0.0, size.x)
		var to_art := 1.0 / ART_SCALE
		# Above the split, all of it; below, only up to the clip
		draw_texture_rect_region(_art, Rect2(0, 0, size.x, split), Rect2(0, 0, _art.get_width(), split * to_art))
		draw_texture_rect_region(_art, Rect2(0, split, width, size.y - split), Rect2(0, split * to_art, width * to_art, (size.y - split) * to_art))
		compass = COMPASS_CENTER * ART_SCALE
		needle = NEEDLE_LENGTH * ART_SCALE
		var clock := CLOCK_CENTER * ART_SCALE
		var hours := time_of_day * 24.0
		_hand(clock, fmod(hours, 12.0) / 12.0 * TAU, HOUR_HAND * ART_SCALE, 2.6)
		_hand(clock, fmod(hours * 60.0, 60.0) / 60.0 * TAU, MINUTE_HAND * ART_SCALE, 1.8)
		draw_circle(clock, 1.8, DARK)
	else:
		var r := PLAIN_SIZE / 2.0 - 2.0
		draw_circle(compass, r, BrassStyle.BRASS_DARK)
		draw_circle(compass, r - 3.0, Color(0.86, 0.82, 0.7))
	# North is where it is relative to the way you face: turned back against your heading
	_needle(compass, -heading, needle)


# The compass needle: a slim diamond, red to the north and dark to the south, with a brass cap
func _needle(center: Vector2, angle: float, length: float) -> void:
	var width := maxf(length * 0.08, 2.0)
	var north := PackedVector2Array([Vector2(0, -length), Vector2(width, 0), Vector2(-width, 0)])
	var south := PackedVector2Array([Vector2(0, length * 0.75), Vector2(width, 0), Vector2(-width, 0)])
	draw_set_transform(center + Vector2(1.0, 1.5), angle)
	draw_colored_polygon(north, SHADOW)
	draw_colored_polygon(south, SHADOW)
	draw_set_transform(center, angle)
	draw_colored_polygon(north, NORTH)
	draw_colored_polygon(south, DARK)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_circle(center, width * 1.1, BrassStyle.BRASS_DARK)
	draw_circle(center - Vector2(0.4, 0.4), width * 0.6, BrassStyle.BRASS)


# A clock hand turned `angle` clockwise from twelve: a dark taper with a soft shadow
func _hand(center: Vector2, angle: float, length: float, width: float) -> void:
	var shape := PackedVector2Array([Vector2(-width / 2.0, 0), Vector2(0, -length), Vector2(width / 2.0, 0), Vector2(0, length * 0.15)])
	draw_set_transform(center + Vector2(0.8, 1.0), angle)
	draw_colored_polygon(shape, SHADOW)
	draw_set_transform(center, angle)
	draw_colored_polygon(shape, DARK)
	draw_set_transform_matrix(Transform2D.IDENTITY)
