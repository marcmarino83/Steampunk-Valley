extends CharacterBody3D

const MOUSE_SENSITIVITY = 0.002
## (walking, sprinting, jumping, stepping, ladders and flying: see PlayerMovement; hunger,
## stamina, warmth, sleeping and the torch: see Survival)
## How far in front of you a dropped tool lands
const DROP_DISTANCE := 1.2


@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var held_items: Node3D = $Camera3D/HeldItems
@onready var status_label: Label = $HUD/Status
@onready var inventory_screen: Control = $HUD/InventoryScreen
@onready var build_menu: Control = $HUD/BuildMenu
@onready var action_bar: ActionBar = $HUD/ActionBar

## What you own (see PlayerInventory, which keeps it): the same dictionary, for whatever reads it
var inventory: Dictionary:
	get:
		return _inventory.items
# Everything you own, and adding, taking, room and paying (a child node, see PlayerInventory)
var _inventory := PlayerInventory.new()
## What's in your hand, or an empty string
var held_item := ""
# Hunger, stamina, warmth, shelter, eating, sleeping and the torch (a child node, see Survival),
# and the values the console sets and the spike logger reads on the player
var _survival := Survival.new()
var hunger: float:
	get:
		return _survival.hunger
	set(value):
		_survival.hunger = value
var warmth: float:
	get:
		return _survival.warmth
	set(value):
		_survival.warmth = value
var stamina: float:
	get:
		return _survival.stamina
	set(value):
		_survival.stamina = value
var _sleeping: bool:
	get:
		return _survival.sleeping

# The heads-up display: the status line and its messages, the vitals panel, compass and watch,
# controls row and prompts, plot tracker and frames-per-second label (a child node, see PlayerHud)
var _ui := PlayerHud.new()
# The panels that open over the game (a child node, see PanelHost: the plot panel, a settler's
# panel, the Village screen, the note page, the pause menu and the banner)
var _panels := PanelHost.new()
# The hammer's controls (the build menu, ghosts, demolishing, plot view) and what the crosshair is
# on (child nodes, see BuildControls and Interaction)
var _build := BuildControls.new()
var _interaction := Interaction.new()
# Walking, sprinting, jumping, stepping, ladders and flying (a child node, see PlayerMovement),
# and the heights tests and the console read on the player: the camera's usual height on the
# body, and half the body's height (your feet are this far below its middle)
var _movement := PlayerMovement.new()
var _camera_height: float:
	get:
		return _movement.camera_height
var _half_height: float:
	get:
		return _movement.half_height
# The dowsing rod's pulse, which only exists while the iron tier is switched on
var _dowsing: Node
# Handles putting a building down, once one's been chosen from the build menu
var _placer: BuildPlacer
# What you've done, the blueprints you've unlocked and the notes you've read (a child node, see
# Progress); the unlocked blueprints also as `_unlocked`, for the console's unlock_all
var _progress := Progress.new()
var _unlocked: Dictionary:
	get:
		return _progress.unlocked
# The "New blueprint" pop-up
var _blueprint_popup: BlueprintPopup
# The black screen sleep fades through
var _fade: SleepFade
# What's open beside the inventory (a chest or town storage), and crafting and the stations in
# reach (child nodes, see ContainerSession and PlayerCrafting)
var _containers := ContainerSession.new()
var _crafting := PlayerCrafting.new()
# The developer console (debug builds only; null otherwise)
var _console: DevConsole
# The bug snapshot key's (F9, debug builds only)
var _bug_snapshot: BugSnapshot
# The settlers
var _settlers: SettlerManager


