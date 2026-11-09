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
## Save as template: everything the plot owns, under this name (built-in: into the project, in
## debug builds only)
signal template_requested(plot: Plot, template_name: String, built_in: bool)
## It closed (the mouse goes back to looking around)
signal closed

const WIDTH := 430.0
const TICK := "✓"
const CROSS := "✗"
const GOOD := Color(0.62, 0.9, 0.5)
const REFRESH_SECONDS := 0.3

## The settlers (for a House's residents and a workplace's worker)
var settlers: SettlerManager

var _plot: Plot
var _name_edit: LineEdit
var _info: Label
var _capacity: Label
# Its residents, or its workers (each with an Unassign button)
var _people: VBoxContainer
var _people_key := ""
# Production (a workplace): what it makes a day, and for the Forager's Hut a slider per item that
# together always add up to 100%
var _production: VBoxContainer
var _production_key := ""
var _sliders := {}
var _slider_labels := {}
var _summary: Label
var _checklist: VBoxContainer
var _status: Label
var _move: Button
var _hint: Label
var _main: Control
var _confirm: Control
# Saving as a template: its name, whether it's built in (debug builds only), what's in it
var _template_part: Control
var _template_name: LineEdit
var _template_built_in: CheckBox
var _template_info: Label
var _template_plot: Plot
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
	_template_part = _build_template_part(center)


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


## True while typing the plot's name or a template's (so E and Esc are letters and cancelling,
## not closing)
func is_typing() -> bool:
	return _name_edit.has_focus() or _template_name.has_focus()


## Esc or E: cancels a question or the template dialog, or closes the panel
func dismiss() -> void:
	if _confirm.get_parent().visible:
		_answer(false)
	elif _template_part.get_parent().visible:
		_back_from_template()
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
	_refresh_people()
	_refresh_production()
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


# A House's residents ("Residents 1/2: Ada Cobb"), or a workplace's worker with Unassign (rebuilt
# only when who's there changes)
func _refresh_people() -> void:
	var house := settlers != null and SettlerManager.is_house(_plot)
	var workplace := settlers != null and SettlerManager.is_workplace(_plot)
	var people: Array = []
	if house:
		people = settlers.residents(_plot)
	elif workplace:
		people = settlers.workers(_plot)
	var key := "%s|%s|%d" % [_plot.plot_id, ",".join(people.map(func(s): return s.settler_id + str(s.hungry_days))), _plot.capacity]
	_people.visible = house or workplace
	if key == _people_key:
		return
	_people_key = key
	for child in _people.get_children():
		child.queue_free()
	if house:
		var names := ", ".join(people.map(func(s): return s.settler_name + (" (hungry)" if s.is_hungry() else "")))
		var line := _line_label()
		line.text = "Residents %d/%d:  %s" % [people.size(), _plot.capacity, names if not names.is_empty() else "none yet"]
		_people.add_child(line)
		return
	if not workplace:
		return
	var wanted := _plot.plot_type.workers
	if people.is_empty():
		var none := _line_label()
		none.text = "%s:  none (assign one from a settler's panel)" % ("Worker" if wanted == 1 else "Workers")
		_people.add_child(none)
		return
	for settler in people:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var line := _line_label()
		line.text = "Worker:  %s%s" % [settler.settler_name, "  (hungry: half output)" if settler.is_hungry() else ""]
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var unassign := _button("Unassign")
		unassign.custom_minimum_size = Vector2(110, 32)
		unassign.pressed.connect(func():
			settlers.assign_job(settler, null)
			_refresh())
		row.add_child(unassign)
		_people.add_child(row)


# A workplace's Production: "Makes each dawn: 12 wood, 8 sticks", or for a plot with shared output
# (the Forager's Hut) a slider per item with its percentage and amount per day. Rebuilt only when
# the plot changes; the amounts follow the sliders as they move.
func _refresh_production() -> void:
	var type := _plot.plot_type
	var shows := not type.daily_output.is_empty() or type.split_output_total > 0
	_production.visible = shows
	if not shows:
		return
	if _production_key != _plot.plot_id:
		_production_key = _plot.plot_id
		_sliders.clear()
		_slider_labels.clear()
		for child in _production.get_children():
			child.queue_free()
		_production.add_child(_label("Production", 17, BrassStyle.TEXT))
		_summary = _line_label()
		_production.add_child(_summary)
		if type.split_output_total > 0:
			var shares := _plot.shares()
			for item in shares:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 10)
				var item_label := _label(item, 15, BrassStyle.TEXT)
				item_label.custom_minimum_size.x = 96
				row.add_child(item_label)
				var slider := HSlider.new()
				slider.min_value = 0
				slider.max_value = 100
				slider.step = 1
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				slider.custom_minimum_size.y = 22
				slider.focus_mode = Control.FOCUS_NONE
				_style_slider(slider)
				slider.set_value_no_signal(int(shares[item]))
				slider.value_changed.connect(_on_share_changed.bind(item))
				row.add_child(slider)
				var amount := _label("", 15, BrassStyle.TEXT_DIM)
				amount.custom_minimum_size.x = 112
				amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				row.add_child(amount)
				_production.add_child(row)
				_sliders[item] = slider
				_slider_labels[item] = amount
	_update_production_text()


