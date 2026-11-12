extends Node
## The hybrid floors' and foundations' measurements and pictures (the look pass, see DESIGN.md). Run
## in a window, each run ending itself:
##
##     godot --path . res://tests/floor_pass.tscn --resolution 1920x1080 --quit-after 60000 -- <mode>
##
## Modes:
##   costs <label>  the drawing cost: the six template buildings from 12 m and the Basic House from
##                  30 m, each the visible and the shadow pass (draw calls, triangles) and the frame
##                  time (average, GPU and CPU render time) with V-Sync off. (Works on older code too.)
##   load cold      the world opened after clearing the bake cache (a first launch after the look code
##                  changes): seconds until it's open, then until the loading cover lifts and every
##                  bake is in; how many variants were baked and read, and the bakes' memory, floors'
##                  share included. "load warm": the same with the cache as it is.
##   switch         the floors' bakes (count, memory, triangles close-up and far), then the switch
##                  distance: at each of SWITCHES, just inside it, the close-up look against the far
##                  look in the same view (how much the switch shows) and how much each shimmers as the
##                  camera sways a few millimetres, from three spots: standing on a floor (a strip of
##                  floors running away from the eye, 1.7 m over their tops), from the ground beside a
##                  raised floor (on foundations, 1 m up, seen from 1.7 m over the ground), and from a
##                  raised spot (6 m up, looking down across the floor); and a row of stone foundations
##                  seen from outside (their sides). It picks the distance where the switch shows least
##                  over all four, among those whose close-up look shimmers no more than twice the far
##                  look's (plus 0.02) in every view; then pictures a floor 1 m either side of it from
##                  standing height and the stone foundations from outside at the same distances, in
##                  SHOTS. (BuildPiece.floor_range is only changed for the run.)
##   shots          only the pictures, at the current BuildPiece.floor_range.
## Opens the world, finds dry open ground with the sun behind the camera, hides the grass, ferns,
## loose pickups and the screen's overlays. Prints "FLOORPASS" lines, then quits itself.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/look_pass/floors"
const SWITCHES := [10.0, 15.0, 20.0, 25.0]
const TEMPLATES := ["basic_house", "forager_s_hut", "storehouse", "woodcutter_s_hut", "workshop", "basic_house"]
const SPACING := 16.0
const DAYLIGHT := 0.42
## The floors and foundations with a hybrid look (see WallBaker.FLOORS); a few for the screen tests
const VIEWS := ["standing", "beside", "raised", "foundation side"]

var player: Node
var registry: PieceRegistry
var sun: Node
var frame := Transform3D.IDENTITY


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if not args.is_empty() else "switch"
	if mode == "load":
		await _load(args.has("cold"))
		get_tree().quit()
		return
	await _open_world()
	if not _find_spot():
		print("FLOORPASS | no dry open ground found")
		get_tree().quit(1)
		return
	_hide_pickups()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	if mode == "costs":
		await _wait_bakes()
		await _costs(args[1] if args.size() > 1 else "now")
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
		_find_flat_spot()
		_hide_pickups()
		await _wait_bakes()
		if mode == "shots":
			await _shots(BuildPiece.floor_range)
		else:
			_report_bakes()
			var chosen := await _switch_distance()
			await _shots(chosen)
	get_tree().quit()


# ---- Load times and bakes ----

func _load(cold: bool) -> void:
	if cold:
		var dir := DirAccess.open(WallBaker.CACHE_DIR)
		var cleared := 0
		if dir:
			for file in dir.get_files():
				dir.remove(file)
				cleared += 1
		print("FLOORPASS | cold start: %d cached bakes cleared" % cleared)
	var start := Time.get_ticks_msec()
	await _open_world()
	var opened := Time.get_ticks_msec()
	for i in 60000:
		await get_tree().process_frame
		var covered := false
		for n in get_tree().root.find_children("*", "Node3D", true, false):
			if n is ShaderWarmup:
				covered = true
				break
		if not covered and registry.baker.is_idle() and i > 10:
			break
	var ready := Time.get_ticks_msec()
	var floors: Array = WallBaker.FLOORS
	print("FLOORPASS | %s launch: world open in %.1f s, then the loading cover and bakes done in %.1f s more (%.1f s in all); %d variants baked, %d read from the cache; bakes %.1f MB (floors and foundations %.1f MB)" % ["cold" if cold else "warm", (opened - start) / 1000.0, (ready - opened) / 1000.0, (ready - start) / 1000.0, registry.baker.made, registry.baker.loaded, registry.baker.memory / 1048576.0, registry.baker.memory_of(floors) / 1048576.0])


