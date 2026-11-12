extends Node
## The look quality pass's measurements and pictures. Run in a window:
##
##     godot --path . res://tests/look_pass.tscn --resolution 1920x1080 --quit-after 60000
##     (add "-- before" after it to measure only the six buildings, on older code)
##
## Opens the world, finds dry open ground with the sun behind the camera, hides the grass, ferns,
## loose pickups and the screen's overlays, and turns V-Sync off. Then:
##   1. bakes every hybrid wall's far look (WallBaker), timing it and counting its memory;
##   2. the switch distance: a Wall 2 m seen at an angle with the switch at 8, 12 and 15 m. Just inside
##      each, it compares the close-up look with the baked slab in the same view (how much the switch
##      shows), and how much each shimmers as the camera sways by a few millimetres (dashes crawl).
##      It picks the distance with the least visible switch whose planks shimmer no more than twice
##      the slab's, and pictures the wall 1 m either side of it;
##   3. anti-aliasing on the Basic House at 15 and 30 m: the current MSAA 2×, TAA with FXAA, TAA
##      alone, and TAA with MSAA 2×. For each it records the frame time, the shimmer as the camera
##      sways, and the fine speckle in a still frame (crops to the scratch folder given after "--"),
##      then pictures the house at 30 and 15 m with the current setting;
##   4. six template buildings (every template, the Basic House twice) in a 3 × 2 grid, from 30 m and
##      12 m in front: the frame time (the average over 180 frames, and the graphics card's own render
##      time) and the video memory in use.
## Pictures go to docs/reference/ours/look_pass/. Prints "LOOKPASS" lines, then quits itself.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/look_pass"
const SWITCHES := [8.0, 12.0, 15.0]
const AA_MODES := ["msaa_2x", "taa_fxaa", "taa", "taa_msaa_2x"]
const AA_VIEWS := [15.0, 30.0]
## The wall is seen this far round from square on
const WALL_ANGLE := 30.0
const TEMPLATES := ["basic_house", "forager_s_hut", "storehouse", "woodcutter_s_hut", "workshop", "basic_house"]
## The grid's spacing (m) and the views of the six (metres in front of the group's front row)
const SPACING := 16.0
const GROUP_VIEWS := [30.0, 12.0]
const DAYLIGHT := 0.42

var player: Node
var registry: PieceRegistry
var sun: Node
var frame := Transform3D.IDENTITY
var placed: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _open_world()
	if not _find_spot():
		print("LOOKPASS | no dry open ground found")
		get_tree().quit(1)
		return
	_hide_pickups()
	var args := OS.get_cmdline_user_args()
	if args.has("before"):
		await _six_buildings("before")
		get_tree().quit()
		return
	scratch = args[0] if not args.is_empty() else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	await _bake_all()
	await _switch_distance()
	await _anti_aliasing()
	await _six_buildings("after")
	get_tree().quit()


var scratch := ""


# ---- 1. The bakes ----

func _bake_all() -> void:
	var baker: WallBaker = registry.baker
	var start := Time.get_ticks_msec()
	baker.prepare_all()
	for i in 20000:
		if baker.is_idle():
			break
		await get_tree().process_frame
	var shapes := (SnapEdges.WALLS + SnapEdges.TRIANGLES).size()
	print("LOOKPASS | bakes: %d shapes × %d variants = %d; %d baked now, %d read from the cache, in %.1f s; textures %.1f MB (colour and surface, DXT1, mipmapped, %d px a metre)" % [shapes, PieceRegistry.DETAIL_VARIANTS, shapes * PieceRegistry.DETAIL_VARIANTS, baker.made, baker.loaded, (Time.get_ticks_msec() - start) / 1000.0, baker.memory / 1048576.0, WallBaker.PIXELS_PER_METER])


# ---- 2. The switch distance ----

