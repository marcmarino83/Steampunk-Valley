extends Control
## The hammer's build menu. It looks just like the inventory screen, with tabs across the top
## (Q and R move between them; E closes it), and lists every Buildable resource in res://buildables/ (and its
## folders) under the tab its `section` names. Adding a buildable never means changing this script.
##
## The Buildings tab has a row for each plot type: its templates (built-in ones, then the player's,
## each with its picture and what building it costs; see BuildingTemplate), then "Empty plot", which
## marks out a plot by drawing it as before. Right-clicking a template (or its ✕ while hovering)
## offers Rename and Delete, each confirmed (see TemplateActions).

signal chosen(buildable: Buildable)
## A template was deleted (whatever was put aside to place it shouldn't come back)
signal template_deleted(template: BuildingTemplate)

const SLOT_SCENE = preload("res://ui/build_slot.tscn")
const BUILDABLES_FOLDER := "res://buildables"
## The tabs in order. A buildable with no section (or one not listed) goes under "Other".
const TABS := ["Foundations", "Floors", "Walls", "Roofs", "Beams & Pillars", "Stairs & Doors", "Round", "Furniture", "Paths", "Other", "Buildings"]
const FALLBACK_TAB := "Other"
const BUILDINGS_TAB := "Buildings"
const COLUMNS := 6
## Room kept free above and below the list, so a short screen scrolls it instead of cutting it off
const SCREEN_MARGIN := 280.0

@onready var grid: GridContainer = $Center/Panel/VBox/Grid
@onready var detail_label: Label = $Center/Panel/VBox/Detail
@onready var hint_label: Label = $Center/Panel/VBox/Hint

var _buildables: Array[Buildable] = []
# Every slot and what it shows: [[slot, buildable], ...]
var _entries: Array = []
var _scroll: ScrollContainer
# Each tab's button and page of slots, in TABS order
var _tab_buttons: Array[Button] = []
var _tab_pages: Array[Container] = []
var _tab := 0
var _inventory := {}
# Says whether the player has unlocked a buildable yet
var _is_unlocked: Callable = func(_b): return true
# The buildable under the mouse, whose details are showing
var _hovered: Buildable
# Rename and Delete for a template, over the menu
var _actions: TemplateActions


func _ready() -> void:
	_buildables = _load_buildables()
	var column := grid.get_parent()
	var frame := BrassStyle.frame("panel")
	$Center/Panel.add_theme_stylebox_override("panel", frame)
	MenuStyle.enlarge($Center/Panel)
	# Tabs across the top, then the tab's slots (scrolling if the screen is short) in place of the
	# scene's single grid
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	column.add_child(tab_row)
	column.move_child(tab_row, grid.get_index())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	column.move_child(_scroll, grid.get_index())
	grid.queue_free()
	var pages := VBoxContainer.new()
	_scroll.add_child(pages)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var button := _tab_button(TABS[i])
		button.button_group = group
		button.pressed.connect(show_tab.bind(i))
		tab_row.add_child(button)
		_tab_buttons.append(button)
		var page: Container
		if TABS[i] == BUILDINGS_TAB:
			var rows := VBoxContainer.new()
			rows.add_theme_constant_override("separation", 10)
			page = rows
		else:
			var page_grid := GridContainer.new()
			page_grid.columns = COLUMNS
			page_grid.add_theme_constant_override("h_separation", 8)
			page_grid.add_theme_constant_override("v_separation", 8)
			page = page_grid
		pages.add_child(page)
		_tab_pages.append(page)
	for buildable in _buildables:
		if _tab_of(buildable) == TABS.find(BUILDINGS_TAB):
			continue
		_tab_pages[_tab_of(buildable)].add_child(_make_slot(buildable))
	_fill_buildings_tab()
	hint_label.text = "[Q] / [R] Change tab   [E], [Tab] or [Esc] Close"
	# The palette (see BrassStyle)
	(column.get_node("Title") as Label).add_theme_color_override("font_color", BrassStyle.HEADING)
	(column.get_node("Title") as Label).add_theme_font_override("font", BrassStyle.title_font())
	detail_label.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	hint_label.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	_actions = TemplateActions.new()
	add_child(_actions)
	_actions.template_deleted.connect(func(template: BuildingTemplate):
		template_deleted.emit(template)
		reload_templates())
	_actions.template_renamed.connect(func(_template): reload_templates())
	# The mouse leaving a closed menu doesn't count as leaving a slot, so clear up on closing
	hidden.connect(func():
		_actions.close()
		_hovered = null
		_update_detail())
	visibility_changed.connect(_fit_to_screen)
	get_viewport().size_changed.connect(_fit_to_screen)
	show_tab(0)


