extends CharacterBody3D

const WALK_SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

## Hunger lost per second. A full belly lasts about 4 in-game days.
const HUNGER_DRAIN = 0.2
## How much hunger one berry fills back up
const BERRY_FOOD = 15.0
## Warmth lost per second in the dead of night, and gained back at midday
const NIGHT_CHILL = 1.5
const DAY_WARMTH = 0.3
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

const NOTE_PANEL_SCENE = preload("res://note_panel.tscn")

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var prompt_label: Label = $HUD/Prompt
@onready var held_items: Node3D = $Camera3D/HeldItems
@onready var hunger_bar: ProgressBar = $HUD/Meters/HungerBar
@onready var warmth_bar: ProgressBar = $HUD/Meters/WarmthBar
@onready var status_label: Label = $HUD/Status
@onready var inventory_screen: Control = $HUD/InventoryScreen
@onready var hints_label: Label = $HUD/Hints
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
var _blueprint_tween: Tween
# Sleeping: the black screen it fades to, and whether you're asleep right now
var _fade: ColorRect
var _sleeping := false


func _ready() -> void:
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
	# Last, so the black of sleep covers everything
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_fade)
	_placer = BuildPlacer.new()
	add_child(_placer)
	if IronTier.ENABLED:
		_dowsing = load("res://iron_tier/dowsing.gd").new()
		add_child(_dowsing)
	build_menu.chosen.connect(_on_buildable_chosen)
	action_bar.held_changed.connect(_on_held_changed)
	action_bar.contents_changed.connect(_refresh_inventory_display)
	inventory_screen.tool_returned.connect(action_bar.remove)
	inventory_screen.crafting.craft_requested.connect(craft)
	_refresh_inventory_display()


func _exit_tree() -> void:
	ToolItem.forget_all()


func _process(delta: float) -> void:
	_update_survival(delta)

	# Show "[E] ..." while you're looking at something you can use
	var target = null if _note_panel.is_open() or _sleeping else _looked_at()
	prompt_label.visible = target != null
	if target:
		prompt_label.text = "[E] %s" % target.get_prompt()
		if target is ResourceNode and target.needs_tool(self):
			prompt_label.text += " (equip the %s)" % target.required_tool

	if _fps_label.visible:
		var triangles := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_fps_label.text = "%d FPS\n%d triangles" % [Engine.get_frames_per_second(), triangles]
	_update_hints()


# The key hints in the corner only list what you can actually do right now
func _update_hints() -> void:
	if _placer.is_placing():
		hints_label.text = "\n".join(_placer.hints())
		return
	var hints: PackedStringArray = []
	if inventory.get("Berries", 0) > 0:
		hints.append("[F] Eat Berries")
	if held_item == "Hammer":
		hints.append("[Tab] Build")
	if _dowsing and held_item == "Dowsing Rod":
		hints.append("[R] Dowse for buried ore")
	if not held_item.is_empty():
		hints.append("[G] Drop %s" % held_item)
	if inventory_screen.crafting.anything_craftable(inventory, nearby_stations(), is_unlocked):
		hints.append("[I] You can craft something")
	for item in inventory:
		if ToolItem.exists_for(item) and not action_bar.has_item(item):
			hints.append("[I] Drag tools onto the action bar to use them")
			break
	hints_label.text = "\n".join(hints)


## Opens a note, journal or log on the parchment panel. Anything readable calls this.
func read_note(title: String, text: String) -> void:
	if inventory_screen.visible:
		_toggle_inventory()
	_placer.cancel()
	_note_panel.open(title, text)


func _unhandled_input(event: InputEvent) -> void:
	# Asleep: nothing until you wake
	if _sleeping:
		return

	# While reading, E or Esc puts the page away, and nothing else happens
	if _note_panel.is_open():
		var close_key: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E
		if close_key or event.is_action_pressed("ui_cancel"):
			_note_panel.close()
		return

	# While the build menu is open, Tab or Esc closes it, and nothing else happens
	if build_menu.visible:
		var close_key: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB
		if close_key or event.is_action_pressed("ui_cancel"):
			_close_build_menu()
		return

	# While placing a building, clicks, R and Esc belong to that
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
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	if not _note_panel.is_open() and not _sleeping:
		if Input.is_key_pressed(KEY_W): input_dir.y -= 1
		if Input.is_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D): input_dir.x += 1

	# Starving or freezing slows you to a trudge
	var speed := WALK_SPEED
	if hunger <= 0.0 or warmth <= 0.0:
		speed *= 0.5

	# Turn the key presses into movement in the direction you're facing
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	move_and_slide()


