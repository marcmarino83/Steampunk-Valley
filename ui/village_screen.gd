class_name VillageScreen
extends Control
## The Village screen: the whole settlement at a glance, built on the standard panel (BrassPanel)
## and the reusable table (BrassTable). V opens and closes it (so does the Village button in the
## Village Center's plot panel); E or Esc closes it; Q and R switch tabs.
##
##   header: "Village", and summary pills: settlers / beds (always), and only when they have
##           something to say, days of food (short), visitors, and buildings needing attention
##   tabs:   Settlers · Buildings · Resources · Tech tree (the last two: coming soon)
##   Settlers: a table of everyone (name; home; job; food; what they're doing), problems coloured; then the visitors at the Village Center
##           (background, time left, Recruit). Clicking a row opens that settler's or visitor's
##           panel; closing it comes back here.
##   Buildings: every plot (type, people, a status pill, what's missing), those needing attention
##           first. Clicking a row opens its plot panel; closing it comes back here.
## Every table sorts by clicking a column's title.

## It closed
signal closed
## A row was clicked: the player opens that settler's (or visitor's) panel, or that plot's
signal settler_requested(settler: Settler)
signal plot_requested(plot: Plot)

const WIDTH := 900.0
const TABS := ["Settlers", "Buildings", "Resources", "Tech tree"]
const REFRESH_SECONDS := 0.5
## Food lasting fewer days than this shows in the header (yellow; red below FOOD_LOW)
const FOOD_SHOWN_BELOW := 7
const FOOD_LOW := 2

var manager: SettlerManager
var plots: PlotRegistry

