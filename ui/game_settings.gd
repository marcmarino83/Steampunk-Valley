class_name GameSettings
extends RefCounted
## The player's settings: volumes, window mode, resolution, V-Sync, render scale, anti-aliasing,
## texture filtering, mouse sensitivity, invert Y,
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
## How much of the screen's resolution the 3D world is drawn at, 50 to 100 (%); below 100 it's
## scaled up to the screen with AMD FSR (the HUD and menus stay sharp at full resolution)
static var render_scale := 100.0
## How the 3D world's edges are smoothed (see ANTI_ALIASING), and how sharp textures stay when seen
## at a slant (anisotropic filtering: 0 off, or 2, 4, 8 or 16 samples). TAA is the default: it
## shimmers least while moving and costs about what MSAA 2× does (tests/look_pass.gd).
static var anti_aliasing := "taa"
static var texture_filtering := 16
## The anti-aliasing choices, as the Settings menu lists them: MSAA smooths the edges of shapes
## (2× or 4× the samples on edges), FXAA blurs high-contrast edges slightly after drawing, TAA blends
## each frame with the ones before (smoothest, softest, and quiet while moving)
const ANTI_ALIASING := ["off", "fxaa", "msaa_2x", "msaa_4x", "taa", "taa_msaa_2x"]
const TEXTURE_FILTERING := [0, 2, 4, 8, 16]
## How fast the mouse turns the view (1 = normal), whether up and down are swapped, and the field
## of view in degrees
static var mouse_sensitivity := 1.0
static var invert_y := false
static var fov := 75.0
## Debug builds only: write a line to the output for every frame slower than 33 ms (see SpikeLog)
static var spike_log := false
## The size of every menu, panel and HUD element, UI_SCALE_MIN to UI_SCALE_MAX (%), in UI_SCALE_STEP
## steps. Until it's set, it's picked from the screen (default_ui_scale). The text stays sharp at
## every size: the default font is a multichannel signed distance field font (project settings).
static var ui_scale := 100.0
const UI_SCALE_MIN := 75.0
const UI_SCALE_MAX := 150.0
const UI_SCALE_STEP := 5.0

static var _loaded := false


## Reads the settings file and applies everything, the first time it's called
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	ui_scale = default_ui_scale()
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		ui_scale = _clean_ui_scale(float(file.get_value("display", "ui_scale", ui_scale)))
		master = float(file.get_value("audio", "master", master))
		music = float(file.get_value("audio", "music", music))
		effects = float(file.get_value("audio", "effects", effects))
		window_mode = str(file.get_value("display", "window_mode", window_mode))
		resolution = file.get_value("display", "resolution", resolution)
		vsync = bool(file.get_value("display", "vsync", vsync))
		render_scale = clampf(float(file.get_value("display", "render_scale", render_scale)), 50.0, 100.0)
		anti_aliasing = str(file.get_value("display", "anti_aliasing", anti_aliasing))
		texture_filtering = int(file.get_value("display", "texture_filtering", texture_filtering))
		mouse_sensitivity = float(file.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
		invert_y = bool(file.get_value("controls", "invert_y", invert_y))
		fov = float(file.get_value("controls", "fov", fov))
		spike_log = bool(file.get_value("debug", "spike_log", spike_log))
	SpikeLog.enabled = spike_log and OS.is_debug_build()
	if not WINDOW_MODES.has(window_mode):
		window_mode = "windowed"
	if not ANTI_ALIASING.has(anti_aliasing):
		anti_aliasing = "taa"
	if not TEXTURE_FILTERING.has(texture_filtering):
		texture_filtering = 16
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
		"render_scale":
			return render_scale
		"ui_scale":
			return ui_scale
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
		"render_scale":
			render_scale = clampf(value, 50.0, 100.0)
			apply_render_scale()
		"ui_scale":
			ui_scale = _clean_ui_scale(value)
			apply_ui_scale()
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
	file.set_value("display", "render_scale", render_scale)
	file.set_value("display", "anti_aliasing", anti_aliasing)
	file.set_value("display", "texture_filtering", texture_filtering)
	file.set_value("display", "ui_scale", ui_scale)
	file.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	file.set_value("controls", "invert_y", invert_y)
	file.set_value("controls", "fov", fov)
	file.set_value("debug", "spike_log", spike_log)
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
	apply_render_scale()
	apply_quality()
	apply_ui_scale()
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


## Draws the 3D world at render_scale % of the window's resolution, scaled up with FSR (at 100%
## it's drawn at full size, with no upscaling)
static func apply_render_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var root := tree.root
	if render_scale >= 99.5:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 1.0
	else:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		root.scaling_3d_scale = render_scale / 100.0


## Anti-aliasing and texture filtering, on the window's 3D world
static func apply_quality() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	apply_anti_aliasing(tree.root, anti_aliasing)
	tree.root.anisotropic_filtering_level = {0: Viewport.ANISOTROPY_DISABLED, 2: Viewport.ANISOTROPY_2X, 4: Viewport.ANISOTROPY_4X, 8: Viewport.ANISOTROPY_8X}.get(texture_filtering, Viewport.ANISOTROPY_16X)


## One of the ANTI_ALIASING choices on a viewport
static func apply_anti_aliasing(viewport: Viewport, choice: String) -> void:
	viewport.msaa_3d = {"msaa_2x": Viewport.MSAA_2X, "msaa_4x": Viewport.MSAA_4X, "taa_msaa_2x": Viewport.MSAA_2X}.get(choice, Viewport.MSAA_DISABLED)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if choice == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = choice.begins_with("taa")


## Sizes every menu, panel and HUD element: the window's 2D content is drawn ui_scale % of its
## size (the screen is laid out at 1920 × 1080 and stretched to the window; this goes on top).
## Everything is anchored, so it all stays in place; the 3D world isn't touched.
static func apply_ui_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if is_equal_approx(tree.root.content_scale_factor, ui_scale / 100.0):
		return
	tree.root.content_scale_factor = ui_scale / 100.0
	# (menus fit themselves to the screen again: see MenuStyle.enlarge)
	tree.root.size_changed.emit()


## The UI scale for this screen: 100% up to about 1080p, 125% at 1440p and 4K
static func default_ui_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 100.0
	var height := DisplayServer.screen_get_size().y
	return 125.0 if height >= 1400 else 100.0


static func _clean_ui_scale(value: float) -> float:
	return clampf(snappedf(value, UI_SCALE_STEP), UI_SCALE_MIN, UI_SCALE_MAX)


## The windowed resolutions that fit this screen
static func resolutions_that_fit() -> Array:
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(3840, 2160)
	return RESOLUTIONS.filter(func(r): return r.x <= screen.x and r.y <= screen.y)
