class_name SettlementNav
extends Node3D
## The ground settlers can walk on: a navigation mesh in square tiles (TILE meters across), kept
## only where it's needed: around every plot (with PLOT_MARGIN to spare, so arrivals can walk in)
## and around every settler. Each tile is baked from the valley's heights (water left out) and the
## solid shapes standing on it: building pieces, furniture, the workbench, chests, campfires, trees
## and rocks. Doors are left out, so settlers path through doorways (they open doors as they pass).
##
## Once a second every tile's pieces are looked over; a tile whose pieces were placed, demolished
## or moved since it was baked is baked again (one tile per physics frame, so nothing hitches).
## Neighbouring tiles join up seamlessly (each is baked with a border of the ground around it).

const TILE := 32.0
## Ground around each plot and each settler that gets a navigation mesh
const PLOT_MARGIN := 64.0
const SETTLER_MARGIN := 20.0
## How much of the surroundings each tile is baked with, beyond its edges (left out of the result)
const BORDER := 2.0
## The ground is sampled this often (meters) for baking
const GROUND_STEP := 1.0
## How often tiles are looked over for changes, in seconds
const CHECK_SECONDS := 1.0
## Settlers: how wide, tall, and how high a step or steep a slope they manage
const AGENT_RADIUS := 0.25
const AGENT_HEIGHT := 1.75
const AGENT_CLIMB := 0.5
const AGENT_SLOPE := 40.0
## Things this far past a tile's edge can still change it (the widest piece is under 3 m)
const REACH := 3.0
## How many things one tile's shape search can find
const MAX_SHAPES := 512

## The plots (for where tiles are needed) and the settlers' manager
var plots: PlotRegistry
var settlers: Node

# Vector2i -> {"region": NavigationRegion3D, "signature": int, "baked": bool}
var _tiles := {}
var _queue: Array[Vector2i] = []
var _check_in := 0.0


func _ready() -> void:
	name = "SettlementNav"
	top_level = true
	global_transform = Transform3D.IDENTITY


## True once the tile under a spot has been baked
func is_ready_at(spot: Vector3) -> bool:
	var tile: Dictionary = _tiles.get(_tile_of(spot), {})
	return tile.get("baked", false)


