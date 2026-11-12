extends Node
## The hybrid roofs' measurements and pictures. Run in a window:
##
##     godot --path . res://tests/roof_pass.tscn --resolution 1920x1080 --quit-after 60000
##     (add "-- before" to measure only the drawing cost, on older code)
##
## Or, to check the bake cache and break the cost down (nothing saved, the switch left as it is):
##     ... -- check [cold] [<folder for crops>]
## "cold" clears the bake cache first, as a first launch after the look code changes. It times the
## world opening until the loading cover lifts and every bake is in, measures the drawing cost as
## below, breaks down the six buildings' 12 m view (draw calls and triangles in the visible and the
## shadow passes, by hybrid roofs, hybrid walls and everything else, with the hybrid looks and
## without: PieceRegistry.hybrid_walls off), and measures the switch at every distance in SWITCHES
## from both spots with the player frozen (its own processing off) so the camera can't drift.
##
## Opens the world, finds dry open ground with the sun behind the camera, hides the grass, ferns,
## loose pickups and the screen's overlays, and turns V-Sync off. Then:
##   1. bakes every hybrid wall's and roof's far look (WallBaker), counting the roofs' bakes and memory;
##   2. the switch distance: a Roof (26°) raised as on walls, with the switch at each of SWITCHES,
##      seen from the ground (eye height, 30° round from straight on) and from a raised spot looking
##      up along the slope at a glancing angle. Just inside each distance it compares the close-up look
##      with the far look in the same view (how much the switch shows) and how much each shimmers as
##      the camera sways a few millimetres. It picks the distance with the least visible switch (both
##      views together) whose shakes shimmer no more than twice the far look's in either view, and
##      pictures the roof 1 m either side of it from both spots;
##   3. the Basic House at 30 and 15 m;
##   4. the drawing cost (draw calls, triangles, video memory) of the Basic House from 30 m and 15 m,
##      and of six template buildings (every template, the Basic House twice, in a 3 × 2 grid) from 30
##      m and 12 m: each the frame with the buildings less the same view empty.
## Pictures go to docs/reference/ours/look_pass/roofs/. Prints "ROOFPASS" lines, then quits itself.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/look_pass/roofs"
const SWITCHES := [12.0, 15.0, 20.0, 25.0]
## The test roof's height (its low edge, as on a wall) and the views' angles
const ROOF_HEIGHT := 2.5
const GROUND_ANGLE := 30.0
const TEMPLATES := ["basic_house", "forager_s_hut", "storehouse", "woodcutter_s_hut", "workshop", "basic_house"]
const SPACING := 16.0
const DAYLIGHT := 0.42
const HOUSE_VIEWS := [30.0, 15.0]
const GROUP_VIEWS := [30.0, 12.0]

var player: Node
var registry: PieceRegistry
var sun: Node
var frame := Transform3D.IDENTITY
var scratch := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("check"):
		await _check(args.has("cold"))
		get_tree().quit()
		return
	await _open_world()
	if not _find_spot():
		print("ROOFPASS | no dry open ground found")
		get_tree().quit(1)
		return
	_hide_pickups()
	if OS.get_cmdline_user_args().has("before"):
		await _costs("before")
		get_tree().quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	# (a folder given after "--" gets crops of each view, close-up and far, for checking by eye)
	if not OS.get_cmdline_user_args().is_empty():
		scratch = OS.get_cmdline_user_args()[0]
	await _bake_all()
	await _switch_distance()
	await _house_shots()
	await _costs("after")
	get_tree().quit()


# ---- Checking the cache and the cost ----

