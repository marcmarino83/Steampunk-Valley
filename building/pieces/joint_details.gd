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
## How long pieces must stop changing before the details are worked out again (see mark_dirty)
const QUIET_TIME := 0.2
var _quiet_left := 0.0
# key -> MeshInstance3D, and what each was made for (so unchanged ones stay)
var _shown := {}
var _made_for := {}
## Meshes made once and shared: kind, size and one of MESH_VARIANTS -> ArrayMesh. Posts, logs and
## lips of the same size share a few versions, so Godot draws them together.
const MESH_VARIANTS := 4
var _meshes := {}
# piece id -> what it adds to the joins, and where it stood then (see _facts_of)
var _facts := {}
# Those facts by join (spot key -> {piece id: entry}): wall ends, roofs' high edges, ridge caps and
# foundation edges; and each round foundation's arc lip (piece id -> spec)
var _ends := {}
var _ridges := {}
var _caps := {}
var _edges := {}
var _arcs := {}


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


## Pieces were added or taken away: work it all out again, once they've stopped changing for
## QUIET_TIME (a template's ghosts going in a few a frame, a save loading: one rebuild at the end,
## not one a frame)
func mark_dirty() -> void:
	_dirty = true
	_quiet_left = QUIET_TIME
	set_process(true)


func _ready() -> void:
	set_process(_dirty)


func _process(delta: float) -> void:
	_quiet_left -= delta
	if _quiet_left > 0.0:
		return
	set_process(false)
	if _dirty:
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	if registry == null or registry.world == null or not is_inside_tree():
		return
	var timing := SpikeLog.begin()
	# Only what changed is worked out again: each piece's facts (see _facts_of) sit in buckets by the
	# join they belong to; a piece placed, moved, taken away or turned into a ghost moves its facts in
	# or out, and only the joins it touched are looked at again (every join was worked out again on
	# every change before: 5 to 8 ms in a village, on top of each piece's sockets)
	var touched := {}
	var seen := {}
	for piece in registry._pieces.values():
		if not is_instance_valid(piece):
			continue
		var bp := piece as BuildPiece
		# Ghosts (not built yet) get no posts, ridge logs or lips
		if bp.is_queued_for_deletion() or bp.is_ghost():
			continue
		seen[bp.piece_id] = true
		var kept: Dictionary = _facts.get(bp.piece_id, {})
		if not kept.is_empty() and kept["at"] == bp.global_transform and kept["shape"] == bp.shape_name:
			continue
		if not kept.is_empty():
			_unbucket(bp.piece_id, kept, touched)
		_bucket(bp.piece_id, _facts_of(bp), touched)
	# (the facts of pieces gone are let go)
	for id in _facts.keys():
		if not seen.has(id):
			_unbucket(id, _facts[id], touched)
			_facts.erase(id)
	for name in touched:
		_show(name, _wanted(name, touched[name]))
	SpikeLog.end("corner posts and ridge logs rebuilt", timing)


# A piece's facts put in (or taken out of) the buckets, noting the joins they touch
func _bucket(id: int, facts: Dictionary, touched: Dictionary) -> void:
	for f in facts["ends"]:
		(_ends.get_or_add(f[0], {}) as Dictionary)[id] = f[1]
		touched["post" + str(f[0])] = f[0]
	for f in facts["ridges"]:
		(_ridges.get_or_add(f[0], {}) as Dictionary)[id] = f[1]
		touched["ridge" + str(f[0])] = f[0]
	for key in facts["caps"]:
		(_caps.get_or_add(key, {}) as Dictionary)[id] = true
		touched["ridge" + str(key)] = key
	for f in facts["foundation_edges"]:
		(_edges.get_or_add(f[0], {}) as Dictionary)[id] = f[1]
		touched["lip" + str(f[0])] = f[0]
	if not (facts["arc"] as Dictionary).is_empty():
		_arcs[id] = facts["arc"]
		touched["arc%d" % id] = id


func _unbucket(id: int, facts: Dictionary, touched: Dictionary) -> void:
	for pair in [[facts["ends"], _ends, "post"], [facts["ridges"], _ridges, "ridge"], [facts["foundation_edges"], _edges, "lip"]]:
		for f in pair[0]:
			var bucket: Dictionary = (pair[1] as Dictionary).get(f[0], {})
			bucket.erase(id)
			if bucket.is_empty():
				(pair[1] as Dictionary).erase(f[0])
			touched[pair[2] + str(f[0])] = f[0]
	for key in facts["caps"]:
		var bucket: Dictionary = _caps.get(key, {})
		bucket.erase(id)
		if bucket.is_empty():
			_caps.erase(key)
		touched["ridge" + str(key)] = key
	if _arcs.has(id):
		_arcs.erase(id)
		touched["arc%d" % id] = id


