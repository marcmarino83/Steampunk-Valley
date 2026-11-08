class_name PlotPanel
extends Control
## The plot panel, opened with E aimed inside a plot in plot view (brass plaque style): its name
## (editable), type, size, how many it houses, and a checklist of its requirements with ticks and
## crosses, kept up to date while it's open, with Move and Remove plot (resizing is by dragging an
## edge in plot view). It also asks the yes/no questions plots need ("Remove this plot?", and
## shrinking one that would lose pieces).

## Move was pressed: the player starts it with the hammer
signal move_requested(plot: Plot)
## Remove plot was pressed and confirmed
signal remove_confirmed(plot: Plot)
## It closed (the mouse goes back to looking around)
signal closed

const WIDTH := 430.0
const TICK := "✓"
const CROSS := "✗"
const GOOD := Color(0.62, 0.9, 0.5)
const REFRESH_SECONDS := 0.3

var _plot: Plot
var _name_edit: LineEdit
var _info: Label
var _capacity: Label
var _checklist: VBoxContainer
var _status: Label
var _move: Button
var _hint: Label
var _main: Control
var _confirm: Control
var _question: Label
var _on_yes: Callable
var _on_no: Callable
var _refresh_in := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_main = _build_main(center)
	_confirm = _build_confirm(center)


## Opens the panel on a plot. Moving and resizing need the hammer in your hand.
func open(plot: Plot, holding_hammer: bool) -> void:
	_plot = plot
	_name_edit.text = plot.plot_name
	_move.disabled = not holding_hammer
	_hint.text = "Drag an edge in plot view to resize   ·   [E] or [Esc] Close" if holding_hammer else "Hold the hammer to move it   ·   [E] or [Esc] Close"
	_show_part(_main)
	_refresh()
	show()


## Asks a yes/no question on its own (shrinking a plot): `on_yes` or `on_no` is called after
func ask(question: String, on_yes: Callable, on_no: Callable) -> void:
	_plot = null
	_on_yes = on_yes
	_on_no = on_no
	_question.text = question
	_show_part(_confirm)
	show()


func is_open() -> bool:
	return visible


## True while typing the plot's name (so E and Esc are letters and cancelling, not closing)
func is_typing() -> bool:
	return _name_edit.has_focus()


## Esc or E: cancels a question, or closes the panel
func dismiss() -> void:
	if _confirm.get_parent().visible:
		_answer(false)
	else:
		close()


func close() -> void:
	if not visible:
		return
	_apply_name()
	hide()
	_plot = null
	closed.emit()


func _process(delta: float) -> void:
	if not visible or _plot == null:
		return
	if not is_instance_valid(_plot):
		close()
		return
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh()


func _refresh() -> void:
	_refresh_in = REFRESH_SECONDS
	var type := _plot.plot_type
	_info.text = "%s   ·   %d × %d m   (at least %s m)" % [type.display_name, roundi(_plot.size.x), roundi(_plot.size.y), PlotType.size_text(type.min_size)]
	_capacity.visible = not type.houses_per.is_empty()
	_capacity.text = "Houses %d %s (one per %s)" % [_plot.capacity, "settler" if _plot.capacity == 1 else "settlers", type.houses_per.to_lower()]
	var lines: Array = _plot.checklist
	while _checklist.get_child_count() < lines.size():
		_checklist.add_child(_line_label())
	for i in _checklist.get_child_count():
		var label: Label = _checklist.get_child(i)
		label.visible = i < lines.size()
		if not label.visible:
			continue
		var line: Dictionary = lines[i]
		var text: String = line["text"]
		var mark: String = TICK if line["ok"] else CROSS
		# The tick or cross goes after the requirement, before any explanation in brackets
		var cut := text.find(" (")
		label.text = ("%s %s%s" % [text.left(cut), mark, text.substr(cut)]) if cut >= 0 else "%s %s" % [text, mark]
		label.add_theme_color_override("font_color", GOOD if line["ok"] else BrassStyle.BAD)
	_status.text = "Working" if _plot.working else "Missing requirements"
	_status.add_theme_color_override("font_color", GOOD if _plot.working else BrassStyle.BAD)