func _wait_bakes() -> void:
	registry.baker.prepare_all()
	for i in 30000:
		if registry.baker.is_idle():
			break
		await get_tree().process_frame


func _report_bakes() -> void:
	var baker: WallBaker = registry.baker
	var floors: Array = WallBaker.FLOORS
	print("FLOORPASS | floor bakes: %d shapes × %d variants = %d bakes; floors' textures %.1f MB, all bakes %.1f MB (%d variants baked now, %d read from the cache)" % [floors.size(), PieceRegistry.DETAIL_VARIANTS, floors.size() * PieceRegistry.DETAIL_VARIANTS, baker.memory_of(floors) / 1048576.0, baker.memory / 1048576.0, baker.made, baker.loaded])
	for shape in floors:
		var detail := PieceRegistry._triangles(registry.detail_mesh(shape, 0)["mesh"])
		var far := PieceRegistry._triangles(baker.far_mesh(shape, 0))
		var mid_mesh: Mesh = PieceDetail.build(shape, hash(shape), true).get("mesh")
		var trim: Mesh = registry.roof_parts(shape, 0)["trim"]
		print("FLOORPASS | %s: close-up %d triangles; far look %d (of them sides and trim %d), one draw; (the old middle look had %d, the plain box %d)" % [shape, detail, far, PieceRegistry._triangles(trim) if trim else 0, PieceRegistry._triangles(mid_mesh), PieceRegistry._triangles(registry.shape_of(shape)["mesh"])])


# ---- The switch distance ----

# Builds what each view looks at, measures every distance, picks one; returns it
func _switch_distance() -> float:
	var keep: float = BuildPiece.floor_range
	var results := {}
	for d in SWITCHES:
		BuildPiece.floor_range = d
		var r := []
		for view in VIEWS:
			var built := await _build(view, d)
			var target: Array = built[0]
			var rect := _rect_of(built[1])
			var near := await _grab()
			var near_shimmer := await _shimmer(rect)
			for p in target:
				(p as BuildPiece).show_simple_look(true)
			var far := await _grab()
			var far_shimmer := await _shimmer(rect)
			var change := _difference(near, far, rect)
			r.append([change[0], near_shimmer, far_shimmer])
			print("FLOORPASS | switch at %d m, %s | close-up vs far look just inside it: %.2f%% average change (%.2f%% of pixels change by over 8%%) | shimmer: close-up %.3f%%, far %.3f%% | region %d × %d px" % [int(d), view, change[0], change[1], near_shimmer, far_shimmer, int(rect.size.x), int(rect.size.y)])
			await _clear()
		results[d] = r
	var chosen := 0.0
	var best := INF
	for d in SWITCHES:
		var ok := true
		var total := 0.0
		for v in results[d]:
			if v[1] > v[2] * 2.0 + 0.02:
				ok = false
			total += v[0]
		print("FLOORPASS | at %d m: total change %.2f%%, shimmer within twice the far look's in every view: %s" % [int(d), total, ok])
		if ok and total < best - 0.1:
			best = total
			chosen = d
	if chosen == 0.0:
		chosen = keep
		print("FLOORPASS | no distance passed the shimmer limit: kept %d m" % int(keep))
	else:
		print("FLOORPASS | chosen floor switch distance: %d m" % int(chosen))
	BuildPiece.floor_range = keep
	return chosen