## Shows a short message at the top of the screen
func flash(text: String) -> void:
	_message = text
	_message_time = 2.5


func add_item(item: String, amount: int) -> void:
	inventory[item] = inventory.get(item, 0) + amount
	_refresh_inventory_display()


## Something gathered from the world (picked, chopped, mined): into your pockets, and it counts
## toward anything that unlocks by gathering it
func gathered(item: String, amount: int) -> void:
	add_item(item, amount)
	report_progress("Gather", item)


## True if this buildable or recipe can be used: it never was locked, or it's been unlocked
func is_unlocked(blueprint: Blueprint) -> bool:
	return not blueprint.starts_locked or _unlocked.has(blueprint)


## Something was crafted, gathered or built ("Craft", "Gather" or "Build", and its name). Unlocks
## any blueprint waiting on exactly that, with a pop-up for each.
func report_progress(action: String, item: String) -> void:
	var blueprints: Array[Blueprint] = []
	blueprints.append_array(build_menu.all_buildables())
	blueprints.append_array(inventory_screen.crafting.all_recipes())
	var learned: PackedStringArray = []
	for blueprint in blueprints:
		if not _unlocked.has(blueprint) and blueprint.unlocks_on(action, item):
			_unlocked[blueprint] = true
			learned.append(blueprint.display_name)
	if learned.is_empty():
		return
	_refresh_inventory_display()
	_blueprint_label.text = "\n".join(Array(learned).map(func(n): return "New blueprint: %s" % n))
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
	night.tween_callback(func(): _sleeping = false)


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
	if interact_ray.is_colliding():
		var target = interact_ray.get_collider()
		# Stumps and emptied piles are still there, but have nothing left
		if target and target.has_method("interact") and target.can_interact():
			return target
	if held_item == MineableRock.TOOL:
		return _scattered_rock_looked_at()
	return null


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
	hunger = maxf(hunger - HUNGER_DRAIN * delta, 0.0)

	# Chilly at night, slowly warming by day, and quickly warming by a fire
	var daylight := 1.0
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		daylight = sun.daylight
	var warmth_change := lerpf(-NIGHT_CHILL, DAY_WARMTH, daylight)
	# Out of the wind, the cold creeps in much more slowly
	var sheltered := is_sheltered()
	if sheltered and warmth_change < 0.0:
		warmth_change *= SHELTER_CHILL
	if _near_lit_fire():
		warmth_change = FIRE_WARMTH
	warmth = clampf(warmth + warmth_change * delta, 0.0, 100.0)

	hunger_bar.value = hunger
	warmth_bar.value = warmth

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
		if warnings.is_empty() and sheltered:
			warnings.append("Sheltered: the cold creeps in slowly here")
		status_label.text = "\n".join(warnings)


## True while standing inside a shelter (any Area3D in the "shelters" group), like the
## intact half of the wreck. Wind and rain will check this too, later.
func is_sheltered() -> bool:
	for shelter in get_tree().get_nodes_in_group("shelters"):
		if shelter.overlaps_body(self):
			return true
	return false


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


## Where you can craft right now. Everything can be made by hand; when there are workbenches
## and forges, add "workbench" or "forge" here while you're near one, and the recipes with
## that station will show up by themselves.
func nearby_stations() -> PackedStringArray:
	return ["hand"]


## Makes a recipe: takes the resources and puts the result in the backpack. If there's no room,
## says so and spends nothing.
func craft(recipe: Recipe) -> void:
	if not recipe.can_craft(inventory):
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


func _open_build_menu() -> void:
	if inventory_screen.visible:
		return
	if held_item != "Hammer":
		flash("Equip a hammer to build")
		return
	build_menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_build_menu() -> void:
	build_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_buildable_chosen(buildable: Buildable) -> void:
	_close_build_menu()
	_placer.begin(buildable)


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


## Call this whenever the inventory changes, so the action bar, the backpack and the build menu
## all stay current. The backpack shows only what isn't on the bar.
func _refresh_inventory_display() -> void:
	action_bar.forget_missing(inventory)
	inventory_screen.show_items(_backpack_contents())
	inventory_screen.crafting.refresh(inventory, nearby_stations(), is_unlocked)
	build_menu.refresh(inventory, is_unlocked)


# Everything you own, minus whatever's on the action bar
func _backpack_contents() -> Dictionary:
	var in_backpack := inventory.duplicate()
	for item in action_bar.items:
		in_backpack.erase(item)
	return in_backpack
