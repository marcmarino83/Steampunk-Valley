class_name TemplateLook
extends RefCounted
## A template's building, fully built and looking real, for showing only: its preview while it's
## being placed, and the picture rendered when it's saved. Nothing in it is solid, counted as a
## piece, or burning as a fire (see BuildPiece.make_preview_only).


## The whole building under one node: one child per template item, in the template's order, each
## at its place relative to the plot. Each child keeps its Buildable as metadata (BUILDABLE_META).
static func build(registry: PieceRegistry, template: BuildingTemplate) -> Node3D:
	var root := Node3D.new()
	root.name = "TemplateLook"
	for i in template.items.size():
		root.add_child(part_for(registry, template, i))
	return root


## One item's look (the template's item at this index), at its place relative to the plot. The
## template preview builds its look a few of these at a time (see TemplatePlacer).
static func part_for(registry: PieceRegistry, template: BuildingTemplate, index: int) -> Node3D:
	var item: Dictionary = template.items[index]
	var buildable: Buildable = item["buildable"]
	var id := index + 1
	var part: Node3D
	if buildable is PieceBuildable:
		var piece := buildable as PieceBuildable
		var bp: BuildPiece = piece.scene.instantiate()
		bp.setup(piece, registry.shape_of(piece.shape), registry.material_for(piece.shape))
		bp.piece_id = id
		bp.dress(registry.detail_mesh(piece.shape, id), registry.detail_material(), registry.mid_mesh(piece.shape, id))
		bp.weather()
		bp.make_preview_only()
		part = bp
	else:
		part = building_look(buildable)
	part.set_meta(BuildPlacer.BUILDABLE_META, buildable.resource_path)
	part.transform = item["relative"]
	return part


## A workbench, chest or campfire's look: its scene's meshes with their own materials (the scene's
## scripts never run)
static func building_look(buildable: Buildable) -> Node3D:
	var look := Node3D.new()
	look.name = "Building"
	var original: Node3D = buildable.scene.instantiate()
	for found in original.find_children("*", "MeshInstance3D", true, false):
		var mesh_look := found as MeshInstance3D
		if not mesh_look.visible or mesh_look.mesh == null:
			continue
		var xform := Transform3D.IDENTITY
		var n: Node = mesh_look
		while n != original and n is Node3D:
			xform = (n as Node3D).transform * xform
			n = n.get_parent()
		var copy := MeshInstance3D.new()
		copy.mesh = mesh_look.mesh
		copy.material_override = mesh_look.material_override
		copy.transform = xform
		look.add_child(copy)
	original.free()
	return look
