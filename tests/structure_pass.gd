extends Node
## The look pass for stairs, pillars, poles and beams (see PieceRegistry.LEAN and SINGLE, and
## DESIGN.md's look pass inventory). Each run ends itself:
##
##     godot --headless --path . res://tests/structure_pass.tscn --quit-after 20000 -- report
##     godot --path . res://tests/structure_pass.tscn --resolution 1920x1080 --quit-after 60000 -- <mode>
##
## Modes:
##   report         (headless) each shape's looks: triangles close-up, far (lean) and the old middle
##                  look and plain box, and how far the far look's box is from the close-up look's
##                  (its outline: ends and sides must not move at the switch)
##   switch         stairs (all four) and pillars (wood and stone, all heights) from three views, at
##                  each of SWITCHES, just inside it: the close-up look against the lean far look in the
##                  same view (how much the switch shows) and how much each shimmers as the camera
##                  sways a few millimetres. Views: standing (1.7 m over the ground), raised (6 m up,
##                  looking down across them: stairs as seen walking up a flight beside them) and below
##                  (the flights raised 2 m, seen from 1 m over the ground under and behind them: their
##                  stringers and tread undersides, as from inside a house). 15 m (the walls'
##                  distance) is measured twice; the noise is twice the gap between those two totals
##                  (at least NOISE_FLOOR). It picks the distance where the switch shows least among
##                  those whose close-up look shimmers no more than twice the far look's (plus 0.02) in
##                  every view, and 15 m whenever 15 m is within the noise of that.
##   costs          the drawing cost, before (lean_structure off: the three looks) and after: the six
##                  template buildings from 12 m, a porch village (twelve porches of pillars, beams,
##                  poles and stairs) from 12 m, and the Basic House from 30 m: visible and shadow
##                  draws and triangles, and the frame time (average, GPU, CPU) with V-Sync off
##   load <cold|warm> <before|after>   seconds to load the user's house (LOAD_SAVE) through Load Game
##                  and lift the loading cover (cold: the bake cache cleared first), with lean_structure
##                  off (before) or on
##   shots          daylight pictures 1 m either side of the switch (BuildPiece.lean_range): the four
##                  flights and a pillar-and-beam porch from standing height, and the flights from the
##                  raised spot, into SHOTS
## Prints "STRUCTPASS" lines, then quits itself.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/look_pass/structure"
const SWITCHES := [10.0, 15.0, 20.0, 25.0]
const VIEWS := ["standing", "raised", "below"]
const NOISE_FLOOR := 0.15
const TEMPLATES := ["basic_house", "forager_s_hut", "storehouse", "woodcutter_s_hut", "workshop", "basic_house"]
const SPACING := 16.0
const DAYLIGHT := 0.42
const FLIGHTS := ["stairs", "half_stairs", "stairs_tall", "half_stairs_tall"]
## The save the load times are measured with (the user's house)
const LOAD_SAVE := "res://tests/fixtures/crowded_corners/house_save.json"

var player: Node
var registry: PieceRegistry
var sun: Node
var frame := Transform3D.IDENTITY


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if not args.is_empty() else "report"
	if mode == "report":
		_report()
		get_tree().quit()
		return
	if mode == "load":
		PieceRegistry.lean_structure = not args.has("before")
		await _load(args.has("cold"))
		get_tree().quit()
		return
	await _open_world()
	if not _find_spot():
		print("STRUCTPASS | no dry open ground found")
		get_tree().quit(1)
		return
	_hide_pickups()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait_bakes()
	match mode:
		"costs":
			await _costs()
		"switch":
			await _switch_distance()
		"shots":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
			await _shots()
	get_tree().quit()


# ---- What each look is made of ----

func _report() -> void:
	var reg := PieceRegistry.new()
	for shape in PieceRegistry.LEAN + PieceRegistry.SINGLE:
		var close_up: Mesh = reg.detail_mesh(shape, 0)["mesh"]
		var mid: Mesh = PieceDetail.build(shape, hash(shape), true).get("mesh")
		var plain: Mesh = reg.shape_of(shape)["mesh"]
		if shape in PieceRegistry.SINGLE:
			print("STRUCTPASS | %s: single look, %d triangles at every distance, its own shadow (was: close-up %d, middle %d, plain box %d, and a shadow copy)" % [shape, PieceRegistry._triangles(close_up), PieceRegistry._triangles(close_up), PieceRegistry._triangles(mid), PieceRegistry._triangles(plain)])
			continue
		var worst := 0.0
		for v in PieceRegistry.DETAIL_VARIANTS:
			var a := reg.detail_mesh(shape, v)["mesh"].get_aabb() as AABB
			var b := reg.lean_mesh(shape, v).get_aabb()
			worst = maxf(worst, maxf((a.position - b.position).abs()[(a.position - b.position).abs().max_axis_index()], (a.end - b.end).abs()[(a.end - b.end).abs().max_axis_index()]))
		var far := reg.lean_mesh(shape, 0)
		print("STRUCTPASS | %s: close-up %d triangles, lean far look %d (old middle look %d, plain box %d); far look's box off the close-up's by %.1f mm at most (4 variants)" % [shape, PieceRegistry._triangles(close_up), PieceRegistry._triangles(far), PieceRegistry._triangles(mid), PieceRegistry._triangles(plain), worst * 1000.0])
	reg.free()


