extends Node
## Saved games: worlds, their manual saves and autosaves, loading, and the "Saving..." sign.
## Runs as the SaveGame autoload, so it's there on the title screen and in the world alike.
##
## It knows nothing about what's being saved. Every system that has something to keep joins the
## "saveable" group and has three functions:
##     save_key() -> String          its own section of the file, like "player"
##     save_data() -> Dictionary     what to keep (plain numbers, text, arrays and dictionaries)
##     load_data(data: Dictionary)   put it back
## and, optionally, save_priority() -> int: lower loads first (the clock before the world, the
## world before the player, and so on). A new feature joins the save just by doing the same.
##
## Each world (one per New Game) has its own folder in Godot's user folder (on Windows,
## %APPDATA%/Godot/app_userdata/Steampunk Valley/saves/), holding world.json (its name) and its
## saves: manual_<time>.json for ones you make from the pause menu, auto_<time>.json for
## autosaves (every few minutes, after sleeping, and on quitting; the newest AUTOSAVES_KEPT are
## kept). Each save is readable JSON, with a small picture of the moment beside it (.png).

const SAVES_DIR := "user://saves"
## The single save file from before there were several; turned into a manual save on first start
const OLD_SAVE_PATH := "user://savegame.json"
## Goes up by one whenever the file's layout changes; _upgrade() brings older saves up to date
const SAVE_VERSION := 2
const WORLD_SCENE := "res://world/world.tscn"
const TITLE_SCENE := "res://ui/title_screen.tscn"
## How often to autosave while playing, in real seconds
const AUTOSAVE_SECONDS := 300.0
## How many autosaves each world keeps; the oldest goes when a new one is made
const AUTOSAVES_KEPT := 3
## The size of the picture saved with each save
const THUMB_SIZE := Vector2i(192, 108)
## How long the "Saving..." sign stays up
const SIGN_SECONDS := 1.4
## How long Quit shows "Saving..." before the game closes, in seconds
const QUIT_DELAY := 0.8
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# The save to load once the world is ready (empty for a new game)
var _load_path := ""
# Set when the title screen (or the pause menu's Load) opens the world. If a world turns up
# without it, the world scene was run directly from the editor.
var _opened_from_menu := false
# A test run: the world scene was run directly, not started from the title screen. Nothing is
# saved for as long as the game stays open, so testing can never overwrite a real save.
var _test_run := false
# True while a world is running (not on the title screen)
var _in_world := false
var _until_autosave := AUTOSAVE_SECONDS
# The world being played: its folder name, and how long it's been played in all, in seconds
var _world_id := ""
var _play_seconds := 0.0
# A picture of the game taken just before the pause menu covered it, for saves made from there
var _snapshot: Image
# A save still being written on a worker thread (its task id), or -1
var _writing := -1
var _sign: Label
var _sign_tween: Tween
var _test_note: Label


func _ready() -> void:
	# Saves are made while the game is paused (from the pause menu), and the sign shows then too
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	_convert_old_save()
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
	if not _in_world or get_tree().paused:
		return
	_play_seconds += delta
	if _test_run:
		return
	_until_autosave -= delta
	if _until_autosave <= 0.0:
		autosave()


# ---- Starting, loading and closing ----

## Opens the world fresh, as a new world with saves of its own. Other worlds aren't touched.
func new_game() -> void:
	_world_id = "world_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	_play_seconds = 0.0
	_open_world("")


## Opens the world from the most recent save of any world
func continue_game() -> void:
	var newest := newest_save()
	if not newest.is_empty():
		load_save(newest["path"])


## Opens the world from this save file
func load_save(path: String) -> void:
	var data := _read(path)
	if data.is_empty():
		return
	var meta: Dictionary = data.get("meta", {})
	_world_id = str(meta.get("world_id", path.get_base_dir().get_file()))
	_play_seconds = float(meta.get("play_seconds", 0.0))
	_open_world(path)


func _open_world(load_path: String) -> void:
	if _in_world:
		world_closed()
	_load_path = load_path
	_opened_from_menu = true
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


