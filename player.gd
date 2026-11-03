extends CharacterBody3D

const WALK_SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var prompt_label: Label = $HUD/Prompt
@onready var inventory_label: Label = $HUD/Inventory

## What you're carrying, like {"Scrap": 3, "Coal": 1}
var inventory := {}


func _ready() -> void:
	# Hide the mouse and lock it to the window so it can steer the camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The look ray starts inside your own body, so tell it to ignore you
	interact_ray.add_exception(self)
	_update_inventory_label()


func _process(_delta: float) -> void:
	# Show "[E] Gather ..." while you're looking at something gatherable
	var target := _looked_at_resource()
	prompt_label.visible = target != null
	if target:
		prompt_label.text = "[E] %s" % target.get_prompt()


func _unhandled_input(event: InputEvent) -> void:
	# Moving the mouse turns your body left/right and tilts your head up/down
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Esc frees the mouse; clicking in the window grabs it again
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# E gathers whatever you're looking at
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var target := _looked_at_resource()
		if target:
			var amount := target.gather()
			# Some things (like trees) take a few hits before giving anything
			if amount > 0:
				_add_to_inventory(target.resource_name, amount)


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

	# Turn the key presses into movement in the direction you're facing
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * WALK_SPEED
	velocity.z = direction.z * WALK_SPEED

	move_and_slide()


## The gatherable thing in front of you (within reach), or null
func _looked_at_resource() -> ResourceNode:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider() as ResourceNode
		# Stumps and emptied piles are still there, but have nothing left
		if target and target.gathers_left > 0:
			return target
	return null


func _add_to_inventory(item: String, amount: int) -> void:
	inventory[item] = inventory.get(item, 0) + amount
	_update_inventory_label()


func _update_inventory_label() -> void:
	if inventory.is_empty():
		inventory_label.text = "Carrying nothing"
		return
	var lines: PackedStringArray = []
	for item in inventory:
		lines.append("%s: %d" % [item, inventory[item]])
	inventory_label.text = "\n".join(lines)
