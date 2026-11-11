class_name BugSnapshot
extends Node
## The bug snapshot key (F9, debug builds only). Pressing it in the game saves, in
## docs/reference/ours/:
##   snap_<date-time>.png        the screen, rendered brighter (the exposure raised for that one
##                               frame) so dark interiors can be read
##   snap_<date-time>.json       what's needed to see it again and make sense of it: the camera's
##                               exact place and rotation, the save file loaded (and the last one
##                               written), and the building piece under the crosshair (its id,
##                               type, place and rotation, the pieces whose snap points its own
##                               meet, and how near the nearest other snap point is to each of
##                               its own)
##   snap_<date-time>_save.json  the whole game as it stood, as a save file, so pieces placed since
##                               the last save are there too
## and shows "Snapshot saved" for a moment (after the picture is taken, so it isn't in it).
##
## tests/snapshot_replay.tscn loads a snapshot's game, puts the camera exactly where it was and
## takes the picture again, the same way (see there).

const FOLDER := "res://docs/reference/ours"
## How much brighter the picture is rendered (the environment's exposure, times this)
const EXPOSURE_BOOST := 2.5
## How far the crosshair looks for a piece, in meters
const LOOK_REACH := 40.0
## How near another piece's snap point counts as meeting one (m), and how far round each of the
## piece's own snap points the nearest other is looked for
const MEET := 0.001
const NEAR_REACH := 3.0

var player
var _busy := false


func _ready() -> void:
	name = "BugSnapshot"
	process_mode = Node.PROCESS_MODE_ALWAYS


