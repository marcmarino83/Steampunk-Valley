class_name Progress
extends Node
## What the player has done and learned: everything crafted, gathered or built, and every plot type
## that's worked ("Craft:Axe", "Build:Workbench", "Plot:Storehouse"), the blueprints (buildables and
## recipes) that started locked and have since been unlocked, and the notes and logs read. Something
## newly done unlocks every blueprint whose conditions are now all met, and says `learned` with
## their names (the blueprint pop-up shows them). A child of the player (see player.gd, which
## forwards its old functions here). Saved with the player, under its "unlocked", "done" and
## "notes_read" keys.

## Blueprints just unlocked, by their display names
signal learned(names: PackedStringArray)

## Blueprint -> true for those unlocked; "Action:Item" -> true for everything done; title -> true for
## every note read
var unlocked := {}
var done := {}
var notes_read := {}
## Every blueprint there is (the build menu's buildables and the crafting tab's recipes). Set by the
## player.
var blueprints: Callable


## True if this buildable or recipe can be used: it never was locked, or it's been unlocked
func is_unlocked(blueprint: Blueprint) -> bool:
	return not blueprint.starts_locked or unlocked.has(blueprint)


## True if this has been done ("Craft", "Gather", "Build" or "Plot", and its name)
func has_done(action: String, item: String) -> bool:
	return done.has("%s:%s" % [action, item])


## True if you've read the note or log with this title
func has_read(title: String) -> bool:
	return notes_read.has(title)


func mark_read(title: String) -> void:
	notes_read[title] = true


## Something was crafted, gathered or built ("Craft", "Gather" or "Build", and its name), or a plot
## of a type is working ("Plot", and the type's name). It's remembered, and any blueprint whose
## conditions are now all met unlocks; if any did, `learned` says which.
func report(action: String, item: String) -> void:
	done["%s:%s" % [action, item]] = true
	var names: PackedStringArray = []
	for blueprint in blueprints.call():
		if blueprint.starts_locked and not unlocked.has(blueprint) and blueprint.is_met(done):
			unlocked[blueprint] = true
			names.append(blueprint.display_name)
	if not names.is_empty():
		learned.emit(names)


func save_data() -> Dictionary:
	return {
		"unlocked": unlocked.keys().map(func(blueprint): return blueprint.resource_path),
		"notes_read": notes_read.keys(),
		"done": done.keys(),
	}


func load_data(data: Dictionary) -> void:
	var unlocked_paths: Array = data.get("unlocked", [])
	unlocked.clear()
	for blueprint in blueprints.call():
		if blueprint.resource_path in unlocked_paths:
			unlocked[blueprint] = true
	notes_read.clear()
	for title in data.get("notes_read", []):
		notes_read[str(title)] = true
	done.clear()
	for entry in data.get("done", []):
		done[str(entry)] = true
	# Blueprints added since this save was made (like plots, or new furniture) unlock quietly if
	# what they need was already done
	for blueprint in blueprints.call():
		if blueprint.starts_locked and blueprint.is_met(done):
			unlocked[blueprint] = true
