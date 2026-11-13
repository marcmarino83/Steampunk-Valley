class_name FurnitureSpot
extends RefCounted
## Where a piece of furniture (or a workbench, chest or campfire) stands when it's placed: resting
## on the floor, foundation or ground under the crosshair. Snapping (Shift not held), on a floor it
## sits on FURNITURE_GRID in the floor's own frame, facing the floor's way (the wheel's turn goes on
## top of that); furniture that backs onto walls stands flush against a wall face aimed at, or one
## close behind it, and wall-mounted furniture (the tool rack) hangs on it. (Moved as it was from
## the old piece placer; nothing here snaps building pieces.)

## The grid it snaps to on a floor, how far below the crosshair it looks for something to stand
## on, and how close to a wall (beyond its back) it backs up against it
const FURNITURE_GRID := 0.25
const SUPPORT_DROP := 4.0
const WALL_BACK_REACH := 0.6

var _player: CharacterBody3D


func _init(player: CharacterBody3D) -> void:
	_player = player


## Where it would stand, given the crosshair's hit (or the end of its reach), before the player's
## turn: {"where", "support" (what it stands on), "on_floor", "normal", "snap" ("On grid",
## "Against wall", "On wall" or "")}, or empty if there's nothing to stand on. `bounds` is its own
## box (its back is -Z); `backs` if it backs onto walls; `mount` how far up a wall it hangs (0:
## it stands); `snapping` false while Shift is held.
func find(hit: Dictionary, far_point: Vector3, bounds: AABB, backs: bool, mount: float, snapping: bool, skip: Array[RID] = []) -> Dictionary:
	var camera: Camera3D = _player.camera
	var toward := (camera.global_position - far_point).normalized()
	# Aimed at a wall's face: furniture that backs onto walls stands (or, wall-mounted, hangs)
	# flush against that face, on the side aimed at
	if (backs or mount > 0.0) and snapping and not hit.is_empty() and _is_wall_face(hit):
		var on_wall := _against_wall_face(hit, bounds, mount, skip)
		if not on_wall.is_empty():
			return on_wall
	var start: Vector3 = (hit["position"] + toward * 0.05) if not hit.is_empty() else far_point
	var support := _support_under(start, skip)
	if support.is_empty():
		return {}
	var floor_piece: BuildPiece = support["collider"] if support["collider"] is BuildPiece else null
	var spot: Vector3 = support["position"]
	var snap := ""
	var yaw := 0.0
	if snapping and floor_piece:
		yaw = floor_piece.global_rotation.y
		var local := floor_piece.global_transform.affine_inverse() * spot
		local.x = snappedf(local.x, FURNITURE_GRID)
		local.z = snappedf(local.z, FURNITURE_GRID)
		spot = floor_piece.global_transform * local
		spot.y = support["position"].y
		snap = "On grid"
	var where := Transform3D(Basis(Vector3.UP, yaw), spot)
	if (backs or mount > 0.0) and snapping:
		var backed := _backed_to_wall(where, bounds, skip)
		if backed != where:
			where = backed
			snap = "Against wall"
			# Wall-mounted: hung on the wall it backed onto, not standing on the floor
			if mount > 0.0:
				where.origin.y += mount
				snap = "On wall"
	return {"where": where, "support": support["collider"], "on_floor": floor_piece != null, "normal": support["normal"], "snap": snap}


# The floor, foundation or ground straight below a spot (passing through furniture, walls and
# anything else), or empty
func _support_under(from: Vector3, skip: Array[RID]) -> Dictionary:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.05, from + Vector3.DOWN * SUPPORT_DROP)
	var exclude: Array[RID] = [_player.get_rid()]
	exclude.append_array(skip)
	for i in 8:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var other: Object = hit["collider"]
		if other.is_in_group("terrain_ground") or (other is BuildPiece and other.is_floor()):
			return hit
		exclude.append(hit["rid"])
	return {}


# True if a ray hit is on an upright face of a building piece that isn't furniture (a wall)
func _is_wall_face(hit: Dictionary) -> bool:
	var other: Object = hit.get("collider")
	return other is BuildPiece and not other.is_furniture() and not other.is_ghost() and absf((hit["normal"] as Vector3).y) < 0.3


# Furniture against the wall face a ray hit: facing out of it, its back flush on the face (just off
# it), slid along the wall on FURNITURE_GRID in the wall's own frame. Standing furniture rests on
# the floor under it (on the side aimed at); wall-mounted furniture (`mount` > 0) hangs with its
# bottom `mount` above the wall's foot. Empty if standing furniture finds no floor there.
func _against_wall_face(hit: Dictionary, bounds: AABB, mount: float, skip: Array[RID]) -> Dictionary:
	var wall: BuildPiece = hit["collider"]
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	normal = normal.normalized()
	var face: Vector3 = hit["position"]
	# Along the wall, on the grid (its own frame), staying on the face aimed at
	var local := wall.global_transform.affine_inverse() * face
	local.x = snappedf(local.x, FURNITURE_GRID)
	var along := wall.global_transform * local
	face += (along - face) - normal * (along - face).dot(normal)
	var y: float
	var support = null
	if mount > 0.0:
		y = wall.global_position.y + mount
	else:
		var under := _support_under(face + normal * 0.3, skip)
		if under.is_empty():
			return {}
		y = under["position"].y
		support = under["collider"]
	var origin := face + normal * (-bounds.position.z + 0.005)
	origin.y = y
	var where := Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z)), origin)
	return {"where": where, "support": support if support else wall, "on_floor": support is BuildPiece, "normal": Vector3.UP, "snap": "On wall" if mount > 0.0 else "Against wall"}


# Slides furniture back (along its -Z) until its back touches a wall close behind it, or returns
# it as it was if there's none within WALL_BACK_REACH. The rays start at its front, so a spot that
# begins inside a wall still finds the wall's near face (and comes out on that side).
func _backed_to_wall(where: Transform3D, bounds: AABB, skip: Array[RID]) -> Transform3D:
	var space := _player.get_world_3d().direct_space_state
	var back := -where.basis.z
	var depth := -bounds.position.z
	var front := maxf(bounds.end.z, 0.0)
	var nearest := INF
	for height: float in [0.3, 0.9]:
		var from := where.origin + Vector3.UP * height - back * front
		var query := PhysicsRayQueryParameters3D.create(from, from + back * (front + depth + WALL_BACK_REACH))
		var exclude: Array[RID] = [_player.get_rid()]
		exclude.append_array(skip)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var wall: Object = hit["collider"]
		# A wall: a building piece with an upright face, not furniture
		if wall is BuildPiece and not wall.is_furniture() and absf((hit["normal"] as Vector3).y) < 0.3:
			nearest = minf(nearest, from.distance_to(hit["position"]))
	if nearest == INF:
		return where
	return Transform3D(where.basis, where.origin + back * (nearest - front - depth - 0.005))
