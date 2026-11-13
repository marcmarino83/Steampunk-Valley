class_name PlayerMovement
extends Node
## How the player's body moves: walking, sprinting and its view widening, jumping, stepping up
## and down low ledges and the camera easing after, climbing ladders, and the fly cheat. A child
## of the player (see player.gd), which calls physics_update each physics frame; looking around
## with the mouse stays on the player.

const WALK_SPEED = 5.0
const JUMP_VELOCITY = 4.5
## Sprinting (hold Shift, going forward): how much faster than walking, how many degrees wider
## the view gets and how quickly it eases there (how much faster hunger drains: see Survival)
const SPRINT_MULTIPLIER := 1.7
const SPRINT_FOV := 7.0
const SPRINT_FOV_EASE := 8.0
## Flying with the fly cheat: how fast (m/s), and how much faster with Shift
const FLY_SPEED := 10.0
const FLY_FAST := 4.0
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

## What it moves and reads, set by the player: the body, its camera and look ray, and survival
## (stamina, winded, slowed)
var body: CharacterBody3D
var camera: Camera3D
var interact_ray: RayCast3D
var survival: Survival
## True while you can't do anything (asleep, or typing in the developer console), and while you
## can't walk (that, or a panel open)
var frozen: Callable
var held_still: Callable
## Sprinting right now (Shift held, going forward, started on the ground)
var sprinting := false
## The camera's usual height on the body, and half the body's height (its origin is its middle,
## so your feet are this far below it)
var camera_height := 0.0
var half_height := 1.0

# How far the camera lags behind after a step (eases to 0), and the usual view angle
var _step_offset := 0.0
var _base_fov := 75.0


## Called from the player's _ready, before anything reads the heights or the view angle
func setup() -> void:
	# Walking off a low ledge keeps you on the ground (no hop); a jump still lifts you off
	body.floor_snap_length = STEP_HEIGHT
	camera_height = camera.position.y
	_base_fov = GameSettings.fov
	camera.fov = _base_fov
	half_height = (body.get_node("CollisionShape3D").shape as CylinderShape3D).height / 2.0


