extends PanelContainer
## One slot in the build menu: a buildable with its name and cost, or an empty space.

signal chosen(buildable: Buildable)
signal hover_changed(buildable: Buildable, hovering: bool)
## A template was right-clicked, or its ✕ clicked: show what can be done with it (Rename, Delete)
signal options_requested(buildable: Buildable)

## How dark a slot goes when you can't afford what's in it
const UNAFFORDABLE_TINT := Color(0.55, 0.55, 0.55)
## A locked blueprint: its name, its picture as a dark silhouette, and how to unlock it, in a
## slot dimmed a little
const LOCKED_TINT := Color(0.78, 0.76, 0.74)
const SILHOUETTE := Color(0.07, 0.06, 0.05, 0.9)
## How big the pictures are drawn (the icons are 256 px, smoothed down with mipmaps)
const ICON_SIZE := 80
const TEMPLATE_ICON_SIZE := 92

# Each icon with mipmaps, made the first time it's shown: texture -> ImageTexture
static var _smoothed := {}

@onready var swatch: ColorRect = $VBox/Swatch
@onready var icon: TextureRect = $VBox/Icon
@onready var name_label: Label = $VBox/NameLabel
@onready var cost_label: Label = $VBox/CostLabel

## Shown instead of the buildable's name, if set ("Empty plot" in the Buildings tab)
var title_override := ""

var _buildable: Buildable
var _affordable := false
var _style: StyleBox
var _badge: Label
var _options: Button


func _ready() -> void:
	name_label.add_theme_color_override("font_color", BrassStyle.HEADING)
	# The shared brass slot (see BrassStyle), lit under the mouse
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# The soft dark vignette behind the picture (the tints below only touch the picture itself)
	var glow := TextureRect.new()
	glow.texture = IconStudio.vignette()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -8
	glow.offset_top = -8
	glow.offset_right = 8
	glow.offset_bottom = 8
	glow.show_behind_parent = true
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(glow)
	# The size or angle badge in the picture's corner ("2 m", "26°"), where it tells pieces apart
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 11)
	_badge.add_theme_color_override("font_color", BrassStyle.TEXT)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.12, 0.08, 0.05, 0.9)
	plate.border_color = BrassStyle.BRASS.darkened(0.15)
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(3)
	plate.content_margin_left = 3
	plate.content_margin_right = 3
	plate.content_margin_top = 0
	plate.content_margin_bottom = 1
	_badge.add_theme_stylebox_override("normal", plate)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.visible = false
	icon.add_child(_badge)
	# A template's ✕, on its picture's corner while the mouse is over the slot: Rename or Delete
	_options = Button.new()
	_options.text = "✕"
	_options.tooltip_text = "Rename or delete"
	_options.focus_mode = Control.FOCUS_NONE
	_options.add_theme_font_size_override("font_size", 13)
	BrassStyle.style_button(_options)
	_options.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_options.custom_minimum_size = Vector2(22, 22)
	_options.offset_left = -18
	_options.offset_right = 4
	_options.offset_top = -4
	_options.offset_bottom = 18
	_options.visible = false
	_options.pressed.connect(func(): options_requested.emit(_buildable))
	icon.add_child(_options)
	_style = BrassStyle.frame("slot")
	add_theme_stylebox_override("panel", _style)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func show_buildable(buildable: Buildable, affordable: bool, locked: bool) -> void:
	_buildable = buildable
	_affordable = affordable and not locked
	name_label.text = title_override if not title_override.is_empty() else buildable.display_name
	# A template's picture is drawn bigger
	icon.custom_minimum_size = Vector2(TEMPLATE_ICON_SIZE, TEMPLATE_ICON_SIZE) if buildable is TemplateBuildable else Vector2(ICON_SIZE, ICON_SIZE)
	icon.self_modulate = Color.WHITE
	_badge.text = IconStudio.badge_for(buildable)
	_badge.visible = not _badge.text.is_empty()
	name_label.modulate = Color.WHITE
	cost_label.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	if locked:
		cost_label.text = buildable.unlock_hint_text()
		modulate = LOCKED_TINT
		if buildable.icon:
			# The picture's own shape, filled dark: you can tell what it is, but not yet see it
			icon.texture = smoothed(buildable.icon)
			icon.self_modulate = SILHOUETTE
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
	elif buildable is TemplateBuildable:
		# Built-in or yours, how many pieces, and what it all costs to build
		cost_label.max_lines_visible = 5
		cost_label.add_theme_font_size_override("font_size", 12)
	# Can't afford it: the picture and name dim, and the cost shows in red
	modulate = Color.WHITE
	icon.self_modulate = Color.WHITE if affordable else UNAFFORDABLE_TINT
	name_label.modulate = Color.WHITE if affordable else UNAFFORDABLE_TINT
	cost_label.add_theme_color_override("font_color", BrassStyle.TEXT if affordable else BrassStyle.BAD)
	if buildable.icon:
		icon.texture = smoothed(buildable.icon)
		icon.show()
		swatch.hide()
	else:
		var gray := buildable.icon_color.get_luminance()
		swatch.color = buildable.icon_color if affordable else Color(gray, gray, gray)
		swatch.show()
		icon.hide()


## A copy of a picture with mipmaps, so a 256 px icon shrinks to the slot cleanly instead of
## shimmering (the texture itself if it can't be read back)
static func smoothed(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	if _smoothed.has(texture):
		return _smoothed[texture]
	var image := texture.get_image()
	if image == null or image.is_compressed():
		return texture
	image = image.duplicate()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	var copy := ImageTexture.create_from_image(image)
	_smoothed[texture] = copy
	return copy


func clear() -> void:
	_buildable = null
	name_label.text = ""
	cost_label.text = ""
	modulate = Color.WHITE
	_badge.hide()
	_options.hide()
	icon.hide()
	# Keep the (invisible) square so empty slots stay the same size as full ones
	swatch.color = Color.TRANSPARENT
	swatch.show()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _buildable and _affordable:
			chosen.emit(_buildable)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _buildable is TemplateBuildable:
			options_requested.emit(_buildable)
			accept_event()


func _set_hover(hovering: bool) -> void:
	# Moving onto the ✕ isn't leaving the slot
	if not hovering and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		return
	BrassStyle.set_lit(_style, hovering and _buildable != null)
	_options.visible = hovering and _buildable is TemplateBuildable and icon.visible \
		and (_buildable as TemplateBuildable).template.can_change()
	if _buildable:
		hover_changed.emit(_buildable, hovering)