# Builds a view's pieces with the camera `d` - 0.5 m from the measured ones (just inside the switch)
# and the camera placed: [pieces measured (their looks toggled), points round them on screen]
func _build(view: String, d: float, distance := -1.0) -> Array:
	var at := d - 0.5 if distance < 0.0 else distance
	var floor_piece: PieceBuildable = load("res://buildables/structure/floor.tres")
	var foundation_wood: PieceBuildable = load("res://buildables/structure/foundation_wood.tres")
	var foundation_stone: PieceBuildable = load("res://buildables/structure/foundation_stone.tres")
	var measured := []
	var points := []
	match view:
		"standing":
			# A strip of floors 3 wide from under the eye out past the measured rows, along +Z (away from
			# the sun, so the camera has it behind), laid level at the highest ground under it so no floor
			# far off is buried by a rise; the eye 1.7 m over their tops
			var rows := int(ceil((at + 6.0) / 2.0))
			var row := roundf(at / 2.0) * 2.0
			var y := _level(-3.0, 3.0, -1.0, rows * 2.0) + 0.2
			for k in rows:
				for x in [-2.0, 0.0, 2.0]:
					var p := registry.spawn(floor_piece, frame * Transform3D(Basis.IDENTITY, Vector3(x, y, k * 2.0)), {})
					# (the row `at` away and the one before it: both just inside the switch)
					if absf(k * 2.0 - row) < 0.01 or absf(k * 2.0 - (row - 2.0)) < 0.01:
						measured.append(p)
			await _frames(10)
			# (the eye stands `at` from the far measured row's middle, along the strip, on the floors)
			_look(frame * Vector3(0, y + 1.7, row - at), frame * Vector3(0, y, row - 1.0))
			for x in [-2.8, 2.8]:
				for z in [row - 2.8, row + 0.8]:
					points.append(frame * Vector3(x, y, z))
		"beside":
			# Two wood foundations (tops 1 m up) seen from the ground: their top at a low glancing angle,
			# and their log sides
			var y := _level(-2.0, 2.0, -1.0, 1.0) + 1.0
			for x in [-1.0, 1.0]:
				measured.append(registry.spawn(foundation_wood, frame * Transform3D(Basis.IDENTITY, Vector3(x, y, 0)), {}))
			await _frames(10)
			var eye := frame * Vector3(0.5, 0, -at)
			eye = Vector3(eye.x, Plot.ground_at(player, eye.x, eye.z) + 1.7, eye.z)
			_look(eye, frame * Vector3(0, y - 0.3, 0))
			for x in [-1.9, 1.9]:
				for p in [Vector3(x, y, 0.9), Vector3(x, y - 0.9, -1.0)]:
					points.append(frame * p)
		"raised":
			# A 3 × 3 floor on the ground seen from 6 m up, looking down across it
			var y := _level(-3.0, 3.0, -3.0, 3.0) + 0.2
			for x in [-2.0, 0.0, 2.0]:
				for z in [-2.0, 0.0, 2.0]:
					measured.append(registry.spawn(floor_piece, frame * Transform3D(Basis.IDENTITY, Vector3(x, y, z)), {}))
			await _frames(10)
			var flat := sqrt(maxf(at * at - 36.0, 1.0))
			_look(frame * Vector3(0, y + 6.0, -flat), frame * Vector3(0, y, 0))
			for x in [-2.6, 2.6]:
				for z in [-2.6, 2.6]:
					points.append(frame * Vector3(x, y, z))
		"foundation side":
			# A row of three stone foundations (tops 1 m up) seen from outside, 30° round from straight on,
			# at eye height: their stone sides (the sunlit -Z side, with the sun behind the camera)
			var y := _level(-3.0, 3.0, -1.0, 1.0) + 1.0
			for x in [-2.0, 0.0, 2.0]:
				measured.append(registry.spawn(foundation_stone, frame * Transform3D(Basis.IDENTITY, Vector3(x, y, 0)), {}))
			await _frames(10)
			var out := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(30.0))
			var eye := frame * (Vector3(0, 0, -1.0) + out * at)
			eye = Vector3(eye.x, Plot.ground_at(player, eye.x, eye.z) + 1.7, eye.z)
			_look(eye, frame * Vector3(0, y - 0.5, -1.0))
			for x in [-2.6, 2.6]:
				for dy in [-0.85, -0.1]:
					points.append(frame * Vector3(x, y + dy, -1.0))
	await _frames(5)
	return [measured, points]


