class_name BrassPanel
extends PanelContainer
## The standard panel every menu panel is built on (DESIGN.md, Interface style), in the brass
## plaque frame and the palette (BrassStyle):
##
##   header:  the subject's name (or an editable name), a status pill on the right, a subtitle
##            under it, and any badges
##   ─────
##   body:    sections, each with a small uppercase brass heading (WORKER, REQUIREMENTS 2/3)
##   ─────
##   actions: the buttons, the primary one far right, a danger one far left
##   hints:   the key-hint row ("M Move · P Plot view · E Close"); never paragraphs
##
## Make one with BrassPanel.create(parent, width), then fill it. It's drawn MenuStyle.MENU_SCALE
## bigger, like every menu.

var header: VBoxContainer
var title_row: HBoxContainer
## The name: a label, or with an editable name, a line edit (see create)
var title: Label
var name_edit: LineEdit
var status: PanelContainer
var subtitle: Label
var badges: HBoxContainer
var body: VBoxContainer
var actions: HBoxContainer
## Danger buttons go here, far left; the rest after the gap, the primary one last
var actions_left: HBoxContainer
var actions_right: HBoxContainer
var hints: HBoxContainer
## How wide a facts list's keys are (layout pixels)
const FACT_KEY_WIDTH := 92.0
## The width of its contents (layout pixels)
var width := 0.0
var _bottom_line: HSeparator
var _shown_hints := []


## A panel `width` wide (layout pixels), added to `parent` (a CenterContainer, usually) and
## enlarged like every menu; with `editable_name`, its name is a line edit
static func create(parent: Control, content_width: float, editable_name := false) -> BrassPanel:
	var p := BrassPanel.new()
	p.width = content_width
	p.add_theme_stylebox_override("panel", BrassStyle.frame("panel"))
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = content_width
	column.add_theme_constant_override("separation", BrassStyle.GAP_M)
	p.add_child(column)

	p.header = VBoxContainer.new()
	p.header.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	column.add_child(p.header)
	p.title_row = HBoxContainer.new()
	p.title_row.add_theme_constant_override("separation", BrassStyle.GAP_S)
	p.header.add_child(p.title_row)
	if editable_name:
		p.name_edit = LineEdit.new()
		p.name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.name_edit.add_theme_font_size_override("font_size", BrassStyle.SIZE_HEADER - 4)
		p.name_edit.add_theme_font_override("font", BrassStyle.title_font())
		p.name_edit.add_theme_color_override("font_color", BrassStyle.TEXT)
		p.name_edit.add_theme_color_override("caret_color", BrassStyle.TEXT)
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, 0)
		flat.border_color = Color(BrassStyle.BRASS_DARK, 0.6)
		flat.border_width_bottom = 1
		flat.content_margin_left = 2
		var lit := flat.duplicate() as StyleBoxFlat
		lit.border_color = BrassStyle.BRASS_LIGHT
		lit.bg_color = Color(0, 0, 0, 0.25)
		p.name_edit.add_theme_stylebox_override("normal", flat)
		p.name_edit.add_theme_stylebox_override("focus", lit)
		p.name_edit.tooltip_text = "Click to rename"
		p.title_row.add_child(p.name_edit)
	else:
		p.title = BrassStyle.title("", BrassStyle.SIZE_HEADER, BrassStyle.TEXT)
		p.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.title_row.add_child(p.title)
	p.status = BrassStyle.pill("", BrassStyle.GOOD)
	p.title_row.add_child(p.status)
	p.subtitle = BrassStyle.label("", BrassStyle.SIZE_SMALL, BrassStyle.TEXT_DIM)
	p.subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.header.add_child(p.subtitle)
	p.badges = HBoxContainer.new()
	p.badges.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	p.badges.visible = false
	p.header.add_child(p.badges)
	column.add_child(BrassStyle.divider())

	p.body = VBoxContainer.new()
	p.body.add_theme_constant_override("separation", BrassStyle.GAP_L)
	column.add_child(p.body)
	p._bottom_line = BrassStyle.divider()
	column.add_child(p._bottom_line)

	p.actions = HBoxContainer.new()
	p.actions.add_theme_constant_override("separation", BrassStyle.GAP_S)
	column.add_child(p.actions)
	p.actions_left = HBoxContainer.new()
	p.actions_left.add_theme_constant_override("separation", BrassStyle.GAP_S)
	p.actions.add_child(p.actions_left)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.actions.add_child(gap)
	p.actions_right = HBoxContainer.new()
	p.actions_right.add_theme_constant_override("separation", BrassStyle.GAP_S)
	p.actions.add_child(p.actions_right)
	p.hints = BrassStyle.hint_row()
	column.add_child(p.hints)

	parent.add_child(p)
	MenuStyle.enlarge(p)
	return p