func _ready() -> void:
	# The player's settings (read in on the title screen; here too when the world is run directly)
	GameSettings.ensure_loaded()
	# How the body moves (its step height, the camera's height and the view angle set up first)
	_movement.name = "Movement"
	_movement.body = self
	_movement.camera = camera
	_movement.interact_ray = interact_ray
	_movement.survival = _survival
	_movement.frozen = func(): return _sleeping or _console_open()
	_movement.held_still = func(): return _panels.any_open() or _sleeping or _console_open()
	_movement.setup()
	add_child(_movement)
	# Hide the mouse and lock it to the window so it can steer the camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The look ray starts inside your own body, so tell it to ignore you
	interact_ray.add_exception(self)
	# So things like campfires can check what you're carrying
	add_to_group("player")
	# What you own (the views showing it watch it, below)
	_inventory.name = "Inventory"
	_inventory.action_bar = action_bar
	_inventory.inventory_screen = inventory_screen
	_inventory.world = get_parent()
	add_child(_inventory)
	# Debug builds: the lag spike logger (it writes nothing until it's turned on in Settings)
	if OS.is_debug_build():
		get_parent().add_child.call_deferred(SpikeLog.new())
		# The bug snapshot key (F9)
		_bug_snapshot = BugSnapshot.new()
		_bug_snapshot.player = self
		add_child(_bug_snapshot)
	# The heads-up display (see PlayerHud.build for where each part is drawn)
	_ui.name = "Hud"
	_ui.body = self
	_ui.held = func(): return held_item
	_ui.inventory = _inventory
	_ui.action_bar = action_bar
	_ui.inventory_screen = inventory_screen
	_ui.build_menu = build_menu
	_ui.panels = _panels
	_ui.survival = _survival
	_ui.interaction = _interaction
	_ui.crafting = _crafting
	_ui.progress = _progress
	_ui.status_label = status_label
	add_child(_ui)
	_ui.build($HUD)
	_blueprint_popup = BlueprintPopup.new()
	$HUD.add_child(_blueprint_popup)
	# What you've done and learned (the crafting tab and build menu watch it, and the pop-up shows
	# what's newly unlocked: below)
	_progress.name = "Progress"
	_progress.blueprints = _all_blueprints
	add_child(_progress)
	# Last, so the black of sleep covers everything
	_fade = SleepFade.new()
	# Hunger, stamina, warmth and sleep: the vitals panel follows them; falling asleep stops any
	# placing and stands you still
	_survival.name = "Survival"
	_survival.body = self
	_survival.half_height = _half_height
	_survival.inventory = _inventory
	_survival.fade = _fade
	add_child(_survival)
	_survival.message.connect(flash)
	_survival.vitals_changed.connect(_ui.vitals.set_values)
	_survival.fell_asleep.connect(func():
		_placer.cancel()
		velocity = Vector3.ZERO)
	$HUD.add_child(_fade)
	_placer = BuildPlacer.new()
	add_child(_placer)
	_ui.placer = _placer
	# Every building look drawn once behind a brief cover, so no shader compiles mid-game
	_warm_up_shaders.call_deferred()
	_placer.plots.became_working.connect(func(plot):
		_panels.show_banner("%s is working" % plot.plot_name))
	_placer.plots.notice.connect(_ui.announce)
	_settlers = SettlerManager.new()
	_settlers.world = get_parent()
	_settlers.plots = _placer.plots
	add_child(_settlers)
	_settlers.arrived.connect(func(settler):
		_ui.announce("A refugee named %s has arrived." % settler.settler_name))
	_settlers.notice.connect(_ui.announce)
	_settlers.visitor_arrived.connect(func(visitor):
		_panels.show_banner("A visitor has arrived",
				"%s is waiting at the Village Center" % visitor.settler_name))
	_placer.plots.town.notice.connect(_ui.announce)
	_ui.plot_tracker.settlers = _settlers
	_ui.plot_tracker.plots = _placer.plots
	_ui.plot_tracker.carrying = func(): return inventory
	# The panels that open over the game (see PanelHost), in the HUD where they've always been drawn
	_panels.name = "Panels"
	_panels.placer = _placer
	_panels.settlers = _settlers
	_panels.is_unlocked = _progress.is_unlocked
	_panels.save_template = save_template
	_panels.flash = flash
	_panels.mark_read = _progress.mark_read
	_panels.hammer_out = func(): return held_item == "Hammer"
	_panels.before_open = func():
		if inventory_screen.visible:
			_toggle_inventory()
		_placer.cancel()
	add_child(_panels)
	_panels.build($HUD, _fade, _ui.fps_label)
	if IronTier.ENABLED:
		_dowsing = load("res://iron_tier/dowsing.gd").new()
		add_child(_dowsing)
		_ui.dowsing = _dowsing
	# The hammer's controls around the placer, and what the crosshair is on
	var hammer_out := func(): return held_item == "Hammer"
	_build.name = "BuildControls"
	_build.placer = _placer
	_build.build_menu = build_menu
	_build.inventory_screen = inventory_screen
	_build.panels = _panels
	_build.survival = _survival
	_build.hammer_out = hammer_out
	_build.flash = flash
	add_child(_build)
	_build.setup()
	_interaction.name = "Interaction"
	_interaction.body = self
	_interaction.camera = camera
	_interaction.interact_ray = interact_ray
	_interaction.placer = _placer
	_interaction.build = _build
	_interaction.held = func(): return held_item
	add_child(_interaction)
	action_bar.held_changed.connect(_on_held_changed)
	inventory_screen.tool_returned.connect(action_bar.remove)
	# What's open beside the inventory (a chest or town storage): it asks for the inventory to open,
	# and to close when you walk away
	_containers.name = "Containers"
	_containers.body = self
	_containers.inventory = _inventory
	_containers.inventory_screen = inventory_screen
	_containers.action_bar = action_bar
	add_child(_containers)
	_containers.open_requested.connect(_toggle_inventory)
	_containers.walked_away.connect(func():
		if inventory_screen.visible:
			_toggle_inventory()
		else:
			_containers.close())
	_containers.message.connect(flash)
	inventory_screen.item_moved.connect(_containers.move_item)
	inventory_screen.deposit_requested.connect(_containers.deposit)
	# Crafting: the Crafting tab follows you toward and away from crafting stations
	_crafting.name = "Crafting"
	_crafting.body = self
	_crafting.inventory = _inventory
	_crafting.progress = _progress
	_crafting.inventory_screen = inventory_screen
	add_child(_crafting)
	inventory_screen.crafting.craft_requested.connect(_crafting.craft)
	# Everything that shows what you own brings itself up to date when it changes, in this order:
	# the action bar, the backpack, the crafting tab, the build menu, an open chest's panel; newly
	# unlocked blueprints show in the pop-up once the menus are up to date
	action_bar.watch(_inventory)
	inventory_screen.watch(_inventory, action_bar)
	inventory_screen.crafting.watch(_inventory, _crafting, _progress)
	build_menu.watch(_inventory, _progress)
	_inventory.changed.connect(_containers.refresh)
	_progress.learned.connect(_blueprint_popup.show_learned)
	_inventory.notify()
	# The developer console: debug builds only (never in a release build). Its cheats start off.
	DevCheats.reset()
	if OS.is_debug_build():
		_console = DevConsole.new()
		_console.player = self
		$HUD.add_child(_console)
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
	var data := {
		"position": SaveGame.from_vector(global_position),
		"turn": rotation.y,
		"look": camera.rotation.x,
		"inventory": inventory.duplicate(),
		"dropped_tools": dropped,
		"item_bundles": bundles,
	}
	# (Survival's "hunger", "warmth", "stamina" and "torch_left", and Progress's "unlocked",
	# "notes_read" and "done", as before)
	data.merge(_survival.save_data())
	data.merge(_progress.save_data())
	return data


