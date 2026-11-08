class_name PieceBuildable
extends Buildable
## A building piece (floor, wall, roof...) for free building: it snaps to other pieces, and the
## hammer can take it down again for everything it cost. Its shape, collision and snap points
## come from PieceShapes; `scene` is res://building/pieces/build_piece.tscn for every piece.

## Which of PieceShapes' shapes it is
@export_enum("floor", "wall", "doorway", "door", "window", "roof", "stairs", "curved_wall_45", "curved_wall_22", "round_floor", "cone_roof", "foundation_wood", "foundation_stone", "round_foundation_wood", "round_foundation_stone", "wall_long", "wall_short", "pillar_wood", "pillar_stone", "floor_rtri", "foundation_wood_rtri", "foundation_stone_rtri", "floor_tri45", "foundation_wood_tri45", "foundation_stone_tri45", "round_floor_22", "round_foundation_wood_22", "round_foundation_stone_22", "floor_1", "wall_1", "wall_half_2", "wall_half_1", "wall_quarter", "gable_26", "gable_45", "roof_45", "roof_inner_26", "roof_outer_26", "ridge_26", "roof_inner_45", "roof_outer_45", "ridge_45", "beam_1", "beam_2", "beam_diag_26", "beam_diag_45", "pole_1", "pole_2", "ladder", "railing_2", "railing_1", "fence") var shape := "floor"
## A real model to show instead of the plain wood shape (optional). It's placed at the piece's
## origin and should match the shape's size; collision and snapping stay the same.
@export var model_scene: PackedScene
