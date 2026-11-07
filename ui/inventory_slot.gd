class_name InventorySlot
extends PanelContainer

## A tool from the action bar was dragged back onto this slot
signal tool_returned(item: String)
## An item was dragged here from the other container ("backpack" or "chest")
signal item_moved(item: String, from: String)
## Shift-click: move this slot's whole stack to the other container
signal quick_move(item: String, from: String)

## Which container this slot belongs to: "backpack" or "chest"
var container := "backpack"
## When a chest is open, anything can be moved between it and the backpack, not just tools
var trading := false

## Placeholder colors for items that don't have an icon image yet.
## Anything not listed here shows up gray.
const ITEM_COLORS := {
	"Scrap": Color(0.55, 0.5, 0.45),
	"Coal": Color(0.12, 0.12, 0.12),
	"Wood": Color(0.45, 0.3, 0.18),
	"Berries": Color(0.72, 0.12, 0.18),
	"Stone": Color(0.62, 0.61, 0.58),
	"Plant Fiber": Color(0.7, 0.72, 0.38),
	"Sticks": Color(0.52, 0.37, 0.2),
	"Tin Ore": Color(0.8, 0.82, 0.86),
	"Dowsing Rod": Color(0.88, 0.66, 0.28),
	"Iron Ore": Color(0.5, 0.22, 0.12),
	"Copper Ore": Color(0.2, 0.62, 0.5),
	"Mushrooms": Color(0.78, 0.6, 0.42),
	"Herbs": Color(0.36, 0.66, 0.26),
	"Rope": Color(0.66, 0.56, 0.36),
	"Planks": Color(0.7, 0.52, 0.3),
	"Torch": Color(0.95, 0.55, 0.2),
	"Spear": Color(0.56, 0.44, 0.3),
}

## Real icon images. When you have one, add a line like:
##     "Coal": preload("res://icons/coal.png"),
## and that item will show the picture instead of its colored square.
const ITEM_ICONS := {
	"Hammer": preload("res://assets/tier_1_tools/icons/hammer.png"),
	"Axe": preload("res://assets/tier_1_tools/icons/axe.png"),
	"Pickaxe": preload("res://assets/tier_1_tools/icons/pickaxe.png"),
	"Knife": preload("res://assets/tier_1_tools/icons/knife.png"),
}

## The have / need count on a recipe's cost slot: normal, and when you're short
const COUNT_COLOR := Color(0.94, 0.9, 0.82)
const MISSING_COLOR := Color(1.0, 0.36, 0.3)

@onready var swatch: ColorRect = $VBox/Swatch
@onready var icon: TextureRect = $VBox/Icon
@onready var name_label: Label = $VBox/NameLabel
@onready var count_label: Label = $VBox/CountLabel

var _item := ""


## An item's picture: its icon, or a little square of its placeholder color
static func icon_for(item: String) -> Texture2D:
	if ITEM_ICONS.has(item):
		return ITEM_ICONS[item]
	var square := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	square.fill(ITEM_COLORS.get(item, Color(0.6, 0.6, 0.6)))
	return ImageTexture.create_from_image(square)


## What follows the mouse while dragging this item
static func make_drag_preview(item: String) -> Control:
	var square: Control
	if ITEM_ICONS.has(item):
		square = TextureRect.new()
		square.texture = ITEM_ICONS[item]
		square.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	else:
		square = ColorRect.new()
		square.color = ITEM_COLORS.get(item, Color(0.6, 0.6, 0.6))
	square.size = Vector2(40, 40)
	square.position = -square.size * 0.5
	var preview := Control.new()
	preview.add_child(square)
	return preview


## Shows an item and how many you have in this slot
func set_item(item: String, count: int) -> void:
	_item = item
	name_label.text = item
	count_label.text = "x%d" % count
	if ITEM_ICONS.has(item):
		icon.texture = ITEM_ICONS[item]
		icon.show()
		swatch.hide()
	else:
		swatch.color = ITEM_COLORS.get(item, Color(0.6, 0.6, 0.6))
		swatch.show()
		icon.hide()


## Shows one ingredient of a recipe as "have / need", in red if you're short
func set_cost(item: String, have: int, need: int) -> void:
	set_item(item, have)
	_item = ""
	count_label.text = "%d/%d" % [have, need]
	count_label.add_theme_color_override("font_color", COUNT_COLOR if have >= need else MISSING_COLOR)


## Makes this an empty slot
func clear() -> void:
	_item = ""
	name_label.text = ""
	count_label.text = ""
	icon.hide()
	# Keep the (invisible) square so empty slots stay the same size as full ones
	swatch.color = Color.TRANSPARENT
	swatch.show()


# Tools can always be dragged out of the backpack (onto the action bar); with a chest open, any
# stack can be dragged across to the other container
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _item.is_empty():
		return null
	var is_tool := container == "backpack" and ToolItem.exists_for(_item)
	if not is_tool and not trading:
		return null
	set_drag_preview(make_drag_preview(_item))
	var data := {"item": _item, "from": container, "from_bar": false}
	if is_tool:
		data["tool_item"] = _item
	return data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	# A tool from the action bar: back to the backpack, or across into an open chest
	if data.get("from_bar", false):
		return container == "backpack" or trading
	return trading and data.has("item") and data.get("from", "") != container


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data.get("from_bar", false):
		if container == "backpack":
			tool_returned.emit(data["tool_item"])
		else:
			item_moved.emit(data["tool_item"], "backpack")
		return
	item_moved.emit(data["item"], data["from"])


func _gui_input(event: InputEvent) -> void:
	if trading and not _item.is_empty() and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
		accept_event()
		quick_move.emit(_item, container)
