extends Node
## Path tiles pictured in daylight, with a few numbers. Run in a window:
##
##     godot --path . res://tests/path_shots.tscn --resolution 1920x1080 --quit-after 6000
##
## Opens the world, finds flat open ground with the sun behind the camera, hides the screen's
## overlays, and lays a road three Dirt tiles wide and five long (6 × 20 m), a row of Gravel tiles
## down its middle, and a row of Stone tiles down the middle of the gravel. Pictures it close up
## and from 10 m into docs/reference/ours/paths/, then prints:
##   - that a Remove laid exactly over a tile takes it out of the list, and laying it again puts it
##     back the same;
##   - that saving and loading gives back exactly the same ground (every byte of the map);
##   - the save's size for this road and for a large network (2,000 tiles: 8 km of 2 m path), and
##     how long working the ground out from a save takes.
## Then quits.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/paths"

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
	var turn := frame.basis.get_euler().y
	var started := Time.get_ticks_msec()
	var area := Rect2()
	# The road: three dirt tiles across, five along; gravel down the middle; stone down the gravel
	for rank in [1, 2, 3]:
		for along in 5:
			for across in ([-2.0, 0.0, 2.0] if rank == 1 else [0.0]):
				var spot := frame * Vector3(across, 0, along * 4.0)
				var changed := paths.lay(rank, Vector2(spot.x, spot.z), turn)
				area = changed if not area.has_area() else area.merge(changed)
	print("PATHSHOTS | laid %d tiles in %d ms" % [paths.tile_count(), Time.get_ticks_msec() - started])
	var foliage = valley.get_node_or_null("Foliage")
	if foliage:
		foliage.hide_plants_on_paths(area)

	# A Remove exactly over a tile takes it out of the list; laying the tile again puts it back
	var before := _map_bytes(paths)
	var count := paths.tile_count()
	var edge := frame * Vector3(-2.0, 0, 0)
	paths.lay(PathTiles.REMOVE, Vector2(edge.x, edge.z), turn)
	var after_remove := paths.tile_count()
	paths.lay(1, Vector2(edge.x, edge.z), turn)
	print("PATHSHOTS | remove over a tile: %d tiles -> %d (the tile gone, no Remove kept) -> %d after laying it again; ground the same again: %s" % [count, after_remove, paths.tile_count(), _map_bytes(paths) == before])

	# Saving and loading gives exactly the same ground
	var saved := paths.save_data()
	var copy := PathTiles.new()
	add_child(copy)
	copy.setup(valley.map_rect(), null)
	copy.load_data(JSON.parse_string(JSON.stringify(saved)))
	print("PATHSHOTS | save and load: %d tiles, every byte of the map the same: %s" % [copy.tile_count(), _map_bytes(copy) == _map_bytes(paths)])
	print("PATHSHOTS | this road's save: %d bytes of JSON" % JSON.stringify(saved).length())
	copy.queue_free()

	# A large network's save size (2,000 tiles), and how long working ground out from a save takes
	var big := PathTiles.new()
	add_child(big)
	big.setup(valley.map_rect(), null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ops := PackedFloat32Array()
	var origin: Vector2 = valley.map_rect().get_center()
	for road in 40:
		var start := origin + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
		var heading := rng.randf() * TAU
		for i in 50:
			var p := start + Vector2(sin(heading), cos(heading)) * i * 4.0
			ops.append_array([rng.randi_range(1, 3), p.x, p.y, heading])
			if i % 10 == 9:
				heading = snappedf(heading + PI / 8.0, PI / 8.0)
	big._ops = ops
	var big_save := JSON.stringify(big.save_data())
	print("PATHSHOTS | a 2,000-tile network's save: %d bytes of JSON (%.1f bytes a tile)" % [big_save.length(), big_save.length() / 2000.0])
	var timed := PathTiles.new()
	add_child(timed)
	timed.setup(valley.map_rect(), null)
	var some := {"version": 1, "count": 200}
	var sample := PathTiles.new()
	sample._ops = ops.slice(0, 800)
	some = sample.save_data()
	var t0 := Time.get_ticks_msec()
	timed.load_data(some)
	var ms := Time.get_ticks_msec() - t0
	print("PATHSHOTS | loading 200 tiles' ground took %d ms (about %d ms for 2,000)" % [ms, ms * 10])
	big.queue_free()
	timed.queue_free()
	sample.free()

	await _frames(30)
	# Close up: standing at the road's side, looking along and across it
	await _aim(Vector3(4.2, 1.7, 3.0), Vector3(0.0, 0.0, 9.0))
	await _save("path_tiles_close.png")
	# From 10 m: back along the road and up, looking at its middle
	await _aim(Vector3(5.0, 4.5, -6.5), Vector3(0.0, 0.0, 8.0))
	await _save("path_tiles_10m.png")
	get_tree().quit()


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


# Flat, dry, open ground about 14 × 30 m (and dry out to where the camera stands), the frame turned
# so the camera, behind the road's start, has the sun behind it
func _find_spot() -> bool:
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
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
			# The road runs along +Z, away from the sun: the camera at -Z has it behind
			var basis := Basis(Vector3.UP.cross(-toward_sun), Vector3.UP, -toward_sun)
			var f := Transform3D(basis, Vector3(c.x, ground, c.z))
			var ok := true
			var x := -7.0
			while x <= 7.0 and ok:
				var z := -9.0
				while z <= 21.0 and ok:
					var q3 := f * Vector3(x, 0, z)
					var height := Plot.ground_at(player, q3.x, q3.z)
					if height < water + 0.5 or absf(height - ground) > (0.8 if z > -3.0 else 3.0):
						ok = false
					if z > -3.0:
						var q := PhysicsRayQueryParameters3D.create(q3 + Vector3.UP * 30.0, q3 + Vector3.DOWN * 5.0)
						q.exclude = [player.get_rid()]
						var hit := space.intersect_ray(q)
						if hit.is_empty() or not ((hit["collider"] as Node).is_in_group("terrain_ground") or hit["collider"] is ResourceNode):
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
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("PATHSHOTS | saved %s" % file)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
