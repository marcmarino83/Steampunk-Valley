class_name GridUpgrade
## Brings pieces saved on an older building grid (DESIGN.md, Building system, "Building grid
## standard") up to the current one: in a saved game (PieceRegistry.load_data) and in a building
## template (BuildingTemplate.read) saved with an older grid version (none saved: version 1). Each
## step takes the pieces on from the version they were saved with, so a save from any older version
## goes through each step in turn. A piece keeps its size wherever there's a piece of that size, and
## the end it attaches by (its snap position) where there isn't.
##
## Version 1 -> 2 (the 1.25 m vertical unit):
##   - Foundation Steps (1 m, gone) came back as Half Stairs (1.25 m), their top edge where it was;
##   - Quarter Walls (1 × 1 m, gone) came back as 1 m Half Walls, their foot where it was;
##   - ladders (2 m to 2.5 m) kept their top;
##   - chimney sections (1 m to 1.25 m) and tops were laid again from the fireplace's new chimney spot.
## Version 2 -> 4 (two families: the Standard one on the 2 m wall, the Tall one on the 2.5 m wall):
##   - every piece that matched the 2.5 m wall comes back as its Tall version, exactly as it was
##     (same size, same place): half walls and strips, Stairs and Half Stairs, half pillars and the
##     ladder (the walls, doorway, windows, door, 2.5 m pillars and the 45° Gable Wall are the Tall
##     family's own pieces already, and load as they are);
##   - pieces with no wall height to match are on the standard sizes: the 1 m beam (gone) comes back
##     as the 2 m beam on the same middle; poles keep their foot (1.25 / 2.5 m to 1 / 2 m) and the
##     5 m pole comes back as the 4 m pole on its foot; fences keep their foot (1.25 m to 1 m);
##     foundations keep their top (3.25 m to 3 m deep); chimney sections (1.25 m to 1 m) and tops are
##     laid again from the 1 m fireplace's chimney spot.
## Version 3 (the 1 m unit, before the Tall family came back) -> 4: nothing changes (its pieces were
## the Standard ones, which keep their names and sizes).

## The grid version saves and templates are written with
const GRID_VERSION := 4

const FOUNDATION_STEPS := "res://buildables/structure/foundation_steps.tres"
const HALF_STAIRS := "res://buildables/structure/half_stairs.tres"
const STAIRS := "res://buildables/structure/stairs.tres"
const QUARTER_WALL := "res://buildables/structure/wall_quarter.tres"
const HALF_WALL_1 := "res://buildables/structure/wall_half_1.tres"
const LADDER := "res://buildables/structure/ladder.tres"
const FIREPLACE := "res://buildables/furniture/fireplace.tres"
const CHIMNEY_SECTION := "res://buildables/furniture/chimney_section.tres"
const CHIMNEY_TOP := "res://buildables/furniture/chimney_top.tres"
const GABLE_WALL_45 := "res://buildables/structure/gable_wall_45.tres"
const BEAM_1 := "res://buildables/structure/beam_1.tres"
const BEAM_2 := "res://buildables/structure/beam_2.tres"
const POLE_5 := "res://buildables/structure/pole_5.tres"
const POLE_4 := "res://buildables/structure/pole_4.tres"
## Pieces that matched the 2.5 m wall before the families: old path -> its Tall version's path
const TALL_VERSIONS := {
	"res://buildables/structure/wall_half_2.tres": "res://buildables/structure/wall_half_2_tall.tres",
	"res://buildables/structure/wall_half_1.tres": "res://buildables/structure/wall_half_1_tall.tres",
	"res://buildables/structure/wall_strip_2.tres": "res://buildables/structure/wall_strip_2_tall.tres",
	"res://buildables/structure/wall_strip_1.tres": "res://buildables/structure/wall_strip_1_tall.tres",
	"res://buildables/structure/stairs.tres": "res://buildables/structure/stairs_tall.tres",
	"res://buildables/structure/half_stairs.tres": "res://buildables/structure/half_stairs_tall.tres",
	"res://buildables/structure/pillar_wood_half.tres": "res://buildables/structure/pillar_wood_half_tall.tres",
	"res://buildables/structure/pillar_stone_half.tres": "res://buildables/structure/pillar_stone_half_tall.tres",
	"res://buildables/structure/ladder.tres": "res://buildables/structure/ladder_tall.tres",
}

## Each version's sizes (only those a step changes): version -> name -> size
const SIZES := {
	1: {"steps": Vector2(1.0, 2.0), "ladder": 2.0, "section": 1.0, "chimney": Vector3(-0.147, 1.187, -0.19)},
	2: {"half_stairs": Vector2(1.25, 2.0), "stairs": Vector2(2.5, 4.0), "ladder": 2.5, "section": 1.25,
		"chimney": Vector3(-0.147, 1.187, -0.19) * (1.25 / 1.187)},
}
## Two points this close are where one piece stood on another
const MEET := 0.02


## Upgrades a list of pieces in place, from grid version `from` to GRID_VERSION: each a Dictionary
## with "buildable" (its path) and "where" (its Transform3D), both changed as needed (other keys are
## left alone)
static func upgrade(entries: Array, from := 1) -> void:
	if from < 2:
		_to_2(entries)
	if from < 3:
		_from_2(entries)


static func _to_2(entries: Array) -> void:
	var old: Dictionary = SIZES[1]
	var steps: Vector2 = old["steps"]
	var new: Dictionary = SIZES[2]
	var half: Vector2 = new["half_stairs"]
	for e in entries:
		var where: Transform3D = e["where"]
		match e["buildable"]:
			FOUNDATION_STEPS:
				var top := where * Vector3(0, steps.x, steps.y / 2.0)
				e["buildable"] = HALF_STAIRS
				e["where"] = Transform3D(where.basis, top - where.basis * Vector3(0, half.x, half.y / 2.0))
			QUARTER_WALL:
				e["buildable"] = HALF_WALL_1
			LADDER:
				e["where"] = where.translated_local(Vector3(0, float(old["ladder"]) - float(new["ladder"]), 0))
	_restack_chimneys(entries, old["chimney"], new["chimney"], old["section"], new["section"])


# Version 2 on: the wall-height pieces as their Tall versions (unchanged), the rest on the standard
# sizes (see the notes at the top)
static func _from_2(entries: Array) -> void:
	var old: Dictionary = SIZES[2]
	for e in entries:
		var path: String = e["buildable"]
		if TALL_VERSIONS.has(path):
			e["buildable"] = TALL_VERSIONS[path]
		elif path == BEAM_1:
			e["buildable"] = BEAM_2
		elif path == POLE_5:
			e["buildable"] = POLE_4
	_restack_chimneys(entries, old["chimney"], PieceShapes.FIREPLACE_CHIMNEY, old["section"], PieceShapes.CHIMNEY_SECTION_HEIGHT)


# Lays each chimney stack again on the new sizes: from the bottom up, a section or top standing on
# a fireplace's old chimney spot (`old_chimney`, in the fireplace's space) goes to its new one, and
# one standing on an old section's top (`old_section` up) goes onto that section's new top
static func _restack_chimneys(entries: Array, old_chimney: Vector3, new_chimney: Vector3, old_section: float, new_section: float) -> void:
	var stack := entries.filter(func(e): return e["buildable"] in [CHIMNEY_SECTION, CHIMNEY_TOP])
	stack.sort_custom(func(a, b): return (a["where"] as Transform3D).origin.y < (b["where"] as Transform3D).origin.y)
	# Old spot (where something stood) -> new spot
	var spots := []
	for e in entries:
		if e["buildable"] == FIREPLACE:
			var t: Transform3D = e["where"]
			spots.append([t * old_chimney, t * new_chimney])
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
			spots.append([old_foot + t.basis.y * old_section, t.origin + t.basis.y * new_section])
