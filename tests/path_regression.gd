extends Node
## The painted dirt path test (the hammer's Paths tab, Dirt Path tool):
##
##     godot --path . res://tests/path_regression.tscn --resolution 1600x900 --quit-after 9000
##
## (add `-- --topdown=<file.png>` to also keep the view from straight above)
##
## It opens the world (a fresh one: nothing is loaded or saved), finds open, flat grass a few
## meters beside one of the editor's Terrain Paths, and paints a 10 m path through it with the
## real tool the way a player does: the camera turned along the line and real mouse events sent
## through the input system (left button held to paint, the wheel for width, the middle button
## held to erase). It checks the grass and ferns are gone from the path and the dirt shows, erases
## the second half (grass grows back there), then saves the paths and loads them again. Every
## frame while dragging is timed, with the lag spike logger on: none may take over 33 ms.
## Run with a window (as above) it also saves docs/reference/ours/paths.png: the painted path
## beside the editor's path. Headless, the checks that need a picture are skipped.
## Each check prints "PATHTEST PASS" or "PATHTEST FAIL"; the exit code is the number of failures.

const WORLD := "res://world/world.tscn"
const TOOL := "res://buildables/paths/dirt_path.tres"
const SHOT := "res://docs/reference/ours/paths.png"
const LENGTH := 10.0
## How far the painted path runs from the editor path's middle (m)
const BESIDE := 5.5
## The slowest a frame may be while dragging (ms)
const MAX_FRAME_MS := 33.0

var player: Node
var bp: BuildPlacer
var painter: PathPainter
var valley: Node
var foliage: Node
var paths: PaintedPaths
# The line painted (A to B, on the ground), along it and across it (flat, unit)
var A := Vector3.ZERO
var B := Vector3.ZERO
var along := Vector3.ZERO
var across := Vector3.ZERO
# A point on the editor path beside it
var trail_point := Vector3.ZERO
var passed := 0
var failed := 0
var windowed := false
# Frame times while dragging (ms), and spikes the logger caught then
var _times: Array[float] = []
var _timing := false
var _last_usec := 0


