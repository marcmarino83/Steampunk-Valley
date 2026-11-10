class_name GameSettings
extends RefCounted
## The player's settings: volumes, window mode, resolution, V-Sync, mouse sensitivity, invert Y,
## field of view and which snap points show while building. Kept in user://settings.cfg (in Godot's user folder, beside the saves),
## applied as soon as they're read and whenever one changes (see SettingsPanel). The title screen
## and the player read them in (ensure_loaded); the player uses the mouse ones and the field of
## view as it goes.

const PATH := "user://settings.cfg"
## The audio buses the volume sliders set (Music and Effects are made if the project has none)
const BUSES := {"master": "Master", "music": "Music", "effects": "Effects"}
## Resolutions offered for windowed mode (only those that fit the screen are listed)
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const WINDOW_MODES := ["windowed", "fullscreen", "borderless"]

## Volumes, 0 to 100
static var master := 100.0
static var music := 80.0
static var effects := 100.0
## "windowed", "fullscreen" (exclusive) or "borderless" (a window covering the screen)
static var window_mode := "windowed"
## The window's size in windowed mode (zero: leave it as the project starts it)
static var resolution := Vector2i.ZERO
static var vsync := true
## How fast the mouse turns the view (1 = normal), whether up and down are swapped, and the field
## of view in degrees
static var mouse_sensitivity := 1.0
static var invert_y := false
static var fov := 75.0
## Which snap points show while placing a piece: "hidden" (only the one in use), "nearby" (those
## within a few meters of the crosshair, faint) or "all" (every one the piece could use around it)
const SNAP_POINT_MODES := ["hidden", "nearby", "all"]
static var snap_points := "nearby"

static var _loaded := false


## Reads the settings file and applies everything, the first time it's called
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		master = float(file.get_value("audio", "master", master))
		music = float(file.get_value("audio", "music", music))
		effects = float(file.get_value("audio", "effects", effects))
		window_mode = str(file.get_value("display", "window_mode", window_mode))
		resolution = file.get_value("display", "resolution", resolution)
		vsync = bool(file.get_value("display", "vsync", vsync))
		mouse_sensitivity = float(file.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
		invert_y = bool(file.get_value("controls", "invert_y", invert_y))
		fov = float(file.get_value("controls", "fov", fov))
		snap_points = str(file.get_value("building", "snap_points", snap_points))
	if not WINDOW_MODES.has(window_mode):
		window_mode = "windowed"
	if not SNAP_POINT_MODES.has(snap_points):
		snap_points = "nearby"
	apply_audio()
	apply_display()


## One of the slider settings by name ("master", "music", "effects", "mouse_sensitivity", "fov")
static func value_of(key: String) -> float:
	match key:
		"master":
			return master
		"music":
			return music
		"effects":
			return effects
		"mouse_sensitivity":
			return mouse_sensitivity
		"fov":
			return fov
	return 0.0


## Sets one of the slider settings by name, applying it (volumes take effect at once; the mouse and
## field of view are read by the player as it goes)
static func set_value(key: String, value: float) -> void:
	match key:
		"master":
			master = value
		"music":
			music = value
		"effects":
			effects = value
		"mouse_sensitivity":
			mouse_sensitivity = value
		"fov":
			fov = value
	if key in ["master", "music", "effects"]:
		apply_audio()


## Writes them all to the settings file
static func save() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "master", master)
	file.set_value("audio", "music", music)
	file.set_value("audio", "effects", effects)
	file.set_value("display", "window_mode", window_mode)
	file.set_value("display", "resolution", resolution)
	file.set_value("display", "vsync", vsync)
	file.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	file.set_value("controls", "invert_y", invert_y)
	file.set_value("controls", "fov", fov)
	file.set_value("building", "snap_points", snap_points)
	file.save(PATH)


## Sets each bus's volume (making the Music and Effects buses, sent to Master, if they're missing)
static func apply_audio() -> void:
	for key in BUSES:
		var bus_name: String = BUSES[key]
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		var volume: float = {"master": master, "music": music, "effects": effects}[key]
		AudioServer.set_bus_mute(index, volume <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001) / 100.0))


## Window mode, V-Sync, and (windowed) the window's size. Nothing happens without a screen.
static func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if resolution != Vector2i.ZERO:
				var screen := DisplayServer.screen_get_usable_rect()
				var size := Vector2i(mini(resolution.x, screen.size.x), mini(resolution.y, screen.size.y))
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## The windowed resolutions that fit this screen
static func resolutions_that_fit() -> Array:
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(3840, 2160)
	return RESOLUTIONS.filter(func(r): return r.x <= screen.x and r.y <= screen.y)
