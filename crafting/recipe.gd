class_name Recipe
extends Blueprint
## One thing that can be crafted. Each is a resource file in res://crafting/, and the Crafting
## tab lists whatever it finds there (see crafting_panel.gd). Crafting makes items you carry;
## structures you place belong in the build menu (see Buildable). Its name and what unlocks it
## are in Blueprint; a locked recipe stays out of the Crafting tab until it's unlocked.

const FOLDER := "res://crafting"
const TIER_FOLDER := "res://iron_tier/crafting"

## One line about what it is
@export var description := ""
## What it's used for
@export var used_for := ""
@export var icon: Texture2D
## What it takes, like {"Sticks": 2, "Stone": 1}
@export var costs := {}
## The inventory item it makes, and how many
@export var result := ""
@export var result_amount := 1
## Where it can be crafted: "hand" is anywhere. A recipe only shows while the player's
## nearby_stations() lists its station, so a forge recipe just says "forge".
@export var station := "hand"


func can_afford(inventory: Dictionary) -> bool:
	for item in costs:
		if inventory.get(item, 0) < costs[item]:
			return false
	return true


## You only ever need one of each tool
func already_owned(inventory: Dictionary) -> bool:
	return ToolItem.exists_for(result) and inventory.has(result)


func can_craft(inventory: Dictionary) -> bool:
	return can_afford(inventory) and not already_owned(inventory)