func _update_production_text() -> void:
	var type := _plot.plot_type
	var made := _plot.daily_output()
	if _summary:
		if type.split_output_total > 0:
			_summary.text = "%d items each dawn into its storage chest, shared out like this:" % type.split_output_total
		else:
			var parts: PackedStringArray = []
			for item in made:
				parts.append("%d %s" % [made[item], item.to_lower()])
			_summary.text = "Each dawn into its storage chest:  %s" % ", ".join(parts)
	var shares := _plot.shares()
	for item in _slider_labels:
		(_slider_labels[item] as Label).text = "%d%%  ·  %d/day" % [int(shares.get(item, 0)), int(made.get(item, 0))]


# One slider moved: the others share out what's left in their current proportions (evenly if they
# were all at 0), so the total stays 100%
func _on_share_changed(value: float, item: String) -> void:
	var shares := _plot.shares()
	var wanted := clampi(roundi(value), 0, 100)
	var others: Array = shares.keys().filter(func(k): return k != item)
	var left := 100 - wanted
	var weights := {}
	var weight_sum := 0
	for other in others:
		weight_sum += int(shares[other])
	for other in others:
		weights[other] = int(shares[other]) if weight_sum > 0 else 1
	var parts := PlotType.split(left, weights) if left > 0 else {}
	shares[item] = wanted
	for other in others:
		shares[other] = int(parts.get(other, 0))
	for other in _sliders:
		(_sliders[other] as HSlider).set_value_no_signal(int(shares[other]))
	_update_production_text()


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = BrassStyle.BAR_BACK
	track.border_color = BrassStyle.BRASS_DARK
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = BrassStyle.BRASS
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var lit := fill.duplicate() as StyleBoxFlat
	lit.bg_color = BrassStyle.BRASS_LIGHT
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", lit)


func _apply_name() -> void:
	if _plot and is_instance_valid(_plot):
		var wanted := _name_edit.text.strip_edges()
		if not wanted.is_empty() and wanted != _plot.plot_name:
			_plot.rename(wanted)
	_name_edit.release_focus()


func _show_part(part: Control) -> void:
	_main.get_parent().visible = part == _main
	_confirm.get_parent().visible = part == _confirm
	_template_part.get_parent().visible = part == _template_part


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
	_people = VBoxContainer.new()
	_people.add_theme_constant_override("separation", 4)
	column.add_child(_people)
	_production = VBoxContainer.new()
	_production.add_theme_constant_override("separation", 4)
	column.add_child(_production)
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
	var save_template := _button("Save as template")
	save_template.custom_minimum_size.x = 170
	save_template.pressed.connect(_open_template)
	buttons.add_child(save_template)
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


# Save as template: its name (the plot's to start with), "Save as built-in" in debug builds, Save
# and Back
func _build_template_part(center: CenterContainer) -> Control:
	var box := MenuStyle.panel()
	center.add_child(box)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 10)
	box.add_child(column)
	column.add_child(MenuStyle.title("Save as template", 24))
	_template_info = _label("", 15, BrassStyle.TEXT_DIM)
	_template_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_template_info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	column.add_child(name_row)
	name_row.add_child(_label("Name", 16, BrassStyle.TEXT_DIM))
	_template_name = LineEdit.new()
	_template_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_name.max_length = 40
	_template_name.add_theme_font_size_override("font_size", 17)
	_template_name.add_theme_color_override("font_color", BrassStyle.TEXT)
	_template_name.add_theme_color_override("caret_color", BrassStyle.TEXT)
	_template_name.add_theme_stylebox_override("normal", BrassStyle.frame("slot"))
	_template_name.add_theme_stylebox_override("focus", BrassStyle.frame("slot_hover"))
	_template_name.text_submitted.connect(func(_t): _save_template())
	name_row.add_child(_template_name)
	# A developer option: writes it into the project as a built-in template
	_template_built_in = CheckBox.new()
	_template_built_in.text = "Save as built-in (into the project)"
	_template_built_in.focus_mode = Control.FOCUS_NONE
	_template_built_in.add_theme_font_size_override("font_size", 15)
	_template_built_in.add_theme_color_override("font_color", BrassStyle.TEXT)
	_template_built_in.visible = OS.is_debug_build()
	column.add_child(_template_built_in)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	var save := _button("Save")
	save.pressed.connect(_save_template)
	buttons.add_child(save)
	var back := _button("Back")
	back.pressed.connect(_back_from_template)
	buttons.add_child(back)
	column.add_child(MenuStyle.note("[Esc] Back"))
	MenuStyle.enlarge(box)
	return box


func _open_template() -> void:
	if _plot == null:
		return
	_apply_name()
	_template_plot = _plot
	var count := 0
	if settlers:
		count = settlers.plots.owned_items(_plot, true).size()
	_template_info.text = "Saves every piece, furniture item and building in %s (%d in all), where each sits, and the plot's type and size (%s, %d × %d m). Placing it later lays it all out as ghosts to build." % [_plot.plot_name, count, _plot.plot_type.display_name, roundi(_plot.size.x), roundi(_plot.size.y)]
	_template_name.text = _plot.plot_name
	_template_built_in.button_pressed = false
	_show_part(_template_part)
	_template_name.grab_focus()
	_template_name.select_all()


func _save_template() -> void:
	var wanted := _template_name.text.strip_edges()
	if wanted.is_empty() or _template_plot == null or not is_instance_valid(_template_plot):
		return
	var plot := _template_plot
	_template_name.release_focus()
	_template_plot = null
	close()
	template_requested.emit(plot, wanted, _template_built_in.button_pressed and OS.is_debug_build())


func _back_from_template() -> void:
	_template_name.release_focus()
	var plot := _template_plot
	_template_plot = null
	if plot and is_instance_valid(plot):
		_plot = plot
		_show_part(_main)
		_refresh()
	else:
		close()


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