## Shows one tab's pieces
func show_tab(index: int) -> void:
	_tab = wrapi(index, 0, TABS.size())
	for i in TABS.size():
		_tab_pages[i].visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	_hovered = null
	_update_detail()
	_fit_to_screen.call_deferred()


## The name of the tab showing ("Buildings"...)
func current_tab_name() -> String:
	return TABS[_tab]


## Moves to the next tab (+1) or the one before (-1), going round
func cycle_tab(step: int) -> void:
	show_tab(_tab + step)


## Keeps every slot up to date whenever what you own or what you've unlocked changes
func watch(inventory: PlayerInventory, progress: Progress) -> void:
	var update := func(): refresh(inventory.items, progress.is_unlocked)
	inventory.changed.connect(update)
	progress.learned.connect(func(_names): update.call())


## Brings every slot up to date with what's in your pockets and what you've unlocked
func refresh(inventory: Dictionary, is_unlocked: Callable) -> void:
	_inventory = inventory
	_is_unlocked = is_unlocked
	for entry in _entries:
		var buildable: Buildable = entry[1]
		var unlocked := _unlocked(buildable)
		entry[0].show_buildable(buildable, unlocked and buildable.can_afford(inventory), not unlocked)
	_update_detail()


## Every buildable, locked or not (templates aren't blueprints of their own: they unlock with
## their plot type)
func all_buildables() -> Array[Buildable]:
	return _buildables


## Reads the templates again (one was just saved) and remakes the Buildings tab
func reload_templates() -> void:
	_hovered = null
	_fill_buildings_tab()
	refresh(_inventory, _is_unlocked)
	_fit_to_screen.call_deferred()


# The Buildings tab: for each plot type, a heading and a row of its templates, then "Empty plot"
func _fill_buildings_tab() -> void:
	var page := _tab_pages[TABS.find(BUILDINGS_TAB)]
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	# Only the Buildings tab holds plot types and templates
	_entries = _entries.filter(func(e): return not (e[1] is PlotType or e[1] is TemplateBuildable))
	var templates := BuildingTemplate.load_all()
	for buildable in _buildables:
		if not buildable is PlotType:
			continue
		var type := buildable as PlotType
		var heading := BrassStyle.heading(type.display_name)
		heading.add_theme_font_size_override("font_size", 17)
		page.add_child(heading)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		page.add_child(row)
		for template in templates:
			if template.plot_type == type or template.plot_type.resource_path == type.resource_path:
				row.add_child(_make_slot(TemplateBuildable.of(template)))
		var empty := _make_slot(type)
		empty.title_override = "Empty plot"
		row.add_child(empty)


## True while a template's Rename / Delete is showing (it takes the keys; Esc steps back out of it)
func template_actions_open() -> bool:
	return _actions != null and _actions.is_open()


func _make_slot(buildable: Buildable) -> Control:
	var slot := SLOT_SCENE.instantiate()
	slot.chosen.connect(chosen.emit)
	slot.hover_changed.connect(_on_hover_changed)
	slot.options_requested.connect(func(b: Buildable):
		if b is TemplateBuildable:
			_actions.open((b as TemplateBuildable).template))
	_entries.append([slot, buildable])
	return slot


# A template unlocks with its plot type
func _unlocked(buildable: Buildable) -> bool:
	if buildable is TemplateBuildable:
		return _is_unlocked.call((buildable as TemplateBuildable).plot_type)
	return _is_unlocked.call(buildable)


# Every buildable file, sorted by tab, then by its menu order, then by file name
func _load_buildables() -> Array[Buildable]:
	var found: Array[Buildable] = []
	var files := _files_in(BUILDABLES_FOLDER)
	files.sort()
	for file in files:
		var buildable := load(file) as Buildable
		# (a retired tool isn't offered any more)
		if buildable is PathTool and (buildable as PathTool).retired:
			continue
		if buildable:
			if buildable is PieceBuildable:
				(buildable as PieceBuildable).ensure_icon()
			found.append(buildable)
	found.sort_custom(func(a, b):
		if _tab_of(a) != _tab_of(b):
			return _tab_of(a) < _tab_of(b)
		if a.menu_order != b.menu_order:
			return a.menu_order < b.menu_order
		return a.resource_path < b.resource_path)
	return found


