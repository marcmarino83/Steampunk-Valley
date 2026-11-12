class_name PathTileType
extends Buildable
## One kind of path tile in the build menu's Paths tab (Dirt, Gravel, Stone, or Remove), laid with
## the hammer like a building piece (see PathTilePlacer) but drawn as paint on the ground (see
## PathTiles). Its `rank` is where it draws: a higher rank always lies over a lower one. Rank 0 is
## the Remove tile, which clears every type under it back to grass. With no costs it's free.
## A new path type needs a rank of its own (PathTiles.RANKS), its texture set and edge
## (PathTiles.RANK_SETS, RANK_EDGES), and a file like these.

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
