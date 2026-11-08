extends PanelContainer
## One slot in the build menu: a buildable with its name and cost, or an empty space.

signal chosen(buildable: Buildable)
signal hover_changed(buildable: Buildable, hovering: bool)

const HOVER_BORDER := Color(0.88, 0.66, 0.28)
## How dark a slot goes when you can't afford what's in it
const UNAFFORDABLE_TINT := Color(0.55, 0.55, 0.55)
## A locked blueprint: its name, its picture as a dark silhouette, and how to unlock it, in a
## slot dimmed a little
const LOCKED_TINT := Color(0.78, 0.76, 0.74)
const SILHOUETTE := Color(0.07, 0.06, 0.05, 0.9)

@onready var swatch: ColorRect = $VBox/Swatch
@onready var icon: TextureRect = $VBox/Icon
@onready var name_label: Label = $VBox/NameLabel
@onready var cost_label: Label = $VBox/CostLabel

var _buildable: Buildable
var _affordable := false
var _style: StyleBoxFlat
var _normal_border: Color


func _ready() -> void:
	_style = get_theme_stylebox("panel").duplicate()
	_normal_border = _style.border_color
	add_theme_stylebox_override("panel", _style)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func show_buildable(buildable: Buildable, affordable: bool, locked: bool) -> void:
	_buildable = buildable
	_affordable = affordable and not locked
	name_label.text = buildable.display_name
	icon.modulate = Color.WHITE
	if locked:
		cost_label.text = buildable.unlock_hint_text()
		modulate = LOCKED_TINT
		if buildable.icon:
			# The picture's own shape, filled dark: you can tell what it is, but not yet see it
			icon.texture = buildable.icon
			icon.modulate = SILHOUETTE
			icon.show()
			swatch.hide()
		else:
			swatch.color = buildable.icon_color.darkened(0.85)
			swatch.show()
			icon.hide()
		return
	cost_label.text = buildable.cost_text()
	modulate = Color.WHITE if affordable else UNAFFORDABLE_TINT
	if buildable.icon:
		icon.texture = buildable.icon
		icon.show()
		swatch.hide()
	else:
		var gray := buildable.icon_color.get_luminance()
		swatch.color = buildable.icon_color if affordable else Color(gray, gray, gray)
		swatch.show()
		icon.hide()


func clear() -> void:
	_buildable = null
	name_label.text = ""
	cost_label.text = ""
	modulate = Color.WHITE
	icon.hide()
	# Keep the (invisible) square so empty slots stay the same size as full ones
	swatch.color = Color.TRANSPARENT
	swatch.show()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _buildable and _affordable:
			chosen.emit(_buildable)


func _set_hover(hovering: bool) -> void:
	_style.border_color = HOVER_BORDER if hovering and _buildable else _normal_border
	if _buildable:
		hover_changed.emit(_buildable, hovering)
