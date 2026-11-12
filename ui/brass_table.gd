class_name BrassTable
extends VBoxContainer
## A table in the interface style (DESIGN.md, Interface style), for panels built on BrassPanel:
## a header row of column titles (small uppercase brass; click one to sort by it, again to reverse,
## a third time for the table's own order), striped rows that light up under the mouse, and a
## scrolling list once it's taller than `max_height`. Clicking a row sends `row_clicked` with the
## row's data.
##
## Rows are given as plain descriptions and the table makes the controls itself, rebuilding only
## when something it shows changed (so hovering and tooltips aren't interrupted by panels that
## refresh). Each row: {"cells": [...], "data": anything, "sort": [a value per column] (optional:
## else each cell's text)}. Each cell is one of:
##   "text"                                   plain text
##   {"text", "color"?, "tooltip"?}           text in a palette colour
##   {"text", "pill", "color"}                text, then a status pill in that colour
##   {"pill", "color"}                        just a status pill
##   {"button", "action": Callable, "kind"?, "disabled"?: reason, "reason_in_label"?: bool}

## A row was clicked (its data)
signal row_clicked(data)

## The columns: [{"title", "width" (layout pixels; 0: takes the rest), "sortable" (default true)}]
var columns: Array = []
## Taller than this, the rows scroll (layout pixels)
var max_height := 240.0
## Shown in place of the rows when there are none
var empty_text := "None"

var _header: HBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _rows: Array = []
var _sort_column := -1
var _sort_descending := false
var _signature := ""
var _row_styles: Array[StyleBoxFlat] = []
var _hover_style: StyleBoxFlat


## A table with these columns, at most `height` tall before it scrolls
static func create(table_columns: Array, height := 240.0, when_empty := "None") -> BrassTable:
	var t := BrassTable.new()
	t.columns = table_columns
	t.max_height = height
	t.empty_text = when_empty
	t._build()
	return t


func _build() -> void:
	add_theme_constant_override("separation", 0)
	for shaded in [false, true]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.18) if shaded else Color(0, 0, 0, 0)
		_pad(style)
		_row_styles.append(style)
	_hover_style = StyleBoxFlat.new()
	_hover_style.bg_color = Color(BrassStyle.BRASS, 0.14)
	_hover_style.border_color = Color(BrassStyle.BRASS, 0.55)
	_hover_style.set_border_width_all(1)
	_pad(_hover_style)
	var header_holder := MarginContainer.new()
	header_holder.add_theme_constant_override("margin_left", 8)
	header_holder.add_theme_constant_override("margin_right", 8)
	add_child(header_holder)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", BrassStyle.GAP_M)
	header_holder.add_child(_header)
	for c in columns.size():
		var title := Button.new()
		title.flat = true
		title.focus_mode = Control.FOCUS_NONE
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.add_theme_font_size_override("font_size", BrassStyle.SIZE_SECTION)
		title.add_theme_font_override("font", BrassStyle.heading_font())
		for state in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
			title.add_theme_color_override(state, BrassStyle.HEADING)
		title.add_theme_color_override("font_hover_color", BrassStyle.HEADING.lightened(0.25))
		title.add_theme_color_override("font_disabled_color", BrassStyle.HEADING)
		var sortable: bool = columns[c].get("sortable", true)
		title.disabled = not sortable
		if sortable:
			title.tooltip_text = "Sort by %s" % str(columns[c]["title"]).to_lower()
			title.pressed.connect(_sort_by.bind(c))
		_size_cell(title, c)
		_header.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_list.minimum_size_changed.connect(_fit_height)
	_empty = BrassStyle.label("  " + empty_text, BrassStyle.SIZE_BODY, BrassStyle.TEXT_DIM)
	add_child(_empty)
	_update_titles()


## Shows these rows (see the top), rebuilding only if something shown changed
func set_rows(rows: Array) -> void:
	var signature := _signature_of(rows)
	_rows = rows
	if signature == _signature:
		return
	_signature = signature
	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var order := range(_rows.size())
	if _sort_column >= 0:
		var c := _sort_column
		order.sort_custom(func(a, b):
			var va = _sort_value(_rows[a], c)
			var vb = _sort_value(_rows[b], c)
			if va == vb:
				return a < b
			return (va > vb) if _sort_descending else (va < vb))
	for i in order.size():
		_list.add_child(_make_row(_rows[order[i]], i % 2 == 0))
	_empty.text = "  " + empty_text
	_empty.visible = _rows.is_empty()
	_scroll.visible = not _rows.is_empty()
	_fit_height()


