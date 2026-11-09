extends CharacterBody3D

const WALK_SPEED = 5.0
const JUMP_VELOCITY = 4.5
## Sprinting (hold Shift, going forward): how much faster than walking, how many degrees wider
## the view gets and how quickly it eases there, and how much faster hunger drains
const SPRINT_MULTIPLIER := 1.7
const SPRINT_FOV := 7.0
const SPRINT_FOV_EASE := 8.0
const SPRINT_HUNGER := 1.5
const MOUSE_SENSITIVITY = 0.002

## Hunger and warmth follow the sun's clock (its Day Minutes and Night Minutes), so they stay fair
## however long the day is. A full belly lasts this many whole days (a day and its night).
const FULL_BELLY_DAYS := 1.0
## How much hunger one berry fills back up
const BERRY_FOOD = 15.0
## Out in the open with no fire: how much warmth a whole night costs at the cold of deep night, and
## how much a whole day gives back at the warmth of midday (dawn and dusk sit in between)
const NIGHT_CHILL_PER_NIGHT := 90.0
const DAY_WARMTH_PER_DAY := 18.0
## If there's no sun to ask, these day and night lengths are used, in seconds
const FALLBACK_DAY_SECONDS := 1680.0
const FALLBACK_NIGHT_SECONDS := 720.0
## Warmth gained per second standing by a lit campfire
const FIRE_WARMTH = 6.0
## Inside a shelter, the cold gets to you only this fast (0.35 = a bit over a third as fast)
const SHELTER_CHILL = 0.35
## How far in front of you a dropped tool lands
const DROP_DISTANCE := 1.2
## Sleeping: when you wake (0.27 is just after sunrise), how much hunger a night costs, how close a
## lit campfire must be to wake up warm, and how warm you are without one
const WAKE_TIME := 0.27
const SLEEP_HUNGER := 25.0
const SLEEP_FIRE_RANGE := 5.0
const COLD_WAKE_WARMTH := 25.0
## How long the screen takes to fade out and back in, and how long it stays dark, in seconds
const SLEEP_FADE := 1.0
const SLEEP_DARK := 0.6
## How long a "New blueprint" pop-up stays up before fading, in seconds
const BLUEPRINT_POPUP_TIME := 3.0
## In plot view, how far ahead E finds the plot whose ground you're aiming at
const PLOT_REACH := 20.0
## More new blueprints than this at once are summed up in the pop-up instead of listed
const BLUEPRINT_POPUP_LINES := 3
## How close a crafting station (like the workbench) must be for its recipes, in meters
const STATION_RANGE := 3.0
## An open chest closes once you're this far from it, in meters
const CHEST_RANGE := 4.0
## A torch burns for this share of a night while held, and while held the cold gets to you only
## this fast (0.75 = three quarters as fast)
const TORCH_NIGHTS := 0.5
const TORCH_CHILL := 0.75
## Checking for a roof overhead and a closed room around you: how often, in seconds, how far the
## rays look, in meters, and how many go round the room
## Climbing a ladder: how fast (m/s), and how close it must be in front of you
const CLIMB_SPEED := 2.5
## Stepping: the highest ledge you walk up onto without jumping (a floor laid on the ground, a low
## foundation; not a full-height foundation), the smallest rise that counts as a step, how far
## ahead a ledge is felt for, and how quickly the camera catches up after a step
const STEP_HEIGHT := 0.45
const STEP_MIN := 0.02
const STEP_PROBE := 0.06
const STEP_CAMERA_EASE := 14.0
## A drop this big in one frame is a ledge stepped off, not a slope walked down (at walking speed
## even a 45° slope drops less): only then does the camera ease down after it
const STEP_SMOOTH_DROP := 0.12
const LADDER_REACH := 0.9
const SHELTER_CHECK_SECONDS := 0.4
const SHELTER_REACH := 14.0
const ENCLOSURE_RAYS := 32

const NOTE_PANEL_SCENE = preload("res://ui/note_panel.tscn")
const PAUSE_MENU_SCENE = preload("res://ui/pause_menu.tscn")

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var held_items: Node3D = $Camera3D/HeldItems
@onready var status_label: Label = $HUD/Status
@onready var inventory_screen: Control = $HUD/InventoryScreen
@onready var build_menu: Control = $HUD/BuildMenu
@onready var action_bar: ActionBar = $HUD/ActionBar

## Everything you own, like {"Scrap": 3, "Coal": 1}, including tools sitting on the action bar
var inventory := {}
## What's in your hand, or an empty string
var held_item := ""
## 100 = full, 0 = starving
var hunger := 100.0
## 100 = toasty, 0 = freezing
var warmth := 100.0

