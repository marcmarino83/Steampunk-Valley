@tool
extends Node3D
## Holds the trees, rocks and bushes placed with the Object Painter (World Tools panel), each
## kind under its own child: Trees, Rocks, Bushes. They stay snapped to the ground through
## every terrain rebuild.
##
## It also remembers where the painter's eraser has rubbed out the valley's own scattered
## trees, rocks and resources, so they stay gone when the valley is rebuilt.

## Spots rubbed out with the eraser: x, z and radius (in meters), one per dab
@export var erased := PackedVector3Array()


func _enter_tree() -> void:
	add_to_group("object_erasers")
