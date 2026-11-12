class_name PlotPanel
extends Control
## The plot panel, opened with E aimed at a plot with the hammer out (its ground or one of its
## pieces; in plot view, or anywhere a door or storage isn't in the way), built on the standard
## panel (BrassPanel):
##   header:  its name (click to rename), a status pill (Working, or what's missing), and its type,
##            size and smallest size
##   body:    the Village Center's picture; a house's "Use as" (Villager housing or Player home) and
##            how many it houses; its residents, its worker (with Unassign) or its visitors; its
##            production (sliders for the Forager's Hut); its requirements, ticked or crossed
##   actions: Remove (asks for a second click), Save as template, Move
##   hints:   M Move · P Plot view: drag edges to resize · E Close
## kept up to date while it's open. It also asks the yes/no questions plots need (shrinking one that
## would lose pieces), and names a template being saved from it.

## Move was pressed: the player starts it with the hammer
signal move_requested(plot: Plot)
## Remove was pressed and confirmed
signal remove_confirmed(plot: Plot)
## Save as template: everything the plot owns, under this name (built-in: into the project, in
## debug builds only)
signal template_requested(plot: Plot, template_name: String, built_in: bool)
## It closed (the mouse goes back to looking around)
signal closed
## The Village Center's Village button: the player opens the Village screen
signal village_requested

const WIDTH := 420.0
const REFRESH_SECONDS := 0.3

## The settlers (for a House's residents, a workplace's worker and the Village Center's visitors)
var settlers: SettlerManager
## Says whether a plot type is unlocked yet (Change type lists only those)
var is_unlocked: Callable

var _plot: Plot
var _holding_hammer := false
var _main: BrassPanel
var _thumb: TextureRect
# A house's use (two buttons, one pressed) and how many it houses
var _housing_part: VBoxContainer
var _villager_button: Button
var _player_button: Button
var _capacity: Label
# Its residents, workers or visitors (rebuilt only when who's there changes)
var _people_part: VBoxContainer
var _people: VBoxContainer
var _people_key := ""
# Production: what it makes a day, and for the Forager's Hut a slider per item that together
# always add up to 100%
var _production_part: VBoxContainer
var _production: VBoxContainer
var _production_key := ""
var _sliders := {}
var _slider_labels := {}
var _summary: Label
var _requirements_part: VBoxContainer
var _checklist: GridContainer
# All met: one line that opens the list
var _all_met: Button
var _requirements_open := false
# The slider being dragged (its percentage shows beside it while it is)
var _dragging := ""
var _remove: Button
var _move: Button
# The Village Center's way to the Village screen
var _village: Button
# A yes/no question (shrinking a plot)
var _confirm: BrassPanel
var _question: Label
var _on_yes: Callable
var _on_no: Callable
# Changing its type: the types it could be
var _type_part: BrassPanel
var _type_list: VBoxContainer
# Saving as a template: its name, whether it's built in (debug builds only)
var _template_part: BrassPanel
var _template_name: LineEdit
var _template_built_in: CheckBox
var _template_plot: Plot
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
	_type_part = _build_type_part(center)


## Opens the panel on a plot. Moving and resizing need the hammer in your hand.
func open(plot: Plot, holding_hammer: bool) -> void:
	_plot = plot
	_holding_hammer = holding_hammer
	_main.set_title(plot.plot_name)
	BrassStyle.disarm(_remove)
	BrassStyle.set_disabled_reason(_move, "" if holding_hammer else "Hold the hammer to move or resize the plot")
	# (no hints for what already has a button: M still moves it, as its tooltip says)
	if holding_hammer:
		_move.tooltip_text = "Move [M]: it and its own pieces follow the crosshair (wheel turns, R resets)"
		_main.set_hints([["P", "Plot view: drag edges to resize"], ["E", "Close"]])
	else:
		_main.set_hints([["E", "Close"]])
	_people_key = ""
	_production_key = ""
	_requirements_open = false
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
	return _main.name_edit.has_focus() or _template_name.has_focus()