func load_data(data: Dictionary) -> void:
	global_position = SaveGame.to_vector(data.get("position", SaveGame.from_vector(global_position)))
	velocity = Vector3.ZERO
	rotation.y = float(data.get("turn", rotation.y))
	camera.rotation.x = float(data.get("look", 0.0))
	_survival.load_data(data)
	inventory.clear()
	var saved_inventory: Dictionary = data.get("inventory", {})
	for item in saved_inventory:
		inventory[item] = int(saved_inventory[item])
	_progress.load_data(data)
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
	# (everything that shows what you own and what you've unlocked brings itself up to date)
	_inventory.notify()


func _all_blueprints() -> Array[Blueprint]:
	var blueprints: Array[Blueprint] = []
	blueprints.append_array(build_menu.all_buildables())
	blueprints.append_array(inventory_screen.crafting.all_recipes())
	return blueprints


func _process(delta: float) -> void:
	# Hunger, stamina, shelter and warmth (and the vitals panel), then the status line, then the
	# torch in your hand
	var holding_torch := held_item == "Torch"
	_survival.update(delta, _movement.sprinting and velocity.length() > 0.1, holding_torch)
	_ui.update_status(delta)
	_survival.burn_torch(delta, holding_torch)

	# The Crafting tab follows you toward and away from crafting stations while it's open
	if inventory_screen.visible:
		_crafting.follow_stations()
	# An open chest (or town storage) closes once you walk away from it, or once town storage has
	# no working Storehouse left
	_containers.follow()

	# With the hammer out: demolishing, ghosts and plot view (see BuildControls.update)
	_build.update(delta)
	# The frames-per-second label and the rest of the HUD (see PlayerHud.update)
	_ui.update()


