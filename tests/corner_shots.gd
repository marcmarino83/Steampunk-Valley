extends Node
## The roof inner corner (with the valley eave corner under it) and the placement preview, pictured
## in daylight. Run in a window:
##
##     godot --path . res://tests/corner_shots.tscn --quit-after 6000
##
## Opens the world, finds flat open ground facing the sun, hides the grass, ferns, loose pickups and
## the screen's overlays, and builds, at each pitch (45° and 26°), an L-shaped house's inside corner:
## stone foundations, two Wall 2 m meeting at a corner post, a roof run along each (one rising +Z,
## one rising -X), the inner corner between them, an eave along each run's low edge and the valley
## eave corner where the eaves cross. Pictures each corner from below and from the side, then a Wall
## 2 m being placed on a foundation's edge, placeable and not (free build off, empty backpack), into
## docs/reference/ours/pieces/, then quits.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/pieces"
## Each pitch: [roof, inner corner, eave, valley eave corner, where the set goes (x, round the frame)]
const PITCHES := [
	["45", "roof_45", "roof_inner_45", "eave_45", "valley_eave_corner_45", 0.0],
	["26", "roof", "roof_inner_26", "eave_26", "valley_eave_corner_26", 9.0],
]

var player: Node
var registry: PieceRegistry
var bp: BuildPlacer
var pp: ValheimPlacer
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
	DevCheats.freebuild = true
	player.set_physics_process(false)
	player._on_held_changed("Hammer")
	bp = player._placer
	pp = bp._pieces
	registry = bp.registry
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.45
	await _frames(5)
	_hide_overlays()
	for f in get_tree().root.find_children("*", "Node3D", true, false):
		if f.get_script() and (f.get_script() as Script).resource_path.ends_with("world/foliage.gd"):
			(f as Node3D).visible = false
	if not _find_spot():
		print("SHOTS | no flat open ground found")
		get_tree().quit(1)
		return
	_hide_pickups()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	for p in PITCHES:
		_build_corner(p, Vector3(float(p[5]), 0, 0))
	await _frames(30)
	for p in PITCHES:
		var at := Vector3(float(p[5]), 0, 0)
		await _aim(at + Vector3(3.2, 1.9, -2.6), at + Vector3(1.2, 2.95, -0.25))
		await _save("inner_corner_%s_below.png" % p[0])
		await _aim(at + Vector3(4.6, 3.3, -3.4), at + Vector3(1.1, 2.9, -0.2))
		await _save("inner_corner_%s_side.png" % p[0])
	# A Wall 2 m on a stone foundation's edge: placeable, then not
	var wall_at := Vector3(-8, 0, 0)
	_spawn("structure/foundation_stone", wall_at + Vector3(0, 1.0, 0), 0.0)
	_spawn("structure/foundation_stone", wall_at + Vector3(2, 1.0, 0), 0.0)
	await _frames(10)
	bp.begin(load("res://buildables/structure/wall_2m.tres"))
	await _aim(wall_at + Vector3(2.2, 2.9, 5.0), wall_at + Vector3(0.15, 1.0, 0.92))
	await _save("wall_preview_valid.png")
	print("SHOTS | wall: snapped %s, red %s" % [not pp._pair.is_empty(), pp._red])
	var kept: Dictionary = player.inventory.duplicate()
	DevCheats.freebuild = false
	player.inventory.clear()
	await _frames(4)
	await _save("wall_preview_invalid.png")
	print("SHOTS | wall, can't place: red %s, problem \"%s\"" % [pp._red, pp._problem])
	player.inventory.merge(kept)
	DevCheats.freebuild = true
	bp.cancel()
	await _frames(2)
	get_tree().quit()


# An L-shaped house's inside corner at `at` (round the frame): the building on +Z and -X of the
# corner post at (1, 1, 0), the crook (open) on +X and -Z
func _build_corner(p: Array, at: Vector3) -> void:
	for cell in [Vector3(2, 1, 1), Vector3(0, 1, 1), Vector3(0, 1, -1)]:
		_spawn("structure/foundation_stone", at + cell, 0.0)
	_spawn("structure/wall_2m", at + Vector3(2, 1, 0), 0.0)
	_spawn("structure/wall_2m", at + Vector3(1, 1, -1), 90.0)
	_spawn("structure/" + p[1], at + Vector3(2, 3, 0), 0.0)
	_spawn("structure/" + p[1], at + Vector3(1, 3, -1), -90.0)
	_spawn("structure/" + p[2], at + Vector3(0, 3, 0), 0.0)
	_spawn("structure/" + p[3], at + Vector3(2, 3, 0), 0.0)
	_spawn("structure/" + p[3], at + Vector3(1, 3, -1), -90.0)
	_spawn("structure/" + p[4], at + Vector3(1, 3, 0), 0.0)


func _spawn(path: String, at: Vector3, yaw_degrees: float) -> BuildPiece:
	return registry.spawn(load("res://buildables/%s.tres" % path), frame * Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), at), {})


func _save(file: String) -> void:
	await _frames(4)
	for k in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("SHOTS | saved %s" % file)


func _aim(eye: Vector3, at: Vector3) -> void:
	var from := frame * eye
	var to := frame * at - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(5)


# Flat, dry ground with nothing standing on it but the ground and loose pickups, 24 × 16 m, the
# frame turned so the camera (+Z, -Z side shots) has the sun behind or beside it
func _find_spot() -> bool:
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var toward_sun := Vector3(light.global_basis.z.x, 0, light.global_basis.z.z).normalized()
	var valley = get_tree().get_first_node_in_group("valley")
	var water: float = valley.global_position.y + valley.water_height() if valley else -INF
	var start: Vector3 = player.global_position
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for r in [12.0, 20.0, 30.0, 40.0, 55.0, 70.0, 90.0]:
		for k in 16:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0) * r
			var ground := Plot.ground_at(player, c.x, c.z)
			if ground < water + 1.0:
				continue
			# (the crook faces -Z and +X: the sun on that side lights it)
			var basis := Basis(Vector3.UP.cross(-toward_sun), Vector3.UP, -toward_sun)
			var f := Transform3D(basis, Vector3(c.x, ground, c.z))
			var ok := true
			var x := -12.0
			while x <= 16.0 and ok:
				var z := -7.0
				while z <= 7.0 and ok:
					var q3 := f * Vector3(x, 0, z)
					if absf(Plot.ground_at(player, q3.x, q3.z) - ground) > 0.5:
						ok = false
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


func _hide_pickups() -> void:
	for node in get_tree().root.find_children("*", "StaticBody3D", true, false):
		if node is ResourceNode and (node as Node3D).global_position.distance_to(frame.origin) < 40.0:
			(node as Node3D).visible = false


func _hide_overlays() -> void:
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for child in player.camera.get_children():
		if child is Node3D:
			(child as Node3D).visible = false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
