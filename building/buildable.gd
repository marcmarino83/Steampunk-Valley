class_name Buildable
extends Blueprint
## One thing the hammer can build. Each one is a resource file in res://buildables/, and the
## build menu lists whatever it finds there, so a new buildable needs no code: duplicate a
## file, then fill it in here in the Inspector. Its name and what unlocks it are in Blueprint.

## The scene that gets placed in the world
@export var scene: PackedScene
## The ways of paying for it, best first, like [{"Wood": 3}, {"Sticks": 6, "Stone": 2}].
## There must be at least one. It's paid with the first one you can afford.
@export var costs: Array[Dictionary] = []
## The placeholder square shown in the menu, until there's an icon image
@export var icon_color := Color(0.6, 0.6, 0.6)
## An icon image, which replaces the colored square (optional)
@export var icon: Texture2D
## The steepest ground it can stand on, in degrees
@export_range(0.0, 90.0) var max_slope_degrees := 30.0
## How much room it needs, in meters. Anything solid inside this makes the spot invalid.
@export var footprint_radius := 1.0
@export var footprint_height := 2.0
## Shown once it's been placed (optional)
@export_multiline var placed_message := ""


## The first way of paying that this inventory covers, or empty if none does
func cost_to_pay(inventory: Dictionary) -> Dictionary:
	for cost in costs:
		if _shortfall(cost, inventory).is_empty():
			return cost
	return {}


func can_afford(inventory: Dictionary) -> bool:
	return not cost_to_pay(inventory).is_empty()


## The price, one way of paying per line: "3 Wood\nor 6 Sticks + 2 Stone"
func cost_text() -> String:
	var lines: PackedStringArray = []
	for cost in costs:
		lines.append(_items_text(cost, " + "))
	return "\nor ".join(lines)


## What you're short of, for each way of paying: "2 Wood, or 6 Sticks and 1 Stone"
func missing_text(inventory: Dictionary) -> String:
	var options: PackedStringArray = []
	for cost in costs:
		options.append(_items_text(_shortfall(cost, inventory), " and "))
	return ", or ".join(options)


# How much more of each item this way of paying needs. Empty means you have it all.
func _shortfall(cost: Dictionary, inventory: Dictionary) -> Dictionary:
	var short := {}
	for item in cost:
		var needed: int = cost[item] - inventory.get(item, 0)
		if needed > 0:
			short[item] = needed
	return short


func _items_text(items: Dictionary, joiner: String) -> String:
	var parts: PackedStringArray = []
	for item in items:
		parts.append("%d %s" % [items[item], item])
	return joiner.join(parts)
