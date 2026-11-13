extends Node
## Path strips pictured in daylight, with a few numbers. Run in a window:
##
##     godot --path . res://tests/path_shots.tscn --resolution 1920x1080 --quit-after 6000
##
## Opens the world, finds flat open ground with the sun behind the camera, hides the screen's
## overlays, and lays (the way the placer does, round ends where a strip carries on from one of
## its type):
##   - a winding dirt path: three straight strips with two bends;
##   - a road three strips wide: dirt along both edges, gravel inside them, stone down the middle.
## Pictures them close up and from 10 m into docs/reference/ours/paths/, then prints:
##   - how far the dirt reaches past its strip's edge (without the shader's fine fray);
##   - that a Remove laid exactly over a strip takes it out of the list, and laying it again puts
##     it back the same;
##   - that saving and loading gives back exactly the same ground (every byte of the map), and
##     that an old save's 2 × 4 m tiles load as the same ground as laying them as strips;
##   - the save's size for these and for a large network (2,000 strips of 4 m: 8 km of path), and
##     how long working the ground out from a save takes.
## Then quits.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/paths"
## The winding path's bends and the road's lanes, in the frame (x across, z along)
const WINDING := [Vector2(-5.0, 0.0), Vector2(-5.0, 6.0), Vector2(-2.0, 10.0),
		Vector2(-5.0, 14.0)]
const ROAD_START := 0.0
const ROAD_END := 16.0
## [rank, lane middle x]: dirt edges, gravel inside them (half over the dirt), stone in the middle
const ROAD := [[1, 2.0], [1, 6.0], [2, 3.0], [2, 4.0], [2, 5.0], [3, 4.0]]

var player: Node
var valley: Node
var paths: PathTiles
var frame := Transform3D.IDENTITY


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node = load(WORLD).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for i in 3000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player:
			break
	await _frames(30)
	SaveGame._test_run = true
	player.set_physics_process(false)
	valley = get_tree().get_first_node_in_group("valley")
	paths = valley.path_tiles
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.42
	await _frames(5)
	_hide_overlays()
	if not _find_spot():
		print("PATHSHOTS | no flat open ground found")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var started := Time.get_ticks_msec()
	var area := Rect2()
	for i in WINDING.size() - 1:
		area = _merge(area, _strip(1, WINDING[i], WINDING[i + 1]))
	for lane in ROAD:
		area = _merge(area, _strip(lane[0], Vector2(lane[1], ROAD_START),
				Vector2(lane[1], ROAD_END)))
	print("PATHSHOTS | laid %d strips in %d ms" % [paths.strip_count(),
			Time.get_ticks_msec() - started])
	var foliage = valley.get_node_or_null("Foliage")
	if foliage:
		foliage.hide_plants_on_paths(area)
	_print_reach()
	_check_remove()
	_check_saves()
	_check_big_network()

	await _frames(30)
	# Close up: beside the winding path's first bend, looking up it
	await _aim(Vector3(-8.5, 1.7, 2.0), Vector3(-3.5, 0.0, 9.0))
	await _save("winding_close.png")
	# Close up: at the road's side, looking along and across it
	await _aim(Vector3(9.0, 1.7, 3.0), Vector3(4.0, 0.0, 9.0))
	await _save("road_close.png")
	# From 10 m: back and up, looking at both
	await _aim(Vector3(0.0, 5.0, -8.5), Vector3(0.0, 0.0, 8.0))
	await _save("paths_10m.png")
	get_tree().quit()


# Lays a strip from a to b (in the frame) as the placer does: an end carrying on from the end of
# a strip of the same type is round, and so is that one's
func _strip(rank: int, a_local: Vector2, b_local: Vector2) -> Rect2:
	var a := _world(a_local)
	var b := _world(b_local)
	var caps := 0
	if _joins(rank, a):
		caps |= PathTiles.ROUND_A
	if _joins(rank, b):
		caps |= PathTiles.ROUND_B
	var area := paths.lay(rank, a, b, caps)
	if caps & PathTiles.ROUND_A:
		area = _merge(area, paths.round_ends_at(a, rank))
	if caps & PathTiles.ROUND_B:
		area = _merge(area, paths.round_ends_at(b, rank))
	return area


