extends Control

## A tool from the action bar was dragged back to the backpack
signal tool_returned(item: String)

const SLOT_SCENE = preload("res://inventory_slot.tscn")

## How many slots the backpack has. Empty ones still show.
@export var slot_count := 20

@onready var grid: GridContainer = $Center/Panel/VBox/Grid


func _ready() -> void:
	for i in slot_count:
		_add_slot()
	# Letting go of a tool anywhere outside the action bar returns it to the backpack
	for target in [self, $Dim, $Center/Panel]:
		target.set_drag_forwarding(Callable(), _can_take_back, _take_back)


## Fills the slots from the player's inventory, in the order things were picked up
func show_items(inventory: Dictionary) -> void:
	var items := inventory.keys()
	# Carrying more kinds of thing than there are slots? Grow the backpack.
	while grid.get_child_count() < items.size():
		_add_slot()

	var slots := grid.get_children()
	for i in slots.size():
		if i < items.size():
			slots[i].set_item(items[i], inventory[items[i]])
		else:
			slots[i].clear()


func _add_slot() -> void:
	var slot := SLOT_SCENE.instantiate()
	grid.add_child(slot)
	slot.tool_returned.connect(tool_returned.emit)


func _can_take_back(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from_bar", false)


func _take_back(_at_position: Vector2, data: Variant) -> void:
	tool_returned.emit(data["tool_item"])