## Opens the plot panel (E aimed inside a plot in plot view calls this; see PanelHost)
func open_plot_panel(plot: Plot) -> void:
	_panels.open_plot_panel(plot)


# Once the world's first frame is up (the camera exists by then)
func _warm_up_shaders() -> void:
	await get_tree().process_frame
	ShaderWarmup.run(get_parent(), _placer.registry)


## Saves everything a plot owns (ghosts included) as a template under a name, with a rendered
## picture: into the project as a built-in one (debug builds only), or into your own templates.
## The build menu's Buildings tab lists it straight away.
func save_template(plot: Plot, template_name: String, built_in: bool) -> void:
	var template := BuildingTemplate.from_plot(_placer.plots, plot, template_name)
	if template == null:
		flash("Nothing to save: build something in %s first" % plot.plot_name)
		return
	var picture: Image = await TemplateThumbnail.render(self, _placer.registry, template)
	var saved := template.write(built_in and OS.is_debug_build(), picture)
	if saved.is_empty():
		flash("Couldn't save the template")
		return
	build_menu.reload_templates()
	flash("Saved the template \"%s\" (%d pieces)%s" % [template_name, template.items.size(), ", built in" if template.built_in else ""], 4.0)


# (PanelHost's own functions, which settlers, notes, plots and the plot placer call on the player)
func open_settler_panel(settler: Settler) -> void:
	_panels.open_settler_panel(settler)


func ask_confirm(question: String, on_yes: Callable, on_no: Callable) -> void:
	_panels.ask_confirm(question, on_yes, on_no)


func read_note(title: String, text: String) -> void:
	_panels.read_note(title, text)


# While placing, the mouse wheel turns what's being placed, taken here before the screen can
# swallow it, and never moving along the action bar (see BuildControls.wheel_input)
func _input(event: InputEvent) -> void:
	_build.wheel_input(event, _sleeping or _console_open())


func _unhandled_input(event: InputEvent) -> void:
	# Asleep: nothing until you wake. Typing in the developer console: nothing else either.
	if _sleeping or _console_open():
		return

	# An open panel (the plot panel, a settler's, the Village screen, the note page) has the keys
	if _panels.handle_input(event):
		return

	# The open build menu has the keys (see BuildControls.menu_input)
	if _build.menu_input(event):
		return

	# The inventory: Q and R switch between its Inventory and Crafting tabs, E closes it
	if inventory_screen.visible and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				inventory_screen.show_tab(false)
				return
			KEY_R:
				inventory_screen.show_tab(true)
				return
			KEY_E:
				_toggle_inventory()
				return

	# The hammer's clicks (demolishing, ghosts, dragging a plot's edge) and whatever's being placed
	if _build.hammer_input(event):
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
	# (as fast as the Mouse sensitivity setting says, and the other way up with Invert Y)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var turn := MOUSE_SENSITIVITY * GameSettings.mouse_sensitivity
		rotate_y(-event.relative.x * turn)
		camera.rotate_x(-event.relative.y * turn * (-1.0 if GameSettings.invert_y else 1.0))
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Esc closes the inventory if it's open, otherwise frees the mouse.
	# Clicking in the window grabs the mouse again (but not while the inventory is open).
	if event.is_action_pressed("ui_cancel"):
		if inventory_screen.visible:
			_toggle_inventory()
		else:
			get_viewport().set_input_as_handled()
			_panels.open_pause_menu()
			return
	elif event is InputEventMouseButton and event.pressed and not inventory_screen.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				# Gather, chop, or feed a fire: whatever you're looking at
				var target = _interaction.looked_at()
				if target:
					target.interact(self)
			KEY_F:
				_survival.eat()
			KEY_TAB:
				_build.open_build_menu()
			KEY_V:
				_panels.open_village()
			KEY_P:
				_build.toggle_plot_view()
			KEY_G:
				_drop_held_tool()
			KEY_R:
				if _dowsing:
					_dowsing.pulse()
			KEY_F3:
				_ui.toggle_fps()
			KEY_F8:
				# Debug builds only: the console's spawn_settler (a refugee arrives in front of you)
				if _console:
					_console.run("spawn_settler")
			KEY_F9:
				# Debug builds only: a bug snapshot (a brighter screenshot, the camera, the piece
				# under the crosshair and the whole game, in docs/reference/ours; see BugSnapshot)
				if _bug_snapshot:
					_bug_snapshot.take()
			KEY_F10:
				# Debug builds only: the console's day (skip to the next dawn)
				if _console:
					_console.run("day")
			KEY_I:
				_toggle_inventory()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				action_bar.press(event.keycode - KEY_1)