func _joins(rank: int, spot: Vector2) -> bool:
	for strip in paths.strips_near(spot, PathTiles.SAME_SPOT):
		if int(strip["rank"]) == rank:
			return true
	return false


func _world(local: Vector2) -> Vector2:
	var spot := frame * Vector3(local.x, 0.0, local.y)
	return Vector2(spot.x, spot.z)


static func _merge(area: Rect2, more: Rect2) -> Rect2:
	if not more.has_area():
		return area
	return more if not area.has_area() else area.merge(more)


# How much dirt there is past the winding path's first strip's side (its own edge, with the
# baked wobble but not the shader's fine fray), along its length
func _print_reach() -> void:
	var parts: PackedStringArray = []
	for past in [0.0, 0.05, 0.1, 0.15, 0.2, 0.3]:
		var most := 0.0
		for k in 20:
			var spot := _world(Vector2(-6.0 - past, 1.0 + k * 0.2))
			most = maxf(most, paths.amount_at(spot.x, spot.y))
		parts.append("%d cm: %.2f" % [roundi(past * 100.0), most])
	print("PATHSHOTS | dirt cover past its strip's edge (most along 4 m): " + ", ".join(parts))


# A Remove exactly over a strip on its own takes it out of the list (dragged the other way
# round), and the ground is as it was before the strip
func _check_remove() -> void:
	var before := _map_bytes(paths)
	var count := paths.strip_count()
	var a := _world(Vector2(0.0, 40.0))
	var b := _world(Vector2(0.0, 44.5))
	paths.lay(2, a, b)
	var laid := paths.strip_count()
	paths.lay(PathTiles.REMOVE, b, a)
	print("PATHSHOTS | remove over a strip: %d strips -> %d -> %d (the strip gone, no Remove kept)"
			% [count, laid, paths.strip_count()]
			+ "; ground as before: %s" % (_map_bytes(paths) == before))


# Saving and loading gives exactly the same ground, and an old save's tiles load as strips
func _check_saves() -> void:
	var saved := paths.save_data()
	var copy := _fresh()
	copy.load_data(JSON.parse_string(JSON.stringify(saved)))
	print("PATHSHOTS | save and load: %d strips, every byte of the map the same: %s"
			% [copy.strip_count(), _map_bytes(copy) == _map_bytes(paths)])
	print("PATHSHOTS | these paths' save: %d bytes of JSON" % JSON.stringify(saved).length())
	# An old save: three 2 × 4 m tiles, one turned
	var middle := _world(Vector2(0.0, 30.0))
	var old := PackedFloat32Array([1, middle.x, middle.y, 0.0, 2, middle.x + 2.0, middle.y, 0.0,
			1, middle.x + 5.0, middle.y + 3.0, PI / 8.0])
	var old_save := {"version": 1, "count": 3,
			"tiles": Marshalls.raw_to_base64(old.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD))}
	var from_old := _fresh()
	from_old.load_data(old_save)
	var as_strips := _fresh()
	for i in 3:
		as_strips.lay_tile(int(old[i * 4]), Vector2(old[i * 4 + 1], old[i * 4 + 2]), old[i * 4 + 3])
	print("PATHSHOTS | an old save's tiles: %d strips, the same ground as laid as strips: %s"
			% [from_old.strip_count(), _map_bytes(from_old) == _map_bytes(as_strips)])
	for node in [copy, from_old, as_strips]:
		node.queue_free()


