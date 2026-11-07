class_name Blueprint
extends Resource
## Something the player can learn to make: a buildable (build menu) or a recipe (crafting). Each
## one can start locked, and says in its own file what unlocks it, so new unlocks need no code.

@export var display_name := ""

@export_group("Unlocking")
## Locked until the player does what's below. Unlocked from the start when off.
@export var starts_locked := false
## What the player has to do
@export_enum("Craft", "Gather", "Build") var unlocked_by := "Craft"
## The item crafted or gathered, or the buildable built, exactly as it's named in the game,
## like "Hammer", "Plant Fiber" or "Campfire"
@export var unlock_item := ""
## What the build menu says about how to unlock it. Left empty, it's worked out for you,
## like "Craft a hammer to unlock".
@export var unlock_hint := ""


## True if doing this unlocks it
func unlocks_on(action: String, item: String) -> bool:
	return starts_locked and action == unlocked_by and item == unlock_item


func unlock_hint_text() -> String:
	if not unlock_hint.is_empty():
		return unlock_hint
	var thing := unlock_item.to_lower()
	# Gathered things are counted by the handful ("gather plant fiber"); made things one at a time
	if unlocked_by != "Gather":
		thing = ("an " if thing.left(1) in ["a", "e", "i", "o", "u"] else "a ") + thing
	return "%s %s to unlock" % [unlocked_by, thing]
