extends StaticBody3D
## A crafting station. While the player is near one, the Crafting tab's recipes for this station
## can be made (see the player's nearby_stations()). E opens the Crafting tab.

## The station recipes name in their Station field
@export var station := "workbench"


func _ready() -> void:
	add_to_group("crafting_stations")


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "Use workbench"


func interact(player) -> void:
	player.open_crafting()