func _physics_process(delta: float) -> void:
	# Walking, jumping, stepping, ladders and flying (see PlayerMovement)
	_movement.physics_update(delta)


func _console_open() -> bool:
	return _console != null and _console.is_open()


## Shows a short message at the top of the screen (everything in the world calls this on the
## player: see PlayerHud.flash)
func flash(text: String, seconds := 2.5) -> void:
	_ui.flash(text, seconds)


# (the inventory's own functions, kept here for whatever calls them on the player: see
# PlayerInventory)
func add_item(item: String, amount: int) -> void:
	_inventory.add(item, amount)


func has_room_for(item: String) -> bool:
	return _inventory.has_room_for(item)


func give_or_drop(items: Dictionary, spot: Vector3) -> Dictionary:
	return _inventory.give_or_drop(items, spot)


# (what the crosshair is on: the build placer asks the player, see Interaction.looked_at)
func _looked_at() -> Object:
	return _interaction.looked_at()


## Something gathered from the world (picked, chopped, mined): into your pockets, and it counts
## toward anything that unlocks by gathering it
func gathered(item: String, amount: int) -> void:
	add_item(item, amount)
	flash("+%d %s" % [amount, item])
	report_progress("Gather", item)


# (Progress's own functions, which the plots and the placers call on the player: see Progress)
func has_done(action: String, item: String) -> bool:
	return _progress.has_done(action, item)


## Something was crafted, gathered or built, or a plot of a type is working (see Progress.report):
## newly unlocked blueprints refresh the menus and show in the pop-up
func report_progress(action: String, item: String) -> void:
	_progress.report(action, item)


## Sleeps through to morning, if it's night (see Survival.sleep; the lean-to's mat calls this)
func sleep(where: Vector3) -> void:
	_survival.sleep(where)


## (see PlayerInventory.pay)
func pay(cost: Dictionary) -> Dictionary:
	return _inventory.pay(cost)


## (see PlayerInventory.remove)
func remove_item(item: String, amount: int) -> bool:
	return _inventory.remove(item, amount)


# (Survival's own functions, which rocks, trees and the console call on the player: see Survival)
func max_stamina() -> float:
	return _survival.max_stamina()


func swing_tool() -> bool:
	return _survival.swing_tool()


## Opens the inventory on its Crafting tab (the workbench does this)
func open_crafting() -> void:
	if not inventory_screen.visible:
		_toggle_inventory()
	inventory_screen.show_tab(true)


## Opens a chest beside the inventory (see ContainerSession)
func open_chest(chest: Node3D) -> void:
	_containers.open(chest, chest)


## Opens the Town Storage screen beside the inventory (E on the Storehouse Storage in a working
## Storehouse): the whole shared pool, whichever shelf it's opened at (see ContainerSession)
func open_town_storage(shelf: Node3D) -> void:
	_containers.open(_placer.plots.town, shelf)


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


## Opens the backpack (freeing the mouse) or closes it (grabbing the mouse again).
## The game keeps running either way.
func _toggle_inventory() -> void:
	_placer.cancel()
	var timing := SpikeLog.begin()
	inventory_screen.visible = not inventory_screen.visible
	SpikeLog.end("inventory opened or closed", timing)
	action_bar.set_editing(inventory_screen.visible)
	if inventory_screen.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Closing the inventory closes any chest that was open beside it
		_containers.close()


## Brings everything that shows what you own and what you've unlocked up to date, after the
## console changed them directly (see PlayerInventory.notify)
func _refresh_inventory_display() -> void:
	_inventory.notify()
