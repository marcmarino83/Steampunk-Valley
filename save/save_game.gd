extends Node
## The save file: writing it, reading it, autosaving, and the "Saving..." sign. Runs as the
## SaveGame autoload, so it's there on the title screen and in the world alike.
##
## It knows nothing about what's being saved. Every system that has something to keep joins the
## "saveable" group and has three functions:
##     save_key() -> String          its own section of the file, like "player"
##     save_data() -> Dictionary     what to keep (plain numbers, text, arrays and dictionaries)
##     load_data(data: Dictionary)   put it back
## and, optionally, save_priority() -> int: lower loads first (the clock before the world, the
## world before the player, and so on). A new feature joins the save just by doing the same.
##
## The file is JSON, readable in any text editor, in Godot's user folder (on Windows,
## %APPDATA%/Godot/app_userdata/Steampunk Valley/savegame.json).

const SAVE_PATH := "user://savegame.json"
## Goes up by one whenever the file's layout changes; _upgrade() brings older saves up to date
const SAVE_VERSION := 1
const WORLD_SCENE := "res://world/world.tscn"
const TITLE_SCENE := "res://ui/title_screen.tscn"
## How often to save while playing, in real seconds
const AUTOSAVE_SECONDS := 300.0
## How long the "Saving..." sign stays up
const SIGN_SECONDS := 1.4
## How long Quit shows "Saving..." before the game closes, in seconds
const QUIT_DELAY := 0.8

# Set when the world is about to open from a save, so it's loaded once the world is ready
var _load_when_ready := false
# Set when the title screen (or the pause menu's Load) opens the world. If a world turns up
# without it, the world scene was run directly from the editor.
var _opened_from_menu := false
# A test run: the world scene was run directly, not started from the title screen. Nothing is
# saved for as long as the game stays open, so testing can never overwrite the real save.
var _test_run := false
# True while a world is running (not on the title screen)
var _in_world := false
var _until_autosave := AUTOSAVE_SECONDS
var _sign: Label
var _sign_tween: Tween
var _test_note: Label


func _ready() -> void:
	# The sign has to work while the game is paused (saving from the pause menu)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_sign = Label.new()
	_sign.text = "Saving..."
	_sign.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_sign.add_theme_font_size_override("font_size", 18)
	_sign.add_theme_color_override("font_color", Color(0.98, 0.78, 0.32))
	_sign.add_theme_color_override("font_outline_color", Color.BLACK)
	_sign.add_theme_constant_override("outline_size", 5)
	_sign.modulate.a = 0.0
	layer.add_child(_sign)
	_test_note = Label.new()
	_test_note.text = "Test run – not saving"
	_test_note.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_test_note.position.y += 26
	_test_note.add_theme_font_size_override("font_size", 15)
	_test_note.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	_test_note.add_theme_color_override("font_outline_color", Color.BLACK)
	_test_note.add_theme_constant_override("outline_size", 4)
	_test_note.visible = false
	layer.add_child(_test_note)


func _process(delta: float) -> void:
	if not _in_world or _test_run or get_tree().paused:
		return
	_until_autosave -= delta
	if _until_autosave <= 0.0:
		save_now()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## When the save was made, as text (empty if there's none)
func saved_when() -> String:
	var data := _read()
	return str(data.get("saved_at", "")).replace("T", " ")


## Opens the world fresh. (The old save stays until the first save of the new game.)
func new_game() -> void:
	_load_when_ready = false
	_opened_from_menu = true
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


## Opens the world from the save
func continue_game() -> void:
	_load_when_ready = true
	_opened_from_menu = true
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


## The player calls this once the world scene is set up. Loading waits until the end of the
## frame, so the valley has grown and everything is in place.
func world_ready() -> void:
	_in_world = true
	_until_autosave = AUTOSAVE_SECONDS
	# A world nobody asked for from the menus was run straight from the editor: a test run, for
	# the rest of this session (even if it later loads the save, it never writes over it)
	if not _opened_from_menu:
		_test_run = true
	_opened_from_menu = false
	_test_note.visible = _test_run
	if _load_when_ready:
		_load_when_ready = false
		_apply_save.call_deferred()


## True unless this is a test run, where nothing is ever saved
func can_save() -> bool:
	return not _test_run


## Saves (unless this is a test run), shows "Saving..." for a moment, then closes the game
func save_and_quit() -> void:
	if can_save() and _in_world:
		save_now()
		# A timer that keeps running while the game is paused (Quit is in the pause menu)
		await get_tree().create_timer(QUIT_DELAY, true).timeout
	get_tree().quit()


## The world is closing (back to the title, or loading)
func world_closed() -> void:
	_in_world = false


## Writes every system's data to the save file (never during a test run)
func save_now() -> void:
	if not _in_world or _test_run:
		return
	_until_autosave = AUTOSAVE_SECONDS
	var systems := {}
	for node in get_tree().get_nodes_in_group("saveable"):
		systems[node.save_key()] = node.save_data()
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"systems": systems,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: couldn't write %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_show_sign()


func _apply_save() -> void:
	var data := _upgrade(_read())
	if data.is_empty():
		return
	var systems: Dictionary = data.get("systems", {})
	var nodes := get_tree().get_nodes_in_group("saveable")
	nodes.sort_custom(func(a, b): return _priority(a) < _priority(b))
	for node in nodes:
		var key: String = node.save_key()
		if systems.has(key):
			node.load_data(systems[key])


func _priority(node: Node) -> int:
	return node.save_priority() if node.has_method("save_priority") else 0


func _read() -> Dictionary:
	if not has_save():
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SaveGame: %s isn't a readable save" % SAVE_PATH)
		return {}
	return parsed


# Brings a save from an older version up to date, one version at a time. When the file's layout
# changes, raise SAVE_VERSION and add a step here that turns the old layout into the new one.
func _upgrade(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return data
	var version := int(data.get("version", 1))
	if version > SAVE_VERSION:
		push_error("SaveGame: this save is from a newer version of the game (%d); not loading it" % version)
		return {}
	while version < SAVE_VERSION:
		match version:
			# 1: (the first version; future steps go here, e.g. "1: data = _from_1_to_2(data)")
			_:
				pass
		version += 1
	data["version"] = SAVE_VERSION
	return data


func _show_sign() -> void:
	if _sign_tween:
		_sign_tween.kill()
	_sign.modulate.a = 1.0
	_sign_tween = create_tween()
	_sign_tween.tween_interval(SIGN_SECONDS)
	_sign_tween.tween_property(_sign, "modulate:a", 0.0, 0.4)


## A Vector3 as a plain list for the file, and back
static func from_vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func to_vector(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO
