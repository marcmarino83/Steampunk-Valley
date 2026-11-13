class_name PathTileType
extends Buildable
## One kind of path in the build menu's Paths tab (Dirt, Gravel, Stone, or Remove), laid with the
## hammer by dragging out a strip (see PathTilePlacer) and drawn as paint on the ground (see
## PathTiles). Its `rank` is where it draws: a higher rank always lies over a lower one. Rank 0 is
## Remove, which clears every type under its strip back to grass. Its costs are for every
## PER_LENGTH meters of strip (a shorter strip pays its share, rounded up); with none it's free.
## A new path type needs a rank of its own (PathTiles.RANKS), its texture set and edge
## (PathTiles.RANK_SETS, RANK_EDGES), and a file like these.

## The strip length (m) its costs pay for
const PER_LENGTH := 4.0

## Where it draws (1 Dirt, 2 Gravel, 3 Stone; 0: Remove)
@export_range(0, 4) var rank := 1
## What the build menu says when it's hovered
@export_multiline var menu_hint := ""


func is_remove() -> bool:
	return rank == PathTiles.REMOVE


func cost_to_pay(inventory: Dictionary) -> Dictionary:
	if costs.is_empty():
		return {}
	return super.cost_to_pay(inventory)


func can_afford(inventory: Dictionary) -> bool:
	return costs.is_empty() or super.can_afford(inventory)


func cost_text() -> String:
	return "Free" if costs.is_empty() else super.cost_text()


func missing_text(inventory: Dictionary) -> String:
	return "" if costs.is_empty() else super.missing_text(inventory)


## The way of paying for a strip this long (m) that the inventory can afford ({} if none, or if
## it's free)
func cost_for(length: float, inventory: Dictionary) -> Dictionary:
	if costs.is_empty():
		return {}
	var scaled := _scaled(length)
	if DevCheats.freebuild:
		return scaled[0]
	for cost in scaled:
		if _shortfall(cost, inventory).is_empty():
			return cost
	return {}


## What a strip this long costs: "3 Stone", or "Free"
func cost_text_for(length: float) -> String:
	if costs.is_empty():
		return "Free"
	var lines: PackedStringArray = []
	for cost in _scaled(length):
		lines.append(_items_text(cost, " + "))
	return "\nor ".join(lines)


## What you're short of for a strip this long
func missing_text_for(length: float, inventory: Dictionary) -> String:
	var options: PackedStringArray = []
	for cost in _scaled(length):
		options.append(_items_text(_shortfall(cost, inventory), " and "))
	return ", or ".join(options)


# Every way of paying, scaled to a strip this long (each item rounded up, at least 1)
func _scaled(length: float) -> Array[Dictionary]:
	var scaled: Array[Dictionary] = []
	for cost in costs:
		var part := {}
		for item in cost:
			part[item] = maxi(1, ceili(cost[item] * length / PER_LENGTH - 0.001))
		scaled.append(part)
	return scaled
