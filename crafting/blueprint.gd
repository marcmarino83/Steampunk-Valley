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
## More things that must all have been done the same way too (crafted, gathered or built at some
## point, in any order), like "Pickaxe" beside "Axe"
@export var unlock_also := PackedStringArray()
## What the build menu says about how to unlock it. Left empty, it's worked out for you,
## like "Craft a hammer to unlock".
@export var unlock_hint := ""


## Everything that has to have been done, as the player records it: "Craft:Axe" and so on
func unlock_needs() -> PackedStringArray:
	var needs: PackedStringArray = ["%s:%s" % [unlocked_by, unlock_item]]
	for item in unlock_also:
		needs.append("%s:%s" % [unlocked_by, item])
	return needs


## True if what the player has done (a record of "Craft:Axe"-style entries) unlocks it
func is_met(done: Dictionary) -> bool:
	if not starts_locked:
		return true
	for need in unlock_needs():
		if not done.has(need):
			return false
	return true


func unlock_hint_text() -> String:
	if not unlock_hint.is_empty():
		return unlock_hint
	var things: PackedStringArray = []
	for item in [unlock_item] + Array(unlock_also):
		var thing: String = item.to_lower()
		# Gathered things are counted by the handful ("gather plant fiber"); made things one at a time
		if unlocked_by != "Gather":
			thing = ("an " if thing.left(1) in ["a", "e", "i", "o", "u"] else "a ") + thing
		things.append(thing)
	return "%s %s to unlock" % [unlocked_by, " and ".join(things)]
