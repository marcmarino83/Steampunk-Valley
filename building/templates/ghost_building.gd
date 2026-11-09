class_name GhostBuilding
extends Node3D
## A ghost of a workbench, storage chest or campfire in a placed template: the building's look in
## see-through blue outlines, nothing solid and nothing running (a ghost chest holds nothing, a
## ghost campfire doesn't burn). Filling it puts the real building there (see GhostBuilder).
## It keeps the buildable it stands for and its plot as metadata, like a real building, and saves
## with the buildings (see BuildPlacer).

## The box round its look, in its own space (for aiming at it)
var bounds := AABB()
var buildable: Buildable


## Makes the ghost of a buildable's scene (its meshes only; the scene's scripts never run)
static func create(of: Buildable) -> GhostBuilding:
	var ghost := GhostBuilding.new()
	ghost.name = "Ghost"
	ghost.buildable = of
	ghost.set_meta(BuildPlacer.BUILDABLE_META, of.resource_path)
	ghost.add_to_group("ghost_buildings")
	var original: Node3D = of.scene.instantiate()
	var first := true
	for found in original.find_children("*", "MeshInstance3D", true, false):
		var look := found as MeshInstance3D
		if not look.visible or look.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var n: Node = look
		while n != original and n is Node3D:
			xform = (n as Node3D).transform * xform
			n = n.get_parent()
		var copy := MeshInstance3D.new()
		copy.mesh = look.mesh
		copy.transform = xform
		copy.material_override = BuildPiece.ghost_material(false, true)
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(copy)
		var part: AABB = xform * look.mesh.get_aabb()
		ghost.bounds = part if first else ghost.bounds.merge(part)
		first = false
	original.free()
	return ghost


func is_ghost() -> bool:
	return true


func display_name() -> String:
	return buildable.display_name if buildable else "Building"


## The ghost under the crosshair shows brighter
func set_ghost_targeted(targeted: bool) -> void:
	for look in get_children():
		if look is MeshInstance3D:
			(look as MeshInstance3D).material_override = BuildPiece.ghost_material(targeted, true)
