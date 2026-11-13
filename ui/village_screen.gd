class_name VillageScreen
extends Control
## The Village screen: the whole settlement at a glance, built on the standard panel (BrassPanel)
## and the reusable table (BrassTable). V opens and closes it (so does the Village button in the
## Village Center's plot panel); E or Esc closes it; Q and R switch tabs.
##
##   header: "Village", and summary pills: settlers / beds (always), and only when they have
##           something to say, days of food (short), visitors, and buildings needing attention
##   tabs:   Settlers · Buildings · Resources · Tech tree (the last: coming soon)
##   Settlers: a table of everyone (name; home; job; food; what they're doing), problems coloured; then the visitors at the Village Center
##           (background, time left, Recruit). Clicking a row opens that settler's or visitor's
##           panel; closing it comes back here.
##   Buildings: every plot (type, people, a status pill, what's missing), those needing attention
##           first. Clicking a row opens its plot panel; closing it comes back here.
##   Resources: the village ledger (VillageLedger): every resource made, used or stored, in
##           collapsible groups (Food, Building materials, Crafting materials, Tools), with
##           tomorrow's planned made and used per day and what's in storage; shortages red, first
##           in their group, with days left. Clicking a row opens its detail panel (where it comes
##           from, with the producing buildings' own sliders; where it goes); E goes back.
## Every table sorts by clicking a column's title.

## It closed
signal closed
## A row was clicked: the player opens that settler's (or visitor's) panel, or that plot's
signal settler_requested(settler: Settler)
signal plot_requested(plot: Plot)

const WIDTH := 900.0
## The resource detail panel's width (layout pixels)
const DETAIL_WIDTH := 440.0
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
# Resources: the storage line, and each category's group: {"box", "toggle", "pill", "table"}
var _storage_line: Label
var _groups := {}
var _closed_groups := {}
# The last ledger worked out (VillageLedger.entries)
var _ledger := {}
# The resource detail panel (in place of the main one while it's open)
var _detail: BrassPanel
var _dock: MarginContainer
var _ledger_center: CenterContainer
var _detail_item := ""
var _detail_facts: GridContainer
var _sources_part: VBoxContainer
var _sources_box: VBoxContainer
var _uses_part: VBoxContainer
var _uses_box: VBoxContainer
var _detail_key := ""
# Each source's line in the detail panel, and the sliders of those with shared output
var _source_lines: Array[Label] = []
var _detail_sliders: Array[ShareSliders] = []


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
	_pages = [settlers_page, buildings_page, _resources_page(), _coming_soon("Tech tree")]
	for page in _pages:
		page.custom_minimum_size.y = 420
		_panel.body.add_child(page)
	_panel.set_hints([["Q / R", "Tabs"], ["E", "Close"]])
	_build_detail(center)
	show_tab(0)


## Opens it (on the tab it was last on)
func open() -> void:
	_show_detail("")
	_refresh()
	show()


func close() -> void:
	if not visible:
		return
	_show_detail("")
	hide()
	closed.emit()


## E or Esc: closes a resource's detail panel (back to the ledger) and says true; false if there
## was none open (then the screen itself closes)
func back() -> bool:
	if _detail_item.is_empty():
		return false
	_show_detail("")
	_refresh()
	return true


func is_open() -> bool:
	return visible


## Q (-1) or R (+1): the tab before or after
func cycle_tab(direction: int) -> void:
	show_tab(posmod(_tab + direction, TABS.size()))


func show_tab(index: int) -> void:
	_show_detail("")
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
		2:
			_refresh_resources()


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


# ---- Resources: the village ledger ----

func _resources_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", BrassStyle.GAP_S)
	_storage_line = BrassStyle.label("", BrassStyle.SIZE_SMALL, BrassStyle.TEXT_DIM)
	_storage_line.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(_storage_line)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var groups := VBoxContainer.new()
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups.add_theme_constant_override("separation", BrassStyle.GAP_M)
	scroll.add_child(groups)
	for category in VillageLedger.CATEGORIES:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", BrassStyle.GAP_XS)
		groups.add_child(box)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", BrassStyle.GAP_S)
		box.add_child(top)
		var toggle := Button.new()
		toggle.flat = true
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.add_theme_font_size_override("font_size", BrassStyle.SIZE_SECTION)
		toggle.add_theme_font_override("font", BrassStyle.heading_font())
		for state in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
			toggle.add_theme_color_override(state, BrassStyle.HEADING)
		toggle.add_theme_color_override("font_hover_color", BrassStyle.HEADING.lightened(0.25))
		toggle.tooltip_text = "Show or hide this group"
		toggle.pressed.connect(func():
			_closed_groups[category] = not _closed_groups.get(category, false)
			_refresh_resources())
		top.add_child(toggle)
		var pill := BrassStyle.pill("", BrassStyle.BAD)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(pill)
		# (packed to the left, so the detail panel docked on the right covers nothing that matters)
		var table := BrassTable.create([
			{"title": "Resource", "width": 220.0}, {"title": "Made per day", "width": 130.0},
			{"title": "Used per day", "width": 130.0}, {"title": "In storage", "width": 0.0},
		], 4000.0, "None")
		table.row_clicked.connect(func(item): if item is String: _show_detail(item))
		box.add_child(table)
		_groups[category] = {"box": box, "toggle": toggle, "pill": pill, "table": table}
	return page