## Esc or E: cancels a question or the template dialog, or closes the panel
func dismiss() -> void:
	if _confirm.get_parent().visible:
		_answer(false)
	elif _type_part.get_parent().visible:
		_back_to_main()
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
	# Its type only once it's been renamed (the name says it otherwise), and its size; the smallest it
	# can be shows only while resizing it in plot view
	var size_text := "%d × %d m" % [roundi(_plot.size.x), roundi(_plot.size.y)]
	_main.set_subtitle(("%s  ·  %s" % [type.display_name, size_text]) if _renamed(_plot) else size_text)
	if type.free_build:
		_main.set_status("Free build", BrassStyle.NEUTRAL)
	elif _plot.working:
		_main.set_status("Working", BrassStyle.GOOD)
	elif not _plot.missing.is_empty():
		_main.set_status("Missing %s" % ", ".join(_plot.missing), BrassStyle.WARN)
	else:
		_main.set_status("Not working", BrassStyle.WARN)
	_village.visible = type.draws_visitors
	_thumb.visible = type.icon != null
	if type.icon and _thumb.texture != type.icon:
		_thumb.texture = type.icon
	# A house: its use, and how many it houses
	var house := not type.houses_per.is_empty()
	var player_home: bool = house and not _plot.is_villager_housing()
	_housing_part.visible = house
	_villager_button.set_pressed_no_signal(not player_home)
	_player_button.set_pressed_no_signal(player_home)
	if player_home:
		_capacity.text = "Your own home: settlers are never assigned here"
	else:
		_capacity.text = "Houses %d %s (one per %s)" % [_plot.capacity, "settler" if _plot.capacity == 1 else "settlers", type.houses_per.to_lower()]
	_refresh_people()
	_refresh_production()
	_refresh_requirements()


# Requirements: all met, one line ("✓ All requirements met") that opens the list when clicked;
# anything missing, the whole list, missing ones first
func _refresh_requirements() -> void:
	var lines: Array = _plot.checklist
	# (a type with no requirements, like Free build, has no section for them)
	_requirements_part.visible = not lines.is_empty()
	var missing := lines.filter(func(l): return not l["ok"])
	var met := lines.filter(func(l): return l["ok"])
	BrassPanel.set_heading(_requirements_part, "Requirements  %d/%d" % [met.size(), lines.size()])
	var all_met := missing.is_empty()
	_all_met.visible = all_met
	_all_met.text = "✓  All requirements met  %s" % ("▾" if _requirements_open else "▸")
	_checklist.visible = not all_met or _requirements_open
	# (one column with anything missing, so the missing ones read first, top to bottom; two when all
	# are met and the short list is opened)
	_main.set_checklist(_checklist, missing + met, 2 if all_met else 1)


# True if the player has named the plot (not its type's name, or "House 2" and so on)
static func _renamed(plot: Plot) -> bool:
	var base := plot.plot_type.display_name
	if plot.plot_name == base:
		return false
	var rest := plot.plot_name.trim_prefix(base + " ")
	return rest == plot.plot_name or not rest.is_valid_int()


