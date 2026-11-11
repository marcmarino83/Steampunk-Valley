class_name PieceBuildable
extends Buildable
## A building piece (floor, wall, roof...) for free building: it snaps to other pieces, and the
## hammer can take it down again for everything it cost. Its shape, collision and snap points
## come from PieceShapes; `scene` is res://building/pieces/build_piece.tscn for every piece.

## Which of PieceShapes' shapes it is
@export_enum("floor", "wall", "doorway", "door", "window", "roof", "stairs", "curved_wall_45", "curved_wall_22", "round_floor", "cone_roof", "foundation_wood", "foundation_stone", "round_foundation_wood", "round_foundation_stone", "wall_long", "wall_short", "pillar_wood", "pillar_stone", "floor_rtri", "foundation_wood_rtri", "foundation_stone_rtri", "floor_tri45", "foundation_wood_tri45", "foundation_stone_tri45", "round_floor_22", "round_foundation_wood_22", "round_foundation_stone_22", "floor_1", "wall_1", "wall_2m", "wall_half_2", "wall_half_1", "wall_half_2_tall", "wall_half_1_tall", "wall_strip_2", "wall_strip_1", "wall_strip_2_tall", "wall_strip_1_tall", "gable_wall_45", "doorway_2m", "door_2m", "window_2m", "window_split_2", "window_split_1", "window_split_2_2m", "window_split_1_2m", "stairs_tall", "half_stairs_tall", "ladder_tall", "pillar_wood_half_tall", "pillar_stone_half_tall", "gable_26", "gable_45", "roof_45", "roof_inner_26", "roof_outer_26", "ridge_26", "roof_inner_45", "roof_outer_45", "ridge_45", "beam_2", "beam_4", "beam_diag_26", "beam_diag_45", "beam_diag_26_4", "beam_diag_45_4", "pole_1", "pole_2", "pole_4", "pillar_wood_2m", "pillar_stone_2m", "pillar_wood_half", "pillar_stone_half", "half_stairs", "ladder", "railing_2", "railing_1", "fence", "bed", "foraging_basket", "chopping_block", "tool_rack", "sorting_table", "storage_shelf", "fireplace", "eave_26", "eave_45", "gable_overhang_26", "gable_overhang_45", "eave_corner_26", "eave_corner_45", "chimney_section", "chimney_top") var shape := "floor"
## A real model to show instead of the plain wood shape (optional). It's placed at the piece's
## origin and should match the shape's size; collision and snapping stay the same.
@export var model_scene: PackedScene

## Where a piece's build icon lives when its file names none: assets/icons/build/<shape>.png (the
## icon updater draws it there; see IconUpdater)
const ICON_FOLDER := "res://assets/icons/build/"


## The icon file this piece's picture is (or will be) in
func icon_path() -> String:
	return icon.resource_path if icon and not icon.resource_path.is_empty() else ICON_FOLDER + shape + ".png"


## A piece whose file names no icon takes the one at icon_path, once it's been drawn
func ensure_icon() -> void:
	if icon == null and ResourceLoader.exists(icon_path()):
		icon = load(icon_path())
