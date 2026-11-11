extends Node
## The placement preview and template ghosts, pictured and measured. Run in a window:
##
##     godot --path . res://tests/preview_shots.tscn --quit-after 12000
##
## Opens the world, finds flat open ground facing the sun, hides the grass, ferns and loose pickups
## (so nothing stands in front, and nothing sways between measurements), and in daylight:
##   - a Wall 2 m being placed on a stone foundation's edge: placeable (the warm tint and outline),
##     then not (red: free build off and an empty backpack, "Not enough");
##   - the Woodcutter's Hut laid out as a template's ghosts (one wall under the crosshair: outlined)
##     beside a built wall;
## saving docs/reference/ours/preview/wall_valid.png, wall_invalid.png and template_ghost.png. It
## measures the draw calls and the render time (CPU and GPU, averaged over FRAMES frames) of the
## preview and of the ghosts, as they are now and as they were (the preview see-through at 70% with
## no overlay; the ghosts in the old flat see-through grey), and prints "PREVIEW" lines, then quits.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/preview"
const FRAMES := 90
## The old ghost look (the flat see-through grey with lighter edges), for comparing against
const OLD_GHOST_SHADER := "shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 fill_color : source_color = vec4(0.604, 0.604, 0.604, 0.15);
uniform vec4 edge_color : source_color = vec4(0.72, 0.72, 0.72, 0.45);
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	ALBEDO = mix(fill_color.rgb, edge_color.rgb, rim);
	ALPHA = clamp(mix(fill_color.a, edge_color.a, rim), 0.0, 1.0);
}"

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
		print("PREVIEW | no flat open ground found")
		get_tree().quit(1)
		return
	_hide_pickups()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	# A Wall 2 m placed on a stone foundation's edge
	_spawn("structure/foundation_stone", Vector3(0, 1.0, 0))
	_spawn("structure/foundation_stone", Vector3(2, 1.0, 0))
	await _frames(10)
	bp.begin(load("res://buildables/structure/wall_2m.tres"))
	await _frames(3)
	await _aim(Vector3(2.2, 2.9, 5.0), Vector3(0.15, 1.0, 0.92))
	(await _grab()).save_png(ProjectSettings.globalize_path(SHOTS.path_join("wall_valid.png")))
	print("PREVIEW | wall: snapped %s, red %s, problem \"%s\"" % [not pp._pair.is_empty(), pp._red, pp._problem])
	var now := await _preview_cost()
	# The old way: see-through at 70%, no tint or outline, no shadow
	for look in pp._looks:
		look.transparency = 0.3
		look.material_overlay = null
		look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var before := await _preview_cost()
	for look in pp._looks:
		look.transparency = 0.0
		look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	PreviewLook.apply(pp._preview, PreviewLook.State.VALID)
	print("PREVIEW | wall preview: now %d draw calls, %.3f ms CPU, %.3f ms GPU | before (see-through) %d draw calls, %.3f ms CPU, %.3f ms GPU" % [now[0], now[1], now[2], before[0], before[1], before[2]])
	# Not placeable: free build off, nothing in the backpack
	var kept: Dictionary = player.inventory.duplicate()
	DevCheats.freebuild = false
	player.inventory.clear()
	await _frames(4)
	(await _grab()).save_png(ProjectSettings.globalize_path(SHOTS.path_join("wall_invalid.png")))
	print("PREVIEW | wall, can't place: red %s, problem \"%s\"" % [pp._red, pp._problem])
	player.inventory.merge(kept)
	DevCheats.freebuild = true
	bp.cancel()
	await _frames(3)
	# A template's ghosts beside a built wall
	var template := BuildingTemplate.read(BuildingTemplate.BUILT_IN_FOLDER.path_join("woodcutter_s_hut.json"))
	var ghosts := []
	for item in template.items:
		if item["buildable"] is PieceBuildable:
			var piece := registry.spawn(item["buildable"], frame * Transform3D(Basis.IDENTITY, Vector3(7, 0, -3)) * (item["relative"] as Transform3D), {})
			piece.set_ghost(true)
			ghosts.append(piece)
	var built := _spawn("structure/wall_2m", Vector3(1, 2.0, -1))
	await _frames(20)
	var target: BuildPiece = null
	for g in ghosts:
		if (g as BuildPiece).shape_name == "wall":
			target = g
			break
	if target:
		target.set_ghost_targeted(true)
	await _aim(Vector3(-1.5, 3.2, 9.0), Vector3(5.5, 1.6, -2.0))
	(await _grab()).save_png(ProjectSettings.globalize_path(SHOTS.path_join("template_ghost.png")))
	var ghosts_now := await _ghost_cost(ghosts)
	# The old way: the flat see-through grey over every look
	var old := ShaderMaterial.new()
	old.shader = Shader.new()
	old.shader.code = OLD_GHOST_SHADER
	for g in ghosts:
		for look in (g as BuildPiece)._ghost_saved:
			(look as GeometryInstance3D).material_override = old
			(look as GeometryInstance3D).material_overlay = null
	var ghosts_before := await _ghost_cost(ghosts)
	print("PREVIEW | template ghosts (%d pieces, the built wall %s): now %d draw calls, %.3f ms CPU, %.3f ms GPU | before (flat grey) %d draw calls, %.3f ms CPU, %.3f ms GPU" % [ghosts.size(), built != null, ghosts_now[0], ghosts_now[1], ghosts_now[2], ghosts_before[0], ghosts_before[1], ghosts_before[2]])
	await _frames(2)
	get_tree().quit()


# The preview's cost: draw calls (the frame with it, less the frame without), and the frame's
# render time with it
func _preview_cost() -> Array:
	var with := await _measure()
	pp._preview.visible = false
	pp.set_physics_process(false)
	var without := await _measure()
	pp._preview.visible = true
	pp.set_physics_process(true)
	await _frames(3)
	return [with[0] - without[0], with[1], with[2]]


func _ghost_cost(ghosts: Array) -> Array:
	var with := await _measure()
	for g in ghosts:
		(g as Node3D).visible = false
	var without := await _measure()
	for g in ghosts:
		(g as Node3D).visible = true
	await _frames(3)
	return [with[0] - without[0], with[1], with[2]]


# [draw calls in the frame, average render time CPU (ms), GPU (ms)] over FRAMES frames
func _measure() -> Array:
	var rid := get_viewport().get_viewport_rid()
	for k in 6:
		await RenderingServer.frame_post_draw
	var cpu := 0.0
	var gpu := 0.0
	for k in FRAMES:
		await RenderingServer.frame_post_draw
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), cpu / FRAMES, gpu / FRAMES]


func _spawn(path: String, at: Vector3) -> BuildPiece:
	return registry.spawn(load("res://buildables/%s.tres" % path), frame * Transform3D(Basis.IDENTITY, at), {})


func _aim(eye: Vector3, at: Vector3) -> void:
	var from := frame * eye
	var to := frame * at - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(5)


func _grab() -> Image:
	await _frames(4)
	for k in 8:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# Flat, dry ground with nothing standing on it but the ground and loose pickups, 16 × 16 m, the
# frame turned so the camera (+Z) stands toward the sun
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
			var basis := Basis(Vector3.UP.cross(toward_sun), Vector3.UP, toward_sun)
			var f := Transform3D(basis, Vector3(c.x, ground, c.z))
			var ok := true
			var x := -4.0
			while x <= 13.0 and ok:
				var z := -9.0
				while z <= 10.0 and ok:
					var p := f * Vector3(x, 0, z)
					if absf(Plot.ground_at(player, p.x, p.z) - ground) > 0.5:
						ok = false
					var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 5.0)
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