func _switch_distance() -> void:
	var wall_piece: PieceBuildable = load("res://buildables/structure/wall_2m.tres")
	var results := {}
	var wall: BuildPiece = null
	for d in SWITCHES:
		if wall:
			registry.remove(wall)
		BuildPiece.hybrid_range = d
		wall = registry.spawn(wall_piece, frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), {})
		await _frames(10)
		await _wall_view(wall, d - 0.5)
		var rect := _wall_rect(wall)
		var near := await _grab()
		var near_shimmer := await _shimmer(rect)
		wall.show_simple_look(true)
		var far := await _grab()
		var far_shimmer := await _shimmer(rect)
		wall.show_simple_look(false)
		var change := _difference(near, far, rect)
		results[d] = [change, near_shimmer, far_shimmer]
		print("LOOKPASS | switch at %d m | planks vs baked slab just inside it: %.2f%% average change (%.2f%% of pixels change by over 8%%) | shimmer: planks %.3f%%, slab %.3f%% | dark pixels: planks %s, slab %s" % [int(d), change[0], change[1], near_shimmer, far_shimmer, _dark(near, rect), _dark(far, rect)])
	# The least visible switch among those whose planks don't shimmer much more than the slab
	var chosen := 0.0
	for d in SWITCHES:
		var r: Array = results[d]
		if r[1] > r[2] * 2.0 + 0.02:
			continue
		if chosen == 0.0 or (r[0] as Array)[0] < (results[chosen][0] as Array)[0] - 0.05:
			chosen = d
	if chosen == 0.0:
		chosen = SWITCHES[0]
	print("LOOKPASS | chosen switch distance: %d m" % int(chosen))
	registry.remove(wall)
	BuildPiece.hybrid_range = chosen
	wall = registry.spawn(wall_piece, frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), {})
	await _frames(10)
	for side in [[-1.0, "inside"], [1.0, "outside"]]:
		await _wall_view(wall, chosen + side[0])
		await _save("wall_%dm_%s_%dm.png" % [int(chosen), side[1], int(chosen + side[0])])
	registry.remove(wall)
	await _frames(5)


# The camera `d` m from the wall's middle, WALL_ANGLE round from square on, at eye height
func _wall_view(wall: BuildPiece, d: float) -> void:
	var middle := wall.global_transform * Vector3(0, 1.0, 0)
	var out := (wall.global_basis * Vector3.BACK).rotated(Vector3.UP, deg_to_rad(WALL_ANGLE)).normalized()
	var eye := middle + out * d
	eye.y = frame.origin.y + 1.7
	_look(eye, middle)
	await _frames(5)


func _wall_rect(wall: BuildPiece) -> Rect2:
	var points := []
	for p in [Vector3(-0.9, 0.15, 0.1), Vector3(0.9, 0.15, 0.1), Vector3(-0.9, 1.85, 0.1), Vector3(0.9, 1.85, 0.1)]:
		points.append(wall.global_transform * p)
	return _screen_rect(points, 0.15)


# ---- 3. Anti-aliasing ----

func _anti_aliasing() -> void:
	var template := BuildingTemplate.read("res://buildables/templates/basic_house.json")
	var house := frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, 6.0))
	var pieces := []
	for item in template.items:
		if item["buildable"] is PieceBuildable:
			pieces.append(registry.spawn(item["buildable"], house * (item["relative"] as Transform3D), {}))
	await _frames(60)
	var vp := get_viewport()
	var front := 6.0 - template.size.y / 2.0
	for d in AA_VIEWS:
		await _aim(Vector3(0, 1.7, front - d), Vector3(0, 2.6, 6.0))
		var corners := []
		for x in [-template.size.x / 2.0, template.size.x / 2.0]:
			for z in [-template.size.y / 2.0, template.size.y / 2.0]:
				for y in [0.0, 6.5]:
					corners.append(house * Vector3(x, y, z))
		var rect := _screen_rect(corners, 0.0)
		for mode in AA_MODES:
			_set_aa(vp, mode)
			await _frames(20)
			var cost := await _frame_cost()
			var still := await _grab(12)
			var shimmer := await _shimmer(rect)
			still.get_region(Rect2i(rect)).save_png(scratch.path_join("aa_%s_%dm.png" % [mode, int(d)]))
			print("LOOKPASS | anti-aliasing %s | %d m | frame %.2f ms (GPU %.2f ms) | shimmer while swaying %.3f%% | fine speckle %.2f%% | house %d × %d px" % [mode, int(d), cost[0], cost[1], shimmer, _speckle(still, rect), int(rect.size.x), int(rect.size.y)])
	_set_aa(vp, "msaa_2x")
	await _frames(20)
	for d in [30.0, 15.0]:
		await _aim(Vector3(0, 1.7, front - d), Vector3(0, 2.6, 6.0))
		await _save("house_%dm.png" % int(d))
	for piece in pieces:
		registry.remove(piece)
	await _frames(10)


