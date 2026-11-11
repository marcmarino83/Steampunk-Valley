extends Node
## Replays a bug snapshot (F9; see BugSnapshot): loads the game it kept, sizes the window as it was,
## puts the camera exactly where the snapshot says and takes the picture again, the same brighter
## way, so what was seen can be seen again and compared before and after a fix:
##
##     godot --path . res://tests/snapshot_replay.tscn -- --snapshot=<snap json> [--out=<png>]
##
## The picture goes to --out, or beside the snapshot as snap_<date-time>_replay.png. It prints the
## crosshair's hit and the piece under it again ("REPLAY describe: ..."), as the snapshot's JSON has
## them, to compare. A test run: nothing is saved. Ends itself (and pass --quit-after as a backup).
##
## With --place=<buildable, like structure/stairs>, it first places that piece the way a player does,
## aimed exactly where the snapshot's crosshair was: the hammer out, the piece begun as the build
## menu does, a real left click (with the free-build cheat on, so no materials are needed), and
## prints where it went and what it hangs from or snapped to ("REPLAY placed: ...").

var _camera_at := Transform3D.IDENTITY
var _hold_camera := false
var _camera: Camera3D


func _ready() -> void:
	# (after everything else each frame, so the camera it holds is the one drawn; and before the
	# placer's own physics step, which reads the camera)
	process_priority = 100000
	process_physics_priority = -100000
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if _hold_camera and is_instance_valid(_camera):
		_camera.global_transform = _camera_at


func _process(_delta: float) -> void:
	# (keeps the camera exactly there, whatever the player's own code would do with it)
	if _hold_camera and is_instance_valid(_camera):
		_camera.global_transform = _camera_at


func _run() -> void:
	var snapshot_path := ""
	var out := ""
	var place := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			snapshot_path = arg.trim_prefix("--snapshot=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--place="):
			place = arg.trim_prefix("--place=")
	var info = JSON.parse_string(FileAccess.get_file_as_string(snapshot_path)) if FileAccess.file_exists(snapshot_path) else null
	if not info is Dictionary:
		print("REPLAY can't read the snapshot %s" % snapshot_path)
		get_tree().quit(1)
		return
	var state := snapshot_path.get_base_dir().path_join(str(info.get("state_file", "")))
	if not FileAccess.file_exists(state):
		state = str(info.get("save_loaded_file", ""))
	if not FileAccess.file_exists(state):
		print("REPLAY no game to load (neither the snapshot's state file nor the save it had loaded)")
		get_tree().quit(1)
		return
	if out.is_empty():
		out = snapshot_path.get_basename() + "_replay.png"
	var size: Array = info.get("window_size", [])
	if size.size() == 2 and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(int(size[0]), int(size[1])))
	print("REPLAY loading %s" % state)
	get_tree().current_scene = null
	SaveGame.load_save(state)
	var player: Node = null
	for i in 4000:
		await get_tree().process_frame
		SaveGame._test_run = true
		player = get_tree().get_first_node_in_group("player")
		if player and i > 200:
			break
	for i in 120:
		await get_tree().process_frame
		SaveGame._test_run = true
	# The player where it stood, then the camera exactly as it was
	player.set_physics_process(false)
	var held: Dictionary = info.get("player", {})
	if held.has("position"):
		player.global_position = _vec(held["position"])
		player.rotation.y = float(held.get("turn", 0.0))
	var cam: Dictionary = info["camera"]
	_camera = player.camera
	var q: Array = cam["quaternion"]
	_camera_at = Transform3D(Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))), _vec(cam["position"]))
	_camera.fov = float(cam.get("fov", _camera.fov))
	_hold_camera = true
	for i in 8:
		await get_tree().physics_frame
	await get_tree().process_frame
	if not place.is_empty():
		await _place(player, place)
	print("REPLAY describe: %s" % JSON.stringify(BugSnapshot.describe(player, _camera)))
	if DisplayServer.get_name() != "headless":
		var image := await BugSnapshot.bright_picture(self)
		image.save_png(out)
		print("REPLAY picture saved: %s" % out)
	get_tree().quit()


# Places a piece as the player would, aimed where the camera is held (see --place)
func _place(player: Node, path: String) -> void:
	DevCheats.freebuild = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player._on_held_changed("Hammer")
	var bp: BuildPlacer = player._placer
	var pp: ValheimPlacer = bp._pieces
	var before := {}
	for piece in bp.registry.all_pieces():
		before[piece] = true
	bp.begin(load("res://buildables/%s.tres" % path))
	for i in 6:
		await get_tree().physics_frame
	var aimed := "target %s, snapped %s, problem \"%s\"" % [("%s %d" % [pp._target.shape_name, pp._target.piece_id]) if pp._target else "none", not pp._pair.is_empty(), pp._problem]
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = get_viewport().get_visible_rect().size / 2.0
		click.global_position = click.position
		Input.parse_input_event(click)
		Input.flush_buffered_events()
	for i in 6:
		await get_tree().physics_frame
	bp.cancel()
	var placed: BuildPiece = null
	for piece in bp.registry.all_pieces():
		if not before.has(piece):
			placed = piece
	if placed == null:
		print("REPLAY placed: nothing (%s)" % aimed)
		return
	var info := BugSnapshot.describe_piece(placed, bp.registry)
	print("REPLAY placed: %s %d at %s, turned %.1f°; aimed: %s; its snap points meet: %s" % [placed.shape_name, placed.piece_id, placed.global_position, placed.global_rotation_degrees.y, aimed, JSON.stringify(info["snapped_to"].map(func(s): return "%s %d (%d corners)" % [s["type"], s["id"], (s["corners_meeting"] as Array).size()]))])
	for i in 4:
		await get_tree().process_frame


static func _vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO
