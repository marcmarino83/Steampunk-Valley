extends Control

## A tool from the action bar was dragged back to the backpack
signal tool_returned(item: String)
## With a chest open: a whole stack is to move from one container ("backpack" or "chest") to the
## other (dragged across, or shift-clicked)
signal item_moved(item: String, from: String)

const SLOT_SCENE = preload("res://ui/inventory_slot.tscn")
const CHEST_SLOTS := 20

## How many slots the backpack has. Empty ones still show.
@export var slot_count := 20

@onready var grid: GridContainer = $Center/Panel/VBox/Grid
@onready var crafting: Control = $Center/Panel/VBox/CraftingPanel
@onready var inventory_tab: Button = $Center/Panel/VBox/Tabs/InventoryTab
@onready var crafting_tab: Button = $Center/Panel/VBox/Tabs/CraftingTab
@onready var panel: PanelContainer = $Center/Panel

# The chest's panel, beside the backpack while a chest is open
var _chest_panel: PanelContainer
var _chest_grid: GridContainer
var _chest_open := false


func _ready() -> void:
	for i in slot_count:
		_add_slot(grid, "backpack")
	# The backpack and the chest side by side
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	$Center.add_child(row)
	panel.reparent(row)
	_build_chest_panel(row)
	# Letting go of a tool anywhere outside the action bar returns it to the backpack; letting go
	# of something from the chest over the backpack's panel moves it to the backpack, and the
	# other way round over the chest's panel
	for target in [self, $Dim]:
		target.set_drag_forwarding(Callable(), _can_take_back, _take_back)
	panel.set_drag_forwarding(Callable(), _can_drop_on.bind("backpack"), _drop_on.bind("backpack"))
	_chest_panel.set_drag_forwarding(Callable(), _can_drop_on.bind("chest"), _drop_on.bind("chest"))
	var tabs := ButtonGroup.new()
	inventory_tab.button_group = tabs
	crafting_tab.button_group = tabs
	inventory_tab.pressed.connect(show_tab.bind(false))
	crafting_tab.pressed.connect(show_tab.bind(true))
	show_tab(false)


## Switches between the Inventory and Crafting tabs
func show_tab(show_crafting: bool) -> void:
	grid.visible = not show_crafting
	crafting.visible = show_crafting
	inventory_tab.set_pressed_no_signal(not show_crafting)
	crafting_tab.set_pressed_no_signal(show_crafting)
	_chest_panel.visible = _chest_open and not show_crafting


## Fills the slots from the player's inventory, in the order things were picked up
func show_items(inventory: Dictionary) -> void:
	var items := inventory.keys()
	# Carrying more kinds of thing than there are slots? Grow the backpack.
	while grid.get_child_count() < items.size():
		_add_slot(grid, "backpack")
	_fill(grid, inventory)


## Opens a chest's panel beside the backpack, showing what's in it
func show_chest(contents: Dictionary) -> void:
	_chest_open = true
	show_tab(false)
	_fill(_chest_grid, contents)
	for slot in grid.get_children() + _chest_grid.get_children():
		slot.trading = true


func hide_chest() -> void:
	_chest_open = false
	_chest_panel.visible = false
	for slot in grid.get_children() + _chest_grid.get_children():
		slot.trading = false


func is_chest_open() -> bool:
	return _chest_open


func _fill(slots_grid: GridContainer, contents: Dictionary) -> void:
	var items := contents.keys()
	var slots := slots_grid.get_children()
	for i in slots.size():
		if i < items.size():
			slots[i].set_item(items[i], contents[items[i]])
		else:
			slots[i].clear()


func _add_slot(slots_grid: GridContainer, container: String) -> void:
	var slot := SLOT_SCENE.instantiate()
	slot.container = container
	slot.trading = _chest_open
	slots_grid.add_child(slot)
	slot.tool_returned.connect(tool_returned.emit)
	slot.item_moved.connect(item_moved.emit)
	slot.quick_move.connect(item_moved.emit)


# The chest's panel: the same look as the backpack's, with its own 20-slot grid
func _build_chest_panel(row: HBoxContainer) -> void:
	_chest_panel = PanelContainer.new()
	_chest_panel.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel"))
	_chest_panel.visible = false
	row.add_child(_chest_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_chest_panel.add_child(column)
	var title := Label.new()
	title.text = "Chest"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.94, 0.8, 0.55))
	title.custom_minimum_size = Vector2(0, 36)
	column.add_child(title)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = grid.columns
	_chest_grid.add_theme_constant_override("h_separation", 8)
	_chest_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_chest_grid)
	for i in CHEST_SLOTS:
		_add_slot(_chest_grid, "chest")
	var hint := Label.new()
	hint.text = "Drag to move a stack across\nShift-click to move it quickly"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.62, 0.5))
	column.add_child(hint)


func _can_take_back(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from_bar", false)


func _take_back(_at_position: Vector2, data: Variant) -> void:
	tool_returned.emit(data["tool_item"])


# Dropping on a panel (between its slots): something from the other container moves here; a tool
# from the action bar goes back to the backpack, or into the chest
func _can_drop_on(_at_position: Vector2, data: Variant, here: String) -> bool:
	if not data is Dictionary:
		return false
	if data.get("from_bar", false):
		return here == "backpack" or _chest_open
	return _chest_open and data.has("item") and data.get("from", "") != here


func _drop_on(_at_position: Vector2, data: Variant, here: String) -> void:
	if data.get("from_bar", false):
		if here == "backpack":
			tool_returned.emit(data["tool_item"])
		else:
			item_moved.emit(data["tool_item"], "backpack")
		return
	item_moved.emit(data["item"], data["from"])
