class_name MenuStyle
## The brass-and-leather look shared by the title screen and the pause menu: a panel and its
## buttons, matching the inventory and crafting screens. Its colours are BrassStyle's palette;
## new panels are built on BrassPanel.

## The screen is laid out at 1920 × 1080 and scales with the window (Project Settings, Display >
## Window > Stretch). The menus were drawn for a 1152 × 648 layout, so their panels are shown this
## much bigger to stay readable; the action bar keeps exactly its old size (OLD_LAYOUT_SCALE).
const MENU_SCALE := 1.5
const OLD_LAYOUT_SCALE := 1920.0 / 1152.0
## An enlarged menu never comes closer than this to the screen's edges (it's shrunk to fit instead)
const FIT_MARGIN := 12.0


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
	label.add_theme_color_override("font_color", BrassStyle.HEADING)
	return label


static func note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
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
		if not is_instance_valid(content):
			return
		var natural := content.get_combined_minimum_size()
		content.size = natural
		# Never bigger than the screen (a tall panel at a large UI scale): shrunk to fit, with a margin
		var room: Vector2 = content.get_viewport_rect().size - Vector2.ONE * FIT_MARGIN * 2.0 if content.is_inside_tree() else Vector2.INF
		var shown := minf(factor, minf(room.x / maxf(natural.x, 1.0), room.y / maxf(natural.y, 1.0)))
		content.scale = Vector2.ONE * shown
		holder.custom_minimum_size = natural * shown
		holder.size = natural * shown
		# Have the CenterContainer above place it again, so it stays centred as it grows
		if parent is Container:
			parent.queue_sort()
	content.minimum_size_changed.connect(fit)
	content.resized.connect(fit)
	# (fitted again when the window or the UI scale changes)
	holder.tree_entered.connect(func():
		var viewport := holder.get_viewport()
		if viewport and not viewport.size_changed.is_connected(fit):
			viewport.size_changed.connect(fit)
		fit.call())
	if holder.is_inside_tree():
		holder.get_viewport().size_changed.connect(fit)
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
