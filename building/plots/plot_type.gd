class_name PlotType
extends Buildable
## One kind of plot (house, workshop...): what it needs to work, and how big it can be. Each is a
## resource file in res://buildables/plots/, listed under the build menu's Plots tab, so a new
## plot type needs no code. Plots cost nothing to mark out. Its name and what unlocks it are in
## Blueprint.

## The smallest it can be, in whole meters: width (side to side) and depth. There's no largest.
@export var min_size := Vector2i(3, 3)
## Every required furniture item must be under a roof (or floor) belonging to the plot
@export var needs_roof := true
## Needs a door belonging to the plot
@export var needs_door := false
## The furniture it needs, each as {"label": "Bed", "items": ["Bed"], "count": 1}: at least
## `count` of the named items (furniture pieces, or the workbench, chest and campfire), counted
## together, belonging to the plot. "items" can name several that each count, like a campfire
## or a fireplace. An optional "summary" is how it reads in the one-line list ("1+ bed").
@export var furniture: Array[Dictionary] = []
## Settlers it holds, one per this item (a house: one per bed). Empty: it houses no one.
@export var houses_per := ""


## Plots are free
func cost_to_pay(_inventory: Dictionary) -> Dictionary:
	return {}


func can_afford(_inventory: Dictionary) -> bool:
	return true


## What the build menu shows in its slot: the smallest size
func cost_text() -> String:
	return "At least %s m" % size_text(min_size)


func missing_text(_inventory: Dictionary) -> String:
	return ""


## "4×4"
static func size_text(size: Vector2i) -> String:
	return "%d×%d" % [size.x, size.y]


## What it needs, in one line: "roofed, door, 1+ bed, campfire or fireplace"
func requirements_text() -> String:
	var parts: PackedStringArray = []
	if needs_roof:
		parts.append("roofed")
	if needs_door:
		parts.append("door")
	for need in furniture:
		parts.append(str(need.get("summary", str(need.get("label", "")).to_lower())))
	return ", ".join(parts)


## Every furniture name that counts toward any of its needs
func required_items() -> Dictionary:
	var found := {}
	for need in furniture:
		for item in need.get("items", []):
			found[str(item)] = true
	return found
