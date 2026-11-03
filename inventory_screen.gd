extends Control

const SLOT_SCENE = preload("res://inventory_slot.tscn")

## How many slots the backpack has. Empty ones still show.
@export var slot_count := 20

@onready var grid: GridContainer = $Center/Panel/VBox/Grid


func _ready() -> void:
	for i in slot_count:
		grid.add_child(SLOT_SCENE.instantiate())


## Fills the slots from the player's inventory, in the order things were picked up
func show_items(inventory: Dictionary) -> void:
	var items := inventory.keys()
	# Carrying more kinds of thing than there are slots? Grow the backpack.
	while grid.get_child_count() < items.size():
		grid.add_child(SLOT_SCENE.instantiate())

	var slots := grid.get_children()
	for i in slots.size():
		if i < items.size():
			slots[i].set_item(items[i], inventory[items[i]])
		else:
			slots[i].clear()