# A short message shown at the top of the screen, and how long it has left
var _message := ""
var _message_time := 0.0
# The parchment page that notes and logs open on
var _note_panel: Control
# The plot panel (E aimed inside a plot in plot view), which also asks plots' yes/no questions
var _plot_panel: PlotPanel
# The plot tracker on the right of the screen (the plot you're in, or aiming at in plot view)
var _plot_tracker: PlotTracker
# What was being placed when the build menu opened, to go back to if nothing else is picked
var _build_resume: Buildable
# Plot view switched on with P (it only shows with the hammer out)
var _plot_view := false
# The camera's usual height on the body, and how far it lags behind after a step (eases to 0)
var _camera_height := 0.0
var _step_offset := 0.0
# Half the body's height: its origin is its middle, so your feet are this far below it
var _half_height := 1.0
# Sprinting right now (Shift held, going forward, started on the ground), and the usual view angle
var _sprinting := false
var _base_fov := 75.0
# The dowsing rod's pulse, which only exists while the iron tier is switched on
var _dowsing: Node
# The grass, ferns and scattered rocks, found the first time a pickaxe needs them
var _foliage: Node
# Frames per second, in the top-right corner (F3 shows or hides it)
var _fps_label: Label
# Handles putting a building down, once one's been chosen from the build menu
var _placer: BuildPlacer
# The blueprints (buildables and recipes) that started locked and have since been unlocked
var _unlocked := {}
# The "New blueprint" pop-up
var _blueprint_label: Label
# The compact controls row, piece panel and crosshair prompts
var _hud: HudControls
# Bottom left: the hunger and warmth panel and gauge; by the action bar: the compass and watch,
# and the crosshair
var _vitals: VitalsPanel
var _instruments: HudInstruments
var _blueprint_tween: Tween
# Sleeping: the black screen it fades to, and whether you're asleep right now
var _fade: ColorRect
var _sleeping := false
# The titles of notes and logs you've read
var _notes_read := {}
# Esc's menu: Resume, Save, Load, Quit
var _pause_menu: Control
# Everything you've ever crafted, gathered or built, as "Craft:Axe", "Build:Workbench" and so on,
# for blueprints that unlock once several things have been done
var _done := {}
# The chest that's open beside the inventory, if any
var _open_chest: Node3D
# The crafting stations in reach last time the Crafting tab was brought up to date
var _last_stations: PackedStringArray = []
# Seconds left on the torch in your hand (0 = a fresh one is lit when you next hold one)
var _torch_left := 0.0
# Under a roof you've built, and shut in a room (see _check_shelter), and when to check again
var _under_roof := false
var _enclosed := false
var _shelter_check_in := 0.0


func _ready() -> void:
	# Walking off a low ledge keeps you on the ground (no hop); a jump still lifts you off
	floor_snap_length = STEP_HEIGHT
	_camera_height = camera.position.y
	_base_fov = camera.fov
	_half_height = ($CollisionShape3D.shape as CylinderShape3D).height / 2.0
	# Hide the mouse and lock it to the window so it can steer the camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The look ray starts inside your own body, so tell it to ignore you
	interact_ray.add_exception(self)
	# So things like campfires can check what you're carrying
	add_to_group("player")
	_note_panel = NOTE_PANEL_SCENE.instantiate()
	$HUD.add_child(_note_panel)
	_fps_label = Label.new()
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 5)
	_fps_label.visible = false
	$HUD.add_child(_fps_label)
	_blueprint_label = Label.new()
	_blueprint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96)
	_blueprint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_blueprint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blueprint_label.add_theme_font_size_override("font_size", 26)
	_blueprint_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.32))
	_blueprint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_blueprint_label.add_theme_constant_override("outline_size", 7)
	_blueprint_label.modulate.a = 0.0
	$HUD.add_child(_blueprint_label)
	# Under the menus, so an open inventory or build menu covers it
	_vitals = VitalsPanel.new()
	$HUD.add_child(_vitals)
	$HUD.move_child(_vitals, inventory_screen.get_index())
	_instruments = HudInstruments.new()
	$HUD.add_child(_instruments)
	# Just above the action bar, so the compass's brass sits on the bar's scrollwork
	$HUD.move_child(_instruments, action_bar.get_index() + 1)
	_hud = HudControls.new()
	$HUD.add_child(_hud)
	$HUD.move_child(_hud, inventory_screen.get_index())
	# The plot tracker, on the right: under the menus too
	_plot_tracker = PlotTracker.new()
	$HUD.add_child(_plot_tracker)
	$HUD.move_child(_plot_tracker, inventory_screen.get_index())
	# Last, so the black of sleep covers everything
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Above the HUD and menus, under the black of sleep
	_plot_panel = PlotPanel.new()
	$HUD.add_child(_plot_panel)
	_plot_panel.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_plot_panel.move_requested.connect(func(plot):
		_plot_panel.close()
		_placer.move_plot(plot))
	_plot_panel.remove_confirmed.connect(func(plot):
		var plot_name: String = plot.plot_name
		_placer.plots.remove_plot(plot)
		flash("Removed %s. Its pieces stay standing" % plot_name))
	$HUD.add_child(_fade)
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	$HUD.add_child(_pause_menu)
	_placer = BuildPlacer.new()
	add_child(_placer)
	_placer.plots.became_working.connect(func(plot): flash("%s is now working" % plot.plot_name))
	if IronTier.ENABLED:
		_dowsing = load("res://iron_tier/dowsing.gd").new()
		add_child(_dowsing)
	build_menu.chosen.connect(_on_buildable_chosen)
	action_bar.held_changed.connect(_on_held_changed)
	action_bar.contents_changed.connect(_refresh_inventory_display)
	inventory_screen.tool_returned.connect(action_bar.remove)
	inventory_screen.item_moved.connect(_move_item)
	inventory_screen.crafting.craft_requested.connect(craft)
	_refresh_inventory_display()
	add_to_group("saveable")
	SaveGame.world_ready()


func _exit_tree() -> void:
	ToolItem.forget_all()
	SaveGame.world_closed()


func save_key() -> String:
	return "player"


# After the world, the respawns and the buildings
func save_priority() -> int:
	return 40


## Where you are and which way you face, how you're doing, what you carry, the blueprints you've
## unlocked, the notes you've read, and the tools you've dropped on the ground
func save_data() -> Dictionary:
	var dropped: Array = []
	for tool_on_ground in get_tree().get_nodes_in_group("dropped_tools"):
		dropped.append({
			"item": tool_on_ground.item(),
			"position": SaveGame.from_vector(tool_on_ground.global_position),
			"turn": tool_on_ground.rotation.y,
		})
	var bundles: Array = []
	for bundle in get_tree().get_nodes_in_group("item_bundles"):
		bundles.append({"position": SaveGame.from_vector(bundle.global_position), "contents": bundle.contents.duplicate()})
	return {
		"position": SaveGame.from_vector(global_position),
		"turn": rotation.y,
		"look": camera.rotation.x,
		"hunger": hunger,
		"warmth": warmth,
		"inventory": inventory.duplicate(),
		"unlocked": _unlocked.keys().map(func(blueprint): return blueprint.resource_path),
		"notes_read": _notes_read.keys(),
		"dropped_tools": dropped,
		"item_bundles": bundles,
		"done": _done.keys(),
		"torch_left": _torch_left,
	}


