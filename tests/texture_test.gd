extends Node
## TEST: texture-based detail against modelled boards, on one piece (Wall 2 m). Run in a window:
##
##     godot --path . res://tests/texture_test.tscn --quit-after 12000
##
## Opens the world, finds flat open ground with a clear view along the sun's direction, and puts
## down two L-shaped corners side by side, each of two Wall 2 m meeting at a corner post: on the left
## the current wall (real pieces, modelled boards; its corner post from JointDetails), on the right
## the test wall (see TexturedWall: a solid slab with texture-based boards, rails and the same corner
## post). The grass, ferns and scattered rocks are hidden (so nothing stands in front of the walls
## or sways in their shadows), the camera is held still, and it measures, at 3, 8, 15, 22 and 30 m:
## each kind's draw calls and triangles (the frame with only that kind shown, less the frame with
## neither), and the share of dark pixels on each wall's face (square on, and the return wall seen
## at an angle). At 22 m it measures again with 4× MSAA and with TAA. Daylight pictures at 3, 8, 15
## and 30 m go to docs/reference/ours/texture_test/. Prints "TEXTEST" lines, then quits itself.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/texture_test"
const DISTANCES := [3.0, 8.0, 15.0, 22.0, 30.0]
const PICTURES := [3.0, 8.0, 15.0, 30.0]
## A pixel counts as dark below this share of its wall face's middle brightness
const DARK := 0.45

var player: Node
var registry: PieceRegistry
# The test's frame: its origin on the ground between the two corners, +Z toward the camera
var frame := Transform3D.IDENTITY
var current: Array = []
var textured: Array = []


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
	player.set_physics_process(false)
	registry = player._placer.registry
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.45
	await _frames(5)
	_hide_overlays()
	for f in get_tree().root.find_children("*", "Node3D", true, false):
		if f.get_script() and (f.get_script() as Script).resource_path.ends_with("world/foliage.gd"):
			(f as Node3D).visible = false
	if not _find_spot():
		print("TEXTEST | no flat open ground with a clear view found")
		get_tree().quit(1)
		return
	_hide_pickups()
	_build()
	await _frames(40)
	# (the current corner's post, made by JointDetails, counts with the current walls)
	var corner := frame * Vector3(-4, 0, 0)
	for node in registry.world.get_children():
		if node is MeshInstance3D and (node as Node3D).global_position.distance_to(corner) < 0.05:
			current.append(node)
	_report_meshes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	for d in DISTANCES:
		await _view(d)
		var shot := await _grab()
		if d in PICTURES:
			shot.save_png(ProjectSettings.globalize_path(SHOTS.path_join("walls_%dm.png" % int(d))))
		var cost_current := await _cost(current, textured)
		var cost_textured := await _cost(textured, current)
		print("TEXTEST | %d m | current: %d draw calls, %d triangles; dark %s (square on), %s (at an angle) | textured: %d draw calls, %d triangles; dark %s (square on), %s (at an angle) | current wall's looks: %s" % [int(d), cost_current[0], cost_current[1], _dark(shot, -3.0, false), _dark(shot, -3.0, true), cost_textured[0], cost_textured[1], _dark(shot, 3.0, false), _dark(shot, 3.0, true), _current_tier()])
	# 22 m again: 4× MSAA, then TAA (the camera and everything else held still)
	await _view(22.0)
	var vp := get_viewport()
	var msaa := vp.msaa_3d
	vp.msaa_3d = Viewport.MSAA_4X
	var four := await _grab()
	vp.msaa_3d = msaa
	print("TEXTEST | 22 m, 4x MSAA | current dark %s (square on), %s (at an angle) | textured dark %s, %s" % [_dark(four, -3.0, false), _dark(four, -3.0, true), _dark(four, 3.0, false), _dark(four, 3.0, true)])
	vp.use_taa = true
	var taa := await _grab(40)
	vp.use_taa = false
	print("TEXTEST | 22 m, TAA (2x MSAA kept) | current dark %s (square on), %s (at an angle) | textured dark %s, %s" % [_dark(taa, -3.0, false), _dark(taa, -3.0, true), _dark(taa, 3.0, false), _dark(taa, 3.0, true)])
	await _frames(2)
	get_tree().quit()


# Two L-shaped corners on the frame's ground: the current Wall 2 m (left) and the test wall (right),
# each a wall square on to the camera and a return wall coming toward it from the outer end, meeting
# at a corner post
func _build() -> void:
	var wall: PieceBuildable = load("res://buildables/structure/wall_2m.tres")
	var turn := Basis(Vector3.UP, PI / 2.0)
	current.append(registry.spawn(wall, frame * Transform3D(Basis.IDENTITY, Vector3(-3, 0, 0)), {}))
	current.append(registry.spawn(wall, frame * Transform3D(turn, Vector3(-4, 0, 1)), {}))
	var holder := Node3D.new()
	holder.name = "TexturedWalls"
	get_tree().current_scene.add_child(holder)
	var material := registry.detail_material()
	var near := TexturedWall.near_mesh()
	var far := TexturedWall.far_mesh()
	var tints := [Color(0.98, 0.97, 0.96), Color(1.02, 1.0, 0.99)]
	var k := 0
	for at in [Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)), Transform3D(turn, Vector3(4, 0, 1))]:
		for look in [[near, 0.0, TexturedWall.NEAR_RANGE], [far, TexturedWall.NEAR_RANGE, 0.0]]:
			var mi := MeshInstance3D.new()
			mi.mesh = look[0]
			mi.material_override = material
			mi.visibility_range_begin = look[1]
			mi.visibility_range_begin_margin = TexturedWall.FADE if look[1] > 0.0 else 0.0
			mi.visibility_range_end = look[2]
			mi.visibility_range_end_margin = TexturedWall.FADE if look[2] > 0.0 else 0.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			holder.add_child(mi)
			mi.global_transform = frame * at
			mi.set_instance_shader_parameter("tint", tints[k])
			textured.append(mi)
		k += 1
	# The corner post, as JointDetails makes it where the current walls meet
	var post := MeshInstance3D.new()
	post.mesh = PieceDetail.post_mesh(PieceShapes.GRID_WALL_HEIGHT, 13)
	post.material_override = material
	post.visibility_range_end = JointDetails.RANGE
	holder.add_child(post)
	post.global_transform = frame * Transform3D(Basis.IDENTITY, Vector3(4, 0, 0))
	textured.append(post)


# What each kind is made of
func _report_meshes() -> void:
	var counts := {}
	for p in current:
		if not p is BuildPiece:
			counts["corner post (JointDetails)"] = PieceRegistry._triangles((p as MeshInstance3D).mesh)
			continue
		for child in (p as Node).get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh:
				var key: String = String(child.name).rstrip("0123456789")
				counts[key] = PieceRegistry._triangles((child as MeshInstance3D).mesh)
	var near := PieceRegistry._triangles(textured[0].mesh)
	var far := PieceRegistry._triangles(textured[1].mesh)
	var post := PieceRegistry._triangles(textured[-1].mesh)
	print("TEXTEST | triangles per wall: current %s | textured near %d, far %d | corner post %d (both kinds)" % [counts, near, far, post])
	print("TEXTEST | looks: current detail 0-%s m, middle %s-%s m, plain box beyond, plus a shadow-only plain box out to %s m; textured near 0-%s m, far beyond, casting their own shadows; fade %s m (fade self)" % [BuildPiece.NEAR_RANGE, BuildPiece.NEAR_RANGE, BuildPiece.MID_RANGE, BuildPiece.MID_RANGE, TexturedWall.NEAR_RANGE, TexturedWall.FADE])


# The camera `d` metres in front of the corners' middle, at eye height, looking at the walls' middle
func _view(d: float) -> void:
	var eye := frame * Vector3(0, 1.7, d)
	var at := frame * Vector3(0, 1.0, 0)
	var to := at - eye
	player.global_position = eye - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(4)


func _grab(settle := 8) -> Image:
	await _frames(4)
	for k in settle:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# A kind's cost: the frame with only `shown` drawn, less the frame with neither
func _cost(shown: Array, other: Array) -> Array:
	_show(other, false)
	_show(shown, true)
	await _grab(4)
	var with := _info()
	_show(shown, false)
	await _grab(4)
	var without := _info()
	_show(shown, true)
	_show(other, true)
	await _grab(2)
	return [with[0] - without[0], with[1] - without[1]]


func _show(list: Array, on: bool) -> void:
	for n in list:
		(n as Node3D).visible = on


func _info() -> Array:
	return [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]


func _current_tier() -> String:
	var eye: Vector3 = player.camera.global_position
	var d := eye.distance_to((current[0] as Node3D).global_position + Vector3.UP)
	if d < BuildPiece.NEAR_RANGE:
		return "detail (%.1f m)" % d
	if d < BuildPiece.MID_RANGE:
		return "middle (%.1f m)" % d
	return "plain (%.1f m)" % d


