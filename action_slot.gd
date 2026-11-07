extends PanelContainer
## One slot on the action bar. Tools can be dragged into it, out of it, and between slots.

## A tool was dragged onto this slot
signal tool_dropped(item: String)

const SELECTED_BORDER := Color(0.98, 0.78, 0.32)
const SELECTED_BACKGROUND := Color(0.36, 0.26, 0.15)
const SELECTED_BORDER_WIDTH := 3

@onready var swatch: ColorRect = $Swatch
@onready var icon: TextureRect = $Icon
@onready var number_label: Label = $Number

var _item := ""
var _style: StyleBoxFlat
var _normal_style: StyleBoxFlat


func _ready() -> void:
	_normal_style = get_theme_stylebox("panel")
	_style = _normal_style.duplicate()
	_style.border_color = SELECTED_BORDER
	_style.bg_color = SELECTED_BACKGROUND
	_style.set_border_width_all(SELECTED_BORDER_WIDTH)


func set_number(number: int) -> void:
	number_label.text = str(number)


func show_item(item: String, selected: bool) -> void:
	_item = item
	add_theme_stylebox_override("panel", _style if selected else _normal_style)
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
	set_drag_preview(InventorySlot.make_drag_preview(_item))
	return {"tool_item": _item, "from_bar": true}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("tool_item")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	tool_dropped.emit(data["tool_item"])