func load_data(data: Dictionary) -> void:
	global_position = SaveGame.to_vector(data.get("position", SaveGame.from_vector(global_position)))
	velocity = Vector3.ZERO
	rotation.y = float(data.get("turn", rotation.y))
	camera.rotation.x = float(data.get("look", 0.0))
	hunger = float(data.get("hunger", hunger))
	warmth = float(data.get("warmth", warmth))
	inventory.clear()
	var saved_inventory: Dictionary = data.get("inventory", {})
	for item in saved_inventory:
		inventory[item] = int(saved_inventory[item])
	var unlocked_paths: Array = data.get("unlocked", [])
	_unlocked.clear()
	for blueprint in _all_blueprints():
		if blueprint.resource_path in unlocked_paths:
			_unlocked[blueprint] = true
	_notes_read.clear()
	for title in data.get("notes_read", []):
		_notes_read[str(title)] = true
	_done.clear()
	for entry in data.get("done", []):
		_done[str(entry)] = true
	# Blueprints added since this save was made (like plots, or new furniture) unlock quietly if
	# what they need was already done
	for blueprint in _all_blueprints():
		if blueprint.starts_locked and blueprint.is_met(_done):
			_unlocked[blueprint] = true
	_torch_left = float(data.get("torch_left", 0.0))
	for tool_on_ground in get_tree().get_nodes_in_group("dropped_tools"):
		tool_on_ground.queue_free()
	for entry in data.get("dropped_tools", []):
		var tool_item := ToolItem.find(str(entry.get("item", "")))
		if tool_item:
			var dropped := DroppedTool.create(tool_item)
			get_parent().add_child(dropped)
			dropped.global_position = SaveGame.to_vector(entry.get("position"))
			dropped.rotation.y = float(entry.get("turn", 0.0))
	for bundle in get_tree().get_nodes_in_group("item_bundles"):
		bundle.queue_free()
	for entry in data.get("item_bundles", []):
		var contents := {}
		var saved: Dictionary = entry.get("contents", {})
		for item in saved:
			contents[item] = int(saved[item])
		if not contents.is_empty():
			var bundle := ItemBundle.create(contents)
			get_parent().add_child(bundle)
			bundle.global_position = SaveGame.to_vector(entry.get("position"))
	_refresh_inventory_display()


## True if you've read the note or log with this title
func has_read(title: String) -> bool:
	return _notes_read.has(title)


func _all_blueprints() -> Array[Blueprint]:
	var blueprints: Array[Blueprint] = []
	blueprints.append_array(build_menu.all_buildables())
	blueprints.append_array(inventory_screen.crafting.all_recipes())
	return blueprints


func _process(delta: float) -> void:
	_update_survival(delta)
	_burn_torch(delta)

	# The Crafting tab follows you toward and away from crafting stations while it's open
	if inventory_screen.visible:
		var stations := nearby_stations()
		if stations != _last_stations:
			_refresh_inventory_display()
	# An open chest closes once you walk away from it
	if _open_chest and (not is_instance_valid(_open_chest) or global_position.distance_to(_open_chest.global_position) > CHEST_RANGE):
		if inventory_screen.visible:
			_toggle_inventory()
		else:
			_close_chest()


	# With the hammer out: while the middle button (see _unhandled_input) or X is held, the
	# building piece that would come down glows red
	_placer.update_demolish(delta, _can_demolish(), Input.is_key_pressed(KEY_X))
	# Plot view, with the hammer out: P toggles it, and it's on anyway while the build menu's Plots
	# tab is open and while a plot is being drawn, moved or resized
	_placer.update_plot_view(_plot_view_on())

	if _fps_label.visible:
		var triangles := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_fps_label.text = "%d FPS\n%d triangles" % [Engine.get_frames_per_second(), triangles]
	_update_hud()


# The compact on-screen controls (see HudControls): what E and F would do, under the crosshair,
# and a row of the controls that apply right now above the action bar (with the piece's panel
# while building). Hidden while a menu, a page or sleep covers the view.
func _update_hud() -> void:
	var bar := action_bar.rect_on_screen()
	_hud.set_bar_top(bar.position.y)
	# The compass needle points the way you face (north is -Z); the watch shows the sun's clock
	var facing := -global_basis.z
	var sun = get_tree().get_first_node_in_group("sun")
	_instruments.update_instruments(atan2(facing.x, -facing.z), sun.time_of_day if sun else 0.5, action_bar.first_slot_rect(), bar.end.y, _hud.row_rect())
	var covered: bool = _note_panel.is_open() or _plot_panel.is_open() or _sleeping or inventory_screen.visible or build_menu.visible
	_instruments.show_crosshair(not covered)
	_plot_tracker.show_plot(null if covered else _tracked_plot())
	if covered:
		_hud.set_prompts([])
		_hud.set_controls([])
		_hud.set_info({})
		return
	var prompts := []
	var target = _looked_at()
	if target:
		var what: String = target.get_prompt()
		if target is ResourceNode and target.needs_tool(self):
			what += " (equip the %s)" % target.required_tool
		prompts.append(["E", what])
	_hud.set_prompts(prompts)

	# Eating isn't aimed at anything, so it goes in the controls row, not under the crosshair
	var eat := [["Eat Berries", "F"]] if inventory.get("Berries", 0) > 0 else []
	if held_item == "Hammer":
		var state: Dictionary = _placer.hud_state()
		_hud.set_controls(state["controls"] + eat)
		_hud.set_info(state["info"])
		return
	var controls := []
	if _dowsing and held_item == "Dowsing Rod":
		controls.append(["Dowse for ore", "R"])
	if not held_item.is_empty():
		controls.append(["Drop %s" % held_item, "G"])
	if inventory_screen.crafting.anything_craftable(inventory, nearby_stations(), is_unlocked):
		controls.append(["Craft something", "I"])
	else:
		for item in inventory:
			if ToolItem.exists_for(item) and not action_bar.has_item(item):
				controls.append(["Put tools on the bar", "I"])
				break
	_hud.set_controls(controls + eat)
	_hud.set_info({})


