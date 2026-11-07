@tool
extends Resource
## What's been painted onto the ground with the Texture Brush, kept in its own file (the
## Valley's Ground Paint Path) so it survives every rebuild and never bloats the world scene.
##
## One pixel per Texel meters, covering the whole map from Origin. Each pixel holds how much
## of each material is painted there, from 0 to 1 (they never add up to more than 1; whatever
## is left over shows the automatic coloring underneath). The materials are kept in channels:
## Maps holds three pictures of four channels each (red, green, blue, alpha), and Layers says
## which material each channel is ("grass", "dirt", or a texture set's "folder/name"), in the
## order they were first painted.

@export var maps: Array[Image] = []
@export var layers := PackedStringArray()
## Paint saved before any texture set could be painted (grass, dirt, forest floor and gravel
## in the first picture, rock in the second). Moved into Maps when it's loaded.
@export var image_a: Image
@export var image_b: Image
## The map's north-west corner (x, z), where the first pixel starts
@export var origin := Vector2.ZERO
## How many meters each pixel covers
@export var texel := 1.0
