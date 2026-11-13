class_name PlayerInventory
extends Node
## Everything the player owns, like {"Scrap": 3, "Coal": 1}, including tools sitting on the action
## bar: adding, taking, whether something fits, paying a cost, and handing things over with what
## won't fit left in a bundle on the ground. A child of the player (see player.gd, which forwards
## its old inventory functions here). Says `changed` whenever the items change.
##
## The backpack has `backpack_slots` slots (the inventory screen's); a slot holds any amount of one
## kind of item, and whatever's on the action bar takes no backpack slot.

## The items changed (added, taken, paid, or changed directly and announced with notify())
signal changed

## What you own: item -> amount (the one dictionary; others may read it, and change it only
## followed by notify())
var items := {}
## The action bar (what's on it takes no backpack slot), the inventory screen (its slot count) and
## where a bundle of what didn't fit is dropped (the world). Set by the player.
var action_bar: ActionBar
var inventory_screen: Control
var world: Node


func add(item: String, amount: int) -> void:
	items[item] = items.get(item, 0) + amount
	changed.emit()


## Takes items out. Returns false (and takes nothing) if there aren't enough.
func remove(item: String, amount: int) -> bool:
	if items.get(item, 0) < amount:
		return false
	items[item] -= amount
	if items[item] == 0:
		items.erase(item)
	changed.emit()
	return true


## Says the items changed after changing `items` directly (moving stacks, the console)
func notify() -> void:
	changed.emit()


## True if this item would fit: you already carry some (stacks have no limit), or the backpack has
## a free slot
func has_room_for(item: String) -> bool:
	return items.has(item) or action_bar.has_item(item) or backpack_contents().size() < backpack_slots()


## How many slots the backpack has
func backpack_slots() -> int:
	return inventory_screen.slot_count


## Puts these items in your pockets; any that won't fit (backpack full) are left in a bundle on the
## ground at `spot`, for E to pick up later. Returns what was left.
func give_or_drop(given: Dictionary, spot: Vector3) -> Dictionary:
	var left := {}
	for item in given:
		if has_room_for(item):
			add(item, given[item])
		else:
			left[item] = given[item]
	if not left.is_empty():
		var bundle := ItemBundle.create(left)
		world.add_child(bundle)
		bundle.global_position = spot
	return left


## Pays a cost (building, filling a ghost, crafting) and returns what was paid, which is what comes
## back if it's taken down again: nothing at all with the freebuild cheat on
func pay(cost: Dictionary) -> Dictionary:
	if DevCheats.freebuild:
		return {}
	for item in cost:
		remove(item, cost[item])
	return cost


## Everything you own, minus whatever's on the action bar
func backpack_contents() -> Dictionary:
	var in_backpack := items.duplicate()
	for item in action_bar.items:
		in_backpack.erase(item)
	return in_backpack