## Opens the plot panel (E aimed inside a plot in plot view calls this)
func open_plot_panel(plot: Plot) -> void:
	if inventory_screen.visible:
		_toggle_inventory()
	_placer.cancel()
	_placer.plots.check(plot)
	_plot_panel.open(plot, held_item == "Hammer")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Asks a yes/no question on the plot panel (shrinking a plot that would lose pieces); one of the
## two is called after
func ask_confirm(question: String, on_yes: Callable, on_no: Callable) -> void:
	_plot_panel.ask(question, on_yes, on_no)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Opens a note, journal or log on the parchment panel. Anything readable calls this.
func read_note(title: String, text: String) -> void:
	if inventory_screen.visible:
		_toggle_inventory()
	_placer.cancel()
	_notes_read[title] = true
	_note_panel.open(title, text)


func _unhandled_input(event: InputEvent) -> void:
	# Asleep: nothing until you wake
	if _sleeping:
		return

	# The plot panel: E or Esc closes it (or cancels its question), unless you're typing its name
	if _plot_panel.is_open():
		var key: bool = event is InputEventKey and event.pressed and not event.echo
		if not _plot_panel.is_typing() and ((key and event.keycode == KEY_E) or event.is_action_pressed("ui_cancel")):
			get_viewport().set_input_as_handled()
			_plot_panel.dismiss()
		return

	# While reading, E or Esc puts the page away, and nothing else happens
	if _note_panel.is_open():
		var close_key: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E
		if close_key or event.is_action_pressed("ui_cancel"):
			_note_panel.close()
		return

	# While the build menu is open, Q and E change tab, Tab or Esc closes it, and nothing else happens
	if build_menu.visible:
		var key: bool = event is InputEventKey and event.pressed and not event.echo
		if key and event.keycode == KEY_Q:
			build_menu.cycle_tab(-1)
		elif key and event.keycode == KEY_E:
			build_menu.cycle_tab(1)
		elif (key and event.keycode == KEY_TAB) or event.is_action_pressed("ui_cancel"):
			_close_build_menu()
		return

	# With the hammer out, placing or not: holding the middle button picks the piece under the
	# crosshair (it glows red), and letting go takes it down
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and _can_demolish():
			_placer.press_demolish()
		elif not event.pressed:
			_placer.release_demolish(_can_demolish())
		return

	# While placing a building, clicks, R and Esc belong to that
	# In plot view, left-click on a plot's edge or corner starts dragging it
	if held_item == "Hammer" and not _placer.is_placing() and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and _plot_view_on() and _placer.try_grab_plot():
		return

	if _placer.is_placing() and _placer.handle_input(event):
		return

	# The mouse wheel moves along the action bar
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			action_bar.cycle(1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			action_bar.cycle(-1)
			return

	# Moving the mouse turns your body left/right and tilts your head up/down
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Esc closes the inventory if it's open, otherwise frees the mouse.
	# Clicking in the window grabs the mouse again (but not while the inventory is open).
	if event.is_action_pressed("ui_cancel"):
		if inventory_screen.visible:
			_toggle_inventory()
		else:
			get_viewport().set_input_as_handled()
			_pause_menu.open()
			return
	elif event is InputEventMouseButton and event.pressed and not inventory_screen.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				# Gather, chop, or feed a fire: whatever you're looking at
				var target = _looked_at()
				if target:
					target.interact(self)
			KEY_F:
				_eat()
			KEY_TAB:
				_open_build_menu()
			KEY_P:
				# Plot view on or off (it shows with the hammer out)
				if held_item == "Hammer":
					_plot_view = not _plot_view
					flash("Plot view on" if _plot_view else "Plot view off")
				else:
					flash("Equip a hammer to see your plots")
			KEY_Z:
				# Snapping on or off for every piece, until pressed again
				if held_item == "Hammer":
					flash("Snapping on" if _placer.toggle_snapping() else "Snapping off")
			KEY_G:
				_drop_held_tool()
			KEY_R:
				if _dowsing:
					_dowsing.pulse()
			KEY_F3:
				_fps_label.visible = not _fps_label.visible
			KEY_I:
				_toggle_inventory()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				action_bar.press(event.keycode - KEY_1)


func _physics_process(delta: float) -> void:
	# Gravity pulls you down when you're in the air
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Space to jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not _sleeping:
		velocity.y = JUMP_VELOCITY

	# WASD to walk (but stand still while reading or asleep)
	var input_dir := Vector2.ZERO
	if not _note_panel.is_open() and not _plot_panel.is_open() and not _sleeping:
		if Input.is_key_pressed(KEY_W): input_dir.y -= 1
		if Input.is_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D): input_dir.x += 1

	# Shift sprints, moving forward or diagonally forward only. It starts only on the ground; a
	# running jump keeps its speed through the air as long as you keep going forward.
	var forward := input_dir.y < 0.0
	if is_on_floor():
		_sprinting = forward and Input.is_key_pressed(KEY_SHIFT) and not _facing_ladder()
	elif not forward:
		_sprinting = false

	# Starving or freezing slows you to a trudge
	var speed := WALK_SPEED
	if _sprinting:
		speed *= SPRINT_MULTIPLIER
	if hunger <= 0.0 or warmth <= 0.0:
		speed *= 0.5
	_ease_sprint_fov(delta)

	# Turn the key presses into movement in the direction you're facing
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# W on a ladder you're facing climbs it; carrying on forward at the top steps you off
	var climbing := input_dir.y < 0.0 and _facing_ladder()
	if climbing:
		velocity.y = CLIMB_SPEED

	# Walking into a low ledge (a floor's edge, a low foundation, a stair step) steps up onto it.
	# That move already covers this frame's walking, so the slide only carries the rest.
	var was_on_floor := is_on_floor()
	var height_before := global_position.y
	if was_on_floor and not climbing and velocity.y <= 0.0 and _try_step_up(delta):
		var walking := velocity
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		velocity.x = walking.x
		velocity.z = walking.z
	else:
		move_and_slide()
		# Walked off a low ledge: straight down onto the ground below instead of a short fall. (Floor
		# snapping alone can't: the body's edge, still brushing the ledge's side, stops its sweep.)
		if was_on_floor and not is_on_floor() and not climbing and velocity.y <= 0.0:
			_step_down()
		# The camera follows the drop smoothly rather than all at once
		var drop := height_before - global_position.y
		if was_on_floor and is_on_floor() and drop > STEP_SMOOTH_DROP:
			_step_offset = minf(_step_offset + drop, STEP_HEIGHT)
	_ease_camera_step(delta)


