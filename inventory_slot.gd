extends PanelContainer

## Placeholder colors for items that don't have an icon image yet.
## Anything not listed here shows up gray.
const ITEM_COLORS := {
	"Scrap": Color(0.55, 0.5, 0.45),
	"Coal": Color(0.12, 0.12, 0.12),
	"Wood": Color(0.45, 0.3, 0.18),
	"Berries": Color(0.72, 0.12, 0.18),
}

## Real icon images. When you have one, add a line like:
##     "Coal": preload("res://icons/coal.png"),
## and that item will show the picture instead of its colored square.
const ITEM_ICONS := {
}

@onready var swatch: ColorRect = $VBox/Swatch
@onready var icon: TextureRect = $VBox/Icon
@onready var name_label: Label = $VBox/NameLabel
@onready var count_label: Label = $VBox/CountLabel


## Shows an item and how many you have in this slot
func set_item(item: String, count: int) -> void:
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


## Makes this an empty slot
func clear() -> void:
	name_label.text = ""
	count_label.text = ""
	icon.hide()
	# Keep the (invisible) square so empty slots stay the same size as full ones
	swatch.color = Color.TRANSPARENT
	swatch.show()
