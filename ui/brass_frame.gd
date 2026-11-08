class_name BrassFrame
extends StyleBox
## A restrained brass frame drawn in code: a thin bevelled border of slightly worn gold (lit along
## the top and left, darker along the bottom and right) round a flat dark brown fill, with a very
## subtle vignette, and small rivets at the corners if asked. Slots use it "recessed": a darker
## fill with a soft shadow along the inside of the top and left edges.

const BRASS := Color(0.72, 0.56, 0.31)
const BRASS_LIGHT := Color(0.93, 0.8, 0.52)
const BRASS_DARK := Color(0.36, 0.26, 0.13)
const GOLD := Color(0.98, 0.8, 0.38)
const SHADOW := Color(0.06, 0.04, 0.025)
const GLOW := Color(1.0, 0.76, 0.3, 0.5)

## The inside colour
@export var fill := Color(0.165, 0.13, 0.094, 0.92):
	set(value):
		fill = value
		emit_changed()
## How thick the brass border is, and how round the corners are, in pixels
@export var band := 3.0:
	set(value):
		band = value
		emit_changed()
@export var radius := 3.0:
	set(value):
		radius = value
		emit_changed()
## Small rivets at the corners
@export var rivets := false:
	set(value):
		rivets = value
		emit_changed()
## The inside darkens a little toward its edges
@export var vignette := false:
	set(value):
		vignette = value
		emit_changed()
## Sunk in, like a slot: a soft shadow along the inside of the top and left edges
@export var recessed := false:
	set(value):
		recessed = value
		emit_changed()
## Brighter brass (under the mouse)
@export var lit := false:
	set(value):
		lit = value
		emit_changed()
## A bright gold edge with a soft glow round it (selected)
@export var glow := false:
	set(value):
		glow = value
		emit_changed()

var _flat := StyleBoxFlat.new()


func _init() -> void:
	_flat.anti_aliasing = true


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var gold := GOLD if glow else (BRASS.lerp(BRASS_LIGHT, 0.35) if lit else BRASS)
	_reset()
	if glow:
		_flat.shadow_color = GLOW
		_flat.shadow_size = 7
	# The border: a dark outline, then the gold with its bevel (light top-left, dark bottom-right)
	_box(to_canvas_item, rect, SHADOW, radius)
	_flat.shadow_size = 0
	var edge := rect.grow(-1.0)
	_box(to_canvas_item, edge, BRASS_DARK, radius - 1.0)
	_box(to_canvas_item, Rect2(edge.position, edge.size - Vector2.ONE), gold.lerp(BRASS_LIGHT, 0.5), radius - 1.0)
	_box(to_canvas_item, Rect2(edge.position + Vector2.ONE, edge.size - Vector2(2, 2)), gold, radius - 1.0)
	# The fill, inside a fine dark line
	var inside := rect.grow(-band)
	if inside.size.x <= 0.0 or inside.size.y <= 0.0:
		return
	_box(to_canvas_item, inside.grow(1.0), SHADOW, maxf(radius - band + 1.0, 0.0))
	_box(to_canvas_item, inside, fill, maxf(radius - band, 0.0))
	if vignette:
		# A wide border that fades from the edge inward, barely there
		_reset()
		_flat.draw_center = false
		_flat.border_blend = true
		_flat.bg_color = Color(0, 0, 0, 0)
		_flat.border_color = Color(0, 0, 0, 0.22)
		_flat.set_border_width_all(int(clampf(minf(inside.size.x, inside.size.y) * 0.18, 6.0, 40.0)))
		_flat.draw(to_canvas_item, inside)
	if recessed:
		_reset()
		_flat.draw_center = false
		_flat.border_blend = true
		_flat.bg_color = Color(0, 0, 0, 0)
		_flat.border_color = Color(0, 0, 0, 0.5)
		_flat.border_width_top = int(maxf(band + 1.0, 3.0))
		_flat.border_width_left = int(maxf(band + 1.0, 3.0))
		_flat.border_width_bottom = 1
		_flat.border_width_right = 1
		_flat.draw(to_canvas_item, inside)
	_reset()
	if rivets:
		var r := clampf(band * 0.8, 1.8, 3.0)
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
			var center: Vector2 = corner + Vector2(band if corner.x < rect.get_center().x else -band, band if corner.y < rect.get_center().y else -band)
			_rivet(to_canvas_item, center, r)


func _reset() -> void:
	_flat.draw_center = true
	_flat.border_blend = false
	_flat.set_border_width_all(0)
	_flat.shadow_size = 0


func _box(canvas_item: RID, rect: Rect2, color: Color, corner: float) -> void:
	_flat.bg_color = color
	_flat.set_corner_radius_all(int(maxf(corner, 0.0)))
	_flat.draw(canvas_item, rect)


# A small round rivet head: a dark rim, worn brass, and a bright spot up and to the left
static func _rivet(canvas_item: RID, center: Vector2, r: float) -> void:
	RenderingServer.canvas_item_add_circle(canvas_item, center, r + 0.8, SHADOW)
	RenderingServer.canvas_item_add_circle(canvas_item, center, r, BRASS_DARK)
	RenderingServer.canvas_item_add_circle(canvas_item, center - Vector2(0.25, 0.25) * r, r * 0.72, BRASS)
	RenderingServer.canvas_item_add_circle(canvas_item, center - Vector2(0.35, 0.35) * r, r * 0.28, BRASS_LIGHT)