# Steps up onto a ledge ahead, if it's low enough (STEP_HEIGHT) to walk onto: there's room to
# rise, nothing in the way once risen, and walkable ground on top. A wall too tall to step onto,
# or ground too steep to stand on, stays a wall. True if it stepped.
func _try_step_up(delta: float) -> bool:
	var walking := Vector3(velocity.x, 0, velocity.z)
	if walking.length() < 0.1:
		return false
	# How far this frame's walking goes (at least a little, to feel the ledge while pressed to it)
	var motion := walking * delta
	if motion.length() < STEP_PROBE:
		motion = walking.normalized() * STEP_PROBE
	var start := global_transform
	var blocked := KinematicCollision3D.new()
	if not test_move(start, motion, blocked):
		return false
	# A walkable slope ahead isn't a ledge: walking handles that
	if blocked.get_normal().y >= cos(floor_max_angle):
		return false
	var rise := Vector3.UP * STEP_HEIGHT
	if test_move(start, rise):
		return false
	var raised := start.translated(rise)
	if test_move(raised, motion):
		return false
	# Down onto the ledge's top: it must be there, and flat enough to stand on
	var ahead := raised.translated(motion)
	var landing := KinematicCollision3D.new()
	if not test_move(ahead, -rise, landing):
		return false
	if landing.get_normal().y < cos(floor_max_angle):
		return false
	var spot := ahead.origin + landing.get_travel()
	var up := spot.y - start.origin.y
	if up < STEP_MIN:
		return false
	global_position = spot
	velocity.y = 0.0
	# The camera stays where it was and catches up over a few frames, so the step is smooth
	_step_offset = maxf(_step_offset - up, -STEP_HEIGHT)
	return true


# Just walked off something: if walkable ground is no more than STEP_HEIGHT below your feet
# (found straight down from the body's middle), stand on it now rather than falling
func _step_down() -> void:
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (_half_height + STEP_HEIGHT + 0.05))
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < cos(floor_max_angle):
		return
	var drop: float = (from.y - _half_height) - hit["position"].y
	if drop <= 0.0 or drop > STEP_HEIGHT + 0.01:
		return
	global_position.y -= drop
	velocity.y = 0.0
	apply_floor_snap()


# Widens the view a little while sprinting, easing in and out
func _ease_sprint_fov(delta: float) -> void:
	var target := _base_fov + (SPRINT_FOV if _sprinting else 0.0)
	if not is_equal_approx(camera.fov, target):
		camera.fov = lerpf(camera.fov, target, 1.0 - exp(-SPRINT_FOV_EASE * delta))


# Eases the camera back to its usual height after a step up or down
func _ease_camera_step(delta: float) -> void:
	if is_zero_approx(_step_offset):
		return
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-STEP_CAMERA_EASE * delta))
	if absf(_step_offset) < 0.002:
		_step_offset = 0.0
	camera.position.y = _camera_height + _step_offset


# True if a ladder is right in front of you: what you're looking at, or (looking up past its top
# or down at its foot) just ahead of your body
func _facing_ladder() -> bool:
	if interact_ray.is_colliding():
		var target = interact_ray.get_collider()
		if target is BuildPiece and target.is_ladder() and interact_ray.get_collision_point().distance_to(camera.global_position) < LADDER_REACH + 0.4:
			return true
	for height in [0.3, 1.0]:
		# Measured up from your feet (the body's origin is its middle)
		var from: Vector3 = global_position + Vector3.UP * (height - _half_height)
		var query := PhysicsRayQueryParameters3D.create(from, from - global_basis.z * LADDER_REACH)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] is BuildPiece and hit["collider"].is_ladder():
			return true
	return false


## Shows a short message at the top of the screen
func flash(text: String) -> void:
	_message = text
	_message_time = 2.5


func add_item(item: String, amount: int) -> void:
	inventory[item] = inventory.get(item, 0) + amount
	_refresh_inventory_display()


## True if this item would fit: you already carry some (stacks have no limit), or the backpack
## has a free slot
func has_room_for(item: String) -> bool:
	return inventory.has(item) or action_bar.has_item(item) or _backpack_contents().size() < inventory_screen.slot_count


## Puts these items in your pockets; any that won't fit (backpack full) are left in a bundle on
## the ground at `spot`, for E to pick up later. Returns what was left.
func give_or_drop(items: Dictionary, spot: Vector3) -> Dictionary:
	var left := {}
	for item in items:
		if has_room_for(item):
			add_item(item, items[item])
		else:
			left[item] = items[item]
	if not left.is_empty():
		var bundle := ItemBundle.create(left)
		get_parent().add_child(bundle)
		bundle.global_position = spot
	return left


# The hammer is out and nothing else is in the way (no menu, page or sleep), so demolishing works
func _can_demolish() -> bool:
	return held_item == "Hammer" and not _sleeping and not _note_panel.is_open() and not _plot_panel.is_open() \
			and not _placer.is_plot_mode() and not inventory_screen.visible and not build_menu.visible \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Something gathered from the world (picked, chopped, mined): into your pockets, and it counts
