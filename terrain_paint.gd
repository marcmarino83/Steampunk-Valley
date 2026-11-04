@tool
extends Resource
## What's been painted onto the ground with the Texture Brush, kept in its own file (the
## Valley's Ground Paint Path) so it survives every rebuild and never bloats the world scene.
##
## One pixel per Texel meters, covering the whole map from Origin. Each pixel holds how much
## of each material is painted there, from 0 to 1 (they never add up to more than 1; whatever
## is left over shows the automatic coloring underneath):
##   image_a: grass (red), dirt (green), forest floor (blue), gravel path (alpha)
##   image_b: rock (red)

@export var image_a: Image
@export var image_b: Image
## The map's north-west corner (x, z), where the first pixel starts
@export var origin := Vector2.ZERO
## How many meters each pixel covers
@export var texel := 1.0
