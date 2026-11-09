class_name PlotTracker
extends Control
## The plot tracker: a compact plaque on the right of the screen, vertically centred, showing one
## plot's name and type, its status ("Working" in green, "Missing requirements" in amber) and its
## checklist ("✓ Bed 1/1", "✗ Door 0/1"). The player shows it with the hammer out while standing
## inside a plot, or aiming at one in plot view, and hides it while a menu is open. It fades in and
## out.

## Pixels at 1920 x 1080: the gap kept to the screen's edges, and the width every line wraps at
const EDGE := 24.0
const LINE_WIDTH := 320.0
## How quickly it fades in and out (per second)
const FADE := 9.0
const WORKING := Color(0.62, 0.92, 0.5)
const MISSING := Color(1.0, 0.72, 0.3)
const BUILDING := Color(0.6, 0.8, 1.0)

## The settlers (for a House's residents and a workplace's workers line)
var settlers: SettlerManager
## The plots (for a placed template's ghosts), and what the player carries (a Callable returning
## their inventory), for the building progress and materials
var plots: PlotRegistry
var carrying: Callable

var _panel: PanelContainer
var _name: Label
var _type: Label
var _status: Label
var _people: Label
# While it has ghosts: "Building: 14/32 pieces", and a line per material: needed, carrying, missing
var _building: Label
var _materials: VBoxContainer
var _lines: VBoxContainer
var _plot: Plot
var _shown_text := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", BrassStyle.frame("plate"))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	_panel.add_child(column)
	_name = _label(20, BrassStyle.TEXT)
	column.add_child(_name)
	_type = _label(14, BrassStyle.TEXT_DIM)
	column.add_child(_type)
	_status = _label(17, WORKING)
	column.add_child(_status)
	_people = _label(15, BrassStyle.TEXT)
	column.add_child(_people)
	_building = _label(16, BUILDING)
	column.add_child(_building)
	_materials = VBoxContainer.new()
	_materials.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_materials.add_theme_constant_override("separation", 1)
	column.add_child(_materials)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	column.add_child(gap)
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 1)
	column.add_child(_lines)
	# Placed again whenever its size settles (wrapped lines change its height after layout) and
	# whenever the window changes
	_panel.resized.connect(_place)
	get_viewport().size_changed.connect(_place)


## The plot to show, or null to fade out
func show_plot(plot: Plot) -> void:
	_plot = plot if is_instance_valid(plot) else null


func _process(delta: float) -> void:
	var target := 1.0 if _plot else 0.0
	modulate.a = move_toward(modulate.a, target, FADE * delta)
	visible = modulate.a > 0.001
	if _plot:
		_refresh()
	_place()


# Right side, vertically centred, always wholly on screen: shrunk to fit what it shows, then kept
# EDGE from every edge (from the top if it's taller than the screen)
func _place() -> void:
	var screen := get_viewport_rect().size
	_panel.size = _panel.get_combined_minimum_size()
	var x := clampf(screen.x - EDGE - _panel.size.x, EDGE, maxf(EDGE, screen.x - EDGE - _panel.size.x))
	var y := clampf((screen.y - _panel.size.y) / 2.0, EDGE, maxf(EDGE, screen.y - EDGE - _panel.size.y))
	_panel.position = Vector2(x, y)


# Rebuilds the text only when something in it changed
func _refresh() -> void:
	var lines: Array = _plot.checklist
	var people := _people_text()
	var build := _build_state()
	var text := "%s|%s|%s|%s|%s" % [_plot.plot_name, _plot.working, str(lines), people, str(build)]
	if text == _shown_text:
		return
	_shown_text = text
	_people.text = people
	_people.visible = not people.is_empty()
	_show_building(build)
	_name.text = _plot.plot_name
	# Its type, unless that's just its name again; and how many it houses
	var parts: PackedStringArray = []
	if _plot.plot_type.display_name != _plot.plot_name:
		parts.append(_plot.plot_type.display_name)
	if not _plot.plot_type.houses_per.is_empty():
		parts.append("Houses %d" % _plot.capacity)
	_type.text = "  ·  ".join(parts)
	_type.visible = not parts.is_empty()
	_status.text = "Working" if _plot.working else ("Under construction" if not build.is_empty() else ("Missing requirements" if _plot.checked else "Checking..."))
	_status.add_theme_color_override("font_color", WORKING if _plot.working else (BUILDING if not build.is_empty() else MISSING))
	while _lines.get_child_count() < lines.size():
		_lines.add_child(_label(15, BrassStyle.TEXT, true))
	for i in _lines.get_child_count():
		var label: Label = _lines.get_child(i)
		label.visible = i < lines.size()
		if label.visible:
			var line: Dictionary = lines[i]
			label.text = "%s %s" % ["✓" if line["ok"] else "✗", line["text"]]
			label.add_theme_color_override("font_color", WORKING if line["ok"] else MISSING)


