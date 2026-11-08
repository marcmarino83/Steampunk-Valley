extends PanelContainer
## One slot in the build menu: a buildable with its name and cost, or an empty space.

signal chosen(buildable: Buildable)
signal hover_changed(buildable: Buildable, hovering: bool)

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
var _style: StyleBox


func _ready() -> void:
	# The shared brass slot (see BrassStyle), lit under the mouse
	_style = BrassStyle.frame("slot")
	add_theme_stylebox_override("panel", _style)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func show_buildable(buildable: Buildable, affordable: bool, locked: bool) -> void:
	_buildable = buildable
	_affordable = affordable and not locked
	name_label.text = buildable.display_name
	icon.modulate = Color.WHITE
	name_label.modulate = Color.WHITE
	cost_label.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
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
	if buildable is PlotType:
		# A plot: its size range, then what it needs
		var needs := (buildable as PlotType).requirements_text()
		cost_label.text += "\n" + needs.left(1).to_upper() + needs.substr(1)
		cost_label.max_lines_visible = 5
		cost_label.add_theme_font_size_override("font_size", 12)
	# Can't afford it: the picture and name dim, and the cost shows in red
	modulate = Color.WHITE
	icon.modulate = Color.WHITE if affordable else UNAFFORDABLE_TINT
	name_label.modulate = Color.WHITE if affordable else UNAFFORDABLE_TINT
	cost_label.add_theme_color_override("font_color", BrassStyle.TEXT if affordable else BrassStyle.BAD)
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
	BrassStyle.set_lit(_style, hovering and _buildable != null)
	if _buildable:
		hover_changed.emit(_buildable, hovering)