## The player calls this once the world scene is set up. Loading waits until the end of the
## frame, so the valley has grown and everything is in place.
func world_ready() -> void:
	_in_world = true
	_until_autosave = AUTOSAVE_SECONDS
	# A world nobody asked for from the menus was run straight from the editor: a test run, for
	# the rest of this session (even if it later loads a save, it never writes over it)
	if not _opened_from_menu:
		_test_run = true
	_opened_from_menu = false
	_test_note.visible = _test_run
	if not _load_path.is_empty():
		_apply_save.call_deferred(_load_path)
		_load_path = ""


## The world is closing (back to the title, or loading)
func world_closed() -> void:
	_in_world = false


## True unless this is a test run, where nothing is ever saved
func can_save() -> bool:
	return not _test_run and _in_world and not _world_id.is_empty()


## Autosaves (unless this is a test run), shows "Saving..." for a moment, then closes the game
func save_and_quit() -> void:
	if can_save():
		autosave()
		# A timer that keeps running while the game is paused (Quit is in the pause menu)
		await get_tree().create_timer(QUIT_DELAY, true).timeout
		finish_saving()
	get_tree().quit()


# ---- Saving ----

## Saves into one of this world's manual slots: a new one, or over `overwrite_path`. With no
## name typed, it's called "Day 3 – 7 Nov 2026, 18:42" (an overwritten slot keeps a name you
## gave it).
func save_manual(save_name: String, overwrite_path := "") -> void:
	var custom := not save_name.strip_edges().is_empty()
	var path := overwrite_path
	if path.is_empty():
		path = _world_dir().path_join("manual_%d.json" % int(Time.get_unix_time_from_system() * 1000.0))
	elif not custom:
		var old: Dictionary = _read(path).get("meta", {})
		if old.get("custom_name", false):
			save_name = str(old.get("name", ""))
			custom = true
	_write(path, "manual", save_name.strip_edges() if custom else "", custom)


## An autosave: the newest of this world's autosaves, replacing the oldest beyond AUTOSAVES_KEPT
func autosave() -> void:
	if not can_save():
		return
	# (the oldest autosaves are cleared away on the worker thread once this one's written)
	_write(_world_dir().path_join("auto_%d.json" % int(Time.get_unix_time_from_system() * 1000.0)), "auto", "", false)


func _write(path: String, kind: String, save_name: String, custom: bool) -> void:
	if not can_save():
		return
	var timing := SpikeLog.begin()
	_write_now(path, kind, save_name, custom)
	# A manual save is waited for (the save list shows it straight after); an autosave isn't
	if kind != "auto":
		finish_saving()
	SpikeLog.end("saving (gathering; the file's written on a worker thread)", timing)
	SpikeLog.note("a save written (%s)" % kind)


## Waits for a save still being written on a worker thread (before quitting, or the next save)
func finish_saving() -> void:
	if _writing >= 0:
		WorkerThreadPool.wait_for_task_completion(_writing)
		_writing = -1


func _exit_tree() -> void:
	finish_saving()


func _write_now(path: String, kind: String, save_name: String, custom: bool) -> void:
	finish_saving()
	_until_autosave = AUTOSAVE_SECONDS
	DirAccess.make_dir_recursive_absolute(_world_dir())
	if not FileAccess.file_exists(_world_dir().path_join("world.json")):
		_write_json(_world_dir().path_join("world.json"), {"name": _next_world_name(), "started_unix": Time.get_unix_time_from_system()})
	var systems := {}
	for node in get_tree().get_nodes_in_group("saveable"):
		systems[node.save_key()] = node.save_data()
	var day := _day_now()
	var when := Time.get_datetime_dict_from_system()
	var data := {
		"version": SAVE_VERSION,
		"meta": {
			"name": save_name if custom else "Day %d – %s" % [day, _date_text(when)],
			"custom_name": custom,
			"kind": kind,
			"world_id": _world_id,
			"day": day,
			"play_seconds": _play_seconds,
			"saved_unix": Time.get_unix_time_from_system(),
			"saved_text": _date_text(when),
		},
		"systems": systems,
	}
	# Gathered here; turned into text and written, with its picture, on a worker thread (a deep
	# copy, so nothing the game changes meanwhile can reach it)
	var image := _snapshot if _snapshot else _screen_image()
	_writing = WorkerThreadPool.add_task(_write_files.bind(path, data.duplicate(true), image, _world_id if kind == "auto" else ""))
	_show_sign()