# While the plot has ghosts: {"done", "total", "needed": {item: amount}, "carrying": {item: amount}};
# empty once it's all built
func _build_state() -> Dictionary:
	if plots == null:
		return {}
	var ghosts := plots.ghosts_of(_plot)
	if ghosts.is_empty():
		return {}
	var progress := plots.build_progress(_plot)
	var needed := plots.materials_needed(_plot)
	var inventory: Dictionary = carrying.call() if carrying.is_valid() else {}
	var have := {}
	for item in needed:
		have[item] = int(inventory.get(item, 0))
	return {"done": progress["done"], "total": progress["total"], "needed": needed, "carrying": have}


# "Building: 14/32 pieces", then "Planks  need 24 · carrying 10 · missing 14" per material (green
# when you carry enough)
func _show_building(build: Dictionary) -> void:
	_building.visible = not build.is_empty()
	_materials.visible = not build.is_empty()
	if build.is_empty():
		return
	_building.text = "Building: %d/%d pieces" % [build["done"], build["total"]]
	var needed: Dictionary = build["needed"]
	var have: Dictionary = build["carrying"]
	var items := needed.keys()
	while _materials.get_child_count() < items.size():
		_materials.add_child(_label(14, BrassStyle.TEXT, true))
	for i in _materials.get_child_count():
		var label: Label = _materials.get_child(i)
		label.visible = i < items.size()
		if not label.visible:
			continue
		var item: String = items[i]
		var missing := maxi(int(needed[item]) - int(have[item]), 0)
		label.text = "%s  need %d · carrying %d%s" % [item, needed[item], have[item], " · missing %d" % missing if missing > 0 else ""]
		label.add_theme_color_override("font_color", MISSING if missing > 0 else WORKING)


# "Residents 1/2: Ada Cobb" and "Food stored: 6 days" (for everyone in the settlement, town storage
# included) for a House, "Worker: Ada Cobb" (or "none") for a workplace, "Town storage: 14/24
# slots" for a Storehouse, else empty; the hungry are marked "(hungry)"
func _people_text() -> String:
	if settlers == null:
		return ""
	var named := func(s): return s.settler_name + (" (hungry)" if s.is_hungry() else "")
	if SettlerManager.is_house(_plot):
		var living: Array = settlers.residents(_plot)
		var names := ", ".join(living.map(named))
		var line := "Residents %d/%d: %s" % [living.size(), _plot.capacity, names if not names.is_empty() else "none"]
		var days: int = settlers.economy.days_of_food()
		if days >= 0:
			line += "\nFood stored: %d %s" % [days, "day" if days == 1 else "days"]
		return line
	if SettlerManager.is_workplace(_plot):
		var working: Array = settlers.workers(_plot)
		var names := ", ".join(working.map(named))
		return "%s: %s" % ["Worker" if _plot.plot_type.workers == 1 else "Workers", names if not names.is_empty() else "none"]
	# A Storehouse: the whole town storage (every working Storehouse together)
	if _plot.plot_type.town_storage_slots > 0 and plots:
		if not _plot.working:
			return "Town storage: closed until it's working"
		return "Town storage: %d/%d slots" % [plots.town.used(), plots.town.capacity()]
	return ""


# Every line wraps at LINE_WIDTH, so the plaque never grows wider than that, however long a plot
# name, checklist line or list of residents gets
func _label(size: int, color: Color, _wrap := true) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = LINE_WIDTH
	return label