var _panel: BrassPanel
var _pills: HBoxContainer
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _tab := 0
var _settlers_part: VBoxContainer
var _settlers_table: BrassTable
var _visitors_part: VBoxContainer
var _visitors_table: BrassTable
var _plots_part: VBoxContainer
var _plots_table: BrassTable
var _refresh_in := 0.0
var _pill_key := ""


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
	_panel.set_title("Village")
	_panel.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.status.visible = false
	_pills = HBoxContainer.new()
	_pills.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	_panel.title_row.add_child(_pills)
	_panel.subtitle.visible = false
	# The tabs, under the title
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	_panel.header.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := BrassStyle.button(TABS[i])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.x = 120
		b.pressed.connect(show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	# The pages
	var settlers_page := VBoxContainer.new()
	settlers_page.add_theme_constant_override("separation", BrassStyle.GAP_L)
	_settlers_part = _panel.section("Settlers", settlers_page)
	_settlers_table = BrassTable.create([
		{"title": "Name", "width": 230.0}, {"title": "Home", "width": 150.0}, {"title": "Job", "width": 150.0},
		{"title": "Food", "width": 110.0}, {"title": "Doing", "width": 0.0},
	], 230.0, "No settlers yet")
	_settlers_table.row_clicked.connect(func(s): if s is Settler and is_instance_valid(s): settler_requested.emit(s))
	_settlers_part.add_child(_settlers_table)
	_visitors_part = _panel.section("Visitors", settlers_page)
	_visitors_table = BrassTable.create([
		{"title": "Name", "width": 190.0}, {"title": "Background", "width": 0.0}, {"title": "Leaves", "width": 110.0},
		{"title": "", "width": 160.0, "sortable": false},
	], 130.0, "No visitors right now")
	_visitors_table.row_clicked.connect(func(s): if s is Settler and is_instance_valid(s): settler_requested.emit(s))
	_visitors_part.add_child(_visitors_table)
	var buildings_page := VBoxContainer.new()
	buildings_page.add_theme_constant_override("separation", BrassStyle.GAP_L)
	_plots_part = _panel.section("Plots", buildings_page)
	_plots_table = BrassTable.create([
		{"title": "Plot", "width": 190.0}, {"title": "Type", "width": 150.0}, {"title": "People", "width": 170.0},
		{"title": "Status", "width": 150.0}, {"title": "Missing", "width": 0.0},
	], 400.0, "No plots yet: mark one out with the hammer's build menu")
	_plots_table.row_clicked.connect(func(p): if p is Plot and is_instance_valid(p): plot_requested.emit(p))
	_plots_part.add_child(_plots_table)
	_pages = [settlers_page, buildings_page, _coming_soon("Resources"), _coming_soon("Tech tree")]
	for page in _pages:
		page.custom_minimum_size.y = 420
		_panel.body.add_child(page)
	_panel.set_hints([["Q / R", "Tabs"], ["E", "Close"]])
	show_tab(0)


## Opens it (on the tab it was last on)
func open() -> void:
	_refresh()
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func is_open() -> bool:
	return visible


## Q (-1) or R (+1): the tab before or after
func cycle_tab(direction: int) -> void:
	show_tab(posmod(_tab + direction, TABS.size()))


func show_tab(index: int) -> void:
	_tab = index
	for i in _pages.size():
		_pages[i].visible = i == index
		_tab_buttons[i].set_pressed_no_signal(i == index)
	if visible:
		_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh()


func _refresh() -> void:
	_refresh_in = REFRESH_SECONDS
	if manager == null or plots == null:
		return
	_refresh_pills()
	match _tab:
		0:
			_refresh_settlers()
		1:
			_refresh_plots()


# Settlers / beds always; food only when it's running short; visitors only when there are some;
# buildings needing attention only when there are any
func _refresh_pills() -> void:
	var settlers := manager.all_settlers().filter(func(s): return not s.leaving)
	var beds := 0
	for p in plots.all_plots():
		if SettlerManager.is_house(p) and p.is_villager_housing() and p.working:
			beds += p.capacity
	var pills := []
	pills.append(["Settlers %d  ·  beds %d" % [settlers.size(), beds], BrassStyle.GOOD if settlers.size() <= beds else BrassStyle.WARN, "Settlers, and beds in working villager Houses"])
	var days := manager.economy.days_of_food()
	if days >= 0 and days < FOOD_SHOWN_BELOW:
		pills.append(["Food %d %s" % [days, "day" if days == 1 else "days"], BrassStyle.BAD if days < FOOD_LOW else BrassStyle.WARN, "How long the stored food lasts everyone"])
	var visitors := manager.staying_visitors().size()
	if visitors > 0:
		pills.append(["Visitors %d/%d" % [visitors, SettlerManager.MAX_VISITORS], BrassStyle.INFO, "Visitors at the Village Center, waiting to be recruited"])
	var attention := plots.all_plots().filter(func(p): return _needs_attention(p)).size()
	if attention > 0:
		pills.append(["%d %s need%s attention" % [attention, "building" if attention == 1 else "buildings", "s" if attention == 1 else ""], BrassStyle.WARN, "Plots that aren't working: see the Buildings tab"])
	var key := str(pills)
	if key == _pill_key:
		return
	_pill_key = key
	for child in _pills.get_children():
		_pills.remove_child(child)
		child.queue_free()
	for p in pills:
		var pill := BrassStyle.pill(p[0], p[1])
		pill.tooltip_text = p[2]
		pill.mouse_filter = Control.MOUSE_FILTER_PASS
		_pills.add_child(pill)


func _refresh_settlers() -> void:
	var settlers := manager.all_settlers().filter(func(s): return not s.leaving)
	BrassPanel.set_heading(_settlers_part, "Settlers  %d" % settlers.size())
	var rows := []
	for s: Settler in settlers:
		var home := manager.plot(s.home_id)
		var job := manager.plot(s.job_id)
		var status := s.status_text()
		rows.append({
			"data": s,
			"cells": [
				s.settler_name,
				{"text": home.plot_name if home else "No home", "color": BrassStyle.TEXT if home else BrassStyle.WARN},
				{"text": job.plot_name if job else "—", "color": BrassStyle.TEXT if job else BrassStyle.TEXT_DIM},
				{"text": s.food_text(), "color": BrassStyle.WARN if s.is_hungry() else BrassStyle.GOOD},
				{"text": status, "color": _status_color(status), "tooltip": status},
			],
			"sort": [s.settler_name.to_lower(), home.plot_name.to_lower() if home else "~", job.plot_name.to_lower() if job else "~", s.hungry_days, status.to_lower()],
		})
	_settlers_table.set_rows(rows)
	var visitors := manager.staying_visitors()
	BrassPanel.set_heading(_visitors_part, "Visitors  %d/%d" % [visitors.size(), SettlerManager.MAX_VISITORS])
	var homes := manager.free_homes()
	var vrows := []
	for v: Settler in visitors:
		var left := v.stay_until - manager.now()
		var visitor := v
		vrows.append({
			"data": v,
			"cells": [
				v.settler_name,
				{"text": v.background, "color": BrassStyle.TEXT_DIM, "tooltip": v.background},
				{"text": _left_text(left), "color": BrassStyle.TEXT_DIM},
				{"button": "Recruit", "kind": "primary", "disabled": "" if not homes.is_empty() else "Needs a free home", "reason_in_label": true,
					"tooltip": "They move into a free villager House as a settler with no job", "action": func(): _recruit(visitor)},
			],
			"sort": [v.settler_name.to_lower(), v.background.to_lower(), left, 0],
		})
	_visitors_table.set_rows(vrows)


func _refresh_plots() -> void:
	var all := plots.all_plots()
	BrassPanel.set_heading(_plots_part, "Plots  %d" % all.size())
	# Those needing attention first, then by name
	all.sort_custom(func(a, b):
		var na := _needs_attention(a)
		var nb := _needs_attention(b)
		if na != nb:
			return na
		return a.plot_name.naturalnocasecmp_to(b.plot_name) < 0)
	var rows := []
	for p: Plot in all:
		var people := _people_of(p)
		var state := _state_of(p)
		rows.append({
			"data": p,
			"cells": [
				p.plot_name,
				{"text": p.plot_type.display_name, "color": BrassStyle.TEXT_DIM},
				{"text": people[0], "color": people[1]},
				{"pill": state[0], "color": state[1]},
				{"text": ", ".join(p.missing) if not p.missing.is_empty() else "—", "color": BrassStyle.WARN if not p.missing.is_empty() else BrassStyle.TEXT_DIM},
			],
			"sort": [p.plot_name.to_lower(), p.plot_type.display_name.to_lower(), people[0].to_lower(), 0 if _needs_attention(p) else 1, ", ".join(p.missing)],
		})
	_plots_table.set_rows(rows)


# A plot needs attention when it isn't working (a Free build plot never does)
static func _needs_attention(p: Plot) -> bool:
	return not p.working and not p.plot_type.free_build


# [text, colour] for a plot's People column: a house's residents, a workplace's worker(s), the
# Village Center's visitors
func _people_of(p: Plot) -> Array:
	if SettlerManager.is_house(p):
		if not p.is_villager_housing():
			return ["Your home", BrassStyle.TEXT_DIM]
		return ["%d/%d residents" % [manager.residents(p).size(), p.capacity], BrassStyle.TEXT]
	if SettlerManager.is_workplace(p):
		var crew := manager.workers(p)
		if crew.is_empty():
			return ["No worker", BrassStyle.WARN]
		return [", ".join(crew.map(func(s): return s.settler_name)), BrassStyle.TEXT]
	if p.plot_type.draws_visitors:
		return ["%d/%d visitors" % [manager.staying_visitors().size(), SettlerManager.MAX_VISITORS], BrassStyle.TEXT]
	return ["—", BrassStyle.TEXT_DIM]


static func _state_of(p: Plot) -> Array:
	if p.plot_type.free_build:
		return ["Free build", BrassStyle.NEUTRAL]
	if p.working:
		return ["Working", BrassStyle.GOOD]
	if not p.missing.is_empty():
		return ["Missing", BrassStyle.WARN]
	return ["Not working", BrassStyle.WARN]


static func _status_color(status: String) -> Color:
	if status.begins_with("Can't") or status.begins_with("We can't") or status.begins_with("Leaving"):
		return BrassStyle.BAD
	if status.begins_with("Idle"):
		return BrassStyle.TEXT_DIM
	return BrassStyle.TEXT


static func _left_text(days: float) -> String:
	if days <= 0.5:
		return "Soon"
	var whole := roundi(days)
	return "~%d %s" % [whole, "day" if whole == 1 else "days"]


# Recruit from the table: into the one free villager House, or (with several) their panel asks which
func _recruit(visitor: Settler) -> void:
	if not is_instance_valid(visitor):
		return
	var homes := manager.free_homes()
	if homes.is_empty():
		return
	if homes.size() == 1:
		manager.recruit(visitor, homes[0])
		_refresh()
	else:
		settler_requested.emit(visitor)


func _coming_soon(tab: String) -> Control:
	var page := CenterContainer.new()
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	page.add_child(words)
	var title := BrassStyle.heading(tab)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(title)
	var soon := BrassStyle.label("Coming soon", BrassStyle.SIZE_BODY, BrassStyle.TEXT_DIM)
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(soon)
	return page