func _clear() -> void:
	for p in registry.all_pieces():
		registry.remove(p)
	await _frames(5)


# The highest ground over a rectangle of the frame (x0..x1, z0..z1), as a height in the frame
func _level(x0: float, x1: float, z0: float, z1: float) -> float:
	var top := -INF
	var x := x0
	while x <= x1 + 0.01:
		var z := z0
		while z <= z1 + 0.01:
			var q := frame * Vector3(x, 0, z)
			top = maxf(top, Plot.ground_at(player, q.x, q.z) - frame.origin.y)
			z += 1.0
		x += 1.0
	return top


# The flattest dry ground near the start for the switch views (a strip 8 m wide from 32 m behind the
# frame to 32 m in front, varying as little as can be found), the frame turned so the camera on -Z has
# the sun behind it. Keeps the frame _find_spot chose if nothing flatter turns up.
func _find_flat_spot() -> void:
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var toward_sun := Vector3(light.global_basis.z.x, 0, light.global_basis.z.z).normalized()
	var basis := Basis(Vector3.UP.cross(-toward_sun), Vector3.UP, -toward_sun)
	var valley = get_tree().get_first_node_in_group("valley")
	var water: float = valley.global_position.y + valley.water_height() if valley else -INF
	var start: Vector3 = player.global_position
	var best := INF
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for r in [20.0, 40.0, 60.0, 90.0, 120.0, 160.0, 200.0]:
		for k in 24:
			var c: Vector3 = start + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 24.0) * r
			var f := Transform3D(basis, Vector3(c.x, Plot.ground_at(player, c.x, c.z), c.z))
			# (on the map, and open: straight down along the strip the first thing hit is the ground
			# itself, not the flat beyond the map's edge or anything standing there, the wreck say)
			var open := true
			var along := -32.0
			while along <= 32.0 and open:
				for across in [-4.0, 0.0, 4.0]:
					var q := f * Vector3(across, 0, along)
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 60.0, q + Vector3.DOWN * 60.0, 0xFFFFFFFF, [player.get_rid()]))
					if hit.is_empty() or absf((hit["position"] as Vector3).y - Plot.ground_at(player, q.x, q.z)) > 0.3:
						open = false
				along += 4.0
			if not open:
				continue
			var lo := INF
			var hi := -INF
			var x := -4.0
			while x <= 4.0:
				var z := -32.0
				while z <= 32.0:
					var q := f * Vector3(x, 0, z)
					var h := Plot.ground_at(player, q.x, q.z)
					lo = minf(lo, h)
					hi = maxf(hi, h)
					z += 2.0
				x += 2.0
			if lo > water + 0.5 and hi - lo < best:
				best = hi - lo
				frame = f
	print("FLOORPASS | switch views on ground varying %.2f m over 8 × 64 m" % best)


func _rect_of(points: Array) -> Rect2:
	return _screen_rect(points, 0.08)


# ---- The pictures ----

# A floor 1 m either side of the switch from standing height, and the stone foundations from outside
# at the same distances
func _shots(chosen: float) -> void:
	var keep: float = BuildPiece.floor_range
	BuildPiece.floor_range = chosen
	for view in ["standing", "foundation side"]:
		for side in [[-1.0, "inside"], [1.0, "outside"]]:
			await _build(view, chosen, chosen + side[0])
			await _frames(20)
			var file := "%s_%dm_%s_%dm.png" % [view.replace(" ", "_"), int(chosen), side[1], int(chosen + side[0])]
			await _grab()
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
			print("FLOORPASS | saved %s" % file)
			await _clear()
	BuildPiece.floor_range = keep


# ---- Drawing cost ----

