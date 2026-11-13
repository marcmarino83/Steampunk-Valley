extends Control

## A tool from the action bar was dragged back to the backpack
signal tool_returned(item: String)
## With a chest open: a whole stack is to move from one container ("backpack" or "chest") to the
## other (dragged across, or shift-clicked)
signal item_moved(item: String, from: String)
## With town storage open: Deposit resources was pressed
signal deposit_requested

const SLOT_SCENE = preload("res://ui/inventory_slot.tscn")
const CHEST_SLOTS := 20
## How many rows of town storage show at once (more scroll)
const TOWN_ROWS := 3

## How many slots the backpack has. Empty ones still show.
@export var slot_count := 20

@onready var grid: GridContainer = $Center/Panel/VBox/Grid
@onready var crafting: Control = $Center/Panel/VBox/CraftingPanel
@onready var inventory_tab: Button = $Center/Panel/VBox/Tabs/InventoryTab
@onready var crafting_tab: Button = $Center/Panel/VBox/Tabs/CraftingTab
@onready var panel: PanelContainer = $Center/Panel

# The chest's panel, beside the backpack while a chest (or town storage) is open
var _chest_panel: PanelContainer
var _chest_grid: GridContainer
var _chest_open := false
# Its title ("Chest" or "Town Storage"), and town storage's extras: slots in use, the totals by
# category, and Deposit resources
var _chest_title: Label
var _town_totals: Label
var _deposit: Button
var _chest_scroll: ScrollContainer


func _ready() -> void:
	# The shared brass look: the panel (and the chest's beside it) and the two tabs
	var frame := BrassStyle.frame("panel")
	panel.add_theme_stylebox_override("panel", frame)
	BrassStyle.style_button(inventory_tab)
	BrassStyle.style_button(crafting_tab)
	$Center/Panel/VBox/Hint.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	for i in slot_count:
		_add_slot(grid, "backpack")
	# The backpack and the chest side by side
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	$Center.add_child(row)
	panel.reparent(row)
	_build_chest_panel(row)
	MenuStyle.enlarge(row)
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


## Keeps the backpack showing what you own that isn't on the action bar, whenever either changes
func watch(inventory: PlayerInventory, bar: ActionBar) -> void:
	var update := func(): show_items(inventory.backpack_contents())
	inventory.changed.connect(update)
	bar.contents_changed.connect(update)


## Fills the slots from the player's inventory, in the order things were picked up
func show_items(inventory: Dictionary) -> void:
	var items := inventory.keys()
	# Carrying more kinds of thing than there are slots? Grow the backpack.
	while grid.get_child_count() < items.size():
		_add_slot(grid, "backpack")
	_fill(grid, inventory)


## Opens a chest's panel beside the backpack, showing what's in it
func show_chest(contents: Dictionary) -> void:
	_chest_title.text = "Chest"
	_town_totals.visible = false
	_deposit.visible = false
	_set_chest_slots(CHEST_SLOTS)
	_chest_scroll.custom_minimum_size.y = _rows_height(ceili(CHEST_SLOTS / float(grid.columns)))
	_open_chest_panel(contents)


## Opens the Town Storage panel beside the backpack: the whole pool (already sorted by
## category), how many of its slots are in use, and the totals for each category. Its slots
## scroll, TOWN_ROWS rows at a time, so the panel stays as tall as a chest's.
func show_town_storage(contents: Dictionary, capacity: int, totals: Dictionary) -> void:
	_chest_title.text = "Town Storage  ·  %d/%d slots" % [contents.size(), capacity]
	_chest_scroll.custom_minimum_size.y = _rows_height(mini(TOWN_ROWS, ceili(maxi(capacity, 1) / float(grid.columns))))
	var parts: PackedStringArray = []
	for category in totals:
		parts.append("%s %d" % [category, totals[category]])
	_town_totals.visible = true
	_town_totals.text = "  ·  ".join(parts)
	_deposit.visible = true
	_set_chest_slots(maxi(capacity, contents.size()))
	_open_chest_panel(contents)


func _open_chest_panel(contents: Dictionary) -> void:
	_chest_open = true
	show_tab(false)
	_fill(_chest_grid, contents)
	for slot in grid.get_children() + _chest_grid.get_children():
		slot.trading = true


# How tall this many rows of slots are (with the gaps between them)
func _rows_height(rows: int) -> float:
	var slot_height: float = _chest_grid.get_child(0).get_combined_minimum_size().y
	return rows * slot_height + (rows - 1) * 8.0


# Shows exactly this many slots in the chest's panel (town storage has as many as its shelves give)
func _set_chest_slots(count: int) -> void:
	while _chest_grid.get_child_count() < count:
		_add_slot(_chest_grid, "chest")
	var slots := _chest_grid.get_children()
	for i in slots.size():
		slots[i].visible = i < count


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
	_chest_title = Label.new()
	_chest_title.text = "Chest"
	_chest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chest_title.add_theme_font_size_override("font_size", 20)
	_chest_title.add_theme_color_override("font_color", BrassStyle.HEADING)
	_chest_title.add_theme_font_override("font", BrassStyle.title_font())
	_chest_title.custom_minimum_size = Vector2(0, 36)
	column.add_child(_chest_title)
	# Town storage: "Food 34 · Materials 210 · Tools 2 · Other 0" (the slots in use go in the title)
	_town_totals = Label.new()
	_town_totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_town_totals.add_theme_font_size_override("font_size", 14)
	_town_totals.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	_town_totals.visible = false
	column.add_child(_town_totals)
	# The slots scroll (town storage can hold more than fits); a chest's 20 show all at once
	_chest_scroll = ScrollContainer.new()
	_chest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Drops between the slots still reach the panel (which takes them)
	_chest_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_chest_scroll)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = grid.columns
	_chest_grid.add_theme_constant_override("h_separation", 8)
	_chest_grid.add_theme_constant_override("v_separation", 8)
	_chest_scroll.add_child(_chest_grid)
	for i in CHEST_SLOTS:
		_add_slot(_chest_grid, "chest")
	var hint := Label.new()
	hint.text = "Drag or shift-click to move a stack across"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	column.add_child(hint)
	# Town storage: every raw material and food from the backpack in one click
	_deposit = MenuStyle.button("Deposit resources")
	_deposit.custom_minimum_size = Vector2(220, 36)
	_deposit.add_theme_font_size_override("font_size", 16)
	_deposit.tooltip_text = "Moves all materials and food from your inventory into town storage (tools and the action bar stay)"
	_deposit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_deposit.pressed.connect(deposit_requested.emit)
	_deposit.visible = false
	column.add_child(_deposit)


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
