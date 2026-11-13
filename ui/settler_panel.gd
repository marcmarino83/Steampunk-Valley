class_name SettlerPanel
extends Control
## A settler's or visitor's panel, opened with E aimed at them, built on the standard panel
## (BrassPanel), kept up to date while it's open.
##
## A settler: their name, a status pill (Working, On the way, Idle, Can't work...); their home, job, food ("Fed", "Hungry (2 days)") and what
## they're doing; Assign home and Assign job. Each lists the working plots with a free place (and
## "No home" / "No job" to move them out); picking one assigns it. Homes are only villager housing
## (never a Player home).
##
## A visitor: their name, "Visiting", how long they'll stay, and a line of background, with Not now
## and Recruit. Recruit needs a working villager House with a free bed (it reads "Needs a free home"
## otherwise); with more than one, it asks which. They move in as a settler with no job.

## It closed (the mouse goes back to looking around)
signal closed

const WIDTH := 380.0
const REFRESH_SECONDS := 0.3

var manager: SettlerManager

var _settler: Settler
var _panel: BrassPanel
var _background: Label
var _facts: GridContainer
# A list of choices (homes, jobs, Houses to recruit into), in place of the facts while it shows
var _choices_part: VBoxContainer
var _choices: VBoxContainer
var _assign_home: Button
var _assign_job: Button
var _not_now: Button
var _recruit: Button
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
	_panel = BrassPanel.create(center, WIDTH)
	_background = BrassStyle.label("", BrassStyle.SIZE_BODY, BrassStyle.TEXT)
	_background.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_background.custom_minimum_size.x = WIDTH
	_panel.body.add_child(_background)
	_facts = BrassPanel.facts(_panel.body)
	_choices_part = _panel.section("Choose")
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	_choices_part.add_child(_choices)
	_choices_part.visible = false
	_assign_home = _panel.add_action(BrassStyle.button("Assign home  ▾"))
	_assign_home.tooltip_text = "Move them into a working villager House with a free bed"
	_assign_home.pressed.connect(_list_homes)
	_assign_job = _panel.add_action(BrassStyle.button("Assign job  ▾"))
	_assign_job.tooltip_text = "Give them a place at a working workplace"
	_assign_job.pressed.connect(_list_jobs)
	_not_now = _panel.add_action(BrassStyle.button("Not now"))
	_not_now.tooltip_text = "They'll stay around the Village Center for a while"
	_not_now.pressed.connect(close)
	_recruit = _panel.add_action(BrassStyle.button("Recruit", "primary"))
	_recruit.pressed.connect(_on_recruit)


func open(settler: Settler) -> void:
	_settler = settler
	_clear_choices()
	_refresh()
	show()


func is_open() -> bool:
	return visible


## Esc or E: closes a list of choices, or the panel
func dismiss() -> void:
	if _choices_part.visible:
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
	var visiting: bool = _settler.visitor
	var choosing := _choices_part.visible
	_panel.set_title(_settler.settler_name)
	_background.text = "\"%s\"" % _settler.background if not _settler.background.is_empty() else ""
	_background.visible = visiting and not _settler.background.is_empty() and not choosing
	_facts.visible = not choosing
	_assign_home.visible = not visiting and not choosing
	_assign_job.visible = not visiting and not choosing
	_not_now.visible = visiting and not choosing
	_recruit.visible = visiting and not choosing
	_panel.set_hints([["E", "Back" if choosing else "Close"]])
	var status := _settler.status_text()
	if visiting:
		var leaving: bool = _settler.leaving
		_panel.set_status("Moving on" if leaving else "Visiting", BrassStyle.NEUTRAL if leaving else BrassStyle.INFO)
		# (the pill already says they're visiting; no free home, and Recruit says so itself)
		_panel.set_subtitle("" if leaving else _stay_text())
		if _panel.badges.get_child_count() > 0:
			_panel.set_badges([])
		var homes := manager.free_homes()
		var rows := []
		if not homes.is_empty():
			rows.append(["Free homes", "%d villager %s with a free bed" % [homes.size(), "House" if homes.size() == 1 else "Houses"]])
		rows.append(["Doing", status, BrassStyle.TEXT_DIM])
		_panel.set_facts(_facts, rows)
		BrassStyle.set_disabled_reason(_recruit, "" if not homes.is_empty() else "Needs a free home",
				"Recruit", true)
		if not homes.is_empty():
			_recruit.tooltip_text = "They move into a free villager House as a settler with no job"
		else:
			_recruit.tooltip_text = SettlerHints.VISITOR_HOME
		return
	var state := _state_of(status)
	_panel.set_status(state[0], state[1])
	# (no subtitle: the name, pill and facts say who they are; but hungry with the only food out
	# of their reach, it says where food has to go)
	var food_hint: bool = _settler.is_hungry() and SettlerHints.food_out_of_reach(manager)
	_panel.set_subtitle(SettlerHints.FOOD_PLACE if food_hint else "")
	# (quest villagers aren't marked: they never leave, but nothing says so)
	var home := manager.plot(_settler.home_id)
	var job := manager.plot(_settler.job_id)
	_panel.set_facts(_facts, [
		["Home", home.plot_name if home else "None", BrassStyle.TEXT if home else BrassStyle.TEXT_DIM],
		["Job", job.plot_name if job else "None", BrassStyle.TEXT if job else BrassStyle.TEXT_DIM],
		["Food", _settler.food_text(), BrassStyle.WARN if _settler.is_hungry() else BrassStyle.GOOD],
		["Doing", status, state[1] if state[1] != BrassStyle.GOOD else BrassStyle.TEXT],
	])