# The share of dark pixels on one corner's wall face (`x`: the corner's middle along the frame):
# the wall square on to the camera, or (`angled`) the return wall's inner face, seen at an angle
func _dark(img: Image, x: float, angled: bool) -> String:
	var points := []
	if not angled:
		for p in [Vector3(x - 0.85, 0.25, 0.115), Vector3(x + 0.85, 0.25, 0.115), Vector3(x - 0.85, 1.75, 0.115), Vector3(x + 0.85, 1.75, 0.115)]:
			points.append(frame * p)
	else:
		var side := -1.0 if x < 0.0 else 1.0
		var face := x + side * 1.0 - side * 0.115
		for p in [Vector3(face, 0.25, 0.25), Vector3(face, 1.75, 0.25), Vector3(face, 0.25, 1.85), Vector3(face, 1.75, 1.85)]:
			points.append(frame * p)
	var cam: Camera3D = player.camera
	var size := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if cam.is_position_behind(p):
			return "behind the camera"
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	lo = lo.clamp(Vector2.ZERO, size - Vector2.ONE)
	hi = hi.clamp(Vector2.ZERO, size - Vector2.ONE)
	# (the middle half of the face's box on screen, clear of its edges)
	var box := Rect2(lo + (hi - lo) * 0.25, (hi - lo) * 0.5)
	if box.size.x < 3 or box.size.y < 3:
		return "too small"
	var lum := []
	for y in range(int(box.position.y), int(box.end.y)):
		for px in range(int(box.position.x), int(box.end.x)):
			var c := img.get_pixel(px, y)
			lum.append(c.r * 0.3 + c.g * 0.59 + c.b * 0.11)
	lum.sort()
	var median: float = lum[lum.size() / 2]
	var dark := lum.filter(func(v): return v < median * DARK).size()
	return "%.2f%% of %d px" % [100.0 * dark / lum.size(), lum.size()]


# Flat, dry, open ground with a clear view: the corners' spot, the frame turned so the camera stands
# toward the sun (the walls' faces lit), or failing that turned a quarter at a time; the ground
# within 0.4 m of level over the corners and the camera's 32 m line, nothing solid between
func _find_spot() -> bool:
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var toward_sun := Vector3(light.global_basis.z.x, 0, light.global_basis.z.z).normalized()
	var valley = get_tree().get_first_node_in_group("valley")
	var water: float = valley.global_position.y + valley.water_height() if valley else -INF
	var start: Vector3 = player.global_position
	for r in [10.0, 20.0, 30.0, 40.0, 55.0, 70.0, 90.0, 110.0, 130.0]:
		for k in 16:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0) * r
			var ground := Plot.ground_at(player, c.x, c.z)
			if ground < water + 1.0:
				continue
			for q in 4:
				var back := toward_sun.rotated(Vector3.UP, q * PI / 2.0)
				var basis := Basis(back.cross(Vector3.UP) * -1.0, Vector3.UP, back)
				var f := Transform3D(basis, Vector3(c.x, ground, c.z))
				if _clear(f, ground, water):
					frame = f
					return true
	return false


func _clear(f: Transform3D, ground: float, water: float) -> bool:
	for x in [-5.0, -3.0, 0.0, 3.0, 5.0]:
		for z in [-1.0, 0.0, 2.0, 5.0, 10.0, 16.0, 22.0, 30.0, 32.0]:
			var p := f * Vector3(x, 0, z)
			var h := Plot.ground_at(player, p.x, p.z)
			if absf(h - ground) > 0.4 or h < water + 0.5:
				return false
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	# Nothing standing anywhere over the corners or along the camera's line but the ground and loose
	# pickups (hidden before measuring: see _hide_pickups): straight down onto every 1.5 m
	var gx := -6.0
	while gx <= 6.0:
		var gz := -2.0
		while gz <= 33.0:
			var at := f * Vector3(gx, 0, gz)
			var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 5.0)
			down.exclude = [player.get_rid()]
			var below := space.intersect_ray(down)
			if below.is_empty():
				return false
			var what := below["collider"] as Node
			if not what.is_in_group("terrain_ground") and not what is ResourceNode:
				return false
			gz += 1.5
		gx += 1.5
	for x in [-3.0, 0.0, 3.0]:
		var query := PhysicsRayQueryParameters3D.create(f * Vector3(0, 1.7, 30.0), f * Vector3(x, 1.0, 0.5))
		query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and not (hit["collider"] as Node).is_in_group("terrain_ground") and not hit["collider"] is ResourceNode:
			return false
	return true


# Loose pickups (plant fiber, sticks, scrap...) within reach of the test's view hidden, so nothing
# stands in front of the walls
func _hide_pickups() -> void:
	var middle := frame.origin + frame.basis.z * 15.0
	for node in get_tree().root.find_children("*", "StaticBody3D", true, false):
		if node is ResourceNode and (node as Node3D).global_position.distance_to(middle) < 45.0:
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