# On a worker thread: the save's file and its picture; after an autosave, the oldest autosaves
# beyond AUTOSAVES_KEPT go
func _write_files(path: String, data: Dictionary, image: Image, prune_world: String) -> void:
	if not _write_json(path, data):
		return
	if image:
		image = image.duplicate()
		image.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
		image.save_png(path.get_basename() + ".png")
	if not prune_world.is_empty():
		var autos := saves_in(prune_world).filter(func(s): return s["kind"] == "auto")
		for old in autos.slice(AUTOSAVES_KEPT):
			delete_save(old["path"])


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: couldn't write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


## The pause menu calls this just before it opens, so saves made from it show the game, not
## the menu
func take_snapshot() -> void:
	_snapshot = _screen_image()


func clear_snapshot() -> void:
	_snapshot = null


func _screen_image() -> Image:
	# Without a screen (a headless check) there's no picture to take
	if DisplayServer.get_name() == "headless":
		return null
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGB8)
	return image


# ---- Listing and deleting ----

func has_save() -> bool:
	return not newest_save().is_empty()


## The most recent save of any kind, in any world (empty if there are none)
func newest_save() -> Dictionary:
	var all := list_saves()
	return all[0] if not all.is_empty() else {}


## Every save, newest first. Each is a Dictionary: path, thumbnail (a path, or empty), name,
## kind ("manual" or "auto"), world_id, world_name, day, play_seconds (-1 if unknown),
## saved_unix and saved_text.
func list_saves() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for world in DirAccess.get_directories_at(SAVES_DIR):
		all.append_array(saves_in(world))
	all.sort_custom(func(a, b): return a["saved_unix"] > b["saved_unix"])
	return all


## One world's saves, newest first
func saves_in(world_id: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := SAVES_DIR.path_join(world_id)
	if not DirAccess.dir_exists_absolute(dir):
		return found
	var world_name := str(_read(dir.path_join("world.json")).get("name", world_id))
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json") or file == "world.json":
			continue
		var path := dir.path_join(file)
		var meta: Dictionary = _read(path).get("meta", {})
		if meta.is_empty():
			continue
		var thumb := path.get_basename() + ".png"
		found.append({
			"path": path,
			"thumbnail": thumb if FileAccess.file_exists(thumb) else "",
			"name": str(meta.get("name", file.get_basename())),
			"kind": str(meta.get("kind", "manual")),
			"world_id": world_id,
			"world_name": world_name,
			"day": int(meta.get("day", 1)),
			"play_seconds": float(meta.get("play_seconds", -1.0)),
			"saved_unix": float(meta.get("saved_unix", 0.0)),
			"saved_text": str(meta.get("saved_text", "")),
		})
	found.sort_custom(func(a, b): return a["saved_unix"] > b["saved_unix"])
	return found


## The world being played right now (empty on the title screen or in a test run)
func current_world() -> String:
	return _world_id if can_save() else ""


## Deletes a save and its picture. A world left with no saves goes too.
func delete_save(path: String) -> void:
	DirAccess.remove_absolute(path)
	var thumb := path.get_basename() + ".png"
	if FileAccess.file_exists(thumb):
		DirAccess.remove_absolute(thumb)
	var dir := path.get_base_dir()
	var left := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".json") and f != "world.json")
	if left.is_empty() and dir.get_file() != current_world():
		DirAccess.remove_absolute(dir.path_join("world.json"))
		DirAccess.remove_absolute(dir)