# ---- Load times ----

func _load(cold: bool) -> void:
	if cold:
		var dir := DirAccess.open(WallBaker.CACHE_DIR)
		var cleared := 0
		if dir:
			for file in dir.get_files():
				dir.remove(file)
				cleared += 1
		print("STRUCTPASS | cold start: %d cached bakes cleared" % cleared)
	# (the user's house, 790 pieces, through Load Game: a new world has no pieces to dress. Loading
	# replaces the current scene, so a stand-in is made current first, as tests/startup_test.gd's title
	# screen is, and this test stays.)
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	var start := Time.get_ticks_msec()
	SaveGame.load_save(ProjectSettings.globalize_path(LOAD_SAVE))
	for i in 6000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player and SaveGame.get("_in_world"):
			break
	SaveGame.set("_test_run", true)
	registry = player._placer.registry
	var opened := Time.get_ticks_msec()
	for i in 60000:
		await get_tree().process_frame
		var covered := not get_tree().root.find_children("*", "ShaderWarmup", true, false).is_empty()
		if not covered and registry.baker.is_idle() and i > 10:
			break
	var ready := Time.get_ticks_msec()
	print("STRUCTPASS | %s launch, %s: world open in %.1f s, loading cover and bakes done %.1f s later (%.1f s in all); %d variants baked, %d read from the cache; bakes %.1f MB" % ["cold" if cold else "warm", "after (lean looks)" if PieceRegistry.lean_structure else "before (three looks)", (opened - start) / 1000.0, (ready - opened) / 1000.0, (ready - start) / 1000.0, registry.baker.made, registry.baker.loaded, registry.baker.memory / 1048576.0])


func _wait_bakes() -> void:
	registry.baker.prepare_all()
	for i in 30000:
		if registry.baker.is_idle():
			break
		await get_tree().process_frame


# ---- The switch distance ----

func _switch_distance() -> void:
	var keep: float = BuildPiece.lean_range
	var totals := {}
	var ok_at := {}
	var runs: Array = SWITCHES + [15.0]
	var fifteen := []
	for d in runs:
		BuildPiece.lean_range = d
		var total := 0.0
		var ok := true
		for view in VIEWS:
			var built := await _build(view, d - 0.5)
			var rect := _screen_rect(built[1], 0.04)
			var near := await _grab()
			var near_shimmer := await _shimmer(rect)
			for p in built[0]:
				(p as BuildPiece).show_simple_look(true)
			var far := await _grab()
			var far_shimmer := await _shimmer(rect)
			var change := _difference(near, far, rect)
			total += change[0]
			if near_shimmer > far_shimmer * 2.0 + 0.02:
				ok = false
			print("STRUCTPASS | switch at %d m, %s | close-up vs far look just inside it: %.2f%% average change (%.2f%% of pixels change by over 8%%) | shimmer: close-up %.3f%%, far %.3f%% | region %d × %d px" % [int(d), view, change[0], change[1], near_shimmer, far_shimmer, int(rect.size.x), int(rect.size.y)])
			await _clear()
		if d == 15.0:
			fifteen.append(total)
		if not totals.has(d):
			totals[d] = total
			ok_at[d] = ok
		print("STRUCTPASS | at %d m: total change %.2f%%, shimmer within twice the far look's in every view: %s" % [int(d), total, ok])
	var noise := maxf(NOISE_FLOOR, 2.0 * absf(fifteen[0] - fifteen[1]) if fifteen.size() > 1 else NOISE_FLOOR)
	var best := 0.0
	for d in SWITCHES:
		if ok_at[d] and (best == 0.0 or totals[d] < totals[best]):
			best = d
	var chosen := best
	if best != 0.0 and ok_at[15.0] and totals[15.0] - totals[best] <= noise:
		chosen = 15.0
	if chosen == 0.0:
		chosen = keep
	print("STRUCTPASS | 15 m measured twice: %.2f%% and %.2f%%, noise %.2f%% | least change at %d m (%.2f%%) | chosen: %d m" % [fifteen[0], fifteen[1] if fifteen.size() > 1 else -1.0, noise, int(best), totals.get(best, -1.0), int(chosen)])
	BuildPiece.lean_range = keep


