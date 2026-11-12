extends Node
## The Bell Mast beside the Basic House, pictured in daylight to check its scale. Run in a window:
##
##     godot --path . res://tests/village_center_shots.tscn --resolution 1920x1080 --quit-after 6000
##
## Opens the world, finds flat open ground with the sun behind the camera, hides the grass, ferns,
## loose pickups and the screen's overlays, lays out the Basic House template's pieces, stands a
## Bell Mast on the ground 3 m past the house's plot edge with a settler beside it (1.7 m, for
## scale), takes one picture into docs/reference/ours/village_center/, then quits.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/village_center"
const TEMPLATE := "res://buildables/templates/basic_house.json"
const HOUSE_AT := Vector3(-3.0, 0, 0)

var player: Node
var registry: PieceRegistry
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
	registry = player._placer.registry
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.42
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
	# The Basic House's pieces (its plot frame's origin on the ground at HOUSE_AT)
	var template := BuildingTemplate.read(TEMPLATE)
	var house := frame * Transform3D(Basis.IDENTITY, HOUSE_AT)
	var placed := 0
	for item in template.items:
		if item["buildable"] is PieceBuildable:
			registry.spawn(item["buildable"], house * (item["relative"] as Transform3D), {})
			placed += 1
	# The mast on the ground 3 m past the plot's +X edge, facing the camera (its front is +Z: turned
	# half round so the camera, on -Z, sees it)
	var mast_local := HOUSE_AT + Vector3(template.size.x / 2.0 + 3.0, 0, 0)
	var mast_world := frame * mast_local
	mast_world.y = Plot.ground_at(player, mast_world.x, mast_world.z)
	var mast := registry.spawn(load("res://buildables/furniture/bell_mast.tres"), Transform3D(frame.basis * Basis(Vector3.UP, PI), mast_world), {})
	print("SHOTS | house pieces %d, mast at %s, mast bounds %s" % [placed, mast_world.snapped(Vector3.ONE * 0.01), PieceShapes.bounds_of(mast.shape_def())])
	# A settler beside it, standing still, for scale
	var manager: SettlerManager = player._settlers
	var person := manager.spawn(frame * (mast_local + Vector3(-1.6, 0, -1.2)), null)
	await _frames(2)
	person.set_physics_process(false)
	person.rotation.y = frame.basis.get_euler().y + PI
	await _frames(40)
	var middle := Vector3(1.5, 0, 0)
	await _aim(middle + Vector3(0, 2.0, -19.0), middle + Vector3(0, 3.6, 0))
	await _save("bell_mast_scale.png")
	get_tree().quit()


func _aim(eye: Vector3, at: Vector3) -> void:
	var from := frame * eye
	from.y = Plot.ground_at(player, from.x, from.z) + eye.y
	var target := frame * at
	target.y = frame.origin.y + at.y
	var to := target - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(5)


# Flat, dry ground with nothing standing on it but the ground and loose pickups, about 28 × 14 m
# (and dry ground out to where the camera stands), the frame turned so the camera on -Z has the sun
# behind it
func _find_spot() -> bool:
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var toward_sun := Vector3(light.global_basis.z.x, 0, light.global_basis.z.z).normalized()
	var valley = get_tree().get_first_node_in_group("valley")
	var water: float = valley.global_position.y + valley.water_height() if valley else -INF
	var start: Vector3 = player.global_position
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for r in [12.0, 20.0, 30.0, 40.0, 55.0, 70.0, 90.0, 120.0, 150.0, 190.0, 240.0]:
		for k in 24:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 24.0) * r
			var ground := Plot.ground_at(player, c.x, c.z)
			if ground < water + 1.0:
				continue
			# (-Z toward the sun's side: the camera there has the sun behind it)
			var basis := Basis(Vector3.UP.cross(-toward_sun), Vector3.UP, -toward_sun)
			var f := Transform3D(basis, Vector3(c.x, ground, c.z))
			var ok := true
			var x := -10.0
			while x <= 10.0 and ok:
				var z := -20.0
				while z <= 7.0 and ok:
					var q3 := f * Vector3(x, 0, z)
					var height := Plot.ground_at(player, q3.x, q3.z)
					if height < water + 0.5:
						ok = false
					# Flat and clear where the house and mast stand; out to the camera, just dry
					if z > -7.0:
						if absf(height - ground) > 0.6:
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
		if node is ResourceNode and (node as Node3D).global_position.distance_to(frame.origin) < 50.0:
			(node as Node3D).visible = false


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
	print("SHOTS | saved %s" % file)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