func _check(cold: bool) -> void:
	for a in OS.get_cmdline_user_args():
		if a.contains("/") or a.contains("\\"):
			scratch = a
	if cold:
		var dir := DirAccess.open(WallBaker.CACHE_DIR)
		var cleared := 0
		if dir:
			for file in dir.get_files():
				dir.remove(file)
				cleared += 1
		print("ROOFPASS | cold start: %d cached bakes cleared" % cleared)
	var start := Time.get_ticks_msec()
	await _open_world()
	var opened := Time.get_ticks_msec()
	# The loading cover (ShaderWarmup) prepares every wall and roof; then every bake is in
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
	print("ROOFPASS | %s launch: world open in %.1f s, then the loading cover and bakes done in %.1f s more (%.1f s in all); %d variants baked, %d read from the cache; bakes %.1f MB" % ["cold" if cold else "warm", (opened - start) / 1000.0, (ready - opened) / 1000.0, (ready - start) / 1000.0, registry.baker.made, registry.baker.loaded, registry.baker.memory / 1048576.0])
	if not _find_spot():
		print("ROOFPASS | no dry open ground found")
		return
	_hide_pickups()
	# (frozen from here on: nothing of the player's own moves it or its camera)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	if OS.get_cmdline_user_args().has("shadows"):
		await _shadow_compare()
		await _low_sun_shot()
		return
	await _costs("check, " + ("cold" if cold else "warm"))
	await _breakdown()
	await _switch_measure()


# The shadow rule (BuildPiece.far_shadows: a piece with a far look casts from its far mesh at every
# distance) against each look casting its own: the 12 m village and the 30 m Basic House, each built
# both ways, with the visible and shadow passes and the frame time
func _shadow_compare() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var views := [["six buildings 12 m", TEMPLATES, Vector3(0, 3.0, -12.0), Vector3(0, 2.5, SPACING * 0.75)],
		["Basic House 30 m", ["basic_house"], Vector3(0, 1.7, 6.0 - 3.0 - 30.0), Vector3(0, 2.6, 6.0)]]
	for view in views:
		for rule in [true, false]:
			BuildPiece.far_shadows = rule
			var pieces := _place(view[1])
			await _frames(90)
			await _aim(view[2], view[3])
			var passes := await _passes()
			var time := await _frame_time()
			print("ROOFPASS | shadows, %s, %s | visible %d draws %d triangles | shadows %d draws %d triangles | frame %.2f ms (GPU %.2f ms, CPU %.2f ms)" % [view[0], "far-mesh shadows" if rule else "each look casts its own", passes[0], passes[1], passes[2], passes[3], time[0], time[1], time[2]])
			for p in pieces:
				registry.remove(p)
			await _frames(10)
	BuildPiece.far_shadows = true


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


# The Basic House from 15 m with the sun low, seen from the side (square to the sunlight), so its
# roof's and walls' shadows stretch out across the ground beside it
func _low_sun_shot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var pieces := _place(["basic_house"])
	if sun:
		sun.time_of_day = 0.31
	await _frames(90)
	var light := get_tree().root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var toward_sun := Vector3(light.global_basis.z.x, 0, light.global_basis.z.z).normalized()
	var middle := frame * Vector3(0, 0, 6.0)
	var side := Vector3.UP.cross(toward_sun).normalized()
	# (from the side the shadows fall to the camera's left or right, across the ground in view; turned
	# a little toward the sun, so the lit walls and roof show too (where acne would), from a little
	# above eye height, so the shadow's outline on the ground can be seen; on the far side from the
	# wreck by the test spot)
	var eye := middle + (-side + toward_sun * 0.35).normalized() * 15.0
	eye.y = Plot.ground_at(player, eye.x, eye.z) + 4.0
	_look(eye, middle + Vector3.UP * (frame.origin.y + 2.2 - middle.y))
	await _frames(5)
	await _save("house_shadows_low_sun_15m.png")
	for p in pieces:
		registry.remove(p)
	await _frames(10)


