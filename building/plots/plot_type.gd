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
## How many settlers can work here (0: it's not a workplace)
@export var workers := 0
## The furniture item a worker stands at while working (the forager's basket, the chopping block)
@export var work_at := ""
## What it makes each dawn while it's working and has a worker, put in its own storage chest:
## fixed amounts ({"Wood": 12, "Sticks": 8})...
@export var daily_output: Dictionary = {}
## ...and/or this many items a day shared out by percentages the player sets with sliders in the
## plot panel (`split_output` holds the items and their starting percentages, adding up to 100)
@export var split_output_total := 0
@export var split_output: Dictionary = {}
## Town storage (see TownStorage): while it's working, each of these items it owns (the
## Storehouse's storage shelves) adds `town_storage_slots` slots to the shared pool. 0: none.
@export var town_storage_item := ""
@export var town_storage_slots := 0


## The day's output for these percentages (item -> amount), at full strength. Fixed amounts as
## they are; the shared amount split so the parts add up exactly (largest remainders get the rest).
func output_for(percentages: Dictionary) -> Dictionary:
	var made := daily_output.duplicate()
	if split_output_total > 0:
		var parts := split(split_output_total, percentages if not percentages.is_empty() else split_output)
		for item in parts:
			made[item] = int(made.get(item, 0)) + parts[item]
	return made


## Shares `total` out by percentages so the whole numbers add up to exactly `total`
static func split(total: int, percentages: Dictionary) -> Dictionary:
	var parts := {}
	var remainders := []
	var given := 0
	var sum := 0.0
	for item in percentages:
		sum += float(percentages[item])
	if sum <= 0.0:
		return parts
	for item in percentages:
		var exact := total * float(percentages[item]) / sum
		parts[item] = int(floor(exact))
		given += parts[item]
		remainders.append([exact - floor(exact), item])
	remainders.sort_custom(func(a, b): return a[0] > b[0])
	for i in total - given:
		var item: String = remainders[i % remainders.size()][1]
		parts[item] += 1
	return parts


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
