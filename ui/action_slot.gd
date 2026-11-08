extends PanelContainer
## One slot on the action bar. Tools can be dragged into it, out of it, and between slots.
## Over the bar's art, it shows the slot picture cut from that art: plain with an item in it, the
## gear slot when empty, golden when selected; the item's icon and the slot's number draw on top.

## A tool was dragged onto this slot
signal tool_dropped(item: String)

## The selected slot: the plain slot tinted gold, with a soft golden glow round it
const GOLD := Color(1.45, 1.18, 0.62)
const GLOW := Color(1.0, 0.78, 0.3, 0.55)

@onready var swatch: ColorRect = $Swatch
@onready var icon: TextureRect = $Icon
@onready var number_label: Label = $Number

var _item := ""
var _selected := false
# The slot pictures (kept loaded while they're drawn); null without the bar's art, when the slot
# is a code-drawn brass frame instead (plain, and selected with a gold edge and glow)
var _plain_art: Texture2D
var _gear_art: Texture2D
var _style: StyleBox
var _normal_style: StyleBox
# Over the bar's art: the picture's size (the slot is wider by the gap to the next one)
var _opening := Vector2.ZERO
var _glow := StyleBoxFlat.new()


func _ready() -> void:
	_normal_style = BrassStyle.frame("slot")
	_style = BrassStyle.frame("slot_selected")
	add_theme_stylebox_override("panel", _normal_style)
	_glow.bg_color = Color(0, 0, 0, 0)
	_glow.shadow_color = GLOW
	_glow.shadow_size = 8
	_glow.set_corner_radius_all(4)


## Sits over one of the bar art's openings: `opening` big, with `gap` to the next one
func fit_opening(opening: Vector2, gap: float) -> void:
	_opening = opening
	_plain_art = BrassStyle.texture("slot_plain")
	_gear_art = BrassStyle.texture("slot_gear")
	custom_minimum_size = Vector2(opening.x + gap, opening.y)
	# The icon and number sit inside the picture's frame, not in the gap after it
	var inside := StyleBoxEmpty.new()
	inside.content_margin_left = opening.x * 0.1
	inside.content_margin_top = opening.y * 0.06
	inside.content_margin_right = opening.x * 0.1 + gap
	inside.content_margin_bottom = opening.y * 0.1
	_normal_style = inside
	_style = inside
	add_theme_stylebox_override("panel", inside)
	icon.custom_minimum_size = Vector2.ONE * opening.x * 0.6
	number_label.add_theme_font_size_override("font_size", 13)


func _draw() -> void:
	if _plain_art == null:
		# The code-drawn slot: a faint gear when empty
		if _item.is_empty():
			BrassStyle.draw_slot_gear(self, Rect2(Vector2.ZERO, size))
		return
	var picture := Rect2(Vector2.ZERO, _opening)
	if _selected:
		_glow.draw(get_canvas_item(), picture.grow(-2.0))
		draw_texture_rect(_plain_art, picture, false, GOLD)
	elif _item.is_empty() and _gear_art:
		draw_texture_rect(_gear_art, picture, false)
	else:
		draw_texture_rect(_plain_art, picture, false)


func set_number(number: int) -> void:
	number_label.text = str(number)


func show_item(item: String, selected: bool) -> void:
	_item = item
	_selected = selected
	if selected:
		add_theme_stylebox_override("panel", _style)
	else:
		add_theme_stylebox_override("panel", _normal_style)
	queue_redraw()
	icon.hide()
	if item.is_empty():
		swatch.color = Color.TRANSPARENT
		swatch.show()
	elif InventorySlot.ITEM_ICONS.has(item):
		icon.texture = InventorySlot.ITEM_ICONS[item]
		icon.show()
		swatch.hide()
	else:
		swatch.color = InventorySlot.ITEM_COLORS.get(item, Color(0.6, 0.6, 0.6))
		swatch.show()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if _item.is_empty():
		return null
	DragIcon.start(self, InventorySlot.make_drag_preview(_item))
	return {"tool_item": _item, "from_bar": true}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		DragIcon.stop()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("tool_item")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	tool_dropped.emit(data["tool_item"])
