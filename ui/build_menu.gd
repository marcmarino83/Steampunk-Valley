extends Control
## The hammer's build menu. It looks just like the inventory screen, with tabs across the top
## (Q and E move between them), and lists every Buildable resource in res://buildables/ (and its
## folders) under the tab its `section` names. Adding a buildable never means changing this script.

signal chosen(buildable: Buildable)

const SLOT_SCENE = preload("res://ui/build_slot.tscn")
const BUILDABLES_FOLDER := "res://buildables"
## The tabs in order. A buildable with no section (or one not listed) goes under "Other".
const TABS := ["Foundations", "Floors", "Walls", "Roofs", "Beams & Pillars", "Stairs & Doors", "Round", "Other"]
const FALLBACK_TAB := "Other"
const COLUMNS := 6
## Room kept free above and below the list, so a short screen scrolls it instead of cutting it off
const SCREEN_MARGIN := 280.0
const TAB_COLOR := Color(0.2, 0.16, 0.12)
const TAB_SELECTED_COLOR := Color(0.36, 0.26, 0.15)
const TAB_BORDER := Color(0.45, 0.28, 0.16)
const TAB_SELECTED_BORDER := Color(0.98, 0.78, 0.32)

@onready var grid: GridContainer = $Center/Panel/VBox/Grid
@onready var detail_label: Label = $Center/Panel/VBox/Detail
@onready var hint_label: Label = $Center/Panel/VBox/Hint

var _buildables: Array[Buildable] = []
# One slot per buildable, in the same order
var _slots: Array = []
var _scroll: ScrollContainer
# Each tab's button and grid of slots, in TABS order
var _tab_buttons: Array[Button] = []
var _tab_grids: Array[GridContainer] = []
var _tab := 0
var _inventory := {}
# Says whether the player has unlocked a buildable yet
var _is_unlocked: Callable = func(_b): return true
# The buildable under the mouse, whose details are showing
var _hovered: Buildable


func _ready() -> void:
	_buildables = _load_buildables()
	var column := grid.get_parent()
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
		var page := GridContainer.new()
		page.columns = COLUMNS
		page.add_theme_constant_override("h_separation", 8)
		page.add_theme_constant_override("v_separation", 8)
		pages.add_child(page)
		_tab_grids.append(page)
	for buildable in _buildables:
		var slot := SLOT_SCENE.instantiate()
		_tab_grids[_tab_of(buildable)].add_child(slot)
		slot.chosen.connect(chosen.emit)
		slot.hover_changed.connect(_on_hover_changed)
		_slots.append(slot)
	hint_label.text = "[Q] / [E] Change tab   [Tab] or [Esc] Close"
	# The mouse leaving a closed menu doesn't count as leaving a slot, so clear up on closing
	hidden.connect(func():
		_hovered = null
		_update_detail())
	visibility_changed.connect(_fit_to_screen)
	get_viewport().size_changed.connect(_fit_to_screen)
	show_tab(0)


## Shows one tab's pieces
func show_tab(index: int) -> void:
	_tab = wrapi(index, 0, TABS.size())
	for i in TABS.size():
		_tab_grids[i].visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	_hovered = null
	_update_detail()
	_fit_to_screen.call_deferred()


## Moves to the next tab (+1) or the one before (-1), going round
func cycle_tab(step: int) -> void:
	show_tab(_tab + step)


## Brings every slot up to date with what's in your pockets and what you've unlocked
func refresh(inventory: Dictionary, is_unlocked: Callable) -> void:
	_inventory = inventory
	_is_unlocked = is_unlocked
	for i in _slots.size():
		var unlocked: bool = is_unlocked.call(_buildables[i])
		_slots[i].show_buildable(_buildables[i], unlocked and _buildables[i].can_afford(inventory), not unlocked)
	_update_detail()


## Every buildable, locked or not
func all_buildables() -> Array[Buildable]:
	return _buildables


# Every buildable file, sorted by tab, then by its menu order, then by file name
func _load_buildables() -> Array[Buildable]:
	var found: Array[Buildable] = []
	var files := _files_in(BUILDABLES_FOLDER)
	files.sort()
	for file in files:
		var buildable := load(file) as Buildable
		if buildable:
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
	var index := TABS.find(buildable.section)
	return index if index >= 0 else TABS.find(FALLBACK_TAB)


func _tab_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, Color(0.94, 0.8, 0.55))
	button.add_theme_stylebox_override("normal", _tab_style(TAB_COLOR, TAB_BORDER))
	button.add_theme_stylebox_override("hover", _tab_style(TAB_COLOR.lightened(0.08), TAB_BORDER))
	button.add_theme_stylebox_override("pressed", _tab_style(TAB_SELECTED_COLOR, TAB_SELECTED_BORDER))
	button.add_theme_stylebox_override("hover_pressed", _tab_style(TAB_SELECTED_COLOR, TAB_SELECTED_BORDER))
	return button


func _tab_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


# As tall as the biggest tab needs (so the menu doesn't jump between tabs), unless the screen is
# too short: then it scrolls
func _fit_to_screen() -> void:
	if not is_inside_tree() or _tab_grids.is_empty():
		return
	var needed := Vector2.ZERO
	for page in _tab_grids:
		var was_visible := page.visible
		page.visible = true
		needed = needed.max(page.get_combined_minimum_size())
		page.visible = was_visible
	var room := get_viewport_rect().size.y - SCREEN_MARGIN
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
	elif not _is_unlocked.call(_hovered):
		detail_label.text = _hovered.unlock_hint_text()
	elif _hovered.can_afford(_inventory):
		detail_label.text = "Click to place a %s" % _hovered.display_name
	else:
		detail_label.text = "Missing %s" % _hovered.missing_text(_inventory)
