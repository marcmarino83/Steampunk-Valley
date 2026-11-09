class_name DevCheats
extends RefCounted
## The developer console's toggles (see DevConsole, debug builds only). They're never saved: they
## start off every time the game starts. In a release build nothing can switch them on.

## Building pieces, furniture, ghosts and crafting cost nothing (and need nothing in your pockets)
static var freebuild := false
## Hunger and stamina never drop (and there's no damage)
static var god := false
## Free flying, passing through everything: Space up, Ctrl down, Shift faster
static var fly := false


## True while any toggle is on (the "DEV" tag shows)
static func any() -> bool:
	return freebuild or god or fly


## The toggles that are on, by name ("freebuild, god")
static func active_names() -> PackedStringArray:
	var on: PackedStringArray = []
	if freebuild:
		on.append("freebuild")
	if god:
		on.append("god")
	if fly:
		on.append("fly")
	return on


## Everything off (a new game or a loaded world starts clean)
static func reset() -> void:
	freebuild = false
	god = false
	fly = false
