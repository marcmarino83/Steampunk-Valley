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
## Wood it takes to build a campfire
const CAMPFIRE_COST = 3

const CAMPFIRE_SCENE = preload("res://campfire.tscn")

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var prompt_label: Label = $HUD/Prompt
@onready var inventory_label: Label = $HUD/Inventory
@onready var hunger_bar: ProgressBar = $HUD/Meters/HungerBar
@onready var warmth_bar: ProgressBar = $HUD/Meters/WarmthBar
@onready var status_label: Label = $HUD/Status
@onready var inventory_screen: Control = $HUD/InventoryScreen

## What you're carrying, like {"Scrap": 3, "Coal": 1}
var inventory := {}
## 100 = full, 0 = starving
var hunger := 100.0
## 100 = toasty, 0 = freezing
var warmth := 100.0

# A short message shown at the top of the screen, and how long it has left
var _message := ""
var _message_time := 0.0


func _ready() -> void:
	# Hide the mouse and lock it to the window so it can steer the camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The look ray starts inside your own body, so tell it to ignore you
	interact_ray.add_exception(self)
	_refresh_inventory_display()


func _process(delta: float) -> void:
	_update_survival(delta)

	# Show "[E] ..." while you're looking at something you can use
	var target = _looked_at()
	prompt_label.visible = target != null
	if target:
		prompt_label.text = "[E] %s" % target.get_prompt()


func _unhandled_input(event: InputEvent) -> void:
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
			KEY_B:
				_build_campfire()
			KEY_TAB, KEY_I:
				_toggle_inventory()


func _physics_process(delta: float) -> void:
	# Gravity pulls you down when you're in the air
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Space to jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# WASD to walk
	var input_dir := Vector2.ZERO
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
	return null


func _update_survival(delta: float) -> void:
	hunger = maxf(hunger - HUNGER_DRAIN * delta, 0.0)

	# Chilly at night, slowly warming by day, and quickly warming by a fire
	var daylight := 1.0
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		daylight = sun.daylight
	var warmth_change := lerpf(-NIGHT_CHILL, DAY_WARMTH, daylight)
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
		status_label.text = "\n".join(warnings)


func _near_lit_fire() -> bool:
	for fire in get_tree().get_nodes_in_group("campfires"):
		if fire.is_lit() and global_position.distance_to(fire.global_position) < fire.warmth_radius:
			return true
	return false


func _eat() -> void:
	if hunger >= 100.0:
		flash("You're not hungry")
	elif remove_item("Berries", 1):
		hunger = minf(hunger + BERRY_FOOD, 100.0)
	else:
		flash("You have nothing to eat")


func _build_campfire() -> void:
	if not remove_item("Wood", CAMPFIRE_COST):
		flash("A campfire needs %d Wood" % CAMPFIRE_COST)
		return

	# Set it down on the ground a couple of steps in front of you
	var spot := global_position - global_basis.z * 2.0
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3.0, spot + Vector3.DOWN * 5.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		spot = hit["position"]

	var fire := CAMPFIRE_SCENE.instantiate()
	get_parent().add_child(fire)
	fire.global_position = spot
	flash("Campfire built. Look at it and press E to add Coal")


## Opens the backpack (freeing the mouse) or closes it (grabbing the mouse again).
## The game keeps running either way.
func _toggle_inventory() -> void:
	inventory_screen.visible = not inventory_screen.visible
	if inventory_screen.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Call this whenever the inventory changes, so the counter and the backpack both stay current
func _refresh_inventory_display() -> void:
	inventory_screen.show_items(inventory)

	if inventory.is_empty():
		inventory_label.text = "Carrying nothing"
		return
	var lines: PackedStringArray = []
	for item in inventory:
		lines.append("%s: %d" % [item, inventory[item]])
	inventory_label.text = "\n".join(lines)