## toward anything that unlocks by gathering it
func gathered(item: String, amount: int) -> void:
	add_item(item, amount)
	flash("+%d %s" % [amount, item])
	report_progress("Gather", item)


## True if this buildable or recipe can be used: it never was locked, or it's been unlocked
func is_unlocked(blueprint: Blueprint) -> bool:
	return not blueprint.starts_locked or _unlocked.has(blueprint)


## Something was crafted, gathered or built ("Craft", "Gather" or "Build", and its name). It's
## remembered, and any blueprint whose conditions are now all met unlocks, with a pop-up for each.
func report_progress(action: String, item: String) -> void:
	_done["%s:%s" % [action, item]] = true
	var learned: PackedStringArray = []
	for blueprint in _all_blueprints():
		if blueprint.starts_locked and not _unlocked.has(blueprint) and blueprint.is_met(_done):
			_unlocked[blueprint] = true
			learned.append(blueprint.display_name)
	if learned.is_empty():
		return
	_refresh_inventory_display()
	# A few are named one per line; many at once (the first planks unlock every building piece)
	# are summed up, so they don't fill the screen
	if learned.size() <= BLUEPRINT_POPUP_LINES:
		_blueprint_label.text = "\n".join(Array(learned).map(func(n): return "New blueprint: %s" % n))
	else:
		_blueprint_label.text = "%d new blueprints: %s and more\nSee the build menu [Tab]" % [learned.size(), ", ".join(learned.slice(0, 2))]
	if _blueprint_tween:
		_blueprint_tween.kill()
	_blueprint_label.modulate.a = 1.0
	_blueprint_tween = create_tween()
	_blueprint_tween.tween_interval(BLUEPRINT_POPUP_TIME)
	_blueprint_tween.tween_property(_blueprint_label, "modulate:a", 0.0, 0.6)


## Sleeps through to morning, if it's night: the screen fades to black, the clock jumps to just
## after sunrise, then it fades back in. A night's sleep costs hunger; you wake up warm only if a
## lit campfire was within reach of where you slept.
func sleep(where: Vector3) -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	if sun == null or _sleeping:
		return
	# Night is when the sun is below the horizon: before sunrise (0.25) or after sunset (0.75)
	if sun.time_of_day > 0.25 and sun.time_of_day < 0.75:
		flash("You can only sleep at night.")
		return
	var warm := false
	for fire in get_tree().get_nodes_in_group("campfires"):
		if fire.is_lit() and where.distance_to(fire.global_position) <= SLEEP_FIRE_RANGE:
			warm = true
	_sleeping = true
	_placer.cancel()
	velocity = Vector3.ZERO
	var night := create_tween()
	night.tween_property(_fade, "modulate:a", 1.0, SLEEP_FADE)
	night.tween_callback(func():
		sun.time_of_day = WAKE_TIME
		hunger = maxf(hunger - SLEEP_HUNGER, 0.0)
		warmth = 100.0 if warm else COLD_WAKE_WARMTH)
	night.tween_interval(SLEEP_DARK)
	night.tween_property(_fade, "modulate:a", 0.0, SLEEP_FADE)
	night.tween_callback(func():
		_sleeping = false
		SaveGame.autosave())


## Takes items out of your pockets. Returns false (and takes nothing) if you don't have enough.
func remove_item(item: String, amount: int) -> bool:
	if inventory.get(item, 0) < amount:
		return false
	inventory[item] -= amount
	if inventory[item] == 0:
		inventory.erase(item)
	_refresh_inventory_display()
	return true


## The thing in front of you (within reach) that E would use, or null
func _looked_at() -> Object:
	var target = interact_ray.get_collider() if interact_ray.is_colliding() else null
	# In plot view, the ground or a building piece inside a plot opens that plot
	if _plot_view_on() and not _placer.is_placing() and (target == null or target is BuildPiece or not target.has_method("interact")):
		var plot := _plot_looked_at()
		if plot:
			return plot
	# Stumps and emptied piles are still there, but have nothing left
	if target and target.has_method("interact") and target.can_interact():
		return target
	if held_item == MineableRock.TOOL:
		return _scattered_rock_looked_at()
	return null


# The plot the tracker shows, with the hammer out: the one aimed at in plot view, or else the one
# you're standing in (of overlapping plots, the one whose middle is nearest); null for none
func _tracked_plot() -> Plot:
	if held_item != "Hammer":
		return null
	var plot: Plot = _plot_looked_at() if _plot_view_on() else null
	if plot == null:
		plot = _placer.plots.find(_placer.plots.owner_for(global_position, global_position))
	return plot


## True while plot view shows: the hammer is out, and P has switched it on, or the build menu's
## Plots tab is open, or a plot is being drawn, moved or resized
func _plot_view_on() -> bool:
	if held_item != "Hammer":
		return false
	return _plot_view or (build_menu.visible and build_menu.current_tab_name() == "Plots") or _placer.is_plot_mode()


# The plot whose ground the crosshair points at (within PLOT_REACH): of overlapping plots, the one
# whose middle is nearest you
func _plot_looked_at() -> Plot:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * PLOT_REACH)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return _placer.plots.find(_placer.plots.owner_for(hit["position"], global_position))


# The valley's scattered rocks have no collision, so the look ray can't see them. Check for one
# between you and whatever the ray did hit, so rocks behind a hillside don't count.
func _scattered_rock_looked_at() -> Object:
	if _foliage == null:
		var valley = get_tree().get_first_node_in_group("valley")
		_foliage = valley.get_node_or_null("Foliage") if valley else null
		if _foliage == null:
			return null
	var from := interact_ray.global_position
	var to := interact_ray.to_global(interact_ray.target_position)
	if interact_ray.is_colliding():
		to = interact_ray.get_collision_point()
	return _foliage.rock_on_line(from, to)