# The six buildings' 12 m view broken down: each category's share of the draw calls and triangles in
# the visible and shadow passes (the frame with it less the frame with it hidden), with the hybrid
# looks and without
func _breakdown() -> void:
	var eye := Vector3(0, 3.0, -12.0)
	var at := Vector3(0, 2.5, SPACING * 0.75)
	for hybrid in [true, false]:
		PieceRegistry.hybrid_walls = hybrid
		var six := _place(TEMPLATES)
		await _frames(90)
		await _aim(eye, at)
		var groups := {"hybrid roofs": [], "hybrid walls": [], "other pieces": []}
		for p in six:
			var shape: String = (p as BuildPiece).shape_name
			if WallBaker.is_roof(shape):
				groups["hybrid roofs"].append(p)
			elif shape in SnapEdges.WALLS or shape in SnapEdges.TRIANGLES:
				groups["hybrid walls"].append(p)
			else:
				groups["other pieces"].append(p)
		var all := await _passes()
		var label := "hybrid looks" if hybrid else "no hybrid looks"
		print("ROOFPASS | breakdown, six buildings 12 m, %s | whole frame: visible %d draws %d triangles, shadows %d draws %d triangles" % [label, all[0], all[1], all[2], all[3]])
		for g in groups:
			_show(groups[g], false)
			var without := await _passes()
			_show(groups[g], true)
			# (what a group is looking like from here: how many of its pieces show their close-up look)
			var near := 0
			for p in groups[g]:
				var detail := (p as Node).get_node_or_null("Detail") as GeometryInstance3D
				if detail and (detail.visibility_range_end == 0.0 or player.camera.global_position.distance_to((p as Node3D).global_transform * detail.get_aabb().get_center()) < detail.visibility_range_end):
					near += 1
			print("ROOFPASS | breakdown, %s | %s (%d pieces, %d in their close-up look) | visible %d draws %d triangles, shadows %d draws %d triangles" % [label, g, groups[g].size(), near, all[0] - without[0], all[1] - without[1], all[2] - without[2], all[3] - without[3]])
		for p in six:
			registry.remove(p)
		await _frames(10)
	PieceRegistry.hybrid_walls = true


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


func _show(list: Array, on: bool) -> void:
	for n in list:
		(n as Node3D).visible = on


# The switch measured at every distance from both spots (as _switch_distance, without choosing or
# saving anything; roof_range is put back as it was), checking the camera stays put
func _switch_measure() -> void:
	var keep := BuildPiece.roof_range
	var piece: PieceBuildable = load("res://buildables/structure/roof.tres")
	var at := frame * Transform3D(Basis.IDENTITY, Vector3(0, ROOF_HEIGHT, 0))
	var roof: BuildPiece = null
	for d in SWITCHES:
		if roof:
			registry.remove(roof)
		BuildPiece.roof_range = d
		roof = registry.spawn(piece, at, {})
		await _frames(10)
		for view in ["ground", "along"]:
			await _roof_view(roof, view, d - 0.5)
			var rect := _roof_rect(roof)
			var placed: Vector3 = player.camera.global_position
			var near := await _grab()
			var near_shimmer := await _shimmer(rect)
			roof.show_simple_look(true)
			var far := await _grab()
			var far_shimmer := await _shimmer(rect)
			roof.show_simple_look(false)
			var drift: float = player.camera.global_position.distance_to(placed)
			var change := _difference(near, far, rect)
			if not scratch.is_empty():
				var crop := Rect2i(rect).grow(40).intersection(Rect2i(Vector2i.ZERO, near.get_size()))
				near.get_region(crop).save_png(scratch.path_join("check_%s_%dm_near.png" % [view, int(d)]))
				far.get_region(crop).save_png(scratch.path_join("check_%s_%dm_far.png" % [view, int(d)]))
			print("ROOFPASS | check switch at %d m, %s | shakes vs far look just inside it: %.2f%% average change (%.2f%% of pixels change by over 8%%) | shimmer: shakes %.3f%%, far %.3f%% | dark pixels: shakes %s, far %s | camera moved %.4f m while measuring" % [int(d), view, change[0], change[1], near_shimmer, far_shimmer, _dark(near, rect), _dark(far, rect), drift])
	registry.remove(roof)
	BuildPiece.roof_range = keep
	await _frames(5)


# ---- 1. The bakes ----