func _apply_name() -> void:
	if _plot and is_instance_valid(_plot):
		var wanted := _name_edit.text.strip_edges()
		if not wanted.is_empty() and wanted != _plot.plot_name:
			_plot.rename(wanted)
	_name_edit.release_focus()


func _show_part(part: Control) -> void:
	_main.get_parent().visible = part == _main
	_confirm.get_parent().visible = part == _confirm


# ---- Building it ----

func _build_main(center: CenterContainer) -> Control:
	var box := MenuStyle.panel()
	center.add_child(box)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)
	column.add_child(MenuStyle.title("Plot", 26))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	column.add_child(name_row)
	var name_label := _label("Name", 16, BrassStyle.TEXT_DIM)
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 32
	_name_edit.add_theme_font_size_override("font_size", 17)
	_name_edit.add_theme_color_override("font_color", BrassStyle.TEXT)
	_name_edit.add_theme_color_override("caret_color", BrassStyle.TEXT)
	_name_edit.add_theme_stylebox_override("normal", BrassStyle.frame("slot"))
	_name_edit.add_theme_stylebox_override("focus", BrassStyle.frame("slot_hover"))
	_name_edit.text_submitted.connect(func(_t): _apply_name())
	_name_edit.focus_exited.connect(_apply_name)
	name_row.add_child(_name_edit)
	_info = _label("", 15, BrassStyle.TEXT_DIM)
	column.add_child(_info)
	_capacity = _label("", 15, BrassStyle.TEXT)
	column.add_child(_capacity)
	column.add_child(_label("Requirements", 17, BrassStyle.TEXT))
	_checklist = VBoxContainer.new()
	_checklist.add_theme_constant_override("separation", 2)
	column.add_child(_checklist)
	_status = _label("", 19, BrassStyle.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	_move = _button("Move")
	_move.pressed.connect(func(): if _plot: move_requested.emit(_plot))
	buttons.add_child(_move)
	var remove := _button("Remove plot")
	remove.pressed.connect(_ask_remove)
	buttons.add_child(remove)
	_hint = MenuStyle.note("")
	column.add_child(_hint)
	MenuStyle.enlarge(box)
	return box


func _build_confirm(center: CenterContainer) -> Control:
	var box := MenuStyle.panel()
	center.add_child(box)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 14)
	box.add_child(column)
	_question = _label("", 18, BrassStyle.TEXT)
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_question)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	var yes := _button("Yes")
	yes.pressed.connect(_answer.bind(true))
	buttons.add_child(yes)
	var no := _button("Cancel")
	no.pressed.connect(_answer.bind(false))
	buttons.add_child(no)
	MenuStyle.enlarge(box)
	return box


func _ask_remove() -> void:
	var plot := _plot
	_apply_name()
	_on_yes = func():
		remove_confirmed.emit(plot)
	_on_no = func():
		open(plot, not _move.disabled)
	_question.text = "Remove %s? Only the plot goes: its pieces stay standing, belonging to no plot." % plot.plot_name
	_plot = null
	_show_part(_confirm)


func _answer(yes: bool) -> void:
	var callback := _on_yes if yes else _on_no
	_on_yes = Callable()
	_on_no = Callable()
	hide()
	if callback.is_valid():
		callback.call()
	# Cancelling "Remove plot" goes back to the panel; otherwise it's closed now
	if not visible:
		closed.emit()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _line_label() -> Label:
	var label := _label("", 16, BrassStyle.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text: String) -> Button:
	var button := MenuStyle.button(text)
	button.custom_minimum_size = Vector2(130, 38)
	button.add_theme_font_size_override("font_size", 16)
	return button
