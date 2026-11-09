class_name JointDetails
extends Node
## The details that belong to where pieces meet rather than to one piece: a rough log post (with
## rope lashings) wherever two or more walls, railings or fences meet end to end at an angle, and a
## log along the peak wherever two roofs (or gable overhangs) meet back to back, unless a ridge cap
## is already there. They're worked out from the pieces whenever pieces are added or taken away, so
## nothing about them is saved. They're only drawn close up, like the pieces' detailed looks.

## How close two ends must be to count as meeting, and how far apart in angle walls must be (as
## the cosine) to need a post
const MEET := 0.05
const STRAIGHT := 0.985
## Drawn only this close (like the pieces' close-up looks)
const RANGE := 60.0

var registry: PieceRegistry

var _dirty := false
# key -> MeshInstance3D, and what each was made for (so unchanged ones stay)
var _shown := {}
var _made_for := {}


## Pieces were added or taken away: work it all out again, once, at the end of this frame
func mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_dirty = false
	if registry == null or registry.world == null or not is_inside_tree():
		return
	var wanted := {}
	var ends := {}
	var ridges := {}
	var caps := {}
	for piece in registry.all_pieces():
		var bp := piece as BuildPiece
		if bp.is_queued_for_deletion():
			continue
		var box := PieceShapes.bounds_of(bp.shape_def())
		for socket in bp.world_sockets():
			var type: String = socket["type"]
			var at: Vector3 = socket["position"]
			if type == "wall_end":
				# Which way the wall leaves this end (curved walls carrying on round a circle point
				# straight on into each other, so they get no post)
				var yaw: float = socket["yaw"]
				ends.get_or_add(_key(at), []).append({"at": at, "dir": Vector3(sin(yaw), 0, cos(yaw)), "top": at.y + box.end.y})
			elif type.begins_with("roof_high") or type.begins_with("overhang_high"):
				var shape := bp.buildable.shape
				# Only straight roof panels and gable overhangs (corners meet at an angle)
				if shape == "roof" or shape == "roof_45" or shape.begins_with("gable_overhang"):
					var width := PieceShapes.GRID if shape.begins_with("roof") else PieceShapes.OVERHANG
					var rise := PieceShapes.ROOF_RISE_45 if shape.ends_with("45") else PieceShapes.ROOF_RISE
					ridges.get_or_add(_key(at), []).append({"at": at, "dir": bp.global_basis.x, "out": -bp.global_basis.z, "width": width, "rise": rise})
			elif type.begins_with("ridge_cap"):
				caps[_key(at)] = true
	for key in ends:
		var list: Array = ends[key]
		if list.size() < 2 or not _bent(list):
			continue
		var at := Vector3.ZERO
		var top := -INF
		var bottom := INF
		for e in list:
			at += e["at"]
			top = maxf(top, e["top"])
			bottom = minf(bottom, (e["at"] as Vector3).y)
		at /= list.size()
		wanted["post" + str(key)] = {"kind": "post", "at": Vector3(at.x, bottom, at.z), "height": top - bottom + 0.06, "seed": hash(key)}
	for key in ridges:
		var list: Array = ridges[key]
		if list.size() < 2 or caps.has(key):
			continue
		var a: Dictionary = list[0]
		var b: Dictionary = list[1]
		# Back to back: facing opposite ways
		if (a["out"] as Vector3).dot(b["out"]) > -0.9:
			continue
		var lift := PieceShapes.ROOF_THICKNESS / cos(atan2(float(a["rise"]), PieceShapes.GRID))
		var at: Vector3 = (a["at"] as Vector3) + Vector3.UP * (lift + PieceDetail.RIDGE_RADIUS * 0.4)
		wanted["ridge" + str(key)] = {"kind": "ridge", "at": at, "dir": a["dir"], "length": float(a["width"]) + 0.04, "seed": hash(key)}
	# Take away what's no longer wanted, add what's new
	for key in _shown.keys():
		if not wanted.has(key) or _made_for[key] != wanted[key]:
			(_shown[key] as Node).queue_free()
			_shown.erase(key)
			_made_for.erase(key)
	for key in wanted:
		if _shown.has(key):
			continue
		var spec: Dictionary = wanted[key]
		var look := MeshInstance3D.new()
		look.material_override = registry.detail_material()
		look.visibility_range_end = RANGE
		if spec["kind"] == "post":
			look.mesh = PieceDetail.post_mesh(spec["height"], spec["seed"])
			registry.world.add_child(look)
			look.global_position = spec["at"]
		else:
			look.mesh = PieceDetail.ridge_mesh(spec["length"], spec["seed"])
			registry.world.add_child(look)
			var dir: Vector3 = spec["dir"]
			look.global_transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).orthonormalized(), spec["at"])
		_shown[key] = look
		_made_for[key] = spec


func _exit_tree() -> void:
	for key in _shown:
		if is_instance_valid(_shown[key]):
			(_shown[key] as Node).queue_free()
	_shown.clear()
	_made_for.clear()


# Do any two of these meet at an angle (not carrying straight on)?
func _bent(list: Array) -> bool:
	for i in list.size():
		for j in range(i + 1, list.size()):
			if absf((list[i]["dir"] as Vector3).dot(list[j]["dir"])) < STRAIGHT:
				return true
	return false


func _key(at: Vector3) -> Vector3i:
	return Vector3i(roundi(at.x / MEET), roundi(at.y / MEET), roundi(at.z / MEET))
