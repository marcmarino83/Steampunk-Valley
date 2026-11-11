class_name GridUpgrade
## Brings pieces saved before the building grid standard (DESIGN.md, Building system) up to it: in a
## saved game (PieceRegistry.load_data) and in a building template (BuildingTemplate.read) without
## the grid version they were made with. Each resized piece keeps the end it attaches by:
##   - Foundation Steps (1 m, gone) come back as Half Stairs (1.25 m), their top edge where it was
##     (on the foundation's edge): their foot goes 0.25 m lower;
##   - Quarter Walls (1 × 1 m, gone) come back as 1 m Half Walls (1 × 1.25 m), their foot where it
##     was: they're 0.25 m taller;
##   - ladders (2 m, now 2.5 m) keep their top (where they hang from a floor's edge): their foot
##     goes 0.5 m lower;
##   - chimney sections (1 m, now 1.25 m) and tops keep standing on what they stood on: each stack
##     is laid again from its fireplace (whose chimney now starts one vertical unit up) or its
##     lowest section, section on section;
##   - everything else keeps its place: poles (now 1.25 / 2.5 m) and strips (0.625 m) their foot,
##     fences (1.25 m) their foot and line, the fireplace its foot (5 % larger), foundations their top
##     (1.25 m above the ground now, 3.25 m deep), beams their snap points (their tops are on that
##     level now, so a beam sits 0.1 m lower than before).

## The grid version saves and templates are written with
const GRID_VERSION := 2

const FOUNDATION_STEPS := "res://buildables/structure/foundation_steps.tres"
const HALF_STAIRS := "res://buildables/structure/half_stairs.tres"
const QUARTER_WALL := "res://buildables/structure/wall_quarter.tres"
const HALF_WALL_1 := "res://buildables/structure/wall_half_1.tres"
const LADDER := "res://buildables/structure/ladder.tres"
const FIREPLACE := "res://buildables/furniture/fireplace.tres"
const CHIMNEY_SECTION := "res://buildables/furniture/chimney_section.tres"
const CHIMNEY_TOP := "res://buildables/furniture/chimney_top.tres"
## The sizes before the standard
const OLD_STEPS := Vector2(1.0, 2.0)
const OLD_LADDER := 2.0
const OLD_SECTION := 1.0
const OLD_FIREPLACE_CHIMNEY := Vector3(-0.147, 1.187, -0.19)
## Two points this close are where one piece stood on another
const MEET := 0.02


## Upgrades a list of pieces in place: each a Dictionary with "buildable" (its path) and "where"
## (its Transform3D), both changed as needed (other keys are left alone)
static func upgrade(entries: Array) -> void:
	for e in entries:
		var path: String = e["buildable"]
		var where: Transform3D = e["where"]
		match path:
			FOUNDATION_STEPS:
				var top := where * Vector3(0, OLD_STEPS.x, OLD_STEPS.y / 2.0)
				var size: Array = PieceShapes.FLIGHTS["half_stairs"]
				e["buildable"] = HALF_STAIRS
				e["where"] = Transform3D(where.basis, top - where.basis * Vector3(0, float(size[0]), float(size[1]) / 2.0))
			QUARTER_WALL:
				e["buildable"] = HALF_WALL_1
			LADDER:
				e["where"] = where.translated_local(Vector3(0, OLD_LADDER - PieceShapes.LADDER_HEIGHT, 0))
	_restack_chimneys(entries)


# Lays each chimney stack again on the new sizes: from the bottom up, a section or top standing on
# a fireplace's old chimney spot goes to its new one, and one standing on an old section's top goes
# onto that section's new top
static func _restack_chimneys(entries: Array) -> void:
	var stack := entries.filter(func(e): return e["buildable"] in [CHIMNEY_SECTION, CHIMNEY_TOP])
	stack.sort_custom(func(a, b): return (a["where"] as Transform3D).origin.y < (b["where"] as Transform3D).origin.y)
	# Old spot (where something stood) -> new spot
	var spots := []
	for e in entries:
		if e["buildable"] == FIREPLACE:
			var t: Transform3D = e["where"]
			spots.append([t * OLD_FIREPLACE_CHIMNEY, t * PieceShapes.FIREPLACE_CHIMNEY])
	for e in stack:
		var t: Transform3D = e["where"]
		var old_foot := t.origin
		for s in spots:
			if old_foot.distance_to(s[0]) < MEET:
				t = Transform3D(t.basis, s[1])
				e["where"] = t
				break
		# (what stood on this section's old top now stands on its new one)
		if e["buildable"] == CHIMNEY_SECTION:
			spots.append([old_foot + t.basis.y * OLD_SECTION, t.origin + t.basis.y * PieceShapes.CHIMNEY_SECTION_HEIGHT])