func _set_aa(vp: Viewport, mode: String) -> void:
	if mode == "taa_fxaa":
		GameSettings.apply_anti_aliasing(vp, "taa")
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	else:
		GameSettings.apply_anti_aliasing(vp, mode)


# ---- Measuring pictures ----

func _grab(settle := 8) -> Image:
	await _frames(2)
	for k in settle:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# How much the picture flickers inside `rect` as the camera sways a few millimetres side to side each
# frame: the average change in brightness from frame to frame (% of the region's average)
func _shimmer(rect: Rect2) -> float:
	var camera: Camera3D = player.camera
	var right := camera.global_basis.x
	var home: Vector3 = player.global_position
	var last: Image = null
	var total := 0.0
	var count := 0
	for i in 16:
		player.global_position = home + right * (0.003 if i % 2 == 0 else -0.003)
		await RenderingServer.frame_post_draw
		if i < 6:
			continue
		var img := get_viewport().get_texture().get_image()
		if last:
			total += (_difference(last, img, rect) as Array)[0]
			count += 1
		last = img
	player.global_position = home
	await _frames(2)
	return total / maxf(count, 1)


# [average brightness change (% of the average brightness), % of pixels changing by over 8%]
func _difference(a: Image, b: Image, rect: Rect2) -> Array:
	var sum := 0.0
	var base := 0.0
	var big := 0
	var n := 0
	for y in range(int(rect.position.y), int(rect.end.y), 2):
		for x in range(int(rect.position.x), int(rect.end.x), 2):
			var la := _lum(a.get_pixel(x, y))
			var lb := _lum(b.get_pixel(x, y))
			sum += absf(la - lb)
			base += la
			if absf(la - lb) > 0.08 * maxf(la, 0.02):
				big += 1
			n += 1
	return [100.0 * sum / maxf(base, 0.0001), 100.0 * big / maxf(n, 1)]


# Fine speckle in a still picture: the average brightness difference between neighbouring pixels
# (% of the average brightness)
func _speckle(img: Image, rect: Rect2) -> float:
	var sum := 0.0
	var base := 0.0
	for y in range(int(rect.position.y), int(rect.end.y) - 1):
		for x in range(int(rect.position.x), int(rect.end.x) - 1):
			var l := _lum(img.get_pixel(x, y))
			sum += absf(l - _lum(img.get_pixel(x + 1, y))) + absf(l - _lum(img.get_pixel(x, y + 1)))
			base += l
	return 100.0 * sum / maxf(base * 2.0, 0.0001)


# The share of pixels darker than 45% of the region's middle brightness
func _dark(img: Image, rect: Rect2) -> String:
	var lum := []
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			lum.append(_lum(img.get_pixel(x, y)))
	if lum.is_empty():
		return "-"
	lum.sort()
	var median: float = lum[lum.size() / 2]
	return "%.2f%%" % (100.0 * lum.filter(func(v): return v < median * 0.45).size() / lum.size())


static func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.59 + c.b * 0.11


# The box on screen round these points, shrunk by `inset` of its size on each side
func _screen_rect(points: Array, inset: float) -> Rect2:
	var camera: Camera3D = player.camera
	var size := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var s := camera.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	lo = lo.clamp(Vector2.ZERO, size - Vector2.ONE)
	hi = hi.clamp(Vector2.ZERO, size - Vector2.ONE)
	return Rect2(lo + (hi - lo) * inset, (hi - lo) * (1.0 - inset * 2.0))


func _save(file: String) -> void:
	await _grab()
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("LOOKPASS | saved %s" % file)


