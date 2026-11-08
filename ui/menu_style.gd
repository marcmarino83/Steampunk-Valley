class_name MenuStyle
## The brass-and-leather look shared by the title screen and the pause menu: a panel and its
## buttons, matching the inventory and crafting screens.

const TEXT := Color(0.94, 0.8, 0.55)
const TEXT_DIM := Color(0.7, 0.62, 0.5)
## The screen is laid out at 1920 × 1080 and scales with the window (Project Settings, Display >
## Window > Stretch). The menus were drawn for a 1152 × 648 layout, so their panels are shown this
## much bigger to stay readable; the action bar keeps exactly its old size (OLD_LAYOUT_SCALE).
const MENU_SCALE := 1.5
const OLD_LAYOUT_SCALE := 1920.0 / 1152.0


## A menu panel in the shared brass look (see BrassStyle)
static func panel() -> PanelContainer:
	var box := PanelContainer.new()
	var style := BrassStyle.frame("panel")
	box.add_theme_stylebox_override("panel", style)
	return box


static func title(text: String, size := 30) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT)
	return label


static func note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", TEXT_DIM)
	return label


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 42)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	BrassStyle.style_button(b)
	return b




## Draws a menu panel `factor` times bigger (clicks and drags still land where they look).
## Containers undo their children's scale, so the panel moves into a plain holder that takes the
## panel's place and is as big as the panel looks: a CenterContainer above still centres it.
static func enlarge(content: Control, factor := MENU_SCALE) -> void:
	var parent := content.get_parent()
	var holder := Control.new()
	holder.name = content.name + "Holder"
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(holder)
	parent.move_child(holder, content.get_index())
	content.reparent(holder, false)
	content.position = Vector2.ZERO
	content.scale = Vector2.ONE * factor
	var fit := func():
		var natural := content.get_combined_minimum_size()
		content.size = natural
		holder.custom_minimum_size = natural * factor
		holder.size = natural * factor
		# Have the CenterContainer above place it again, so it stays centred as it grows
		if parent is Container:
			parent.queue_sort()
	content.minimum_size_changed.connect(fit)
	content.resized.connect(fit)
	fit.call()


## A full-screen dark backdrop with a centred column in a panel, to put titles and buttons in
static func screen(parent: Control, dim := 0.55) -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var box := panel()
	center.add_child(box)
	enlarge(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)
	return column