func _update_survival(delta: float) -> void:
	var daylight := 1.0
	var day_seconds := FALLBACK_DAY_SECONDS
	var night_seconds := FALLBACK_NIGHT_SECONDS
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		daylight = sun.daylight
		day_seconds = sun.day_seconds()
		night_seconds = sun.night_seconds()

	# Sprinting works up an appetite
	var appetite := SPRINT_HUNGER if _sprinting and velocity.length() > 0.1 else 1.0
	hunger = maxf(hunger - 100.0 / (FULL_BELLY_DAYS * (day_seconds + night_seconds)) * appetite * delta, 0.0)

	# Chilly at night, slowly warming by day, and quickly warming by a fire
	var night_chill := NIGHT_CHILL_PER_NIGHT / night_seconds
	var day_warmth := DAY_WARMTH_PER_DAY / day_seconds
	var warmth_change := lerpf(-night_chill, day_warmth, daylight)
	# Out of the wind, the cold creeps in much more slowly; shut in a room, not at all
	_check_shelter(delta)
	var sheltered := is_sheltered()
	if sheltered and warmth_change < 0.0:
		warmth_change *= SHELTER_CHILL
	if _enclosed and warmth_change < 0.0:
		warmth_change = 0.0
	# A lit torch in your hand keeps a little of the cold off
	if held_item == "Torch" and warmth_change < 0.0:
		warmth_change *= TORCH_CHILL
	if _near_lit_fire():
		warmth_change = FIRE_WARMTH
	warmth = clampf(warmth + warmth_change * delta, 0.0, 100.0)

	_vitals.set_values(hunger, warmth)

	# A recent message wins; otherwise warn about anything that's run out
	_message_time -= delta
	if _message_time > 0.0:
		status_label.text = _message
	else:
		var warnings: PackedStringArray = []
		if hunger <= 0.0:
			warnings.append("You're starving! Eat something [F]")
		if warmth <= 0.0:
			warnings.append("You're freezing! Get to a fire")
		if warnings.is_empty() and _enclosed:
			warnings.append("Indoors: the cold can't get in here")
		elif warnings.is_empty() and sheltered:
			warnings.append("Sheltered: the cold creeps in slowly here")
		status_label.text = "\n".join(warnings)


## True while standing inside a shelter (any Area3D in the "shelters" group), like the
## intact half of the wreck, or under a roof you've built. Wind and rain will check this too, later.
func is_sheltered() -> bool:
	if _under_roof or _enclosed:
		return true
	for shelter in get_tree().get_nodes_in_group("shelters"):
		if shelter.overlaps_body(self):
			return true
	return false


## True while shut inside a room you've built: floor underneath, walls all round (with any door
## closed) and a roof overhead. The cold can't get in at all.
func is_enclosed() -> bool:
	return _enclosed


# Under a roof, and shut in a room, checked a few times a second with rays: one up for a roof,
# one down for a floor, a ring of them across the room (below window height) that must all meet
# a wall or a closed door, and some up from around the room that must all meet a roof or a
# floor above. Works for round rooms as for square ones.
func _check_shelter(delta: float) -> void:
	_shelter_check_in -= delta
	if _shelter_check_in > 0.0:
		return
	_shelter_check_in = SHELTER_CHECK_SECONDS
	# The body's origin is its middle: the feet are half its height below
	var feet := global_position + Vector3.DOWN * _half_height
	var overhead := _roof_hit(feet + Vector3.UP * 1.6, feet + Vector3.UP * SHELTER_REACH)
	_under_roof = overhead != null and (overhead.is_roof() or overhead.is_floor())
	_enclosed = false
	if not _under_roof:
		return
	var underfoot := _piece_hit(feet + Vector3.UP * 0.3, feet + Vector3.DOWN * 1.0)
	if underfoot == null or not underfoot.is_floor():
		return
	for i in ENCLOSURE_RAYS:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / ENCLOSURE_RAYS)
		var reach := INF
		for height in [0.5, 1.0]:
			var from: Vector3 = feet + Vector3.UP * height
			var hit := _wall_hit(from, from + direction * SHELTER_REACH)
			# A gap, something that isn't part of the building, or a door standing open
			if hit.is_empty() or not hit["collider"] is BuildPiece or not hit["collider"].is_closed():
				return
			reach = minf(reach, from.distance_to(hit["position"]))
		# The ceiling must cover the room, not just the spot you're standing on
		if i % 4 == 0:
			var inside := feet + direction * reach * 0.7 + Vector3.UP * 1.6
			var ceiling := _roof_hit(inside, inside + Vector3.UP * SHELTER_REACH)
			if ceiling == null or not (ceiling.is_roof() or ceiling.is_floor()):
				return
	_enclosed = true


# What a level ray across a room meets, looking past furniture, chimneys and the workbench, chest
# and campfire (things standing in the room, not part of its walls)
func _wall_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = [get_rid()]
	for i in 8:
		query.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return hit
		var other: Object = hit["collider"]
		var in_room: bool = (other is BuildPiece and (other.is_furniture() or other.is_chimney())) \
				or (other is Node and (other as Node).is_in_group("buildings"))
		if not in_room:
			return hit
		skip.append(hit["rid"])
	return {}


# Like _piece_hit, looking up for a roof: chimneys and furniture (a chimney stack passing through
# the roof, a tall shelf) are looked past, so they never break the shelter or enclosure check
func _roof_hit(from: Vector3, to: Vector3) -> BuildPiece:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = [get_rid()]
	for i in 8:
		query.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit["collider"] is BuildPiece:
			return null
		var piece: BuildPiece = hit["collider"]
		if not (piece.is_chimney() or piece.is_furniture()):
			return piece
		skip.append(piece.get_rid())
	return null


# The building piece a line from one point to another meets first, or null if it meets something
# else first (or nothing)
func _piece_hit(from: Vector3, to: Vector3) -> BuildPiece:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit["collider"] is BuildPiece:
		return null
	return hit["collider"]


func _near_lit_fire() -> bool:
	for fire in get_tree().get_nodes_in_group("campfires"):
		if fire.is_lit() and global_position.distance_to(fire.global_position) < fire.heat_radius():
			return true
	return false


