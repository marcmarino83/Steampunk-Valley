extends StaticBody3D
## A storage chest: 20 slots, one kind of item in each. E opens it beside the inventory. Its
## contents are kept in the save along with the building (see save_data and load_data).

## How many kinds of item it holds
const SLOTS := 20

## What's inside, like {"Wood": 12, "Rope": 2}, in the order things were put in
var contents := {}


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "Open chest"


func interact(player) -> void:
	player.open_chest(self)


## True if there's room for this item (it's already in here, or there's an empty slot)
func can_take(item: String) -> bool:
	return contents.has(item) or contents.size() < SLOTS


func put(item: String, amount: int) -> void:
	if amount > 0:
		contents[item] = contents.get(item, 0) + amount


## Takes out every one of an item and says how many that was
func take_all(item: String) -> int:
	var amount: int = contents.get(item, 0)
	contents.erase(item)
	return amount


func save_data() -> Dictionary:
	return {"contents": contents.duplicate()}


func load_data(data: Dictionary) -> void:
	contents.clear()
	var saved: Dictionary = data.get("contents", {})
	for item in saved:
		contents[item] = int(saved[item])
