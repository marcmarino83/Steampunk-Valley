extends Node
## TEST: the game starts and loads a save without an error. Run headless (or in a window, which also
## runs the icon updater, the loading cover and the wall bakes):
##
##     godot --headless --path . res://tests/startup_test.tscn --quit-after 20000
##
## Every error the engine or a script reports while it runs is caught (a Logger) and fails the test
## (it first checks the catcher works, with one error of its own).
##   1. A piece registry outside the world (as the icon updater's is) builds every hybrid wall's looks.
##   2. The real title screen (the project's main scene) opens and runs for a moment.
##   3. A save (FIXTURE) is loaded through SaveGame, as Load Game does: the world opens, its pieces
##      come back, and (in a window) the loading cover and the wall bakes finish.
## Then it checks the pieces are there and every wall has its baker, prints "STARTUP PASS" or
## "STARTUP FAIL" with what went wrong, and quits (exit code 1 on a failure). Nothing is saved: the
## loaded world is marked a test run.

const FIXTURE := "res://tests/fixtures/stairs_snapshots/snap_2026-11-10_20-22-44_save.json"
## How long each step may take (frames) before it counts as stuck
const STEP_LIMIT := 3000


class ErrorCatcher extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d, %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func taken() -> Array[String]:
		_lock.lock()
		var found := errors.duplicate()
		_lock.unlock()
		return found


var _catcher := ErrorCatcher.new()
var _problems: Array[String] = []


func _ready() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	# (the catcher must see errors, or the test would pass whatever happened)
	push_error("startup test: checking errors are caught")
	if _catcher.taken().size() != 1:
		_problems.append("errors aren't being caught, so this test can't see a crash")
	_catcher.errors.clear()
	_registry_outside_the_world()
	await _title_screen()
	await _load_save()
	_finish()


# 1. The icon updater's way: a registry never added to the tree, asked for every wall's looks
func _registry_outside_the_world() -> void:
	var registry := PieceRegistry.new()
	if registry.baker == null:
		_problems.append("a registry outside the world has no wall baker")
	else:
		for shape in WallBaker.all_shapes():
			registry.material_for(shape)
			registry.mid_mesh(shape, 1)
	print("STARTUP | a registry outside the world built every wall's looks")
	registry.free()


# 2. The project's main scene, as F5 opens it
func _title_screen() -> void:
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var title := main.instantiate()
	get_tree().root.add_child(title)
	get_tree().current_scene = title
	await _frames(120)
	print("STARTUP | the title screen opened")


# 3. Load Game: the world opens from the save, its pieces come back, the loading cover lifts
func _load_save() -> void:
	SaveGame.load_save(FIXTURE)
	var player: Node = null
	for i in STEP_LIMIT:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player and SaveGame.get("_in_world"):
			break
	if player == null:
		_problems.append("the world didn't open from the save")
		return
	# (a test run: nothing it does is ever saved over the fixture's world)
	SaveGame.set("_test_run", true)
	var registry: PieceRegistry = player._placer.registry
	for i in STEP_LIMIT:
		await get_tree().process_frame
		if not registry.all_pieces().is_empty() and get_tree().root.find_children("*", "ShaderWarmup", true, false).is_empty() and (registry.baker.is_idle() or not WallBaker.can_bake()):
			break
	await _frames(30)
	var pieces := registry.all_pieces()
	var walls := pieces.filter(func(p): return PieceRegistry.is_hybrid(p.shape_name))
	print("STARTUP | the save loaded: %d pieces, %d of them hybrid walls; %d wall shapes baked, %d read from the cache" % [pieces.size(), walls.size(), registry.baker.made / PieceRegistry.DETAIL_VARIANTS, registry.baker.loaded / PieceRegistry.DETAIL_VARIANTS])
	if pieces.is_empty():
		_problems.append("the save's pieces didn't come back")
	if walls.is_empty():
		_problems.append("the save has no hybrid walls to check")
	if registry.baker == null:
		_problems.append("the world's registry has no wall baker")
	if not get_tree().root.find_children("*", "ShaderWarmup", true, false).is_empty():
		_problems.append("the loading cover never lifted")


func _finish() -> void:
	var errors := _catcher.taken()
	for e in errors:
		_problems.append("error: " + e)
	if _problems.is_empty():
		print("STARTUP PASS: the game started, opened the title screen and loaded a save without an error")
	else:
		print("STARTUP FAIL: %d problem(s)" % _problems.size())
		for p in _problems:
			print("STARTUP FAIL | " + p)
	OS.remove_logger(_catcher)
	get_tree().quit(0 if _problems.is_empty() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