func _refresh_resources() -> void:
	_ledger = VillageLedger.entries(manager)
	var items: Dictionary = _ledger["items"]
	var town := plots.town
	if town.is_open():
		_storage_line.text = "Town storage  %d/%d slots" % [town.used(), town.capacity()]
		_storage_line.tooltip_text = "The Storehouses' shared storage: each slot holds any amount of one kind of item.\nIn storage counts it and the plots' own storage chests, not your own chests."
	else:
		_storage_line.text = "No working Storehouse"
		_storage_line.tooltip_text = "Output goes into each workplace's own storage chest.\nIn storage counts the plots' chests, not your own chests."
	for category in VillageLedger.CATEGORIES:
		var group: Dictionary = _groups[category]
		var list: Array = items.values().filter(func(e): return e["category"] == category)
		# Shortages first, then by name
		list.sort_custom(func(a, b):
			if a["short"] != b["short"]:
				return a["short"]
			return String(a["item"]).naturalnocasecmp_to(b["item"]) < 0)
		var shorts := list.filter(func(e): return e["short"]).size()
		var open: bool = not _closed_groups.get(category, false)
		(group["box"] as Control).visible = not list.is_empty()
		(group["toggle"] as Button).text = "%s  %s  %d" % ["▾" if open else "▸", category.to_upper(), list.size()]
		BrassStyle.set_pill(group["pill"], "%d short" % shorts if shorts > 0 else "", BrassStyle.BAD)
		(group["pill"] as Control).visible = shorts > 0
		var table: BrassTable = group["table"]
		table.visible = open
		if not open:
			continue
		var rows := []
		for e: Dictionary in list:
			var colour: Color = BrassStyle.BAD if e["short"] else BrassStyle.TEXT
			rows.append({
				"data": e["item"],
				"cells": [
					{"text": e["item"], "color": colour},
					_amount_cell(e["made"], colour),
					_amount_cell(e["used"], colour),
					{"text": _storage_text(e, _ledger["short"]), "color": colour, "tooltip": "Town storage %d  ·  plot chests %d" % [e["town"], e["chests"]]},
				],
				"sort": [String(e["item"]).to_lower(), e["made"], e["used"], e["stored"]],
			})
		table.set_rows(rows)
	if not _detail_item.is_empty():
		_refresh_detail()
		# (the window or the UI scale may have changed)
		_place_ledger()


static func _amount_cell(amount: int, colour: Color) -> Dictionary:
	if amount <= 0:
		return {"text": "—", "color": BrassStyle.TEXT_DIM if colour == BrassStyle.TEXT else colour}
	return {"text": str(amount), "color": colour}


# "20", or short: "20 · 6 days left" ("runs out tomorrow" under a day; "meals short" when the
# food doesn't cover everyone)
static func _storage_text(e: Dictionary, short_meals: int) -> String:
	var stored := str(e["stored"])
	if not e["short"]:
		return stored
	var days: int = e["days_left"]
	if days < 0:
		return "%s  ·  %d %s short" % [stored, short_meals, "meal" if short_meals == 1 else "meals"]
	if days == 0:
		return "%s  ·  runs out tomorrow" % stored
	return "%s  ·  %d %s left" % [stored, days, "day" if days == 1 else "days"]


# The detail panel, docked at the screen's right edge beside the ledger (which moves to the left
# edge while it's open, so the row stays in view): the resource's name, its numbers, where it comes
# from (with the producing buildings' sliders) and where it goes
func _build_detail(center: Control) -> void:
	_ledger_center = center
	_dock = MarginContainer.new()
	_dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		_dock.add_theme_constant_override("margin_" + side, int(MenuStyle.FIT_MARGIN))
	_dock.visible = false
	add_child(_dock)
	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.add_child(right)
	var middle := CenterContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(middle)
	_detail = BrassPanel.create(middle, DETAIL_WIDTH)
	_detail.status.visible = false
	_detail_facts = BrassPanel.facts(_detail.section("Tomorrow's plan"))
	_sources_part = _detail.section("Where it comes from")
	_sources_box = VBoxContainer.new()
	_sources_box.add_theme_constant_override("separation", BrassStyle.GAP_S)
	_sources_part.add_child(_sources_box)
	_uses_part = _detail.section("Where it goes")
	_uses_box = VBoxContainer.new()
	_uses_box.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	_uses_part.add_child(_uses_box)
	_detail.set_hints([["E", "Back"]])


