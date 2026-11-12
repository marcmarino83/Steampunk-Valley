extends Control
## THROWAWAY: UI proposal mockups with sample data (not game code; delete once the real panels are
## built). Builds each proposed screen in turn over the title painting, saves a screenshot of each
## into docs/reference/ours/ui/mockups/, then quits. Run in a window:
##
##     godot --path . res://tests/ui_mockups/ui_mockups.tscn --resolution 1920x1080 --quit-after 3000
##
## Sizes are in the game's 1152 x 648 menu layout, drawn 1.5x bigger like every menu (MenuStyle).

const SHOTS := "res://docs/reference/ours/ui/mockups"

# ---- The proposed style guide, as constants ----
## Text: one palette (BrassStyle's), headings in brass
const TEXT := BrassStyle.TEXT
const TEXT_DIM := BrassStyle.TEXT_DIM
const HEADING := Color(0.86, 0.7, 0.42)
## Status: good, warning (clear yellow), error, neutral, and info (building / in progress)
const GOOD := Color(0.62, 0.9, 0.5)
const WARN := Color(1.0, 0.92, 0.35)
const BAD := Color(1.0, 0.4, 0.33)
const NEUTRAL := Color(0.72, 0.64, 0.5)
const INFO := Color(0.6, 0.8, 1.0)
## Type sizes (layout px): header, section heading, body, small/meta, key hints
const SIZE_HEADER := 24
const SIZE_SECTION := 14
const SIZE_BODY := 15
const SIZE_SMALL := 13
const SIZE_HINT := 12
## Spacing (layout px): the 4-step scale
const GAP_XS := 4
const GAP_S := 8
const GAP_M := 12
const GAP_L := 18
## Buttons: standard and small heights
const BUTTON_H := 30
const BUTTON_SMALL_H := 24

var _stage: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/title_background.jpg")
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var screens := [
		["plot_woodcutter.png", _plot_woodcutter],
		["plot_forager.png", _plot_forager],
		["settler_panel.png", _settler],
		["visitor_panel.png", _visitor],
		["village_settlers.png", _village.bind(0)],
		["village_buildings.png", _village.bind(1)],
		["village_resources.png", _village.bind(2)],
		["village_tech_tree.png", _village.bind(3)],
	]
	for s in screens:
		_new_stage()
		(s[1] as Callable).call()
		await _save(s[0])
	get_tree().quit()


func _new_stage() -> void:
	if _stage:
		_stage.queue_free()
	_stage = CenterContainer.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)


func _save(file: String) -> void:
	for k in 6:
		await get_tree().process_frame
	for k in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("MOCKUP | saved %s" % file)


# ---- The standard panel: header, body, action row, key-hint row ----

# A panel `width` wide (layout px), enlarged like every menu. Returns {"panel", "header", "body",
# "actions", "hints"}
func _panel(width: float) -> Dictionary:
	var box := MenuStyle.panel()
	_stage.add_child(box)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.add_theme_constant_override("separation", GAP_M)
	box.add_child(column)
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", GAP_XS)
	column.add_child(header)
	column.add_child(_divider())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", GAP_L)
	column.add_child(body)
	column.add_child(_divider())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", GAP_S)
	actions.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(actions)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", GAP_M)
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(hints)
	MenuStyle.enlarge(box)
	return {"panel": box, "header": header, "body": body, "actions": actions, "hints": hints}


