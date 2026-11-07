@tool
extends Resource
## What's been shaped with the Sculpt Brush, kept in its own file (the Valley's Ground Sculpt
## Path) so it survives every rebuild and never bloats the world scene.
##
## One value per terrain grid point: how many meters that point has been moved up or down.
## It's added on top of the heightmap and terrain modifiers, before trails cut in.

## How many grid points across and down the map this was made for
@export var points_x := 0
@export var points_z := 0
@export var deltas := PackedFloat32Array()