func _files_in(folder: String) -> PackedStringArray:
	var files: PackedStringArray = []
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			files.append_array(_files_in(folder.path_join(entry.trim_suffix("/"))))
		elif entry.ends_with(".tres"):
			files.append(folder.path_join(entry))
	return files


func _tab_of(buildable: Buildable) -> int:
	if buildable is PlotType or buildable is TemplateBuildable:
		return TABS.find(BUILDINGS_TAB)
	var index := TABS.find(buildable.section)
	return index if index >= 0 else TABS.find(FALLBACK_TAB)


func _tab_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	BrassStyle.style_button(button)
	return button


# As tall as the biggest tab needs (so the menu doesn't jump between tabs), unless the screen is
# too short: then it scrolls. The Buildings tab wraps its rows to the other tabs' width.
func _fit_to_screen() -> void:
	if not is_inside_tree() or _tab_pages.is_empty():
		return
	var needed := Vector2.ZERO
	for page in _tab_pages:
		if page is GridContainer:
			var was_visible := page.visible
			page.visible = true
			needed = needed.max(page.get_combined_minimum_size())
			page.visible = was_visible
	var buildings := _tab_pages[TABS.find(BUILDINGS_TAB)]
	buildings.custom_minimum_size.x = needed.x
	var was_shown := buildings.visible
	buildings.visible = true
	needed.y = maxf(needed.y, buildings.get_combined_minimum_size().y)
	buildings.visible = was_shown
	var room := get_viewport_rect().size.y / MenuStyle.MENU_SCALE - SCREEN_MARGIN
	_scroll.custom_minimum_size = Vector2(needed.x + 12.0, minf(needed.y, maxf(room, 200.0)))


func _on_hover_changed(buildable: Buildable, hovering: bool) -> void:
	if hovering:
		_hovered = buildable
	elif _hovered == buildable:
		_hovered = null
	_update_detail()


func _update_detail() -> void:
	if _hovered == null:
		detail_label.text = ""
	elif not _unlocked(_hovered):
		var lock_of: Buildable = (_hovered as TemplateBuildable).plot_type if _hovered is TemplateBuildable else _hovered
		detail_label.text = lock_of.unlock_hint_text()
	elif _hovered is TemplateBuildable:
		var template := (_hovered as TemplateBuildable).template
		detail_label.text = "Click to lay out %s as ghosts in a new %s plot (%s m), then build its %d pieces with the hammer" % [template.template_name, template.plot_type.display_name, PlotType.size_text(Vector2i(template.size)), template.items.size()]
	elif _hovered is PlotType:
		var plot_type := _hovered as PlotType
		var housing := "  ·  One settler per bed" if not plot_type.houses_per.is_empty() else ""
		detail_label.text = "Click to mark out an empty %s plot (free)  ·  Needs %s%s" % [plot_type.display_name, plot_type.requirements_text(), housing]
	elif _hovered is PathTileType:
		var tile := _hovered as PathTileType
		if not tile.menu_hint.is_empty():
			detail_label.text = tile.menu_hint
		else:
			detail_label.text = "Click to lay %s tiles (%s a tile)" % [tile.display_name.to_lower(), tile.cost_text()]
		if not tile.can_afford(_inventory):
			detail_label.text = "Missing %s" % tile.missing_text(_inventory)
	elif _hovered is PathTool:
		detail_label.text = (_hovered as PathTool).menu_hint if not (_hovered as PathTool).menu_hint.is_empty() else "Click to paint %s (free)" % _hovered.display_name
	elif _hovered.can_afford(_inventory):
		detail_label.text = "Click to place a %s" % _hovered.display_name
	else:
		detail_label.text = "Missing %s" % _hovered.missing_text(_inventory)
	# What you're short of reads as an error; the rest quietly
	detail_label.add_theme_color_override("font_color", BrassStyle.BAD if detail_label.text.begins_with("Missing") else BrassStyle.TEXT_DIM)
