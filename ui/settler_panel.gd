class_name SettlerPanel
extends Control
## A settler's panel, opened with E aimed at them (brass plaque style, like the plot panel): their
## name, home, job, whether they're fed ("Fed", "Hungry (2 days)") and what they're doing ("Working at Forager's Hut", "Sleeping", "Idle: no job"),
## kept up to date while it's open, with Assign home and Assign job. Each lists the working plots
## with a free place (and "No home" / "No job" to move them out); picking one assigns it.

## It closed (the mouse goes back to looking around)
signal closed

const WIDTH := 430.0
const REFRESH_SECONDS := 0.3

var manager: SettlerManager

var _settler: Settler
var _name: Label
var _home: Label
var _job: Label
var _food: Label
var _status: Label
var _buttons: HBoxContainer
var _choices: VBoxContainer
var _choices_title: Label
var _hint: Label
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
	var box := MenuStyle.panel()
	center.add_child(box)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)
	column.add_child(MenuStyle.title("Settler", 26))
	_name = _label("", 22, BrassStyle.TEXT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_name)
	_home = _label("", 16, BrassStyle.TEXT)
	column.add_child(_home)
	_job = _label("", 16, BrassStyle.TEXT)
	column.add_child(_job)
	_food = _label("", 16, BrassStyle.TEXT)
	column.add_child(_food)
	_status = _label("", 18, BrassStyle.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_buttons)
	var assign_home := _button("Assign home")
	assign_home.pressed.connect(_list_homes)
	_buttons.add_child(assign_home)
	var assign_job := _button("Assign job")
	assign_job.pressed.connect(_list_jobs)
	_buttons.add_child(assign_job)
	_choices_title = _label("", 16, BrassStyle.TEXT_DIM)
	_choices_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choices_title.visible = false
	column.add_child(_choices_title)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	column.add_child(_choices)
	_hint = MenuStyle.note("[E] or [Esc] Close")
	column.add_child(_hint)
	MenuStyle.enlarge(box)


func open(settler: Settler) -> void:
	_settler = settler
	_clear_choices()
	_refresh()
	show()


func is_open() -> bool:
	return visible


## Esc or E: closes a list of choices, or the panel
func dismiss() -> void:
	if _choices_title.visible:
		_clear_choices()
	else:
		close()


func close() -> void:
	if not visible:
		return
	hide()
	_settler = null
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	if _settler == null or not is_instance_valid(_settler):
		close()
		return
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh()


func _refresh() -> void:
	_refresh_in = REFRESH_SECONDS
	var home := manager.plot(_settler.home_id)
	var job := manager.plot(_settler.job_id)
	_name.text = _settler.settler_name
	_home.text = "Home:  %s" % (home.plot_name if home else "none")
	_job.text = "Job:  %s" % (job.plot_name if job else "none")
	_food.text = "Food:  %s" % _settler.food_text()
	_food.add_theme_color_override("font_color", BrassStyle.BAD if _settler.is_hungry() else Color(0.62, 0.9, 0.5))
	var status := _settler.status_text()
	_status.text = status
	var trouble := status.begins_with("Can't") or status.begins_with("Idle")
	_status.add_theme_color_override("font_color", BrassStyle.BAD if status.begins_with("Can't") else (BrassStyle.TEXT_DIM if trouble else Color(0.62, 0.9, 0.5)))


func _list_homes() -> void:
	var options := manager.free_homes().filter(func(p): return p.plot_id != _settler.home_id)
	var lines := []
	for house in options:
		lines.append(["%s  (%d/%d beds taken)" % [house.plot_name, manager.residents(house).size(), house.capacity], house])
	if not _settler.home_id.is_empty():
		lines.append(["No home", null])
	_show_choices("Move into which House?" if not options.is_empty() else "No working House has a free bed.", lines, func(house):
		manager.assign_home(_settler, house))


func _list_jobs() -> void:
	var options := manager.free_jobs().filter(func(p): return p.plot_id != _settler.job_id)
	var lines := []
	for workplace in options:
		lines.append(["%s  (%d/%d workers)" % [workplace.plot_name, manager.workers(workplace).size(), workplace.plot_type.workers], workplace])
	if not _settler.job_id.is_empty():
		lines.append(["No job", null])
	_show_choices("Work where?" if not options.is_empty() else "No working workplace has a free place.", lines, func(workplace):
		manager.assign_job(_settler, workplace))


func _show_choices(title: String, lines: Array, pick: Callable) -> void:
	_clear_choices()
	_choices_title.text = title
	_choices_title.visible = true
	_buttons.visible = false
	for line in lines:
		var choice := _button(line[0])
		choice.custom_minimum_size.x = WIDTH - 40
		var target = line[1]
		choice.pressed.connect(func():
			pick.call(target)
			_clear_choices()
			_refresh())
		_choices.add_child(choice)
	var cancel := _button("Back")
	cancel.pressed.connect(_clear_choices)
	_choices.add_child(cancel)


func _clear_choices() -> void:
	for child in _choices.get_children():
		child.queue_free()
	_choices_title.visible = false
	_buttons.visible = true


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String) -> Button:
	var button := MenuStyle.button(text)
	button.custom_minimum_size = Vector2(150, 38)
	button.add_theme_font_size_override("font_size", 16)
	return button