## Opens a resource's detail panel in place of the ledger ("" closes it)
func _show_detail(item: String) -> void:
	_detail_item = item
	_detail_key = ""
	if _detail == null:
		return
	_dock.visible = not item.is_empty()
	_place_ledger()
	if not item.is_empty():
		_refresh_detail()


# The ledger centred, or with the detail open, against the screen's left edge
func _place_ledger() -> void:
	var shift := 0.0
	if _dock.visible:
		var holder := _panel.get_parent() as Control
		shift = maxf(get_viewport_rect().size.x - holder.size.x - MenuStyle.FIT_MARGIN * 2.0, 0.0)
	_ledger_center.offset_right = -shift


func _refresh_detail() -> void:
	var items: Dictionary = _ledger.get("items", {})
	var e: Dictionary = items.get(_detail_item, {})
	if e.is_empty():
		e = {"item": _detail_item, "category": VillageLedger.category_of(_detail_item), "made": 0, "used": 0,
			"stored": 0, "town": 0, "chests": 0, "short": false, "days_left": -1, "sources": [], "uses": []}
	var short_meals: int = _ledger.get("short", 0)
	_detail.set_title(_detail_item)
	_detail.set_subtitle(e["category"])
	if e["short"]:
		var days: int = e["days_left"]
		_detail.set_status("Runs out tomorrow" if days == 0 else ("%d %s left" % [days, "day" if days == 1 else "days"]) if days > 0 else "Short", BrassStyle.BAD)
	_detail.status.visible = e["short"]
	var colour: Color = BrassStyle.BAD if e["short"] else BrassStyle.TEXT
	_detail.set_facts(_detail_facts, [
		["Made", "%d a day" % e["made"], colour],
		["Used", "%d a day" % e["used"], colour],
		["In storage", "%d  (town storage %d, plot chests %d)" % [e["stored"], e["town"], e["chests"]], colour],
	])
	# Where it comes from: rebuilt only when the buildings (or their workers) change, so the sliders
	# aren't remade under the mouse
	var sources: Array = e["sources"]
	var key := _detail_item
	for s in sources:
		key += "|%s:%s" % [s["plot"].plot_id, ",".join(s["workers"].map(func(w): return w.settler_id))]
	if key != _detail_key:
		_detail_key = key
		for child in _sources_box.get_children():
			_sources_box.remove_child(child)
			child.queue_free()
		_source_lines.clear()
		_detail_sliders.clear()
		if sources.is_empty():
			_sources_box.add_child(BrassStyle.label("Nothing in the village makes this", BrassStyle.SIZE_BODY, BrassStyle.TEXT_DIM))
		for s in sources:
			var line := BrassStyle.label("", BrassStyle.SIZE_BODY, BrassStyle.TEXT)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_sources_box.add_child(line)
			_source_lines.append(line)
			var plot: Plot = s["plot"]
			if plot.plot_type.split_output_total > 0:
				var sliders := ShareSliders.create(plot)
				sliders.tooltip_text = "The same sliders as at the building. Changes take effect at the next dawn."
				sliders.changed.connect(_refresh_resources)
				_sources_box.add_child(sliders)
				_detail_sliders.append(sliders)
	for i in mini(sources.size(), _source_lines.size()):
		var s: Dictionary = sources[i]
		var plot: Plot = s["plot"]
		var parts: PackedStringArray = [plot.plot_name]
		var crew: Array = s["workers"]
		parts.append(", ".join(crew.map(func(w): return w.settler_name)) if not crew.is_empty() else "No worker")
		if s["share"] >= 0:
			parts.append("%d%%" % s["share"])
		parts.append("%d/day" % s["amount"])
		_source_lines[i].text = "  ·  ".join(parts)
		var idle: bool = crew.is_empty() or not plot.working
		_source_lines[i].add_theme_color_override("font_color", BrassStyle.WARN if idle else BrassStyle.TEXT)
		_source_lines[i].tooltip_text = "Not working: see the Buildings tab" if not plot.working else ""
		_source_lines[i].mouse_filter = Control.MOUSE_FILTER_PASS
	for sliders in _detail_sliders:
		sliders.sync()
	# Where it goes
	for child in _uses_box.get_children():
		_uses_box.remove_child(child)
		child.queue_free()
	var uses: Array = e["uses"]
	for u in uses:
		_uses_box.add_child(BrassStyle.label("%s  ·  %d/day" % [u["text"], u["amount"]], BrassStyle.SIZE_BODY, BrassStyle.TEXT))
	if short_meals > 0 and e["category"] == "Food":
		_uses_box.add_child(BrassStyle.label("%d %s short tomorrow" % [short_meals, "meal" if short_meals == 1 else "meals"], BrassStyle.SIZE_BODY, BrassStyle.BAD))
	if uses.is_empty() and _uses_box.get_child_count() == 0:
		_uses_box.add_child(BrassStyle.label("Nothing in the village uses this", BrassStyle.SIZE_BODY, BrassStyle.TEXT_DIM))


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
