extends RefCounted
## Which family a building piece's shape belongs to, for the snapping tests' reports ("(converted)"
## for those snapping by whole edges: SnapEdges.converted)


static func of(shape: String) -> String:
	var name := _family(shape)
	return name + " (converted)" if SnapEdges.converted(shape) else name


static func _family(shape: String) -> String:
	if shape in SnapEdges.WALLS:
		return "walls"
	if shape in SnapEdges.FLOORS:
		return "floors & foundations"
	if shape.begins_with("gable_overhang") or shape.begins_with("eave") or shape.begins_with("outer_eave") or shape.begins_with("valley_eave"):
		return "roofs"
	if shape == "roof" or shape.begins_with("roof_") or shape.begins_with("ridge_") or shape.begins_with("topper_") and not shape.begins_with("topper_gable") or shape.begins_with("hip_end"):
		return "roofs"
	if shape.begins_with("gable") or shape.begins_with("inverse") or shape.begins_with("topper_gable"):
		return "triangles & gables"
	if shape.contains("stairs") or shape.begins_with("ladder"):
		return "stairs & ladders"
	if shape.begins_with("pillar") or shape.begins_with("pole") or shape.begins_with("beam"):
		return "pillars, poles & beams"
	if shape.begins_with("door"):
		return "doors"
	if shape.begins_with("chimney") or shape == "fireplace":
		return "chimney"
	if shape.begins_with("round") or shape.begins_with("curved") or shape.begins_with("cone"):
		return "round"
	if shape.begins_with("railing") or shape == "fence":
		return "railings & fences"
	return "other"