# What a join wants now (a post, a ridge log, a lip or an arc's lip), or empty for nothing. `key`: the
# join's spot (see _key), or for an arc the piece's id
func _wanted(name: String, key: Variant) -> Dictionary:
	if name.begins_with("arc"):
		return _arcs.get(int(key), {})
	if name.begins_with("post"):
		var list: Array = (_ends.get(key, {}) as Dictionary).values()
		if list.size() < 2 or not _bent(list):
			return {}
		# Two split-window walls joined at their open ends make one window: no post in it
		if list.all(func(e): return e.get("open", false)):
			return {}
		var at := Vector3.ZERO
		var top := -INF
		var bottom := INF
		for e in list:
			at += e["at"]
			top = maxf(top, e["top"])
			bottom = minf(bottom, (e["at"] as Vector3).y)
		at /= list.size()
		return {"kind": "post", "at": Vector3(at.x, bottom, at.z), "height": top - bottom + 0.06, "seed": hash(key)}
	if name.begins_with("ridge"):
		var list: Array = (_ridges.get(key, {}) as Dictionary).values()
		if list.size() < 2 or not (_caps.get(key, {}) as Dictionary).is_empty():
			return {}
		var a: Dictionary = list[0]
		var b: Dictionary = list[1]
		# Back to back: facing opposite ways
		if (a["out"] as Vector3).dot(b["out"]) > -0.9:
			return {}
		var lift := PieceShapes.ROOF_THICKNESS / cos(atan2(float(a["rise"]), PieceShapes.GRID))
		var at: Vector3 = (a["at"] as Vector3) + Vector3.UP * (lift + PieceDetail.RIDGE_RADIUS * 0.4)
		return {"kind": "ridge", "at": at, "dir": a["dir"], "length": float(a["width"]) + 0.04, "seed": hash(key)}
	# A foundation edge no other foundation shares is outside: it gets a lip
	var list: Array = (_edges.get(key, {}) as Dictionary).values()
	if list.size() != 1:
		return {}
	var e: Dictionary = list[0]
	var yaw: float = e["yaw"]
	var out := Vector3(sin(yaw), 0, cos(yaw))
	var xform := Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), e["at"])
	return {"kind": "lip", "xform": xform, "length": e["length"], "stone": e["stone"], "seed": hash(key)}


# A join's look shown as it's wanted now: left as it is if unchanged, made again if changed, taken
# away if nothing is wanted there any more
func _show(name: String, spec: Dictionary) -> void:
	if _shown.has(name):
		if not spec.is_empty() and _made_for[name] == spec:
			return
		(_shown[name] as Node).queue_free()
		_shown.erase(name)
		_made_for.erase(name)
	if spec.is_empty():
		return
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
	_shown[name] = look
	_made_for[name] = spec


# What one piece adds to the joins (its round arc's lip, its foundation edges, its wall ends, its
# roofs' high edges, its ridge caps), worked out once and kept while it stays where it is: a piece
# placed or taken away changes nothing about the others, so only new or moved pieces are worked out
# again (it used to be every piece's sockets on every change: 20 to 30 ms in a village)
func _facts_of(bp: BuildPiece) -> Dictionary:
	var kept: Dictionary = _facts.get(bp.piece_id, {})
	if not kept.is_empty() and kept["at"] == bp.global_transform and kept["shape"] == bp.shape_name:
		return kept
	var facts := {"at": bp.global_transform, "shape": bp.shape_name, "arc": {}, "foundation_edges": [], "ends": [], "ridges": [], "caps": []}
	var box := PieceShapes.bounds_of(bp.shape_def())
	var shape := bp.buildable.shape
	var sockets := bp.world_sockets()
	if shape.contains("foundation"):
		var stone := shape.contains("stone")
		if shape.begins_with("round"):
			# A round wedge's curved outside is always outside
			var half := 11.25 if shape.ends_with("_22") else 22.5
			facts["arc"] = {"kind": "arc", "xform": bp.global_transform, "half": half, "stone": stone, "seed": bp.piece_id}
		for socket in sockets:
			var length: float = EDGE_LENGTHS.get(socket["type"], 0.0)
			if length > 0.0:
				facts["foundation_edges"].append([_key(socket["position"]), {"at": socket["position"], "yaw": socket["yaw"], "length": length, "stone": stone}])
	for socket in sockets:
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
			facts["ends"].append([_key(at), {"at": at, "dir": Vector3(sin(yaw), 0, cos(yaw)), "top": at.y + height, "open": open}])
		elif type.begins_with("roof_high") or type.begins_with("overhang_high"):
			# Only straight roof panels and gable overhangs (corners meet at an angle)
			if shape == "roof" or shape == "roof_45" or shape.begins_with("gable_overhang"):
				var width := PieceShapes.GRID if shape.begins_with("roof") else PieceShapes.OVERHANG
				var rise := PieceShapes.ROOF_RISE_45 if shape.ends_with("45") else PieceShapes.ROOF_RISE
				facts["ridges"].append([_key(at), {"at": at, "dir": bp.global_basis.x, "out": -bp.global_basis.z, "width": width, "rise": rise}])
		elif type.begins_with("ridge_cap"):
			facts["caps"].append(_key(at))
	_facts[bp.piece_id] = facts
	return facts


func _exit_tree() -> void:
	_facts.clear()
	for bucket in [_ends, _ridges, _caps, _edges, _arcs]:
		(bucket as Dictionary).clear()
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