# The header line: a name (optionally an editable-looking field) and a status pill on the right,
# with a subtitle under it
func _header(into: Control, title: String, subtitle: String, status := "", status_color := GOOD, editable := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_S)
	into.add_child(row)
	if editable:
		var field := LineEdit.new()
		field.text = title
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_font_size_override("font_size", SIZE_HEADER - 4)
		field.add_theme_color_override("font_color", TEXT)
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, 0)
		flat.border_color = Color(BrassStyle.BRASS_DARK, 0.6)
		flat.border_width_bottom = 1
		flat.content_margin_left = 2
		field.add_theme_stylebox_override("normal", flat)
		field.tooltip_text = "Click to rename"
		row.add_child(field)
	else:
		var name_label := _label(title, SIZE_HEADER, TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
	if not status.is_empty():
		row.add_child(_pill(status, status_color))
	if not subtitle.is_empty():
		into.add_child(_label(subtitle, SIZE_SMALL, TEXT_DIM))


func _section(into: Control, title: String) -> VBoxContainer:
	var part := VBoxContainer.new()
	part.add_theme_constant_override("separation", GAP_XS)
	into.add_child(part)
	part.add_child(_label(title.to_upper(), SIZE_SECTION, HEADING))
	return part


# A two-column list of "Key   value" lines; values can carry a colour
func _facts(into: Control, lines: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", GAP_L)
	grid.add_theme_constant_override("v_separation", GAP_XS)
	into.add_child(grid)
	for line in lines:
		grid.add_child(_label(line[0], SIZE_BODY, TEXT_DIM))
		grid.add_child(_label(line[1], SIZE_BODY, line[2] if line.size() > 2 else TEXT))
	return grid


func _hint(into: Control, pairs: Array) -> void:
	for p in pairs:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", GAP_XS)
		var key := _label(p[0], SIZE_HINT, BrassStyle.BRASS_LIGHT)
		key.add_theme_stylebox_override("normal", BrassStyle.frame("badge"))
		pair.add_child(key)
		pair.add_child(_label(p[1], SIZE_HINT, TEXT_DIM))
		into.add_child(pair)


# ---- Pieces ----

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


# kind: "primary" (the main action), "secondary", "danger" (needs a confirm), "small" (inline)
func _button(text: String, kind := "secondary", disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = disabled
	BrassStyle.style_button(b)
	var small := kind == "small"
	b.custom_minimum_size = Vector2(0 if small else 96, BUTTON_SMALL_H if small else BUTTON_H)
	b.add_theme_font_size_override("font_size", SIZE_SMALL if small else SIZE_BODY)
	if kind == "primary":
		for state in ["normal", "hover"]:
			var lit: StyleBox = BrassStyle.frame("button_hover" if state == "hover" else "button").duplicate()
			if lit is BrassFrame:
				(lit as BrassFrame).fill = Color(0.42, 0.3, 0.15) if state == "normal" else Color(0.5, 0.36, 0.18)
			b.add_theme_stylebox_override(state, lit)
	if kind == "danger":
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, BAD)
	return b


func _pill(text: String, color: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.14)
	style.border_color = Color(color, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_child(_label("● " + text, SIZE_SMALL, color))
	return pill


func _divider() -> HSeparator:
	var line := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = Color(BrassStyle.BRASS_DARK, 0.55)
	style.thickness = 1
	line.add_theme_stylebox_override("separator", style)
	return line


func _check(into: Control, items: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", GAP_L * 2)
	grid.add_theme_constant_override("v_separation", GAP_XS)
	into.add_child(grid)
	for item in items:
		var ok: bool = item[1]
		grid.add_child(_label(("✓  " if ok else "✗  ") + item[0], SIZE_BODY, GOOD if ok else BAD))


func _slider_row(into: Control, item: String, percent: int, per_day: int, label_width := 92.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_S)
	into.add_child(row)
	var name_label := _label(item, SIZE_BODY, TEXT)
	name_label.custom_minimum_size.x = label_width
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.max_value = 100
	slider.value = percent
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 18
	BrassStyle.style_slider(slider)
	row.add_child(slider)
	var amount := _label("%d%%" % percent, SIZE_SMALL, TEXT_DIM)
	amount.custom_minimum_size.x = 36
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	var day := _label("%d/day" % per_day, SIZE_SMALL, TEXT)
	day.custom_minimum_size.x = 44
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(day)


# ---- Plot panels ----

func _plot_woodcutter() -> void:
	var p := _panel(420)
	_header(p["header"], "Woodcutter's Hut", "Woodcutter's Hut  ·  8 × 10 m  ·  min 6 × 6", "Working", GOOD, true)
	var worker := _section(p["body"], "Worker")
	var row := HBoxContainer.new()
	worker.add_child(row)
	var who := _label("Yusuf Oakes", SIZE_BODY, TEXT)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(who)
	row.add_child(_button("Unassign", "small"))
	var made := _section(p["body"], "Production  ·  each dawn")
	made.add_child(_label("12 wood  ·  8 sticks   → town storage", SIZE_BODY, TEXT))
	_check(_section(p["body"], "Requirements  3/3"), [["Chopping block", true], ["Tool rack", true], ["Storage chest", true]])
	_plot_actions(p)


func _plot_forager() -> void:
	var p := _panel(420)
	_header(p["header"], "Forager's Hut", "Forager's Hut  ·  11 × 15 m  ·  min 6 × 6", "Missing roof", WARN, true)
	var worker := _section(p["body"], "Worker")
	var row := HBoxContainer.new()
	worker.add_child(row)
	var who := _label("Lorne Ivers", SIZE_BODY, TEXT)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(who)
	row.add_child(_button("Unassign", "small"))
	var made := _section(p["body"], "Production  ·  35 items each dawn")
	for s in [["Berries", 30, 11], ["Herbs", 12, 4], ["Mushrooms", 12, 4], ["Plant Fiber", 6, 2], ["Stone", 24, 8], ["Copper Ore", 8, 3], ["Tin Ore", 8, 3]]:
		_slider_row(made, s[0], s[1], s[2])
	_check(_section(p["body"], "Requirements  2/3"), [["Foraging basket", true], ["Storage chest", true], ["Roofed", false]])
	_plot_actions(p)


func _plot_actions(p: Dictionary) -> void:
	var actions: HBoxContainer = p["actions"]
	var remove := _button("Remove", "danger")
	remove.tooltip_text = "Only the plot goes: its pieces stay standing (asks first)"
	actions.add_child(remove)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_button("Save as template"))
	var move := _button("Move", "primary")
	move.tooltip_text = "It and its own pieces follow the crosshair (wheel turns, R resets)"
	actions.add_child(move)
	_hint(p["hints"], [["M", "Move"], ["P", "Plot view: drag edges to resize"], ["E", "Close"]])


# ---- Settler and visitor panels ----

func _settler() -> void:
	var p := _panel(380)
	_header(p["header"], "Lorne Ivers", "Settler  ·  arrived day 3", "Working", GOOD)
	var tag := _pill("Permanent  ·  quest villager", INFO)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	(p["header"] as Control).add_child(tag)
	_facts(p["body"], [
		["Home", "Basic House  (2/2 beds)"],
		["Job", "Forager's Hut"],
		["Food", "Fed", GOOD],
		["Doing", "Walking to Forager's Hut"],
	])
	var actions: HBoxContainer = p["actions"]
	actions.add_child(_button("Assign home  ▾"))
	actions.add_child(_button("Assign job  ▾"))
	_hint(p["hints"], [["E", "Close"]])


func _visitor() -> void:
	var p := _panel(380)
	_header(p["header"], "Mira Fenwick", "Visitor at the Village Center  ·  leaves in about 1 day", "Visiting", INFO)
	var line := _label("\"Mended clocks in the city. Says the valley ticks slower, and likes it.\"", SIZE_BODY, TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 380
	(p["body"] as Control).add_child(line)
	_facts(p["body"], [["Free homes", "None: build a House or free a bed", WARN]])
	var actions: HBoxContainer = p["actions"]
	actions.add_child(_button("Not now"))
	var recruit := _button("Needs a free home", "primary", true)
	actions.add_child(recruit)
	_hint(p["hints"], [["E", "Close"]])


# ---- The Village screen ----

const TABS := ["Settlers", "Buildings", "Resources", "Tech tree"]


func _village(tab: int) -> void:
	var p := _panel(900)
	var header: VBoxContainer = p["header"]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", GAP_S)
	header.add_child(top)
	var title := _label("Village", SIZE_HEADER, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_pill("Settlers 5  ·  beds 6", GOOD))
	top.add_child(_pill("Food 4 days", WARN))
	top.add_child(_pill("Visitors 2/3", INFO))
	top.add_child(_pill("1 building needs attention", BAD))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", GAP_XS)
	header.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var t := _button(TABS[i])
		t.toggle_mode = true
		t.button_group = group
		t.button_pressed = i == tab
		t.custom_minimum_size.x = 120
		tabs.add_child(t)
	var body: VBoxContainer = p["body"]
	body.custom_minimum_size.y = 400
	match tab:
		0:
			_tab_settlers(body)
		1:
			_tab_buildings(body)
		2:
			_tab_resources(body)
		3:
			_tab_tech(body)
	(p["actions"] as Control).visible = false
	_hint(p["hints"], [["Q / E", "Change tab"], ["Click", "Open a row's panel"], ["V / Esc", "Close"]])


# A table: column titles and widths (0: takes the rest), rows of cells ([text, colour] or a Control)
func _table(into: Control, columns: Array, rows: Array, striped := true) -> VBoxContainer:
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 0)
	into.add_child(table)
	table.add_child(_table_row(columns.map(func(c): return [String(c[0]).to_upper(), HEADING, SIZE_SECTION]), columns, false, -1))
	for i in rows.size():
		table.add_child(_table_row(rows[i], columns, striped and i % 2 == 0, i))
	return table


func _table_row(cells: Array, columns: Array, shaded: bool, index: int) -> PanelContainer:
	var holder := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.18) if shaded else Color(0, 0, 0, 0)
	# The second row shows the hover look (rows open their panel when clicked)
	if index == 1:
		style.bg_color = Color(BrassStyle.BRASS, 0.12)
		style.border_color = Color(BrassStyle.BRASS, 0.5)
		style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.set_corner_radius_all(2)
	holder.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_M)
	holder.add_child(row)
	for c in cells.size():
		var width: float = columns[c][1]
		var cell = cells[c]
		var node: Control
		if cell is Control:
			node = cell
		else:
			node = _label(cell[0], cell[2] if cell.size() > 2 else SIZE_BODY, cell[1] if cell.size() > 1 else TEXT)
			(node as Label).clip_text = true
		if width > 0.0:
			node.custom_minimum_size.x = width
		else:
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(node)
	return holder


func _name_cell(text: String, permanent: bool) -> HBoxContainer:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", GAP_XS)
	cell.add_child(_label(text, SIZE_BODY, TEXT))
	if permanent:
		cell.add_child(_pill("Permanent", INFO))
	return cell


func _tab_settlers(body: Control) -> void:
	var cols := [["Name", 210.0], ["Home", 140.0], ["Job", 150.0], ["Food", 110.0], ["Doing", 0.0]]
	_table(_section(body, "Settlers  5"), cols, [
		[_name_cell("Lorne Ivers", true), ["Basic House"], ["Forager's Hut"], ["Fed", GOOD], ["Working at Forager's Hut"]],
		[_name_cell("Greta Hale", true), ["Basic House"], ["Woodcutter's Hut"], ["Hungry 1 day", WARN], ["We can't work hungry", BAD]],
		[_name_cell("Yusuf Oakes", false), ["Riverside House"], ["Woodcutter's Hut"], ["Fed", GOOD], ["Walking to Woodcutter's Hut"]],
		[_name_cell("Tamsin Rook", false), ["Riverside House"], ["—", TEXT_DIM], ["Fed", GOOD], ["Idle: no job", TEXT_DIM]],
		[_name_cell("Odo Marsh", false), ["—", TEXT_DIM], ["—", TEXT_DIM], ["Fed", GOOD], ["Idle: no home or job", WARN]],
	])
	var visitors := _section(body, "Visitors at the Village Center  2/3  ·  free homes: 1")
	var vcols := [["Name", 210.0], ["Background", 0.0], ["Leaves", 90.0], ["", 150.0]]
	var recruit := _button("Recruit", "primary")
	recruit.custom_minimum_size = Vector2(140, BUTTON_SMALL_H)
	var recruit2 := _button("Recruit", "primary")
	recruit2.custom_minimum_size = Vector2(140, BUTTON_SMALL_H)
	_table(visitors, vcols, [
		[["Mira Fenwick"], ["Mended clocks in the city…", TEXT_DIM], ["~1 day", TEXT_DIM], recruit],
		[["Silas Thorne"], ["A shepherd whose flock was sold off…", TEXT_DIM], ["~2 days", TEXT_DIM], recruit2],
	])


func _tab_buildings(body: Control) -> void:
	var cols := [["Plot", 190.0], ["Type", 150.0], ["People", 150.0], ["Status", 160.0], ["Missing", 0.0]]
	_table(_section(body, "Plots  6"), cols, [
		[["Basic House"], ["House", TEXT_DIM], ["2/2 residents"], _pill("Working", GOOD), ["—", TEXT_DIM]],
		[["Riverside House"], ["House", TEXT_DIM], ["2/3 residents"], _pill("Working", GOOD), ["—", TEXT_DIM]],
		[["Forager's Hut"], ["Forager's Hut", TEXT_DIM], ["Lorne Ivers"], _pill("Missing", WARN), ["roof", WARN]],
		[["Woodcutter's Hut"], ["Woodcutter's Hut", TEXT_DIM], ["Greta Hale"], _pill("Not working", BAD), ["worker hungry", BAD]],
		[["Storehouse"], ["Storehouse", TEXT_DIM], ["42/60 slots"], _pill("Working", GOOD), ["—", TEXT_DIM]],
		[["Village Center"], ["Village Center", TEXT_DIM], ["2/3 visitors"], _pill("Working", GOOD), ["—", TEXT_DIM]],
	])
	var note := _label("Click a row to open its plot panel. Player homes show as \"Your home\".", SIZE_SMALL, TEXT_DIM)
	body.add_child(note)


func _tab_resources(body: Control) -> void:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", GAP_L)
	body.add_child(split)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", GAP_M)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	var cols := [["Resource", 150.0], ["Made/day", 80.0], ["Used/day", 80.0], ["Net/day", 80.0], ["Stock", 0.0]]
	var net := func(n: int) -> Array:
		return [("+%d" % n) if n > 0 else ("%d" % n if n < 0 else "0"), GOOD if n > 0 else (BAD if n < 0 else NEUTRAL)]
	_table(_section(left, "Food"), cols, [
		[["Berries"], ["11"], ["8"], net.call(3), ["26"]],
		[["Mushrooms"], ["4"], ["2"], net.call(2), ["9"]],
		[["Herbs"], ["4"], ["0"], net.call(4), ["17"]],
	])
	_table(_section(left, "Building materials"), cols, [
		[["Wood"], ["12"], ["0"], net.call(12), ["140"]],
		[["Sticks"], ["8"], ["0"], net.call(8), ["66"]],
		[["Stone"], ["8"], ["0"], net.call(8), ["51"]],
		[["Plant Fiber"], ["2"], ["0"], net.call(2), ["12"]],
	])
	_table(_section(left, "Ores"), cols, [
		[["Copper Ore"], ["3"], ["0"], net.call(3), ["14"]],
		[["Tin Ore"], ["3"], ["0"], net.call(3), ["11"]],
	])
	# The Forager's shares, the same sliders as in its plot panel (one setting, shown in both)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", BrassStyle.frame("slot"))
	right.custom_minimum_size.x = 330
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	split.add_child(right)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", GAP_XS)
	right.add_child(box)
	box.add_child(_label("FORAGER'S HUT  ·  SHARES", SIZE_SECTION, HEADING))
	box.add_child(_label("35 items each dawn. Same setting as in its plot panel.", SIZE_SMALL, TEXT_DIM))
	for s in [["Berries", 30, 11], ["Herbs", 12, 4], ["Mushrooms", 12, 4], ["Plant Fiber", 6, 2], ["Stone", 24, 8], ["Copper Ore", 8, 3], ["Tin Ore", 8, 3]]:
		_slider_row(box, s[0], s[1], s[2], 84.0)
	box.add_child(_label("Food: 5 settlers eat 10 a day  ·  stores last 4 days", SIZE_SMALL, WARN))


func _tab_tech(body: Control) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", GAP_M)
	body.add_child(top)
	top.add_child(_label("Schematic fragments", SIZE_BODY, TEXT_DIM))
	top.add_child(_label("3", SIZE_HEADER, BrassStyle.BRASS_LIGHT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(_label("Layout only: the tree's contents come later", SIZE_SMALL, TEXT_DIM))
	var eras := HBoxContainer.new()
	eras.add_theme_constant_override("separation", GAP_M)
	body.add_child(eras)
	var tree := [
		["1  Scrap and Survival", [["Stone tools", "Learned", 0], ["Campfire", "Learned", 0], ["Storehouse", "Learned", 0], ["Village Center", "Learned", 0]]],
		["2  The Forge", [["Smelter", "2 fragments", 1], ["Forge", "3 fragments  ·  needs Smelter", 2], ["Workshop", "3 fragments", 1], ["Bronze tools", "2 fragments  ·  needs Forge", 2]]],
		["3  Steam Power", [["Sawmill", "5 fragments", 2], ["Water wheel", "4 fragments", 2], ["Steam pump", "6 fragments  ·  needs a working Forge", 2], ["Granary", "4 fragments", 2]]],
		["4  The Sky", [["Airship dock", "10 fragments", 2], ["Aether extractor", "8 fragments", 2], ["Clockwork guardian", "12 fragments", 2]]],
	]
	for era in tree:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", GAP_S)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eras.add_child(col)
		col.add_child(_label(String(era[0]).to_upper(), SIZE_SECTION, HEADING))
		for node in era[1]:
			col.add_child(_tech_node(node[0], node[1], node[2]))
			var link := _label("│", SIZE_SMALL, Color(BrassStyle.BRASS_DARK, 0.8))
			link.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(link)
		col.get_child(col.get_child_count() - 1).queue_free()


# state: 0 learned, 1 affordable (can buy now), 2 locked
func _tech_node(title: String, cost: String, state: int) -> PanelContainer:
	var node := PanelContainer.new()
	var style: StyleBox = BrassStyle.frame("slot_selected" if state == 1 else "slot")
	node.add_theme_stylebox_override("panel", style)
	node.modulate = Color(1, 1, 1, 0.55) if state == 2 else Color.WHITE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	node.add_child(box)
	var mark: String = ["✓ ", "", "Locked  ·  "][state]
	box.add_child(_label(title, SIZE_BODY, GOOD if state == 0 else TEXT))
	box.add_child(_label(mark + cost, SIZE_SMALL, GOOD if state == 0 else (BrassStyle.BRASS_LIGHT if state == 1 else TEXT_DIM)))
	return node
