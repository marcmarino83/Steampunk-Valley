class_name PlayerCrafting
extends Node
## Crafting: which stations are in reach (by hand anywhere, plus every crafting station within
## STATION_RANGE: anything in the "crafting_stations" group, like the workbench, naming its
## station), and making a recipe. A child of the player (see player.gd, which forwards its old
## functions here). While the inventory is open, says `stations_changed` as you walk toward or away
## from a station, so the Crafting tab follows.

## The stations in reach are no longer what the Crafting tab last showed
signal stations_changed

## How close a crafting station (like the workbench) must be for its recipes, in meters
const STATION_RANGE := 3.0

## Where you stand (the player), what you own, what you've learned and the inventory screen (its
## Crafting tab and slot count). Set by the player.
var body: Node3D
var inventory: PlayerInventory
var progress: Progress
var inventory_screen: Control

# The stations in reach when the Crafting tab was last brought up to date
var _last_stations: PackedStringArray = []


## Where you can craft right now: "hand", plus every station within reach
func nearby_stations() -> PackedStringArray:
	var stations: PackedStringArray = ["hand"]
	for station in get_tree().get_nodes_in_group("crafting_stations"):
		if body.global_position.distance_to(station.global_position) <= STATION_RANGE and not stations.has(station.station):
			stations.append(station.station)
	return stations


## The stations in reach, remembered as what the Crafting tab now shows
func stations_for_tab() -> PackedStringArray:
	_last_stations = nearby_stations()
	return _last_stations


## While the inventory is open: says `stations_changed` if the stations in reach changed since the
## Crafting tab was last brought up to date
func follow_stations() -> void:
	if nearby_stations() != _last_stations:
		stations_changed.emit()


## Makes a recipe: takes the resources and puts the result in the backpack. If there's no room,
## says so and spends nothing.
func craft(recipe: Recipe) -> void:
	if not progress.is_unlocked(recipe) or not recipe.can_craft(inventory.items) or not nearby_stations().has(recipe.station):
		return
	var crafting: Control = inventory_screen.crafting
	if inventory.backpack_contents().size() >= inventory.backpack_slots() and not inventory.items.has(recipe.result):
		crafting.show_status("Inventory full", true)
		return
	inventory.pay(recipe.costs)
	inventory.add(recipe.result, recipe.result_amount)
	crafting.show_status("%s added to your inventory" % recipe.display_name, false)
	progress.report("Craft", recipe.result)