#
# Each view twice in the same run, so the world is the same: floors and foundations with their old
# three looks (PieceRegistry.hybrid_floors off: "before") and with the hybrid look ("after"). The
# empty view is measured after the buildings are taken away, once the world has settled.
func _costs(label: String) -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _frames(240)
	var views := [["six buildings 12 m", TEMPLATES, Vector3(0, 3.0, -12.0), Vector3(0, 2.5, SPACING * 0.75)],
		["Basic House 30 m", ["basic_house"], Vector3(0, 1.7, 6.0 - 3.0 - 30.0), Vector3(0, 2.6, 6.0)]]
	for view in views:
		for hybrid in [false, true]:
			PieceRegistry.hybrid_floors = hybrid
			var pieces := _place(view[1])
			await _frames(90)
			await _aim(view[2], view[3])
			var passes := await _passes()
			var time := await _frame_time()
			for p in pieces:
				registry.remove(p)
			await _frames(30)
			var empty := await _passes()
			print("FLOORPASS | costs, %s, %s | %s | visible %d draws %d triangles | shadows %d draws %d triangles | (the empty view: visible %d draws %d triangles, shadows %d draws %d triangles) | frame %.2f ms (GPU %.2f ms, CPU %.2f ms) | %d pieces" % [label, "after (hybrid floors)" if hybrid else "before (floors' three looks)", view[0], passes[0], passes[1], passes[2], passes[3], empty[0], empty[1], empty[2], empty[3], time[0], time[1], time[2], pieces.size()])
	PieceRegistry.hybrid_floors = true


# [visible draws, visible triangles, shadow draws, shadow triangles] in the root viewport's frame
func _passes() -> Array:
	for i in 20:
		await get_tree().process_frame
	for k in 4:
		await RenderingServer.frame_post_draw
	var rid := get_viewport().get_viewport_rid()
	var found := []
	for kind in [RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]:
		found.append(RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		found.append(RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	return found


# [average frame ms, GPU render ms, CPU render ms] over 180 frames (V-Sync off)
func _frame_time() -> Array:
	var rid := get_viewport().get_viewport_rid()
	for i in 30:
		await get_tree().process_frame
	var gpu := 0.0
	var cpu := 0.0
	var n := 180
	var start := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	return [(Time.get_ticks_usec() - start) / 1000.0 / n, gpu / n, cpu / n]


# Template buildings in a 3 × 2 grid behind the frame's origin (one alone: the grid's first spot)
func _place(names: Array) -> Array:
	var placed := []
	for i in names.size():
		var template := BuildingTemplate.read("res://buildables/templates/%s.json" % names[i])
		var at := frame * Transform3D(Basis.IDENTITY, Vector3((i % 3 - 1) * SPACING if names.size() > 1 else 0.0, 0.0, (i / 3) * SPACING + 6.0))
		for item in template.items:
			if item["buildable"] is PieceBuildable:
				placed.append(registry.spawn(item["buildable"], at * (item["relative"] as Transform3D), {}))
	return placed


# ---- Measuring pictures ----

func _grab(settle := 8) -> Image:
	await _frames(2)
	for k in settle:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# How much the picture flickers inside `rect` as the camera sways a few millimetres side to side each
# frame: the average change in brightness from frame to frame (% of the region's average)
func _shimmer(rect: Rect2) -> float:
	var right: Vector3 = player.camera.global_basis.x
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


# ---- The world, the camera and the spot ----

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
	await _frames(5)
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for child in player.camera.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
	for f in get_tree().root.find_children("*", "Node3D", true, false):
		if f.get_script() and (f.get_script() as Script).resource_path.ends_with("world/foliage.gd"):
			(f as Node3D).visible = false


func _aim(eye: Vector3, at: Vector3) -> void:
	var from := frame * eye
	from.y = Plot.ground_at(player, from.x, from.z) + eye.y
	var target := frame * at
	target.y = frame.origin.y + at.y
	_look(from, target)
	await _frames(5)


func _look(from: Vector3, target: Vector3) -> void:
	var to := target - from
	player.global_position = from - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


# Dry, fairly level ground over the six buildings' grid and out to 34 m in front of it (as
# tests/roof_pass.gd), the frame turned so the camera on -Z has the sun behind it
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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