func _open_world() -> void:
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
	sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = DAYLIGHT
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _frames(5)
	_hide_overlays()
	for f in get_tree().root.find_children("*", "Node3D", true, false):
		if f.get_script() and (f.get_script() as Script).resource_path.ends_with("world/foliage.gd"):
			(f as Node3D).visible = false


# The six buildings in a 3 × 2 grid behind the frame's origin (the front row's middle at z = 0), and
# the cost from each group view
func _six_buildings(label: String) -> void:
	for i in TEMPLATES.size():
		var template := BuildingTemplate.read("res://buildables/templates/%s.json" % TEMPLATES[i])
		var at := frame * Transform3D(Basis.IDENTITY, Vector3((i % 3 - 1) * SPACING, 0.0, (i / 3) * SPACING + 6.0))
		for item in template.items:
			if item["buildable"] is PieceBuildable:
				placed.append(registry.spawn(item["buildable"], at * (item["relative"] as Transform3D), {}))
	await _frames(90)
	for d in GROUP_VIEWS:
		await _aim(Vector3(0, 6.0 if d > 20.0 else 3.0, -d), Vector3(0, 2.5, SPACING * 0.75))
		var cost := await _frame_cost()
		print("LOOKPASS | six buildings %s | %d m | frame %.2f ms (GPU %.2f ms, CPU %.2f ms) | video memory %.0f MB (textures %.0f MB, buffers %.0f MB) | %d pieces" % [label, int(d), cost[0], cost[1], cost[2], cost[3], cost[4], cost[5], placed.size()])


# [average frame ms, GPU render ms, CPU render ms, video memory MB, texture MB, buffer MB]
func _frame_cost() -> Array:
	var rid := get_viewport().get_viewport_rid()
	for i in 30:
		await get_tree().process_frame
	var total := 0.0
	var gpu := 0.0
	var cpu := 0.0
	var n := 180
	var start := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	total = (Time.get_ticks_usec() - start) / 1000.0
	var mb := 1024.0 * 1024.0
	return [total / n, gpu / n, cpu / n, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / mb, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / mb, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / mb]


func _aim(eye: Vector3, at: Vector3) -> void:
	var from := frame * eye
	from.y = Plot.ground_at(player, from.x, from.z) + eye.y
	var target := frame * at
	target.y = frame.origin.y + at.y
	_look(from, target)
	await _frames(5)


# The camera at `from` (world), looking at `target`
func _look(from: Vector3, target: Vector3) -> void:
	var to := target - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


# Dry ground (above the water) over the six buildings' grid and out to 34 m in front of it, the
# frame turned so the camera on -Z has the sun behind it
func _find_spot() -> bool:
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var toward_sun := Vector3(light.global_basis.z.x, 0, light.global_basis.z.z).normalized()
	var valley = get_tree().get_first_node_in_group("valley")
	var water: float = valley.global_position.y + valley.water_height() if valley else -INF
	var start: Vector3 = player.global_position
	for r in [20.0, 30.0, 40.0, 55.0, 70.0, 90.0, 120.0, 150.0, 190.0, 240.0]:
		for k in 24:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 24.0) * r
			var ground := Plot.ground_at(player, c.x, c.z)
			if ground < water + 1.0:
				continue
			var basis := Basis(Vector3.UP.cross(-toward_sun), Vector3.UP, -toward_sun)
			var f := Transform3D(basis, Vector3(c.x, ground, c.z))
			var ok := true
			var x := -SPACING * 1.6
			while x <= SPACING * 1.6 and ok:
				var z := -34.0
				while z <= SPACING * 2.0 and ok:
					var q := f * Vector3(x, 0, z)
					var height := Plot.ground_at(player, q.x, q.z)
					if height < water + 0.5 or (z > 0.0 and absf(height - ground) > 2.5):
						ok = false
					z += 3.0
				x += 3.0
			if ok:
				frame = f
				return true
	return false


func _hide_pickups() -> void:
	for node in get_tree().root.find_children("*", "StaticBody3D", true, false):
		if node is ResourceNode and (node as Node3D).global_position.distance_to(frame.origin) < 80.0:
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