func _bake_all() -> void:
	var baker: WallBaker = registry.baker
	var start := Time.get_ticks_msec()
	baker.prepare_all()
	for i in 30000:
		if baker.is_idle():
			break
		await get_tree().process_frame
	var tiles := 0
	for shape in WallBaker.ROOFS:
		tiles += (baker._roof_layout(shape)["tiles"] as Array).size()
	print("ROOFPASS | roof bakes: %d shapes × %d variants = %d bakes (%d facet tiles in a set of shapes, from above and below); roof textures %.1f MB, all bakes %.1f MB; %d variants baked now, %d read from the cache, in %.1f s" % [WallBaker.ROOFS.size(), PieceRegistry.DETAIL_VARIANTS, WallBaker.ROOFS.size() * PieceRegistry.DETAIL_VARIANTS, tiles, baker.memory_of(WallBaker.ROOFS) / 1048576.0, baker.memory / 1048576.0, baker.made, baker.loaded, (Time.get_ticks_msec() - start) / 1000.0])
	for shape in WallBaker.ROOFS:
		var detail := PieceRegistry._triangles(registry.detail_mesh(shape, 0)["mesh"])
		var far := PieceRegistry._triangles(baker.far_mesh(shape, 0))
		var trim: Mesh = registry.roof_parts(shape, 0)["trim"]
		print("ROOFPASS | %s: close-up %d triangles; far look %d (of them trim %d), one draw" % [shape, detail, far, PieceRegistry._triangles(trim) if trim else 0])


# ---- 2. The switch distance ----

func _switch_distance() -> void:
	var piece: PieceBuildable = load("res://buildables/structure/roof.tres")
	var at := frame * Transform3D(Basis.IDENTITY, Vector3(0, ROOF_HEIGHT, 0))
	var results := {}
	var roof: BuildPiece = null
	for d in SWITCHES:
		if roof:
			registry.remove(roof)
		BuildPiece.roof_range = d
		roof = registry.spawn(piece, at, {})
		await _frames(10)
		var r := []
		for view in ["ground", "along"]:
			await _roof_view(roof, view, d - 0.5)
			var rect := _roof_rect(roof)
			var near := await _grab()
			var near_shimmer := await _shimmer(rect)
			roof.show_simple_look(true)
			var far := await _grab()
			var far_shimmer := await _shimmer(rect)
			roof.show_simple_look(false)
			var change := _difference(near, far, rect)
			r.append([change[0], near_shimmer, far_shimmer])
			if not scratch.is_empty():
				var crop := Rect2i(rect).grow(40).intersection(Rect2i(Vector2i.ZERO, near.get_size()))
				near.get_region(crop).save_png(scratch.path_join("roof_%s_%dm_near.png" % [view, int(d)]))
				far.get_region(crop).save_png(scratch.path_join("roof_%s_%dm_far.png" % [view, int(d)]))
			print("ROOFPASS | switch at %d m, %s | shakes vs far look just inside it: %.2f%% average change (%.2f%% of pixels change by over 8%%) | shimmer: shakes %.3f%%, far %.3f%% | dark pixels: shakes %s, far %s | roof %d × %d px" % [int(d), view, change[0], change[1], near_shimmer, far_shimmer, _dark(near, rect), _dark(far, rect), int(rect.size.x), int(rect.size.y)])
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
		if ok and total < best - 0.1:
			best = total
			chosen = d
	if chosen == 0.0:
		chosen = SWITCHES[0]
	print("ROOFPASS | chosen roof switch distance: %d m" % int(chosen))
	registry.remove(roof)
	BuildPiece.roof_range = chosen
	roof = registry.spawn(piece, at, {})
	await _frames(10)
	for view in ["ground", "along"]:
		for side in [[-1.0, "inside"], [1.0, "outside"]]:
			await _roof_view(roof, view, chosen + side[0])
			await _save("roof_%s_%dm_%s_%dm.png" % [view, int(chosen), side[1], int(chosen + side[0])])
	registry.remove(roof)
	await _frames(5)