## Each physics frame (from the player's _physics_process)
func physics_update(delta: float) -> void:
	# The fly cheat: free flying through everything
	if DevCheats.fly:
		_fly(delta)
		return

	# Gravity pulls you down when you're in the air
	if not body.is_on_floor():
		body.velocity += body.get_gravity() * delta

	# Space to jump (not while typing in the developer console)
	if Input.is_action_just_pressed("ui_accept") and body.is_on_floor() and not frozen.call():
		body.velocity.y = JUMP_VELOCITY
		survival.spend_stamina(Survival.JUMP_STAMINA)

	# WASD to walk (but stand still while reading, asleep, or typing in the developer console)
	var input_dir := Vector2.ZERO
	if not held_still.call():
		if Input.is_key_pressed(KEY_W): input_dir.y -= 1
		if Input.is_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D): input_dir.x += 1

	# Shift sprints, moving forward or diagonally forward only. It starts only on the ground; a
	# running jump keeps its speed through the air as long as you keep going forward.
	var forward := input_dir.y < 0.0
	# Out of stamina, you can't sprint until it's come back a little.
	if body.is_on_floor():
		sprinting = forward and Input.is_key_pressed(KEY_SHIFT) and not _facing_ladder() \
				and not survival.winded
	elif not forward:
		sprinting = false
	if sprinting and survival.winded:
		sprinting = false
	if sprinting and body.velocity.length() > 0.1:
		survival.spend_stamina(Survival.SPRINT_STAMINA * delta)

	# Starving (or freezing, while warmth is on) slows you to a trudge
	var speed := WALK_SPEED
	if sprinting:
		speed *= SPRINT_MULTIPLIER
	if survival.slowed():
		speed *= 0.5
	_ease_sprint_fov(delta)

	# Turn the key presses into movement in the direction you're facing
	var direction := (body.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	body.velocity.x = direction.x * speed
	body.velocity.z = direction.z * speed

	# W on a ladder you're facing climbs it; carrying on forward at the top steps you off
	var climbing := input_dir.y < 0.0 and _facing_ladder()
	if climbing:
		body.velocity.y = CLIMB_SPEED

	# Walking into a low ledge (a floor's edge, a low foundation, a stair step) steps up onto it.
	# That move already covers this frame's walking, so the slide only carries the rest.
	var was_on_floor := body.is_on_floor()
	var height_before := body.global_position.y
	if was_on_floor and not climbing and body.velocity.y <= 0.0 and _try_step_up(delta):
		var walking := body.velocity
		body.velocity.x = 0.0
		body.velocity.z = 0.0
		body.move_and_slide()
		body.velocity.x = walking.x
		body.velocity.z = walking.z
	else:
		body.move_and_slide()
		# Walked off a low ledge: straight down onto the ground below instead of a short fall.
		# (Floor snapping alone can't: the body's edge, still brushing the ledge's side, stops
		# its sweep.)
		if was_on_floor and not body.is_on_floor() and not climbing and body.velocity.y <= 0.0:
			_step_down()
		# The camera follows the drop smoothly rather than all at once
		var drop := height_before - body.global_position.y
		if was_on_floor and body.is_on_floor() and drop > STEP_SMOOTH_DROP:
			_step_offset = minf(_step_offset + drop, STEP_HEIGHT)
	_ease_camera_step(delta)


# Flying (the fly cheat): WASD along the way you look, Space up, Ctrl down, Shift faster, passing
# straight through the ground and everything else
func _fly(delta: float) -> void:
	var move := Vector3.ZERO
	if not frozen.call():
		var look := camera.global_basis
		if Input.is_key_pressed(KEY_W): move -= look.z
		if Input.is_key_pressed(KEY_S): move += look.z
		if Input.is_key_pressed(KEY_A): move -= look.x
		if Input.is_key_pressed(KEY_D): move += look.x
		if Input.is_key_pressed(KEY_SPACE): move += Vector3.UP
		if Input.is_key_pressed(KEY_CTRL): move += Vector3.DOWN
	var speed := FLY_SPEED * (FLY_FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	body.velocity = move.normalized() * speed if move != Vector3.ZERO else Vector3.ZERO
	body.global_position += body.velocity * delta
	sprinting = false
	_ease_sprint_fov(delta)


# Steps up onto a ledge ahead, if it's low enough (STEP_HEIGHT) to walk onto: there's room to
# rise, nothing in the way once risen, and walkable ground on top. A wall too tall to step onto,
# or ground too steep to stand on, stays a wall. True if it stepped.
func _try_step_up(delta: float) -> bool:
	var walking := Vector3(body.velocity.x, 0, body.velocity.z)
	if walking.length() < 0.1:
		return false
	# How far this frame's walking goes (at least a little, to feel the ledge while pressed to it)
	var motion := walking * delta
	if motion.length() < STEP_PROBE:
		motion = walking.normalized() * STEP_PROBE
	var start := body.global_transform
	var blocked := KinematicCollision3D.new()
	if not body.test_move(start, motion, blocked):
		return false
	# A walkable slope ahead isn't a ledge: walking handles that
	if blocked.get_normal().y >= cos(body.floor_max_angle):
		return false
	var rise := Vector3.UP * STEP_HEIGHT
	if body.test_move(start, rise):
		return false
	var raised := start.translated(rise)
	if body.test_move(raised, motion):
		return false
	# Down onto the ledge's top: it must be there, and flat enough to stand on
	var ahead := raised.translated(motion)
	var landing := KinematicCollision3D.new()
	if not body.test_move(ahead, -rise, landing):
		return false
	if landing.get_normal().y < cos(body.floor_max_angle):
		return false
	var spot := ahead.origin + landing.get_travel()
	var up := spot.y - start.origin.y
	if up < STEP_MIN:
		return false
	body.global_position = spot
	body.velocity.y = 0.0
	# The camera stays where it was and catches up over a few frames, so the step is smooth
	_step_offset = maxf(_step_offset - up, -STEP_HEIGHT)
	return true


# Just walked off something: if walkable ground is no more than STEP_HEIGHT below your feet
# (found straight down from the body's middle), stand on it now rather than falling
func _step_down() -> void:
	var from := body.global_position
	var query := PhysicsRayQueryParameters3D.create(from,
			from + Vector3.DOWN * (half_height + STEP_HEIGHT + 0.05))
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < cos(body.floor_max_angle):
		return
	var drop: float = (from.y - half_height) - hit["position"].y
	if drop <= 0.0 or drop > STEP_HEIGHT + 0.01:
		return
	body.global_position.y -= drop
	body.velocity.y = 0.0
	body.apply_floor_snap()


# Widens the view a little while sprinting, easing in and out
func _ease_sprint_fov(delta: float) -> void:
	# The Field of view setting, wider while sprinting
	_base_fov = GameSettings.fov
	var target := _base_fov + (SPRINT_FOV if sprinting else 0.0)
	if not is_equal_approx(camera.fov, target):
		camera.fov = lerpf(camera.fov, target, 1.0 - exp(-SPRINT_FOV_EASE * delta))


# Eases the camera back to its usual height after a step up or down
func _ease_camera_step(delta: float) -> void:
	if is_zero_approx(_step_offset):
		return
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-STEP_CAMERA_EASE * delta))
	if absf(_step_offset) < 0.002:
		_step_offset = 0.0
	camera.position.y = camera_height + _step_offset


# True if a ladder is right in front of you: what you're looking at, or (looking up past its top
# or down at its foot) just ahead of your body
func _facing_ladder() -> bool:
	if interact_ray.is_colliding():
		var target = interact_ray.get_collider()
		if target is BuildPiece and target.is_ladder() \
				and interact_ray.get_collision_point().distance_to(camera.global_position) \
				< LADDER_REACH + 0.4:
			return true
	for height in [0.3, 1.0]:
		# Measured up from your feet (the body's origin is its middle)
		var from: Vector3 = body.global_position + Vector3.UP * (height - half_height)
		var query := PhysicsRayQueryParameters3D.create(from,
				from - body.global_basis.z * LADDER_REACH)
		query.exclude = [body.get_rid()]
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] is BuildPiece and hit["collider"].is_ladder():
			return true
	return false