func _ready() -> void:
	windowed = DisplayServer.get_name() != "headless"
	_run.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _timing and _last_usec > 0:
		_times.append((now - _last_usec) / 1000.0)
	_last_usec = now


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
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.45
	player.set_physics_process(false)
	player._on_held_changed("Hammer")
	bp = player._placer
	painter = bp._paths
	valley = get_tree().get_first_node_in_group("valley")
	foliage = valley.get_node("Foliage")
	paths = valley.painted_paths
	_check("the valley has painted paths, in the save", paths != null and paths.is_in_group("saveable") and paths.save_key() == "painted_paths", "")
	if not _find_spot():
		_check("found open flat grass beside an editor path", false, "none; rejected: %s" % _rejected)
		_finish()
		return
	print("PATHTEST line from %s to %s, editor path at %s" % [A, B, trail_point])

	# Stand to the side of the line, and let the grass grow there
	await _look_at_line(0.5)
	await _wait_for_grass()
	var before_grass := _grass_on(0.0, LENGTH)
	print("PATHTEST grass across the line before (0.5 m strips, -3 m to 3 m): ", _grass_across())
	_check("grass grows where the path will go", before_grass > 0, "%d clumps on the line" % before_grass)
	var before_profile: Array = await _ground_profile() if windowed else []

	# The tool, from the build menu's Paths tab
	var menu = player.build_menu
	var tabs: Array = menu.get_script().get_script_constant_map()["TABS"]
	_check("the build menu has a Paths tab", tabs.has("Paths"), str(tabs))
	var tool: PathTool = load(TOOL)
	var listed := false
	for b in menu.all_buildables():
		if b.resource_path == TOOL and b.section == "Paths":
			listed = true
	_check("the Dirt Path tool is in the Paths tab", listed, "")
	_check("the Dirt Path is free", tool.can_afford({}) and tool.cost_text() == "Free", tool.cost_text())
	bp.begin(tool)
	await _frames(2)
	var keys: Array = []
	var labels: Array = []
	for c in bp.hud_state()["controls"]:
		labels.append(c[0])
		keys.append(c[1])
	_check("controls row: Paint [LMB] · Width [Wheel] · Erase [MMB] · Cancel [RMB]", labels == ["Paint", "Width", "Erase", "Cancel"] and keys == ["LMB", "Wheel", "MMB", "RMB"], "%s %s" % [labels, keys])
	_check("it starts 1.5 m wide", is_equal_approx(painter._width, 1.5), "%.2f" % painter._width)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(2)
	_wheel(3)
	var wider := painter._width
	_wheel(-12)
	var narrowest := painter._width
	_wheel(20)
	var widest := painter._width
	_wheel(-6)
	_check("the wheel changes the width, 1 to 3 m", is_equal_approx(wider, 2.25) and is_equal_approx(narrowest, 1.0) and is_equal_approx(widest, 3.0) and is_equal_approx(painter._width, 1.5), "up 3: %.2f, down: %.2f, up: %.2f, back: %.2f" % [wider, narrowest, widest, painter._width])
	var heights := _heights()

	# Paint the 10 m: hold the left button and sweep the crosshair along the line
	# (the camera has just jumped here: let that settle, then time from the press to after the release)
	SpikeLog.enabled = true
	await _look_at_line(0.0)
	await _frames(40)
	_start_timing()
	_button(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check("holding the left button paints", painter._painting, "")
	await _sweep(0.0, 1.0)
	_button(MOUSE_BUTTON_LEFT, false)
	await _frames(12)
	_check_frames("painting")
	var middle_amounts: Array = []
	for t in [0.05, 0.25, 0.5, 0.75, 0.95]:
		middle_amounts.append(snappedf(_amount(t, 0.0), 0.01))
	_check("path all along the 10 m", middle_amounts.all(func(a): return a > 0.9), str(middle_amounts))
	var edge := _amount(0.5, 0.75)
	var outside := _amount(0.5, 1.6)
	_check("a soft edge about 1.5 m across", edge > 0.2 and edge < 0.95 and outside < 0.01, "at 0.75 m out: %.2f, at 1.6 m out: %.2f" % [edge, outside])
	_check("the ground's height hasn't changed", _heights() == heights, "")
	var grass_after := _grass_on(0.0, LENGTH)
	print("PATHTEST grass across the line after (0.5 m strips, -3 m to 3 m): ", _grass_across())
	var ferns_after := _ferns_on(0.0, LENGTH)
	_check("no grass or ferns left on the path", grass_after == 0 and ferns_after == 0, "%d grass, %d ferns (were %d grass)" % [grass_after, ferns_after, before_grass])
	var info: Vector4 = valley._ground.get_shader_parameter("path_info")
	_check("the ground shader is drawing painted path", info.w == 1.0 and valley._ground.get_shader_parameter("path_tiles") != null, str(info))
	if windowed:
		# (a copy of the view from above, if asked for: -- --topdown=<file>)
		var save_to := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--topdown="):
				save_to = arg.trim_prefix("--topdown=")
		var after_profile: Array = await _ground_profile(save_to)
		var redder_middle := true
		for k in [5, 6, 7]:
			if after_profile[k] - before_profile[k] < 0.03:
				redder_middle = false
		var same_outside: bool = absf(after_profile[0] - before_profile[0]) < 0.03 and absf(after_profile[12] - before_profile[12]) < 0.03
		_check("the dirt shows on the path, from above (red minus green across it, -3 m to 3 m)", redder_middle and same_outside, "before %s, after %s" % [before_profile, after_profile])
		await _screenshot()
	# Grass grown afresh there (a patch worked out again from scratch) still keeps off it
	foliage.regrow_plants_in(Rect2(A.x, A.z, 0, 0).expand(Vector2(B.x, B.z)).grow(4.0))
	await _wait_for_grass()
	_check("grass grown again there still keeps off the path", _grass_on(0.0, LENGTH) == 0, "%d" % _grass_on(0.0, LENGTH))

	# Erase the second half: the middle button held, swept along it
	await _look_at_line(0.5)
	await _frames(40)
	_start_timing()
	_button(MOUSE_BUTTON_MIDDLE, true)
	await _frames(2)
	_check("holding the middle button erases", painter._erasing(), "")
	await _sweep(0.5, 1.0)
	_button(MOUSE_BUTTON_MIDDLE, false)
	await _frames(12)
	_check_frames("erasing")
	_check("the second half is gone, the first half stays", _amount(0.8, 0.0) < 0.01 and _amount(0.95, 0.0) < 0.01 and _amount(0.3, 0.0) > 0.9, "at 3 m: %.2f, 8 m: %.2f, 9.5 m: %.2f" % [_amount(0.3, 0.0), _amount(0.8, 0.0), _amount(0.95, 0.0)])
	await _wait_for_grass()
	var back := _grass_on(0.6 * LENGTH, LENGTH)
	_check("grass grows back where it was erased, not on the path left", back > 0 and _grass_on(0.0, 0.4 * LENGTH) == 0, "%d clumps back on the erased half, %d on the rest" % [back, _grass_on(0.0, 0.4 * LENGTH)])

	# Save and load again: the same path, the grass still off it
	var samples: Array = []
	for t in [0.1, 0.3, 0.45, 0.55, 0.7, 0.9]:
		for off in [0.0, 0.6, 1.0]:
			samples.append(_amount(t, off))
	var text := JSON.stringify({"systems": {paths.save_key(): paths.save_data()}})
	var size_kb := text.length() / 1024.0
	paths.clear()
	await _frames(2)
	_check("cleared before loading", _amount(0.3, 0.0) == 0.0 and not paths.has_paths(), "")
	paths.load_data((JSON.parse_string(text) as Dictionary)["systems"][paths.save_key()])
	await _frames(2)
	var same := true
	var i := 0
	for t in [0.1, 0.3, 0.45, 0.55, 0.7, 0.9]:
		for off in [0.0, 0.6, 1.0]:
			if not is_equal_approx(_amount(t, off), samples[i]):
				same = false
			i += 1
	_check("saved and loaded, the path is the same", same, "save text %.1f KB" % size_kb)
	info = valley._ground.get_shader_parameter("path_info")
	_check("loaded, the ground shader draws it again", info.w == 1.0, str(info))
	await _wait_for_grass()
	_check("loaded, grass still keeps off the path", _grass_on(0.0, 0.4 * LENGTH) == 0 and _grass_on(0.6 * LENGTH, LENGTH) > 0, "%d on the path, %d on the erased half" % [_grass_on(0.0, 0.4 * LENGTH), _grass_on(0.6 * LENGTH, LENGTH)])

	# Right-click puts the tool away; what's painted stays
	_button(MOUSE_BUTTON_RIGHT, true)
	_button(MOUSE_BUTTON_RIGHT, false)
	await _frames(2)
	_check("right-click cancels, the path stays", not painter.is_active() and not bp.is_placing() and _amount(0.3, 0.0) > 0.9, "")
	_finish()


func _finish() -> void:
	SpikeLog.enabled = false
	if bp:
		bp.cancel()
	print("PATHTEST SUMMARY: %d passed, %d failed" % [passed, failed])
	get_tree().quit(failed)


# ---- Measuring ----

# The painted path at a point: `t` along the line (0 to 1), `off` meters across it
func _amount(t: float, off: float) -> float:
	var p := A.lerp(B, t) + across * off
	return paths.amount_at(p.x, p.z)


# Grass clumps standing within 0.5 m of the line, between `from` and `to` meters along it
func _grass_on(from: float, to: float) -> int:
	return _plants_on("grass", from, to)


func _ferns_on(from: float, to: float) -> int:
	return _plants_on("fern", from, to)


func _plants_on(key: String, from: float, to: float) -> int:
	var count := 0
	for chunk in foliage._patch_buffers:
		var buffer: PackedFloat32Array = foliage._patch_buffers[chunk].get(key, PackedFloat32Array())
		for j in range(0, buffer.size(), 16):
			if buffer[j + 5] == 0.0:
				continue
			var d := Vector3(buffer[j + 3], 0.0, buffer[j + 11]) - Vector3(A.x, 0.0, A.z)
			var s := d.dot(along)
			if s >= from and s <= to and absf(d.dot(across)) < 0.5:
				count += 1
	return count


# Grass clumps along the whole line in 0.5 m strips across it, from 3 m one side to 3 m the other
func _grass_across() -> Array:
	var counts: Array = []
	counts.resize(12)
	counts.fill(0)
	for chunk in foliage._patch_buffers:
		var buffer: PackedFloat32Array = foliage._patch_buffers[chunk].get("grass", PackedFloat32Array())
		for j in range(0, buffer.size(), 16):
			if buffer[j + 5] == 0.0:
				continue
			var d := Vector3(buffer[j + 3], 0.0, buffer[j + 11]) - Vector3(A.x, 0.0, A.z)
			var s := d.dot(along)
			var c := d.dot(across)
			if s >= 0.0 and s <= LENGTH and c >= -3.0 and c < 3.0:
				counts[int((c + 3.0) / 0.5)] += 1
	return counts


# The ground's heights along and around the line
func _heights() -> PackedFloat32Array:
	var found := PackedFloat32Array()
	for t in 11:
		for off in [-2.0, 0.0, 2.0]:
			var p: Vector3 = A.lerp(B, t / 10.0) + across * off
			found.append(valley.get_height(p.x, p.z))
	return found


func _start_timing() -> void:
	SpikeLog.spikes.clear()
	_times.clear()
	_last_usec = 0
	_timing = true


func _check_frames(what: String) -> void:
	_timing = false
	var slowest := 0.0
	for ms in _times:
		slowest = maxf(slowest, ms)
	var spikes := SpikeLog.spikes.size()
	_check("no frame over %d ms while %s" % [int(MAX_FRAME_MS), what], slowest <= MAX_FRAME_MS and spikes == 0, "%d frames, slowest %.1f ms, %d spikes logged" % [_times.size(), slowest, spikes])
	for spike in SpikeLog.spikes:
		print("PATHTEST spike: ", spike)


# Waits until the grass round the line is worked out (and none of it is waiting to be again)
func _wait_for_grass() -> void:
	var chunks := {}
	for t in 11:
		var p := A.lerp(B, t / 10.0)
		for off in [-1.0, 1.0]:
			var q: Vector3 = p + across * off
			chunks[valley.chunk_at(q.x, q.z)] = true
	for k in 900:
		await get_tree().process_frame
		var ready := true
		for chunk in chunks:
			if not foliage._patches.has(chunk) or foliage._pending.has(chunk) or foliage._stale.has(chunk):
				ready = false
		if ready:
			await get_tree().process_frame
			return
	print("PATHTEST note: grass still being worked out after 900 frames")


# How brown the ground looks across the middle of the line, seen from straight above: red minus
# green at 0.5 m steps from 3 m one side to 3 m the other (the grass is cut short where it's
# hidden, so this is the ground). With `save_to`, the view is saved there too.
func _ground_profile(save_to := "") -> Array:
	var middle := A.lerp(B, 0.5)
	player.global_position = middle + Vector3.UP * (9.0 - player._camera_height)
	player.rotation.y = atan2(-along.x, -along.z)
	player.camera.rotation.x = -PI / 2.0 + 0.001
	painter.set_process(false)
	if painter._ring:
		painter._ring.visible = false
	await _frames(4)
	for k in 3:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	painter.set_process(painter.is_active())
	if not save_to.is_empty():
		image.save_png(save_to)
	var profile: Array = []
	# (the camera projects into the viewport's own size, which the picture may be scaled from)
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	for step in range(-6, 7):
		var at: Vector2 = player.camera.unproject_position(middle + across * step * 0.5) * scale
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var px := Vector2i(at) + Vector2i(dx, dy)
				if px.x >= 0 and px.y >= 0 and px.x < image.get_width() and px.y < image.get_height():
					sum += image.get_pixelv(px)
					n += 1
		sum /= maxf(n, 1)
		profile.append(snappedf(sum.r - sum.g, 0.01))
	return profile


# ---- Moving and input ----

# Stands beside the line (away from the editor path) looking at the point `t` along it
func _look_at_line(t: float) -> void:
	var middle := A.lerp(B, 0.5)
	var eye := middle + across * 5.0 + Vector3.UP * 1.7
	_eye(eye, A.lerp(B, t))
	await _frames(3)


func _eye(eye: Vector3, at: Vector3) -> void:
	var to := at - eye
	player.global_position = eye - Vector3.UP * player._camera_height
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


# Sweeps the crosshair along the line from `from` to `to` (0 to 1) at a walking pace, timing
# every frame
func _sweep(from: float, to: float) -> void:
	var middle := A.lerp(B, 0.5)
	var eye := middle + across * 5.0 + Vector3.UP * 1.7
	var steps := int(absf(to - from) * LENGTH / 0.08)
	for k in steps + 1:
		_eye(eye, A.lerp(B, lerpf(from, to, float(k) / steps)))
		await get_tree().process_frame


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button(button: MouseButton, pressed: bool) -> void:
	var centre := get_viewport().get_visible_rect().size / 2.0
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = centre
	event.global_position = centre
	_send(event)


func _wheel(notches: int) -> void:
	for i in absi(notches):
		_button(MOUSE_BUTTON_WHEEL_UP if notches > 0 else MOUSE_BUTTON_WHEEL_DOWN, true)
		_button(MOUSE_BUTTON_WHEEL_UP if notches > 0 else MOUSE_BUTTON_WHEEL_DOWN, false)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("PATHTEST %s %s (%s)" % ["PASS" if ok else "FAIL", what, detail])


# ---- Finding the spot ----

# A 10 m line of open, flat, dry grass running BESIDE meters from one of the editor's Terrain
# Paths, alongside it, with nothing standing on it and no trail under it
func _find_spot() -> bool:
	var water: float = valley.water_height()
	var start: Vector3 = player.global_position
	var candidates: Array = []
	for trail in get_tree().root.find_children("*", "Node3D", true, false):
		if trail.get_script() == null or not str(trail.get_script().resource_path).ends_with("terrain_path.gd") or trail.curve == null:
			continue
		var points: PackedVector3Array = trail.curve.get_baked_points()
		for i in range(8, points.size() - 8, 3):
			var p: Vector3 = trail.to_global(points[i])
			var dir: Vector3 = trail.to_global(points[i + 6]) - trail.to_global(points[i - 6])
			dir.y = 0.0
			if dir.length() < 1.0:
				continue
			candidates.append([p, dir.normalized(), p.distance_to(start)])
	candidates.sort_custom(func(a, b): return a[2] < b[2])
	for c in candidates:
		var p: Vector3 = c[0]
		var t: Vector3 = c[1]
		var n := t.cross(Vector3.UP).normalized()
		for side in [1.0, -1.0]:
			var mid: Vector3 = p + n * side * BESIDE
			if _line_ok(mid, t, n * side, water):
				A = mid - t * LENGTH * 0.5
				B = mid + t * LENGTH * 0.5
				A.y = valley.get_height(A.x, A.z)
				B.y = valley.get_height(B.x, B.z)
				along = t
				across = n * side
				trail_point = Vector3(p.x, valley.get_height(p.x, p.z), p.z)
				return true
	return false


var _rejected := {}


func _line_ok(mid: Vector3, t: Vector3, out: Vector3, water: float) -> bool:
	var base: float = valley.get_height(mid.x, mid.z)
	if base < water + 1.0:
		return _reject("water")
	for k in 11:
		for off in [-1.0, 0.0, 1.0, 3.0, 5.0]:
			var q: Vector3 = mid + t * (k - 5) + out * off
			var h: float = valley.get_height(q.x, q.z)
			if absf(h - base) > 1.5:
				return _reject("uneven")
			if valley.get_normal(q.x, q.z).y < 0.9:
				return _reject("steep")
			if valley.trail_amount(q.x, q.z) > 0.05:
				return _reject("trail")
			var query := PhysicsRayQueryParameters3D.create(Vector3(q.x, h + 30.0, q.z), Vector3(q.x, h - 5.0, q.z))
			var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or not (hit["collider"] as Node).is_in_group("terrain_ground"):
				return _reject("something standing")
	return true


func _reject(why: String) -> bool:
	_rejected[why] = int(_rejected.get(why, 0)) + 1
	return false


# The painted path beside the editor's path, from behind the start, a little above
func _screenshot() -> void:
	# (from the painted path's far side, so both paths are left of the hammer in your hand)
	var middle := A.lerp(B, 0.5)
	var eye := A - along * 6.0 + across * 2.0 + Vector3.UP * 5.5
	_eye(eye, middle - across * 1.5)
	# (the brush ring left out of the picture)
	painter.set_process(false)
	painter._ring.visible = false
	await _frames(4)
	for k in 3:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(SHOT))
	_check("screenshot saved", err == OK, SHOT)
	painter.set_process(true)