## The nearest walkable spot to a point (the point itself if there's no navigation there yet)
func closest_point(spot: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return spot
	var found := NavigationServer3D.map_get_closest_point(map, spot)
	return found if found != Vector3.ZERO else spot


func _physics_process(delta: float) -> void:
	_check_in -= delta
	if _check_in <= 0.0:
		_check_in = CHECK_SECONDS
		var timing := SpikeLog.begin()
		_update_tiles()
		SpikeLog.end("settler navigation: what changed", timing)
	if not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		if _tiles.has(key):
			var timing := SpikeLog.begin()
			_bake(key)
			SpikeLog.end("settler navigation: tile baked", timing)


# Works out which tiles are needed (adding and dropping tiles), and queues any that changed
func _update_tiles() -> void:
	var wanted := {}
	if plots:
		for plot in plots.all_plots():
			var half: Vector2 = plot.size / 2.0
			var reach := half.length() + PLOT_MARGIN
			_want_around(wanted, plot.global_position, reach)
	if settlers:
		for settler in settlers.all_settlers():
			_want_around(wanted, settler.global_position, SETTLER_MARGIN)
	for key in _tiles.keys():
		if not wanted.has(key):
			(_tiles[key]["region"] as Node).queue_free()
			_tiles.erase(key)
			_queue.erase(key)
	var signatures := _signatures(wanted)
	for key in wanted:
		var signature: int = signatures.get(key, 0)
		if not _tiles.has(key):
			var region := NavigationRegion3D.new()
			region.name = "Tile_%d_%d" % [key.x, key.y]
			add_child(region)
			_tiles[key] = {"region": region, "signature": signature, "baked": false}
			_queue.append(key)
		elif _tiles[key]["signature"] != signature and not _queue.has(key):
			_tiles[key]["signature"] = signature
			_queue.append(key)


func _want_around(wanted: Dictionary, spot: Vector3, reach: float) -> void:
	var low := _tile_of(spot - Vector3(reach, 0, reach))
	var high := _tile_of(spot + Vector3(reach, 0, reach))
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			wanted[Vector2i(x, z)] = true


# A number for each wanted tile that changes whenever anything solid built on it is placed,
# removed or moved
func _signatures(wanted: Dictionary) -> Dictionary:
	var sums := {}
	var things: Array = get_tree().get_nodes_in_group("build_pieces") + get_tree().get_nodes_in_group("buildings")
	for thing in things:
		var node := thing as Node3D
		if node == null or not node.is_inside_tree() or node.is_queued_for_deletion():
			continue
		var at := node.global_position
		var mark := hash([node.get_instance_id(), node.global_transform])
		var low := _tile_of(at - Vector3(REACH, 0, REACH))
		var high := _tile_of(at + Vector3(REACH, 0, REACH))
		for x in range(low.x, high.x + 1):
			for z in range(low.y, high.y + 1):
				var key := Vector2i(x, z)
				if wanted.has(key):
					sums[key] = int(sums.get(key, 0)) ^ mark
	return sums


func _tile_of(spot: Vector3) -> Vector2i:
	return Vector2i(floori(spot.x / TILE), floori(spot.z / TILE))


# Bakes one tile from the ground and everything standing on it
func _bake(key: Vector2i) -> void:
	var valley = get_tree().get_first_node_in_group("valley")
	if valley == null or not valley.has_heights():
		_queue.append(key)
		return
	var low := Vector2(key.x * TILE, key.y * TILE)
	var area := Rect2(low - Vector2(BORDER, BORDER), Vector2(TILE + BORDER * 2.0, TILE + BORDER * 2.0))
	var source := NavigationMeshSourceGeometryData3D.new()
	var heights := _add_ground(source, valley, area)
	if heights.x > heights.y:
		# All water (or off the map): nothing to walk on
		_finish(key, null)
		return
	_add_shapes(source, area, heights)
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.agent_height = AGENT_HEIGHT
	navmesh.agent_max_climb = AGENT_CLIMB
	navmesh.agent_max_slope = AGENT_SLOPE
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.border_size = BORDER
	navmesh.filter_baking_aabb = AABB(Vector3(area.position.x, heights.x - 5.0, area.position.y), Vector3(area.size.x, heights.y - heights.x + 40.0, area.size.y))
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	_finish(key, navmesh)


func _finish(key: Vector2i, navmesh: NavigationMesh) -> void:
	var tile: Dictionary = _tiles[key]
	(tile["region"] as NavigationRegion3D).navigation_mesh = navmesh if navmesh else NavigationMesh.new()
	tile["baked"] = true


# The ground in an area as triangles, leaving out anything under water. Returns the lowest and
# highest ground heights found (x > y if there was no dry ground at all).
func _add_ground(source: NavigationMeshSourceGeometryData3D, valley: Node3D, area: Rect2) -> Vector2:
	var origin := valley.global_position
	var water: float = origin.y + valley.water_height()
	var map: Rect2 = valley.map_rect()
	var steps := ceili(area.size.x / GROUND_STEP)
	var points := PackedVector3Array()
	points.resize((steps + 1) * (steps + 1))
	for j in steps + 1:
		for i in steps + 1:
			var x := area.position.x + i * GROUND_STEP
			var z := area.position.y + j * GROUND_STEP
			var y: float = origin.y + valley.get_surface_height(x - origin.x, z - origin.z)
			if not map.has_point(Vector2(x - origin.x, z - origin.z)):
				y = water - 10.0
			points[j * (steps + 1) + i] = Vector3(x, y, z)
	var faces := PackedVector3Array()
	var lowest := INF
	var highest := -INF
	for j in steps:
		for i in steps:
			var a := points[j * (steps + 1) + i]
			var b := points[j * (steps + 1) + i + 1]
			var c := points[(j + 1) * (steps + 1) + i]
			var d := points[(j + 1) * (steps + 1) + i + 1]
			if minf(minf(a.y, b.y), minf(c.y, d.y)) < water + 0.05:
				continue
			# Wound clockwise seen from above, as the baker wants for an upward face
			faces.append_array([a, b, c, b, d, c])
			lowest = minf(lowest, minf(minf(a.y, b.y), minf(c.y, d.y)))
			highest = maxf(highest, maxf(maxf(a.y, b.y), maxf(c.y, d.y)))
	if not faces.is_empty():
		source.add_faces(faces, Transform3D.IDENTITY)
	return Vector2(lowest, highest)


# Every solid shape standing in the area (not the ground itself, not doors, nothing that moves)
func _add_shapes(source: NavigationMeshSourceGeometryData3D, area: Rect2, heights: Vector2) -> void:
	var box := BoxShape3D.new()
	var tall := heights.y - heights.x + 60.0
	box.size = Vector3(area.size.x, tall, area.size.y)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, Vector3(area.get_center().x, heights.x - 10.0 + tall / 2.0, area.get_center().y))
	var hits := get_world_3d().direct_space_state.intersect_shape(query, MAX_SHAPES)
	var done := {}
	for hit in hits:
		var body := hit["collider"] as CollisionObject3D
		if body == null or not _counts(body):
			continue
		var owner_id := body.shape_find_owner(int(hit["shape"]))
		var key := "%d:%d" % [body.get_instance_id(), owner_id]
		if done.has(key):
			continue
		done[key] = true
		var holder = body.shape_owner_get_owner(owner_id)
		if not holder is Node3D:
			continue
		var where: Transform3D = (holder as Node3D).global_transform
		for k in body.shape_owner_get_shape_count(owner_id):
			var faces := shape_faces(body.shape_owner_get_shape(owner_id, k))
			if not faces.is_empty():
				source.add_faces(faces, where)