## Takes the snapshot (F9)
func take() -> void:
	if _busy:
		return
	_busy = true
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var folder := ProjectSettings.globalize_path(FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var base := folder.path_join("snap_" + stamp)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var info := describe(player, camera)
	info["taken"] = Time.get_datetime_string_from_system(false, true)
	# Which code took it (see BuildStamp)
	info["build"] = BuildStamp.text()
	info["code_hash"] = BuildStamp.code_hash()
	info["picture"] = "snap_%s.png" % stamp
	info["state_file"] = "snap_%s_save.json" % stamp
	info["save_loaded"] = SaveGame.loaded_path
	info["save_loaded_file"] = ProjectSettings.globalize_path(SaveGame.loaded_path) if not SaveGame.loaded_path.is_empty() else ""
	info["last_save_written"] = SaveGame.last_written_path
	info["test_run"] = SaveGame._test_run
	# (the window's real size, so a replay frames it the same; the viewport's own size is the HUD's
	# 1920 × 1080 layout, whatever the window)
	var window := DisplayServer.window_get_size()
	info["window_size"] = [window.x, window.y]
	_write(base + "_save.json", SaveGame.state_now("snapshot"))
	_write(base + ".json", info)
	var image := await bright_picture(self)
	image.save_png(base + ".png")
	if player and player.has_method("flash"):
		player.flash("Snapshot saved")
	_busy = false


## The screen, rendered with the exposure raised for one frame (then put back)
static func bright_picture(node: Node) -> Image:
	var environment := _environment(node)
	var before := environment.tonemap_exposure if environment else 1.0
	if environment:
		environment.tonemap_exposure = before * EXPOSURE_BOOST
	# (the change shows from the next frame drawn)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := node.get_viewport().get_texture().get_image()
	if environment:
		environment.tonemap_exposure = before
	return image


static func _environment(node: Node) -> Environment:
	var found := node.get_tree().root.find_children("*", "WorldEnvironment", true, false)
	return (found[0] as WorldEnvironment).environment if not found.is_empty() else null


## The camera, the player, what the crosshair is on, and the piece there (see the class notes)
static func describe(the_player, camera: Camera3D) -> Dictionary:
	var t := camera.global_transform
	var q := t.basis.get_rotation_quaternion()
	var info := {
		"camera": {
			"position": _vec(t.origin),
			"rotation_degrees": _vec(camera.global_rotation_degrees),
			"quaternion": [q.x, q.y, q.z, q.w],
			"fov": camera.fov,
		},
	}
	if the_player:
		info["player"] = {"position": _vec(the_player.global_position), "turn": the_player.rotation.y, "look": camera.rotation.x}
	var query := PhysicsRayQueryParameters3D.create(t.origin, t.origin - t.basis.z * LOOK_REACH)
	if the_player is CollisionObject3D:
		query.exclude = [(the_player as CollisionObject3D).get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var registry: PieceRegistry = the_player._placer.registry if the_player else null
	if hit.is_empty():
		info["crosshair"] = {"hit": false}
	else:
		var collider: Node = hit["collider"]
		info["crosshair"] = {"hit": true, "point": _vec(hit["position"]), "normal": _vec(hit["normal"]), "collider": str(collider.name), "distance": t.origin.distance_to(hit["position"])}
		if collider is BuildPiece:
			info["crosshair"]["piece_id"] = (collider as BuildPiece).piece_id
	if registry == null:
		return info
	# The piece under the crosshair is the one whose look it meets first: much of what's drawn has no
	# collision (a flight's stringers and header board, trim), so the physics hit can be behind it
	var reach: float = info["crosshair"]["distance"] + 0.01 if hit else LOOK_REACH
	var seen := visible_piece(registry, t.origin, -t.basis.z, reach)
	var piece: BuildPiece = seen["piece"] if not seen.is_empty() else (hit["collider"] if hit and hit["collider"] is BuildPiece else null)
	if not seen.is_empty():
		info["crosshair"]["look_point"] = _vec(seen["point"])
		info["crosshair"]["look_distance"] = seen["distance"]
		info["crosshair"]["look_piece_id"] = (seen["piece"] as BuildPiece).piece_id
	if piece:
		info["piece"] = describe_piece(piece, registry)
	return info


# Each mesh's triangles, worked out once, for meeting rays with what's drawn
static var _triangles := {}


## The building piece whose drawn look a ray (world) meets first within `reach`: {"piece",
## "distance", "point"}, or empty
static func visible_piece(registry: PieceRegistry, from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var candidates := {}
	var along := 0.0
	while along <= reach + 3.0:
		for p in registry.pieces_near(from + dir * along, 5.0):
			candidates[p] = true
		along += 3.0
	var best := {}
	for piece: BuildPiece in candidates:
		if not is_instance_valid(piece):
			continue
		var looks: Array = piece.find_children("*", "MeshInstance3D", true, false)
		for look in piece._detail_looks:
			if not looks.has(look):
				looks.append(look)
		for look in looks:
			var mi := look as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
				continue
			# (only the look drawn at this distance, not the shadow-only copies: each look shows over
			# its own range of distance from the camera)
			if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				continue
			var away := from.distance_to(mi.global_transform * mi.get_aabb().get_center())
			if away < mi.visibility_range_begin or (mi.visibility_range_end > 0.0 and away > mi.visibility_range_end):
				continue
			if not _triangles.has(mi.mesh):
				_triangles[mi.mesh] = mi.mesh.generate_triangle_mesh()
			var tri: TriangleMesh = _triangles[mi.mesh]
			if tri == null:
				continue
			var inv := mi.global_transform.affine_inverse()
			var hit := tri.intersect_ray(inv * from, inv.basis * dir)
			if hit.is_empty():
				continue
			var point: Vector3 = mi.global_transform * (hit["position"] as Vector3)
			var d := (point - from).dot(dir)
			if d >= 0.0 and d <= reach and (best.is_empty() or d < float(best["distance"])):
				best = {"piece": piece, "distance": d, "point": point}
	return best


## A building piece: id, type, where and how it's turned, its snap points, the pieces whose snap
## points meet its own (with which), and the nearest other snap point to each of its own (within
## NEAR_REACH; piece -1 and distance -1 if there's none)
static func describe_piece(piece: BuildPiece, registry: PieceRegistry) -> Dictionary:
	var t := piece.global_transform
	var q := t.basis.get_rotation_quaternion()
	var own := SnapCorners.in_world(piece)
	var snapped := []
	var nearest := []
	for c: Vector3 in own:
		nearest.append({"own": _vec(c), "nearest": [], "piece": -1, "distance": -1.0})
	for other in registry.pieces_near(t.origin, 12.0):
		if other == piece or not is_instance_valid(other):
			continue
		var theirs := SnapCorners.in_world(other)
		var meeting := []
		for i in own.size():
			for p: Vector3 in theirs:
				var d := (own[i] as Vector3).distance_to(p)
				if d < MEET:
					meeting.append(_vec(own[i]))
				var best := float(nearest[i]["distance"])
				if (best < 0.0 or d < best) and d <= NEAR_REACH:
					nearest[i] = {"own": _vec(own[i]), "nearest": _vec(p), "piece": (other as BuildPiece).piece_id, "distance": d}
		if not meeting.is_empty():
			snapped.append({"id": other.piece_id, "type": other.shape_name, "position": _vec(other.global_position), "corners_meeting": meeting})
	return {
		"id": piece.piece_id,
		"type": piece.shape_name,
		"buildable": piece.buildable.resource_path if piece.buildable else "",
		"position": _vec(t.origin),
		"rotation_degrees": _vec(piece.global_rotation_degrees),
		"quaternion": [q.x, q.y, q.z, q.w],
		"snap_points": own.map(func(c): return _vec(c)),
		"snapped_to": snapped,
		"nearest_snap_points": nearest,
	}


static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("BugSnapshot: couldn't write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