# A large network's save size (2,000 strips), and how long working ground out from a save takes
func _check_big_network() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ops := PackedFloat32Array()
	var origin: Vector2 = valley.map_rect().get_center()
	for road in 40:
		var at := origin + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
		var heading := rng.randf() * TAU
		for i in 50:
			var next := at + Vector2(sin(heading), cos(heading)) * 4.0
			ops.append_array([rng.randi_range(1, 3), at.x, at.y, next.x, next.y,
					PathTiles.ROUND_A | PathTiles.ROUND_B])
			at = next
			if i % 10 == 9:
				heading += PI / 8.0
	var big := PathTiles.new()
	big._ops = ops
	var big_save := JSON.stringify(big.save_data())
	print("PATHSHOTS | a 2,000-strip network's save: %d bytes of JSON (%.1f bytes a strip)"
			% [big_save.length(), big_save.length() / 2000.0])
	var sample := PathTiles.new()
	sample._ops = ops.slice(0, 200 * PathTiles.STRIDE)
	var some := sample.save_data()
	var timed := _fresh()
	var t0 := Time.get_ticks_msec()
	timed.load_data(some)
	var ms := Time.get_ticks_msec() - t0
	print("PATHSHOTS | loading 200 strips' ground took %d ms (about %d ms for 2,000)"
			% [ms, ms * 10])
	big.free()
	sample.free()
	timed.queue_free()


func _fresh() -> PathTiles:
	var made := PathTiles.new()
	add_child(made)
	made.setup(valley.map_rect(), null)
	return made


func _map_bytes(of: PathTiles) -> Dictionary:
	var copy := {}
	for tile in of._data:
		var bytes: PackedByteArray = of._data[tile]
		if bytes.count(0) != bytes.size():
			copy[tile] = bytes
	return copy


func _aim(eye: Vector3, at: Vector3) -> void:
	var from := frame * eye
	from.y = Plot.ground_at(player, from.x, from.z) + eye.y
	var target := frame * at
	target.y = Plot.ground_at(player, target.x, target.z) + at.y
	var to := target - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(8)


# Flat, dry, open ground about 20 × 30 m (and dry out to where the camera stands), the frame
# turned so the camera, behind the paths' start, has the sun behind it
func _find_spot() -> bool:
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] \
			as DirectionalLight3D
	var toward_sun := Vector3(light.global_basis.z.x, 0, light.global_basis.z.z).normalized()
	var water: float = valley.global_position.y + valley.water_height()
	var start: Vector3 = player.global_position
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for r in [15.0, 25.0, 40.0, 60.0, 90.0, 130.0, 180.0, 240.0]:
		for k in 24:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 24.0) * r
			var ground := Plot.ground_at(player, c.x, c.z)
			if ground < water + 1.0:
				continue
			# The paths run along +Z, away from the sun: the camera at -Z has it behind
			var basis := Basis(Vector3.UP.cross(-toward_sun), Vector3.UP, -toward_sun)
			var f := Transform3D(basis, Vector3(c.x, ground, c.z))
			var ok := true
			var x := -10.0
			while x <= 10.0 and ok:
				var z := -10.0
				while z <= 20.0 and ok:
					var q3 := f * Vector3(x, 0, z)
					var height := Plot.ground_at(player, q3.x, q3.z)
					if height < water + 0.5 or absf(height - ground) > (0.8 if z > -3.0 else 3.0):
						ok = false
					if z > -3.0:
						var q := PhysicsRayQueryParameters3D.create(q3 + Vector3.UP * 30.0,
								q3 + Vector3.DOWN * 5.0)
						q.exclude = [player.get_rid()]
						var hit := space.intersect_ray(q)
						if hit.is_empty() or not ((hit["collider"] as Node).is_in_group(
								"terrain_ground") or hit["collider"] is ResourceNode):
							ok = false
					z += 1.5
				x += 1.5
			if ok:
				frame = f
				return true
	return false


func _hide_overlays() -> void:
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for child in player.camera.get_children():
		if child is Node3D:
			(child as Node3D).visible = false


func _save(file: String) -> void:
	await _frames(4)
	for k in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("PATHSHOTS | saved %s" % file)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