func set_title(text: String) -> void:
	if name_edit:
		name_edit.text = text
	else:
		title.text = text


## The status pill (empty hides it), in a palette status colour
func set_status(text: String, color := BrassStyle.GOOD) -> void:
	BrassStyle.set_pill(status, text, color)


func set_subtitle(text: String) -> void:
	subtitle.text = text
	subtitle.visible = not text.is_empty()


## The header's badges: [[text, colour], ...] (empty clears them)
func set_badges(list: Array) -> void:
	for child in badges.get_children():
		badges.remove_child(child)
		child.queue_free()
	for b in list:
		badges.add_child(BrassStyle.pill(b[0], b[1]))
	badges.visible = not list.is_empty()


## A new section at the end of the body (or `into` another box): its heading (uppercase, brass)
## and the box its contents go in. Its heading label is the box's first child (see set_heading).
func section(heading: String, into: Control = null) -> VBoxContainer:
	var part := VBoxContainer.new()
	part.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	(into if into else body).add_child(part)
	part.add_child(BrassStyle.heading(heading))
	return part


## Changes a section's heading
static func set_heading(part: VBoxContainer, heading: String) -> void:
	(part.get_child(0) as Label).text = heading.to_upper()


## Adds a button to the action row: "danger" ones go far left, the rest to the right (add the
## primary one last, so it sits far right)
func add_action(b: Button, danger := false) -> Button:
	(actions_left if danger else actions_right).add_child(b)
	return b


func set_hints(pairs: Array) -> void:
	# (only rebuilt when they change: panels set them on every refresh)
	if pairs == _shown_hints:
		return
	_shown_hints = pairs.duplicate(true)
	BrassStyle.set_hints(hints, pairs)


## A grid of "Key   value" lines (two columns) in a section; returns the grid, whose values are
## filled with set_facts
static func facts(into: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", BrassStyle.GAP_L)
	grid.add_theme_constant_override("v_separation", BrassStyle.GAP_XS)
	into.add_child(grid)
	return grid


## Fills a facts grid: [[key, value], or [key, value, colour]], reusing its labels (values wrap
## within the panel)
func set_facts(grid: GridContainer, rows: Array) -> void:
	while grid.get_child_count() < rows.size() * 2:
		var key := BrassStyle.label("", BrassStyle.SIZE_BODY, BrassStyle.TEXT_DIM)
		key.custom_minimum_size.x = FACT_KEY_WIDTH
		grid.add_child(key)
		var value := BrassStyle.label("", BrassStyle.SIZE_BODY, BrassStyle.TEXT)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size.x = width - FACT_KEY_WIDTH - BrassStyle.GAP_L
		grid.add_child(value)
	for i in grid.get_child_count():
		(grid.get_child(i) as Control).visible = i < rows.size() * 2
	for r in rows.size():
		var row: Array = rows[r]
		(grid.get_child(r * 2) as Label).text = row[0]
		var value := grid.get_child(r * 2 + 1) as Label
		value.text = row[1]
		value.add_theme_color_override("font_color", row[2] if row.size() > 2 else BrassStyle.TEXT)


## A checklist ("✓ Chopping block", "✗ Roofed (...)") in a section, in two columns (or `columns`),
## reusing its labels
func set_checklist(grid: GridContainer, lines: Array, columns := 2) -> void:
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", BrassStyle.GAP_L)
	while grid.get_child_count() < lines.size():
		var l := BrassStyle.label("", BrassStyle.SIZE_BODY, BrassStyle.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(l)
	for child in grid.get_children():
		(child as Control).custom_minimum_size.x = (width - BrassStyle.GAP_L * (columns - 1)) / columns
	for i in grid.get_child_count():
		var l := grid.get_child(i) as Label
		l.visible = i < lines.size()
		if not l.visible:
			continue
		var line: Dictionary = lines[i]
		l.text = ("✓  " if line["ok"] else "✗  ") + str(line["text"])
		l.add_theme_color_override("font_color", BrassStyle.GOOD if line["ok"] else BrassStyle.BAD)