func _make_row(row: Dictionary, shaded: bool) -> PanelContainer:
	var holder := PanelContainer.new()
	var resting: StyleBoxFlat = _row_styles[1 if shaded else 0]
	holder.add_theme_stylebox_override("panel", resting)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.mouse_entered.connect(func(): holder.add_theme_stylebox_override("panel", _hover_style))
	holder.mouse_exited.connect(func(): holder.add_theme_stylebox_override("panel", resting))
	var data = row.get("data")
	holder.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			row_clicked.emit(data))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", BrassStyle.GAP_M)
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(line)
	var cells: Array = row.get("cells", [])
	for c in columns.size():
		var node := _make_cell(cells[c] if c < cells.size() else "")
		_size_cell(node, c)
		node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(node)
	return holder


func _make_cell(cell) -> Control:
	if cell is String:
		cell = {"text": cell}
	var spec: Dictionary = cell
	if spec.has("button"):
		var b := BrassStyle.button(spec["button"], spec.get("kind", "small"))
		b.custom_minimum_size.y = BrassStyle.BUTTON_SMALL_H
		b.add_theme_font_size_override("font_size", BrassStyle.SIZE_SMALL)
		var reason: String = spec.get("disabled", "")
		BrassStyle.set_disabled_reason(b, reason, spec["button"], spec.get("reason_in_label", false))
		if spec.has("tooltip") and reason.is_empty():
			b.tooltip_text = spec["tooltip"]
		var action: Callable = spec.get("action", Callable())
		if action.is_valid():
			b.pressed.connect(action)
		return b
	if spec.has("pill") and not spec.has("text"):
		return BrassStyle.pill(spec["pill"], spec.get("color", BrassStyle.NEUTRAL))
	# (with a pill, "color" is the pill's; the text stays plain)
	var text_color: Color = BrassStyle.TEXT if spec.has("pill") else spec.get("color", BrassStyle.TEXT)
	var text := BrassStyle.label(spec.get("text", ""), BrassStyle.SIZE_BODY, text_color)
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if spec.has("tooltip"):
		text.tooltip_text = spec["tooltip"]
		text.mouse_filter = Control.MOUSE_FILTER_PASS
	if not spec.has("pill"):
		return text
	var both := HBoxContainer.new()
	both.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	both.mouse_filter = Control.MOUSE_FILTER_PASS
	text.clip_text = false
	text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	both.add_child(text)
	both.add_child(BrassStyle.pill(spec["pill"], spec.get("color", BrassStyle.INFO)))
	return both


func _size_cell(node: Control, column: int) -> void:
	var width: float = columns[column].get("width", 0.0)
	if width > 0.0:
		node.custom_minimum_size.x = width
		node.size_flags_horizontal = Control.SIZE_FILL
	else:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _sort_by(column: int) -> void:
	if _sort_column != column:
		_sort_column = column
		_sort_descending = false
	elif not _sort_descending:
		_sort_descending = true
	else:
		_sort_column = -1
	_update_titles()
	_rebuild()


func _update_titles() -> void:
	for c in _header.get_child_count():
		var title := _header.get_child(c) as Button
		var arrow := ""
		if c == _sort_column:
			arrow = "  ▾" if _sort_descending else "  ▴"
		title.text = str(columns[c]["title"]).to_upper() + arrow


func _sort_value(row: Dictionary, column: int):
	var sorts: Array = row.get("sort", [])
	if column < sorts.size():
		return sorts[column]
	var cells: Array = row.get("cells", [])
	var cell = cells[column] if column < cells.size() else ""
	if cell is Dictionary:
		return str(cell.get("text", cell.get("pill", cell.get("button", "")))).to_lower()
	return str(cell).to_lower()


# The scrolling part's height: its rows', up to max_height
func _fit_height() -> void:
	_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, max_height)


func _signature_of(rows: Array) -> String:
	var parts: PackedStringArray = []
	for row in rows:
		for cell in row.get("cells", []):
			if cell is Dictionary:
				var spec: Dictionary = (cell as Dictionary).duplicate()
				spec.erase("action")
				parts.append(str(spec))
			else:
				parts.append(str(cell))
		parts.append("|")
	return "".join(parts)


func _pad(style: StyleBoxFlat) -> void:
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.set_corner_radius_all(2)