# A House's residents, a workplace's workers (each with Unassign), or the Village Center's visitors
# (rebuilt only when who's there changes)
func _refresh_people() -> void:
	var house := settlers != null and SettlerManager.is_house(_plot)
	var workplace := settlers != null and SettlerManager.is_workplace(_plot)
	var center: bool = settlers != null and _plot.plot_type.draws_visitors
	var people: Array = []
	if house:
		people = settlers.residents(_plot)
	elif workplace:
		people = settlers.workers(_plot)
	elif center:
		people = settlers.staying_visitors()
	var key := "%s|%s|%d|%s|%s" % [_plot.plot_id, ",".join(people.map(func(s): return s.settler_id + str(s.hungry_days))), _plot.capacity, _plot.housing, _plot.working]
	_people_part.visible = center or workplace or (house and _plot.is_villager_housing())
	if key == _people_key:
		return
	_people_key = key
	for child in _people.get_children():
		_people.remove_child(child)
		child.queue_free()
	if center:
		BrassPanel.set_heading(_people_part, "Visitors  %d/%d" % [people.size(), SettlerManager.MAX_VISITORS])
		var names := ", ".join(people.map(func(s): return s.settler_name))
		_people.add_child(_wrapped(names if not names.is_empty() else "None right now", BrassStyle.TEXT if not names.is_empty() else BrassStyle.TEXT_DIM))
		var when := _wrapped("A visitor comes every 2–4 days" if _plot.working else "No visitors until it's working", BrassStyle.TEXT_DIM)
		when.tooltip_text = "Talk to a visitor to recruit them into a free villager House"
		when.mouse_filter = Control.MOUSE_FILTER_PASS
		_people.add_child(when)
		return
	if house:
		BrassPanel.set_heading(_people_part, "Residents  %d/%d" % [people.size(), _plot.capacity])
		if people.is_empty():
			_people.add_child(_wrapped("None yet", BrassStyle.TEXT_DIM))
		for settler in people:
			_people.add_child(_wrapped(settler.settler_name + ("  (hungry)" if settler.is_hungry() else ""), BrassStyle.WARN if settler.is_hungry() else BrassStyle.TEXT))
		return
	var wanted := _plot.plot_type.workers
	BrassPanel.set_heading(_people_part, "Worker" if wanted == 1 else "Workers  %d/%d" % [people.size(), wanted])
	if people.is_empty():
		var none := _wrapped("None", BrassStyle.TEXT_DIM)
		none.tooltip_text = "Assign a worker from a settler's panel"
		none.mouse_filter = Control.MOUSE_FILTER_PASS
		_people.add_child(none)
		return
	for settler in people:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", BrassStyle.GAP_S)
		var hungry: bool = settler.is_hungry()
		var who := BrassStyle.label(settler.settler_name + ("  (hungry: half output)" if hungry else ""), BrassStyle.SIZE_BODY, BrassStyle.WARN if hungry else BrassStyle.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		var unassign := BrassStyle.button("Unassign", "small")
		unassign.tooltip_text = "Takes %s off this job" % settler.settler_name
		unassign.pressed.connect(func():
			settlers.assign_job(settler, null)
			_refresh())
		row.add_child(unassign)
		_people.add_child(row)


# A workplace's Production: its fixed output a day, or for a plot with shared output (the
# Forager's Hut) a slider per item with its percentage and amount per day. Rebuilt only when the
# plot changes; the amounts follow the sliders as they move.
func _refresh_production() -> void:
	var type := _plot.plot_type
	var shows := not type.daily_output.is_empty() or type.split_output_total > 0
	_production_part.visible = shows
	if not shows:
		return
	if _production_key != _plot.plot_id:
		_production_key = _plot.plot_id
		_sliders.clear()
		_slider_labels.clear()
		for child in _production.get_children():
			_production.remove_child(child)
			child.queue_free()
		_summary = null
		if type.split_output_total > 0:
			BrassPanel.set_heading(_production_part, "Production  ·  %d items each dawn" % type.split_output_total)
			var shares := _plot.shares()
			for item in shares:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", BrassStyle.GAP_S)
				var item_label := BrassStyle.label(item, BrassStyle.SIZE_BODY, BrassStyle.TEXT)
				item_label.custom_minimum_size.x = 92
				row.add_child(item_label)
				var slider := HSlider.new()
				slider.min_value = 0
				slider.max_value = 100
				slider.step = 1
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				slider.custom_minimum_size.y = 18
				slider.focus_mode = Control.FOCUS_NONE
				BrassStyle.style_slider(slider)
				slider.set_value_no_signal(int(shares[item]))
				slider.value_changed.connect(_on_share_changed.bind(item))
				# Its percentage shows beside it only while it's dragged
				slider.drag_started.connect(func():
					_dragging = item
					_update_production_text())
				slider.drag_ended.connect(func(_changed):
					_dragging = ""
					_update_production_text())
				row.add_child(slider)
				var amount := BrassStyle.label("", BrassStyle.SIZE_SMALL, BrassStyle.TEXT_DIM)
				amount.custom_minimum_size.x = 84
				amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				row.add_child(amount)
				_production.add_child(row)
				_sliders[item] = slider
				_slider_labels[item] = amount
		else:
			BrassPanel.set_heading(_production_part, "Production  ·  each dawn")
			_summary = _wrapped("", BrassStyle.TEXT)
			_summary.tooltip_text = "Into town storage while it has room, otherwise into the plot's own storage chest"
			_summary.mouse_filter = Control.MOUSE_FILTER_PASS
			_production.add_child(_summary)
	_update_production_text()


func _update_production_text() -> void:
	var made := _plot.daily_output()
	if _summary:
		var parts: PackedStringArray = []
		for item in made:
			parts.append("%d %s" % [made[item], item.to_lower()])
		_summary.text = "  ·  ".join(parts)
	var shares := _plot.shares()
	for item in _slider_labels:
		var per_day := "%d/day" % int(made.get(item, 0))
		(_slider_labels[item] as Label).text = ("%d%%  ·  %s" % [int(shares.get(item, 0)), per_day]) if item == _dragging else per_day


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


# Villager housing or Player home (anyone living there moves out when it becomes the player's)
func _set_housing(mode: String) -> void:
	if _plot == null or settlers == null or _plot.housing == mode:
		return
	settlers.set_housing(_plot, mode)
	_people_key = ""
	_refresh()


func _apply_name() -> void:
	if _plot and is_instance_valid(_plot):
		var wanted := _main.name_edit.text.strip_edges()
		if not wanted.is_empty() and wanted != _plot.plot_name:
			_plot.rename(wanted)
	_main.name_edit.release_focus()


# M on the panel (not while typing a name): Move, as its button
func _input(event: InputEvent) -> void:
	if not visible or _plot == null or not _main.get_parent().visible or is_typing():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and not _move.disabled:
		get_viewport().set_input_as_handled()
		move_requested.emit(_plot)


func _show_part(part: Control) -> void:
	_main.get_parent().visible = part == _main
	_confirm.get_parent().visible = part == _confirm
	_template_part.get_parent().visible = part == _template_part
	_type_part.get_parent().visible = part == _type_part


# ---- Building it ----

func _build_main(center: CenterContainer) -> BrassPanel:
	var p := BrassPanel.create(center, WIDTH, true)
	p.name_edit.max_length = 32
	p.name_edit.text_submitted.connect(func(_t): _apply_name())
	p.name_edit.focus_exited.connect(_apply_name)
	# The plot type's picture, if it has one (the Village Center's)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(WIDTH, 150)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.visible = false
	p.body.add_child(_thumb)
	_housing_part = p.section("Use as")
	var choice := HBoxContainer.new()
	choice.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	_housing_part.add_child(choice)
	var group := ButtonGroup.new()
	_villager_button = BrassStyle.button("Villager housing")
	_villager_button.tooltip_text = "Settlers can be given a home here"
	_player_button = BrassStyle.button("Player home")
	_player_button.tooltip_text = "Your own home: settlers are never assigned here (anyone living here moves out)"
	for b in [_villager_button, _player_button]:
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.add_child(b)
	_villager_button.pressed.connect(_set_housing.bind("villager"))
	_player_button.pressed.connect(_set_housing.bind("player"))
	_capacity = BrassStyle.label("", BrassStyle.SIZE_SMALL, BrassStyle.TEXT_DIM)
	_housing_part.add_child(_capacity)
	_people_part = p.section("Worker")
	_people = VBoxContainer.new()
	_people.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	_people_part.add_child(_people)
	_production_part = p.section("Production")
	_production = VBoxContainer.new()
	_production.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	_production_part.add_child(_production)
	_requirements_part = p.section("Requirements")
	_all_met = Button.new()
	_all_met.flat = true
	_all_met.focus_mode = Control.FOCUS_NONE
	_all_met.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_all_met.add_theme_font_size_override("font_size", BrassStyle.SIZE_BODY)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_all_met.add_theme_color_override(state, BrassStyle.GOOD)
	_all_met.tooltip_text = "Show or hide the list"
	_all_met.pressed.connect(func():
		_requirements_open = not _requirements_open
		_refresh_requirements())
	_requirements_part.add_child(_all_met)
	_checklist = GridContainer.new()
	_checklist.add_theme_constant_override("v_separation", BrassStyle.GAP_XS)
	_requirements_part.add_child(_checklist)
	_remove = p.add_action(BrassStyle.button("Remove", "danger"), true)
	_remove.tooltip_text = "Removes only the plot: its pieces stay standing, belonging to no plot"
	BrassStyle.arm_confirm(_remove, _confirm_remove, "Click again to remove")
	_village = p.add_action(BrassStyle.button("Village"))
	_village.tooltip_text = "The Village screen: every settler, visitor and building [V]"
	_village.pressed.connect(func(): village_requested.emit())
	# The less used actions in one menu, so the row fits the panel: Change type, Save as template
	var more := MenuButton.new()
	more.text = "More  ▾"
	more.flat = false
	more.focus_mode = Control.FOCUS_NONE
	BrassStyle.style_button(more)
	more.custom_minimum_size = Vector2(BrassStyle.BUTTON_MIN_W, BrassStyle.BUTTON_H)
	more.add_theme_font_size_override("font_size", BrassStyle.SIZE_BODY)
	var menu := more.get_popup()
	# (the popup isn't enlarged with the panel: its text is drawn at the enlarged size)
	menu.add_theme_font_size_override("font_size", roundi(BrassStyle.SIZE_BODY * MenuStyle.MENU_SCALE))
	menu.add_item("Change type…", 0)
	menu.set_item_tooltip(0, "Make it another kind of plot: its pieces stay, and its requirements are checked again")
	menu.add_item("Save as template…", 1)
	menu.set_item_tooltip(1, "Saves everything in the plot as a template, to lay out again as ghosts to build")
	menu.id_pressed.connect(func(id):
		if id == 0:
			_open_types()
		else:
			_open_template())
	p.add_action(more)
	_move = p.add_action(BrassStyle.button("Move", "primary"))
	_move.pressed.connect(func(): if _plot: move_requested.emit(_plot))
	return p


func _build_confirm(center: CenterContainer) -> BrassPanel:
	var p := BrassPanel.create(center, WIDTH)
	p.set_title("Are you sure?")
	p.set_subtitle("")
	_question = BrassStyle.label("", BrassStyle.SIZE_BODY, BrassStyle.TEXT)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.custom_minimum_size.x = WIDTH
	p.body.add_child(_question)
	var no := p.add_action(BrassStyle.button("Cancel"))
	no.pressed.connect(_answer.bind(false))
	var yes := p.add_action(BrassStyle.button("Yes", "primary"))
	yes.pressed.connect(_answer.bind(true))
	p.set_hints([["E", "Cancel"]])
	return p


# Save as template: its name (the plot's to start with), "Save as built-in" in debug builds, Back
# and Save
func _build_template_part(center: CenterContainer) -> BrassPanel:
	var p := BrassPanel.create(center, WIDTH)
	p.set_title("Save as template")
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", BrassStyle.GAP_S)
	p.body.add_child(name_row)
	name_row.add_child(BrassStyle.label("Name", BrassStyle.SIZE_BODY, BrassStyle.TEXT_DIM))
	_template_name = LineEdit.new()
	_template_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_name.max_length = 40
	_template_name.add_theme_font_size_override("font_size", BrassStyle.SIZE_BODY)
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
	_template_built_in.add_theme_font_size_override("font_size", BrassStyle.SIZE_SMALL)
	_template_built_in.add_theme_color_override("font_color", BrassStyle.TEXT)
	_template_built_in.visible = OS.is_debug_build()
	p.body.add_child(_template_built_in)
	var back := p.add_action(BrassStyle.button("Back"))
	back.pressed.connect(_back_from_template)
	var save := p.add_action(BrassStyle.button("Save", "primary"))
	save.pressed.connect(_save_template)
	p.set_hints([["Enter", "Save"], ["Esc", "Back"]])
	return p


# Change type: the unlocked plot types it could become (one too small for it, or one the village
# already has its one of, is listed but disabled, saying why); Back
func _build_type_part(center: CenterContainer) -> BrassPanel:
	var p := BrassPanel.create(center, WIDTH)
	p.set_title("Change type")
	_type_list = VBoxContainer.new()
	_type_list.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	p.body.add_child(_type_list)
	var back := p.add_action(BrassStyle.button("Back"))
	back.pressed.connect(_back_to_main)
	p.set_hints([["E", "Back"]])
	return p


func _open_types() -> void:
	if _plot == null:
		return
	_apply_name()
	var plot := _plot
	_type_part.set_subtitle("From %s  ·  its pieces stay" % plot.plot_type.display_name)
	for child in _type_list.get_children():
		_type_list.remove_child(child)
		child.queue_free()
	for type: PlotType in PlotRegistry.all_types():
		if type == plot.plot_type or (is_unlocked.is_valid() and not is_unlocked.call(type)):
			continue
		var b := BrassStyle.button(type.display_name)
		b.custom_minimum_size.x = WIDTH
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var reason := ""
		if plot.size.x < type.min_size.x or plot.size.y < type.min_size.y:
			reason = "Needs at least %s m" % PlotType.size_text(type.min_size)
		elif type.one_per_village and settlers and not settlers.plots.plots_of(type.display_name).is_empty():
			reason = "One per village: there's one already"
		BrassStyle.set_disabled_reason(b, reason)
		if reason.is_empty():
			b.tooltip_text = "Needs %s" % type.requirements_text()
		b.pressed.connect(_change_type.bind(type))
		_type_list.add_child(b)
	_show_part(_type_part)


# Its new type: who lives or works there and no longer can moves out, and its requirements are
# checked again
func _change_type(type: PlotType) -> void:
	var plot := _plot
	if plot == null or settlers == null:
		return
	for settler in settlers.residents(plot):
		if type.houses_per.is_empty():
			settlers.assign_home(settler, null)
	var crew := settlers.workers(plot)
	for i in crew.size():
		if i >= type.workers:
			settlers.assign_job(crew[i], null)
	settlers.plots.change_type(plot, type)
	_main.set_title(plot.plot_name)
	_back_to_main()


func _back_to_main() -> void:
	_people_key = ""
	_production_key = ""
	_requirements_open = false
	if _plot and is_instance_valid(_plot):
		_show_part(_main)
		_refresh()
	else:
		close()


func _open_template() -> void:
	if _plot == null:
		return
	_apply_name()
	_template_plot = _plot
	var count := 0
	if settlers:
		count = settlers.plots.owned_items(_plot, true).size()
	_template_part.set_subtitle("%d pieces and buildings  ·  %s, %d × %d m" % [count, _plot.plot_type.display_name, roundi(_plot.size.x), roundi(_plot.size.y)])
	_template_part.subtitle.tooltip_text = "Saves every piece, furniture item and building in the plot, where each sits, and the plot's type and size. Placing it later lays it all out as ghosts to build."
	_template_part.subtitle.mouse_filter = Control.MOUSE_FILTER_PASS
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


# Remove's second click: the plot goes (its pieces stay)
func _confirm_remove() -> void:
	var plot := _plot
	if plot == null:
		return
	close()
	remove_confirmed.emit(plot)


func _answer(yes: bool) -> void:
	var callback := _on_yes if yes else _on_no
	_on_yes = Callable()
	_on_no = Callable()
	hide()
	if callback.is_valid():
		callback.call()
	if not visible:
		closed.emit()


func _wrapped(text: String, color: Color) -> Label:
	var l := BrassStyle.label(text, BrassStyle.SIZE_BODY, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH
	return l