# The camera `d` m from the roof's middle: from the ground (eye height, GROUND_ANGLE round from
# straight down the slope), or from a raised spot down the slope looking up along it, 0.6 m over the
# roof's middle
func _roof_view(roof: BuildPiece, view: String, d: float) -> void:
	var middle := roof.global_transform * Vector3(0, 0.6, 1.0)
	var down := -roof.global_basis.z
	if view == "ground":
		var out := down.rotated(Vector3.UP, deg_to_rad(GROUND_ANGLE))
		var eye := middle + out * d
		eye.y = Plot.ground_at(player, eye.x, eye.z) + 1.7
		_look(eye, middle)
	else:
		var eye := middle + down * d
		eye.y = middle.y + 0.6
		_look(eye, middle)
	await _frames(5)


func _roof_rect(roof: BuildPiece) -> Rect2:
	var points := []
	for p in [Vector3(-0.85, 0.1, 0.2), Vector3(0.85, 0.1, 0.2), Vector3(-0.85, 1.1, 1.8), Vector3(0.85, 1.1, 1.8)]:
		points.append(roof.global_transform * p)
	return _screen_rect(points, 0.1)


# ---- 3. The Basic House ----

func _house_shots() -> void:
	var house := _place(["basic_house"])
	await _frames(60)
	for d in [30.0, 15.0]:
		await _aim(Vector3(0, 1.7, 6.0 - 3.0 - d), Vector3(0, 2.6, 6.0))
		await _save("house_%dm.png" % int(d))
	for piece in house:
		registry.remove(piece)
	await _frames(10)


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
	print("ROOFPASS | saved %s" % file)


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
	_hide_overlays()
	for f in get_tree().root.find_children("*", "Node3D", true, false):
		if f.get_script() and (f.get_script() as Script).resource_path.ends_with("world/foliage.gd"):
			(f as Node3D).visible = false


# ---- Drawing cost ----

# The Basic House alone, then the six buildings, each against the same views empty
func _costs(label: String) -> void:
	await _frames(120)
	var house_eyes := []
	for d in HOUSE_VIEWS:
		house_eyes.append([Vector3(0, 1.7, 6.0 - 3.0 - d), Vector3(0, 2.6, 6.0), "Basic House %d m" % int(d)])
	var group_eyes := []
	for d in GROUP_VIEWS:
		group_eyes.append([Vector3(0, 6.0 if d > 20.0 else 3.0, -d), Vector3(0, 2.5, SPACING * 0.75), "six buildings %d m" % int(d)])
	var empty := {}
	for eye in house_eyes + group_eyes:
		await _aim(eye[0], eye[1])
		empty[eye[2]] = await _info()
	var house := _place(["basic_house"])
	await _frames(90)
	for eye in house_eyes:
		await _aim(eye[0], eye[1])
		_report(label, eye[2], await _info(), empty[eye[2]], house.size())
	for piece in house:
		registry.remove(piece)
	await _frames(10)
	var six := _place(TEMPLATES)
	await _frames(90)
	for eye in group_eyes:
		await _aim(eye[0], eye[1])
		_report(label, eye[2], await _info(), empty[eye[2]], six.size())
	for piece in six:
		registry.remove(piece)
	await _frames(10)


func _report(label: String, what: String, with: Array, without: Array, pieces: int) -> void:
	print("ROOFPASS | %s | %s | %d draw calls, %d triangles (frame %d, %d less the empty view) | video memory %.0f MB | %d pieces" % [label, what, with[0] - without[0], with[1] - without[1], with[0], with[1], with[2], pieces])


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


# [draw calls, triangles, video memory MB], settled over a few frames
func _info() -> Array:
	for i in 20:
		await get_tree().process_frame
	for k in 4:
		await RenderingServer.frame_post_draw
	return [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]


# ---- The camera and the spot ----

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


# Dry ground over the six buildings' grid and out to 34 m in front of it (the same spot as
# tests/look_pass.gd), the frame turned so the camera on -Z has the sun behind it
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