func _eat() -> void:
	if hunger >= 100.0:
		flash("You're not hungry")
	elif remove_item("Berries", 1):
		hunger = minf(hunger + BERRY_FOOD, 100.0)
	else:
		flash("You have nothing to eat")


## Where you can craft right now: by hand anywhere, plus every crafting station within reach
## (anything in the "crafting_stations" group, like the workbench, naming its station)
func nearby_stations() -> PackedStringArray:
	var stations: PackedStringArray = ["hand"]
	for station in get_tree().get_nodes_in_group("crafting_stations"):
		if global_position.distance_to(station.global_position) <= STATION_RANGE and not stations.has(station.station):
			stations.append(station.station)
	return stations


## Opens the inventory on its Crafting tab (the workbench does this)
func open_crafting() -> void:
	if not inventory_screen.visible:
		_toggle_inventory()
	inventory_screen.show_tab(true)


## Opens a chest beside the inventory
func open_chest(chest: Node3D) -> void:
	_open_chest = chest
	if not inventory_screen.visible:
		_toggle_inventory()
	inventory_screen.show_chest(chest.contents)


func _close_chest() -> void:
	_open_chest = null
	inventory_screen.hide_chest()


# A whole stack moving between the backpack and the open chest, if there's room for it
func _move_item(item: String, from: String) -> void:
	if _open_chest == null or not is_instance_valid(_open_chest):
		return
	if from == "chest":
		if _backpack_contents().size() >= inventory_screen.slot_count and not inventory.has(item):
			flash("Inventory full")
			return
		add_item(item, _open_chest.take_all(item))
	else:
		if not _open_chest.can_take(item):
			flash("The chest is full")
			return
		var amount: int = inventory.get(item, 0)
		if remove_item(item, amount):
			_open_chest.put(item, amount)
	_refresh_inventory_display()


# A torch in your hand burns down; when it's out, it's gone and the next one is ready to light
func _burn_torch(delta: float) -> void:
	if held_item != "Torch":
		return
	var burn_time := TORCH_NIGHTS * FALLBACK_NIGHT_SECONDS
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		burn_time = TORCH_NIGHTS * sun.night_seconds()
	if _torch_left <= 0.0:
		_torch_left = burn_time
	_torch_left -= delta
	if _torch_left <= 0.0:
		_torch_left = 0.0
		remove_item("Torch", 1)
		flash("Your torch burned out")


## Makes a recipe: takes the resources and puts the result in the backpack. If there's no room,
## says so and spends nothing.
func craft(recipe: Recipe) -> void:
	if not is_unlocked(recipe) or not recipe.can_craft(inventory) or not nearby_stations().has(recipe.station):
		return
	var crafting: Control = inventory_screen.crafting
	if _backpack_contents().size() >= inventory_screen.slot_count and not inventory.has(recipe.result):
		crafting.show_status("Inventory full", true)
		return
	for item in recipe.costs:
		remove_item(item, recipe.costs[item])
	add_item(recipe.result, recipe.result_amount)
	crafting.show_status("%s added to your inventory" % recipe.display_name, false)
	report_progress("Craft", recipe.result)


# What's in your hand changed: swap the model in front of the view to match
func _on_held_changed(item: String) -> void:
	# Whatever you were placing needed the hammer you've just let go of
	_placer.cancel()
	held_item = item
	for model in held_items.get_children():
		model.queue_free()
	var tool_item := ToolItem.find(item)
	if tool_item:
		held_items.add_child(tool_item.make_held_model())


# Sets the tool in your hand down on the ground in front of you, for E to pick up again
func _drop_held_tool() -> void:
	var tool_item := ToolItem.find(held_item)
	if tool_item == null:
		return
	var spot := global_position - global_basis.z * DROP_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 4.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		spot = hit["position"]
	var dropped := DroppedTool.create(tool_item)
	get_parent().add_child(dropped)
	dropped.global_position = spot
	dropped.rotation.y = rotation.y
	remove_item(held_item, 1)


# Opens the build menu. While placing something, what you were placing is put aside: picking
# something else switches to it (keeping the height and turn), closing the menu goes back to it.
func _open_build_menu() -> void:
	if inventory_screen.visible:
		return
	if held_item != "Hammer":
		flash("Equip a hammer to build")
		return
	if _placer.is_placing():
		_build_resume = _placer.current_buildable()
		# Moving or resizing a plot: finish that first
		if _build_resume == null:
			return
		_placer.cancel()
	build_menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# Closes the build menu without picking anything: back to whatever was being placed
func _close_build_menu() -> void:
	build_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _build_resume:
		var resume := _build_resume
		_build_resume = null
		_placer.begin(resume, true)


func _on_buildable_chosen(buildable: Buildable) -> void:
	var switching := _build_resume != null
	_build_resume = null
	_close_build_menu()
	_placer.begin(buildable, switching)


## Opens the backpack (freeing the mouse) or closes it (grabbing the mouse again).
## The game keeps running either way.
func _toggle_inventory() -> void:
	_placer.cancel()
	inventory_screen.visible = not inventory_screen.visible
	action_bar.set_editing(inventory_screen.visible)
	if inventory_screen.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Closing the inventory closes any chest that was open beside it
		_close_chest()


## Call this whenever the inventory changes, so the action bar, the backpack and the build menu
## all stay current. The backpack shows only what isn't on the bar.
func _refresh_inventory_display() -> void:
	action_bar.forget_missing(inventory)
	inventory_screen.show_items(_backpack_contents())
	_last_stations = nearby_stations()
	inventory_screen.crafting.refresh(inventory, _last_stations, is_unlocked)
	build_menu.refresh(inventory, is_unlocked)
	if _open_chest and is_instance_valid(_open_chest):
		inventory_screen.show_chest(_open_chest.contents)


# Everything you own, minus whatever's on the action bar
func _backpack_contents() -> Dictionary:
	var in_backpack := inventory.duplicate()
	for item in action_bar.items:
		in_backpack.erase(item)
	return in_backpack