## Play time as text, like "2h 14m" ("–" if unknown)
static func play_time_text(seconds: float) -> String:
	if seconds < 0.0:
		return "–"
	var minutes := int(seconds / 60.0)
	return "%dh %02dm" % [minutes / 60, minutes % 60] if minutes >= 60 else "%dm" % minutes


# ---- Reading ----

func _apply_save(path: String) -> void:
	var data := _upgrade(_read(path))
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


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("SaveGame: %s isn't a readable save" % path)
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
			# 1 -> 2: saves gained "meta" (name, kind, world, day...); the game's data is the same
			1:
				if not data.has("meta"):
					data["meta"] = {}
		version += 1
	data["version"] = SAVE_VERSION
	return data


# ---- Helpers ----

func _world_dir() -> String:
	return SAVES_DIR.path_join(_world_id)


# "World 1", "World 2"... one more than the highest so far
func _next_world_name() -> String:
	var highest := 0
	for world in DirAccess.get_directories_at(SAVES_DIR):
		var world_name := str(_read(SAVES_DIR.path_join(world).path_join("world.json")).get("name", ""))
		if world_name.begins_with("World "):
			highest = maxi(highest, int(world_name.substr(6)))
	return "World %d" % (highest + 1)


# Today's day number, counting the first day as Day 1
func _day_now() -> int:
	var sun = get_tree().get_first_node_in_group("sun")
	return int(sun.day) + 1 if sun else 1


static func _date_text(when: Dictionary) -> String:
	return "%d %s %d, %02d:%02d" % [when["day"], MONTHS[int(when["month"]) - 1], when["year"], when["hour"], when["minute"]]


# The one save from before there were several becomes a manual save in a world of its own, so
# nothing is lost. The old file is kept beside it, renamed savegame.json.converted.
func _convert_old_save() -> void:
	if not FileAccess.file_exists(OLD_SAVE_PATH):
		return
	var data := _upgrade(_read(OLD_SAVE_PATH))
	if data.is_empty():
		return
	var saved_at := str(data.get("saved_at", ""))
	var when := Time.get_datetime_dict_from_datetime_string(saved_at, false) if not saved_at.is_empty() else Time.get_datetime_dict_from_system()
	# The old file kept local time; sorting uses universal time
	var unix: float = Time.get_unix_time_from_datetime_dict(when) - Time.get_time_zone_from_system()["bias"] * 60.0
	var day := int(Dictionary(data.get("systems", {}).get("clock", {})).get("day", 0)) + 1
	var world_id := "world_%d" % int(unix * 1000.0)
	var dir := SAVES_DIR.path_join(world_id)
	DirAccess.make_dir_recursive_absolute(dir)
	_write_json(dir.path_join("world.json"), {"name": _next_world_name(), "started_unix": unix})
	data["meta"] = {
		"name": "Day %d – %s" % [day, _date_text(when)],
		"custom_name": false,
		"kind": "manual",
		"world_id": world_id,
		"day": day,
		"saved_unix": unix,
		"saved_text": _date_text(when),
	}
	data.erase("saved_at")
	if _write_json(dir.path_join("manual_%d.json" % int(unix * 1000.0)), data):
		DirAccess.rename_absolute(OLD_SAVE_PATH, OLD_SAVE_PATH + ".converted")


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


## A full rotation (turned, tilted and tipped) for a save: [x, y, z, w] of its quaternion
static func from_rotation(b: Basis) -> Array:
	var q := b.orthonormalized().get_rotation_quaternion()
	return [q.x, q.y, q.z, q.w]


## True if a rotation is more than a turn round the upright (tilted or tipped), so it needs saving
## in full (see from_rotation); an upright one saves as just its turn, as before
static func is_leaning(b: Basis) -> bool:
	return b.orthonormalized().y.dot(Vector3.UP) < 0.99999


## A saved entry's rotation: its full rotation if it has one ("rotation"), else its turn round the
## upright ("turn"), as older saves have
static func to_rotation(entry: Dictionary) -> Basis:
	var a = entry.get("rotation")
	if a is Array and a.size() >= 4:
		return Basis(Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized())
	return Basis(Vector3.UP, float(entry.get("turn", 0.0)))
