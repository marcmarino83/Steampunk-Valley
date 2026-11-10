class_name JointDetails
extends Node
## The details that belong to where pieces meet rather than to one piece: a rough log post (with
## rope lashings) wherever two or more walls, railings or fences meet end to end at an angle, a
## log along the peak wherever two roofs (or gable overhangs) meet back to back, unless a ridge cap
## is already there, and a lip of stone (or logs) reaching past every foundation edge no other
## foundation shares, so walls on the edge sit on top with a little stone showing. They're worked out from the pieces whenever pieces are added or taken away, so
## nothing about them is saved. They're only drawn close up, like the pieces' detailed looks.

## How close two ends must be to count as meeting, and how far apart in angle walls must be (as
## the cosine) to need a post
const MEET := 0.05
const STRAIGHT := 0.985
## Drawn only this close (like the pieces' close-up looks)
const RANGE := 60.0
## How long a foundation's edge is, by its snap point's type (for its lip)
const EDGE_LENGTHS := {
	"floor_edge": PieceShapes.GRID,
	"floor_edge_long": PieceShapes.LONG_EDGE,
	"floor_edge_short": PieceShapes.SHORT_EDGE,
}

var registry: PieceRegistry

var _dirty := false
# key -> MeshInstance3D, and what each was made for (so unchanged ones stay)
var _shown := {}
var _made_for := {}
## Meshes made once and shared: kind, size and one of MESH_VARIANTS -> ArrayMesh. Posts, logs and
## lips of the same size share a few versions, so Godot draws them together.
const MESH_VARIANTS := 4
var _meshes := {}


# The shared mesh for a detail (see _meshes), made the first time it's wanted
func _mesh_for(spec: Dictionary) -> ArrayMesh:
	var variant := posmod(int(spec["seed"]), MESH_VARIANTS)
	var kind: String = spec["kind"]
	var key := ""
	match kind:
		"post":
			key = "post:%.3f:%d" % [spec["height"], variant]
		"lip":
			key = "lip:%.3f:%s:%d" % [spec["length"], spec["stone"], variant]
		"arc":
			key = "arc:%.3f:%s:%d" % [spec["half"], spec["stone"], variant]
		_:
			key = "ridge:%.3f:%d" % [spec["length"], variant]
	if not _meshes.has(key):
		var seed_value := variant * 7919 + 13
		match kind:
			"post":
				_meshes[key] = PieceDetail.post_mesh(spec["height"], seed_value)
			"lip":
				_meshes[key] = PieceDetail.lip_mesh(spec["length"], spec["stone"], seed_value)
			"arc":
				_meshes[key] = PieceDetail.lip_arc_mesh(spec["half"], spec["stone"], seed_value)
			_:
				_meshes[key] = PieceDetail.ridge_mesh(spec["length"], seed_value)
	return _meshes[key]


## Pieces were added or taken away: work it all out again, once, at the end of this frame
func mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_dirty = false
	if registry == null or registry.world == null or not is_inside_tree():
		return
	var timing := SpikeLog.begin()
	var wanted := {}
	var ends := {}
	var ridges := {}
	var caps := {}
	var foundation_edges := {}
	for piece in registry.all_pieces():
		var bp := piece as BuildPiece
		# Ghosts (not built yet) get no posts, ridge logs or lips
		if bp.is_queued_for_deletion() or bp.is_ghost():
			continue
		var box := PieceShapes.bounds_of(bp.shape_def())
		var shape := bp.buildable.shape
		if shape.contains("foundation"):
			var stone := shape.contains("stone")
			if shape.begins_with("round"):
				# A round wedge's curved outside is always outside
				var half := 11.25 if shape.ends_with("_22") else 22.5
				wanted["arc%d" % bp.piece_id] = {"kind": "arc", "xform": bp.global_transform, "half": half, "stone": stone, "seed": bp.piece_id}
			for socket in bp.world_sockets():
				var length: float = EDGE_LENGTHS.get(socket["type"], 0.0)
				if length > 0.0:
					foundation_edges.get_or_add(_key(socket["position"]), []).append({"at": socket["position"], "yaw": socket["yaw"], "length": length, "stone": stone})
		for socket in bp.world_sockets():
			var type: String = socket["type"]
			var at: Vector3 = socket["position"]
			if type == "wall_end":
				# Which way the wall leaves this end (curved walls carrying on round a circle point
				# straight on into each other, so they get no post)
				var yaw: float = socket["yaw"]
				# As tall as the wall is at this end (a sloped gable wall is lower at one end)
				var height := box.end.y
				var end_tops: Array = bp.shape_def().get("end_tops", [])
				var plus_end := (bp.global_transform.affine_inverse() * at).x > 0.0
				if end_tops.size() == 2:
					height = end_tops[1] if plus_end else end_tops[0]
				# A split-window wall's open end (where the window runs on into the next wall)
				var open_ends: Array = bp.shape_def().get("open_ends", [])
				var open: bool = open_ends.size() == 2 and open_ends[1 if plus_end else 0]
				ends.get_or_add(_key(at), []).append({"at": at, "dir": Vector3(sin(yaw), 0, cos(yaw)), "top": at.y + height, "open": open})
			elif type.begins_with("roof_high") or type.begins_with("overhang_high"):
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
		# Two split-window walls joined at their open ends make one window: no post in it
		if list.all(func(e): return e.get("open", false)):
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
	# A foundation edge no other foundation shares is outside: it gets a lip
	for key in foundation_edges:
		var list: Array = foundation_edges[key]
		if list.size() != 1:
			continue
		var e: Dictionary = list[0]
		var yaw: float = e["yaw"]
		var out := Vector3(sin(yaw), 0, cos(yaw))
		var xform := Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), e["at"])
		wanted["lip" + str(key)] = {"kind": "lip", "xform": xform, "length": e["length"], "stone": e["stone"], "seed": hash(key)}
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
		look.mesh = _mesh_for(spec)
		if spec["kind"] == "post":
			registry.world.add_child(look)
			look.global_position = spec["at"]
		elif spec["kind"] == "lip" or spec["kind"] == "arc":
			# Low along the ground, under the walls: its shadow would never show
			look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			registry.world.add_child(look)
			look.global_transform = spec["xform"]
		else:
			registry.world.add_child(look)
			var dir: Vector3 = spec["dir"]
			look.global_transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).orthonormalized(), spec["at"])
		_shown[key] = look
		_made_for[key] = spec
	SpikeLog.end("corner posts and ridge logs rebuilt", timing)


func _exit_tree() -> void:
	for key in _shown:
		if is_instance_valid(_shown[key]):
			(_shown[key] as Node).queue_free()
	_shown.clear()
	_made_for.clear()
	_meshes.clear()


# Do any two of these meet at an angle (not carrying straight on)?
func _bent(list: Array) -> bool:
	for i in list.size():
		for j in range(i + 1, list.size()):
			if absf((list[i]["dir"] as Vector3).dot(list[j]["dir"])) < STRAIGHT:
				return true
	return false


func _key(at: Vector3) -> Vector3i:
	return Vector3i(roundi(at.x / MEET), roundi(at.y / MEET), roundi(at.z / MEET))