# The status pill for what they're doing: [text, colour]
func _state_of(status: String) -> Array:
	if status.begins_with("Can't") or status.begins_with("We can't"):
		return ["Can't work", BrassStyle.BAD]
	if status.begins_with("Leaving"):
		return ["Leaving", BrassStyle.BAD]
	if status.begins_with("Working"):
		return ["Working", BrassStyle.GOOD]
	if status.begins_with("Walking") or status.begins_with("Heading"):
		return ["On the way", BrassStyle.INFO]
	if status.begins_with("Sleeping"):
		return ["Asleep", BrassStyle.NEUTRAL]
	if status.begins_with("Idle"):
		return ["Idle", BrassStyle.NEUTRAL]
	return ["At home", BrassStyle.NEUTRAL]


# "Leaves in about a day", from how long their stay has left
func _stay_text() -> String:
	var left: float = _settler.stay_until - manager.now()
	if left <= 0.5:
		return "Leaving soon"
	var days := roundi(left)
	return "Leaves in about %s" % ("a day" if days <= 1 else "%d days" % days)


func _list_homes() -> void:
	var options := manager.free_homes().filter(func(p): return p.plot_id != _settler.home_id)
	var lines := []
	for house in options:
		lines.append(["%s  (%d/%d beds taken)" % [house.plot_name, manager.residents(house).size(), house.capacity], house])
	if not _settler.home_id.is_empty():
		lines.append(["No home", null])
	_show_choices("Move into which House?" if not options.is_empty() else "No working villager House has a free bed", lines, func(house):
		manager.assign_home(_settler, house))


func _list_jobs() -> void:
	var options := manager.free_jobs().filter(func(p): return p.plot_id != _settler.job_id)
	var lines := []
	for workplace in options:
		lines.append(["%s  (%d/%d workers)" % [workplace.plot_name, manager.workers(workplace).size(), workplace.plot_type.workers], workplace])
	if not _settler.job_id.is_empty():
		lines.append(["No job", null])
	_show_choices("Work where?" if not options.is_empty() else "No working workplace has a free place", lines, func(workplace):
		manager.assign_job(_settler, workplace))


# Recruit: straight into the one free villager House, or a choice of them
func _on_recruit() -> void:
	var homes := manager.free_homes()
	if homes.is_empty():
		return
	if homes.size() == 1:
		_recruit_into(homes[0])
		return
	var lines := []
	for house in homes:
		lines.append(["%s  (%d/%d beds taken)" % [house.plot_name, manager.residents(house).size(), house.capacity], house])
	_show_choices("Move into which House?", lines, _recruit_into)


func _recruit_into(house) -> void:
	if house is Plot and manager.recruit(_settler, house):
		_clear_choices()
		_refresh()


func _show_choices(heading: String, lines: Array, pick: Callable) -> void:
	_clear_choices()
	BrassPanel.set_heading(_choices_part, heading)
	_choices_part.visible = true
	for line in lines:
		var choice := BrassStyle.button(line[0])
		choice.custom_minimum_size.x = WIDTH
		var target = line[1]
		choice.pressed.connect(func():
			pick.call(target)
			_clear_choices()
			_refresh())
		_choices.add_child(choice)
	var back := BrassStyle.button("Back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(func():
		_clear_choices()
		_refresh())
	_choices.add_child(back)
	_refresh()


func _clear_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_choices_part.visible = false
