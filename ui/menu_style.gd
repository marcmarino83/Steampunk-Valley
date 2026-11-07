class_name MenuStyle
## The brass-and-leather look shared by the title screen and the pause menu: a panel and its
## buttons, matching the inventory and crafting screens.

const TEXT := Color(0.94, 0.8, 0.55)
const TEXT_DIM := Color(0.7, 0.62, 0.5)


static func panel() -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.96)
	style.border_color = Color(0.54, 0.29, 0.16)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
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
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Color(1.0, 0.93, 0.78))
	b.add_theme_stylebox_override("normal", _button_style(Color(0.36, 0.24, 0.12)))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.54, 0.36, 0.14)))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.66, 0.45, 0.18)))
	return b


static func _button_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(0.98, 0.78, 0.32)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style


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
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)
	return column