# Whether a solid thing shapes the walkable ground: not the terrain (added from its heights), the
# valley's edge walls, doors, settlers, the player, or anything that moves
func _counts(body: CollisionObject3D) -> bool:
	if body is CharacterBody3D or body is RigidBody3D or body is Area3D:
		return false
	if body.is_in_group("terrain_ground") or body.is_in_group("valley"):
		return false
	if body is BuildPiece and body.is_door():
		return false
	return true


## A collision shape as a list of triangles in its own space (boxes, convex shapes, trimeshes;
## cylinders, capsules and spheres as boxes around them)
static func shape_faces(shape: Shape3D) -> PackedVector3Array:
	if shape is BoxShape3D:
		return _box_faces((shape as BoxShape3D).size / 2.0)
	if shape is ConvexPolygonShape3D:
		return _hull_faces((shape as ConvexPolygonShape3D).points)
	if shape is ConcavePolygonShape3D:
		return (shape as ConcavePolygonShape3D).get_faces()
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return _box_faces(Vector3(cylinder.radius, cylinder.height / 2.0, cylinder.radius))
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return _box_faces(Vector3(capsule.radius, capsule.height / 2.0, capsule.radius))
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return _box_faces(Vector3(r, r, r))
	return PackedVector3Array()


static func _box_faces(half: Vector3) -> PackedVector3Array:
	var c := []
	for i in 8:
		c.append(Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z))
	# Each face wound clockwise seen from outside (the baker's front faces), so the top faces up
	var quads := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var faces := PackedVector3Array()
	for q in quads:
		faces.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return faces


# The outside faces of a convex shape's points (they're few, so every triple is tried)
static func _hull_faces(points: PackedVector3Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var n := points.size()
	if n < 4 or n > 40:
		if n >= 4:
			var box := AABB(points[0], Vector3.ZERO)
			for p in points:
				box = box.expand(p)
			var shifted := _box_faces(box.size / 2.0)
			for i in shifted.size():
				shifted[i] += box.get_center()
			return shifted
		return faces
	var middle := Vector3.ZERO
	for p in points:
		middle += p
	middle /= n
	var seen := {}
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				var normal := (points[b] - points[a]).cross(points[c] - points[a])
				if normal.length_squared() < 1e-8:
					continue
				normal = normal.normalized()
				var d := normal.dot(points[a])
				var above := false
				var below := false
				for k in n:
					var side := normal.dot(points[k]) - d
					if side > 1e-4:
						above = true
					elif side < -1e-4:
						below = true
					if above and below:
						break
				if above and below:
					continue
				# One triangle per face plane is enough to block or carry the ground
				var plane_key := "%.3f,%.3f,%.3f,%.3f" % [normal.x, normal.y, normal.z, d] if not above else "%.3f,%.3f,%.3f,%.3f" % [-normal.x, -normal.y, -normal.z, -d]
				# Clockwise seen from outside: the cross product of its edges points inward
				var tri := [points[a], points[b], points[c]]
				if normal.dot(middle) - d < 0.0:
					tri = [points[a], points[c], points[b]]
				if not seen.has(plane_key + str(a) + str(b) + str(c)):
					seen[plane_key + str(a) + str(b) + str(c)] = true
					faces.append_array(tri)
	return faces