# What a view looks at, the eye `at` m from the measured pieces: [pieces measured, points round them]
func _build(view: String, at: float) -> Array:
	var measured := []
	var points := []
	var y := _level(-6.0, 6.0, -3.0, 3.0)
	match view:
		"standing", "raised":
			# The four flights side by side (each 2 m wide) and a row of pillars beside them
			measured += _flights(y, 0.0)
			measured += _pillars(y, 3.0)
			await _frames(10)
			var target := frame * Vector3(0, y + 1.0, 0)
			if view == "standing":
				var eye := frame * Vector3(0.5, 0, -at)
				eye.y = Plot.ground_at(player, eye.x, eye.z) + 1.7
				_look(eye, target)
			else:
				var flat := sqrt(maxf(at * at - 36.0, 1.0))
				_look(frame * Vector3(0.3, y + 6.0, -flat), frame * Vector3(0, y, 0))
			for x in [-4.2, 4.2]:
				for p in [Vector3(x, y, -2.0), Vector3(x, y + 2.6, 2.0), Vector3(x, y + 2.6, -2.0), Vector3(x, y, 3.4)]:
					points.append(frame * p)
		"below":
			# The four flights raised 2 m (as hung from a raised floor), seen from under and behind
			measured += _flights(y + 2.0, 0.0)
			await _frames(10)
			var eye := frame * Vector3(0.3, 0, -at)
			eye.y = Plot.ground_at(player, eye.x, eye.z) + 1.0
			_look(eye, frame * Vector3(0, y + 2.5, 0))
			for x in [-4.2, 4.2]:
				for p in [Vector3(x, y + 2.0, -2.0), Vector3(x, y + 4.6, 2.0)]:
					points.append(frame * p)
	await _frames(5)
	return [measured, points]


# The four flights side by side across X (each 2 m wide), their feet at height y, starting at z0 - 2
func _flights(y: float, z0: float) -> Array:
	var out := []
	for i in FLIGHTS.size():
		var b: PieceBuildable = load("res://buildables/structure/%s.tres" % FLIGHTS[i])
		var length: float = PieceShapes.FLIGHTS[FLIGHTS[i]][1]
		out.append(registry.spawn(b, frame * Transform3D(Basis.IDENTITY, Vector3(-3.0 + i * 2.0, y, z0 - 2.0 + length / 2.0)), {}))
	return out


# A row of every pillar, wood and stone, every height, 1 m apart along X at z
func _pillars(y: float, z: float) -> Array:
	var out := []
	var shapes := PieceRegistry.LEAN.filter(func(s): return s.begins_with("pillar"))
	for i in shapes.size():
		var b: PieceBuildable = load("res://buildables/structure/%s.tres" % shapes[i])
		out.append(registry.spawn(b, frame * Transform3D(Basis.IDENTITY, Vector3(-3.5 + i * 1.0, y, z)), {}))
	return out


# A porch: four 2.5 m pillars (wood in front, stone behind) at the corners of 4 × 2 m, a 4 m beam
# across each long side and a 2 m beam across each end on their tops, a 45° brace, two poles beside
# it and a flight of stairs up to it
func _porch(at: Vector3) -> Array:
	var out := []
	var h: float = PieceShapes.PILLAR_HEIGHTS["pillar_wood"]
	for c in [[-2.0, 0.0, "pillar_wood"], [2.0, 0.0, "pillar_wood"], [-2.0, 2.0, "pillar_stone"], [2.0, 2.0, "pillar_stone"]]:
		out.append(_put("structure/" + c[2], at + Vector3(c[0], 0, c[1]), 0.0))
	for z in [0.0, 2.0]:
		out.append(_put("structure/beam_4", at + Vector3(0, h, z), 0.0))
	for x in [-2.0, 2.0]:
		out.append(_put("structure/beam_2", at + Vector3(x, h, 1.0), 90.0))
	out.append(_put("structure/beam_diag_45", at + Vector3(-1.0, h - 2.0, 0.0), 0.0))
	for x in [3.0, 3.6]:
		out.append(_put("structure/pole_2", at + Vector3(x, 0, -0.6), 0.0))
	out.append(_put("structure/half_stairs_tall", at + Vector3(0, 0, -1.0), 0.0))
	return out


