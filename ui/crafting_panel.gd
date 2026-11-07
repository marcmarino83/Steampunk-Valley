extends HBoxContainer
## The Crafting tab: a scrolling list of recipes on the left, and the chosen one's details on
## the right.

signal craft_requested(recipe: Recipe)

const COST_SLOT_SCENE = preload("res://ui/inventory_slot.tscn")
const ROW_COLOR := Color(0.2, 0.16, 0.12)
const ROW_SELECTED_COLOR := Color(0.36, 0.26, 0.15)
const ROW_BORDER := Color(0.45, 0.28, 0.16)
const ROW_SELECTED_BORDER := Color(0.98, 0.78, 0.32)
## How dark a recipe's row goes when you can't make it right now
const UNAVAILABLE_TINT := Color(0.6, 0.6, 0.6)
## The little picture on the row of a recipe that needs a crafting station, and what to call the
## station when you're not near one. A new station (a forge, say) adds a line to each.
const STATION_ICONS := {
	"workbench": preload("res://assets/buildables/workbench/icon.png"),
}
const STATION_NAMES := {
	"workbench": "a workbench",
}

@onready var list: VBoxContainer = $ListScroll/List
@onready var large_icon: TextureRect = $Details/LargeIcon
@onready var name_label: Label = $Details/NameLabel
@onready var description_label: Label = $Details/DescriptionLabel
@onready var used_for_label: Label = $Details/UsedForLabel
@onready var cost_grid: GridContainer = $Details/CostGrid
@onready var status_label: Label = $Details/StatusLabel
@onready var craft_button: Button = $Details/CraftButton

var _recipes: Array[Recipe] = []
var _rows: Array[Button] = []
var _selected: Recipe
var _inventory := {}
# The crafting stations within reach right now ("hand" is always there)
var _stations: PackedStringArray = ["hand"]


func _ready() -> void:
	_recipes = _load_recipes()
	var group := ButtonGroup.new()
	for recipe in _recipes:
		var row := _make_row(recipe)
		row.button_group = group
		row.pressed.connect(_select.bind(recipe))
		list.add_child(row)
		_rows.append(row)
	craft_button.pressed.connect(func(): craft_requested.emit(_selected))


## Brings the list and details up to date. Unlocked recipes all show; ones that need a station
## you're not near are greyed out, saying which station they need.
func refresh(inventory: Dictionary, stations: PackedStringArray, is_unlocked: Callable) -> void:
	_inventory = inventory
	_stations = stations
	var first_shown: Recipe
	var selected_shown := false
	for i in _recipes.size():
		var shown: bool = is_unlocked.call(_recipes[i])
		_rows[i].visible = shown
		var makeable := stations.has(_recipes[i].station) and _recipes[i].can_craft(inventory)
		_rows[i].modulate = Color.WHITE if makeable else UNAVAILABLE_TINT
		if shown and first_shown == null:
			first_shown = _recipes[i]
		if shown and _recipes[i] == _selected:
			selected_shown = true
	if not selected_shown:
		_select(first_shown)
	else:
		_show_details()


## Every recipe, locked or not
func all_recipes() -> Array[Recipe]:
	return _recipes


# Every recipe file in res://crafting/ (and the iron tier's, when that's switched on)
func _load_recipes() -> Array[Recipe]:
	var found: Array[Recipe] = []
	for folder in IronTier.folders(Recipe.FOLDER, Recipe.TIER_FOLDER):
		var files := ResourceLoader.list_directory(folder)
		files.sort()
		for file in files:
			if file.ends_with(".tres"):
				var recipe := load(folder.path_join(file)) as Recipe
				if recipe:
					found.append(recipe)
	return found


## True if there's anything here you could make right now
func anything_craftable(inventory: Dictionary, stations: PackedStringArray, is_unlocked: Callable) -> bool:
	for recipe in _recipes:
		if stations.has(recipe.station) and is_unlocked.call(recipe) and recipe.can_craft(inventory):
			return true
	return false


## Shows a line above the Craft button, like "Inventory full"
func show_status(text: String, is_problem: bool) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", InventorySlot.MISSING_COLOR if is_problem else InventorySlot.COUNT_COLOR)


func _select(recipe: Recipe) -> void:
	_selected = recipe
	for i in _recipes.size():
		_rows[i].set_pressed_no_signal(_recipes[i] == recipe)
	_show_details()


func _show_details() -> void:
	# Any message was about how things stood before, so it goes when anything changes
	status_label.text = ""
	var has_recipe := _selected != null
	$Details.visible = has_recipe
	if not has_recipe:
		return
	large_icon.texture = _selected.icon if _selected.icon else InventorySlot.icon_for(_selected.result)
	name_label.text = _selected.display_name
	description_label.text = _selected.description
	used_for_label.text = "Used for: %s" % _selected.used_for

	# One slot per ingredient, reusing what's already there
	var items := _selected.costs.keys()
	while cost_grid.get_child_count() < items.size():
		var slot := COST_SLOT_SCENE.instantiate()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_grid.add_child(slot)
	for i in cost_grid.get_child_count():
		var slot := cost_grid.get_child(i)
		slot.visible = i < items.size()
		if slot.visible:
			slot.set_cost(items[i], _inventory.get(items[i], 0), _selected.costs[items[i]])

	var at_station := _stations.has(_selected.station)
	craft_button.disabled = not (at_station and _selected.can_craft(_inventory))
	if not at_station:
		show_status("Requires %s." % STATION_NAMES.get(_selected.station, _selected.station), true)
	elif _selected.already_owned(_inventory):
		show_status("You already have one", false)


func _make_row(recipe: Recipe) -> Button:
	var row := Button.new()
	row.text = recipe.display_name
	row.icon = recipe.icon if recipe.icon else InventorySlot.icon_for(recipe.result)
	row.toggle_mode = true
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(0, 56)
	row.add_theme_constant_override("icon_max_width", 40)
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_font_size_override("font_size", 15)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		row.add_theme_color_override(state, Color(0.94, 0.8, 0.55))
	row.add_theme_stylebox_override("normal", _row_style(ROW_COLOR, ROW_BORDER))
	row.add_theme_stylebox_override("hover", _row_style(ROW_COLOR.lightened(0.08), ROW_BORDER))
	row.add_theme_stylebox_override("pressed", _row_style(ROW_SELECTED_COLOR, ROW_SELECTED_BORDER))
	row.add_theme_stylebox_override("hover_pressed", _row_style(ROW_SELECTED_COLOR, ROW_SELECTED_BORDER))
	# Recipes made at a station carry its picture, small, at the right-hand end of the row
	if STATION_ICONS.has(recipe.station):
		var mark := TextureRect.new()
		mark.texture = STATION_ICONS[recipe.station]
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.anchor_left = 1.0
		mark.anchor_right = 1.0
		mark.anchor_top = 0.5
		mark.anchor_bottom = 0.5
		mark.offset_left = -32
		mark.offset_right = -6
		mark.offset_top = -13
		mark.offset_bottom = 13
		row.add_child(mark)
	return row


func _row_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	return style