func _put(path: String, at: Vector3, turn: float) -> BuildPiece:
	return registry.spawn(load("res://buildables/%s.tres" % path), frame * Transform3D(Basis(Vector3.UP, deg_to_rad(turn)), at), {})


func _clear() -> void:
	for p in registry.all_pieces():
		registry.remove(p)
	await _frames(5)


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


# ---- The pictures ----

func _shots() -> void:
	var d: float = BuildPiece.lean_range
	for side in [[-1.0, "inside"], [1.0, "outside"]]:
		var at: float = d + side[0]
		for view in ["standing", "raised"]:
			await _build(view, at)
			await _frames(20)
			await _save("flights_%s_%dm_%s_%dm.png" % [view, int(d), side[1], int(at)])
			await _clear()
		var y := _level(-3.0, 3.0, -2.0, 3.0)
		_porch(Vector3(0, y, 0))
		await _frames(10)
		var eye := frame * Vector3(1.0, 0, -at)
		eye.y = Plot.ground_at(player, eye.x, eye.z) + 1.7
		_look(eye, frame * Vector3(0, y + 1.3, 1.0))
		await _frames(20)
		await _save("porch_%dm_%s_%dm.png" % [int(d), side[1], int(at)])
		await _clear()


func _save(file: String) -> void:
	for k in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("STRUCTPASS | saved %s" % file)


# ---- Drawing cost ----

func _costs() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await _frames(120)
	var views := [["six buildings 12 m", "templates", Vector3(0, 3.0, -12.0), Vector3(0, 2.5, SPACING * 0.75)],
		["porch village 12 m", "porches", Vector3(0, 3.0, -12.0), Vector3(0, 1.5, SPACING * 0.75)],
		["Basic House 30 m", "house", Vector3(0, 1.7, 6.0 - 3.0 - 30.0), Vector3(0, 2.6, 6.0)]]
	for view in views:
		for lean in [false, true]:
			PieceRegistry.lean_structure = lean
			var pieces := _place(view[1])
			await _frames(60)
			await _aim(view[2], view[3])
			var passes := await _passes()
			var time := await _frame_time()
			var counts := {}
			for p in pieces:
				var kind := "stairs" if (p as BuildPiece).shape_name.contains("stairs") else ("pillars" if (p as BuildPiece).shape_name.begins_with("pillar") else ("poles and beams" if (p as BuildPiece).shape_name in PieceRegistry.SINGLE else ""))
				if kind != "":
					counts[kind] = int(counts.get(kind, 0)) + 1
				registry.remove(p)
			await _frames(20)
			print("STRUCTPASS | costs, %s | %s | visible %d draws %d triangles | shadows %d draws %d triangles | frame %.2f ms (GPU %.2f ms, CPU %.2f ms) | %d pieces %s" % [view[0], "after (lean looks)" if lean else "before (three looks)", passes[0], passes[1], passes[2], passes[3], time[0], time[1], time[2], pieces.size(), counts])
	PieceRegistry.lean_structure = true


func _place(what: String) -> Array:
	var placed := []
	if what == "porches":
		for i in 12:
			var x := (i % 4 - 1.5) * 8.0
			var z := (i / 4) * 7.0 + 6.0
			var at := Vector3(x, 0, z)
			var q := frame * at
			at.y = Plot.ground_at(player, q.x, q.z) - frame.origin.y
			placed += _porch(at)
		return placed
	var names: Array = TEMPLATES if what == "templates" else ["basic_house"]
	for i in names.size():
		var template := BuildingTemplate.read("res://buildables/templates/%s.json" % names[i])
		var at := frame * Transform3D(Basis.IDENTITY, Vector3((i % 3 - 1) * SPACING if names.size() > 1 else 0.0, 0.0, (i / 3) * SPACING + 6.0))
		for item in template.items:
			if item["buildable"] is PieceBuildable:
				placed.append(registry.spawn(item["buildable"], at * (item["relative"] as Transform3D), {}))
	return placed


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


# ---- Measuring pictures (as tests/floor_pass.gd) ----

func _grab(settle := 8) -> Image:
	await _frames(2)
	for k in settle:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


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


# ---- The world, the camera and the spot (as tests/floor_pass.gd) ----

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
	SaveGame._test_run = true
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


# Dry, fairly level ground over the six buildings' grid and out to 34 m in front of it, the frame
# turned so the camera on -Z has the sun behind it (as tests/floor_pass.gd)
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
