class_name Settler
extends CharacterBody3D
## A settler: a refugee who lives in a House and works at a workplace plot. A simple low-poly
## placeholder figure in refugee clothing (colours, hair and build vary per settler, see `look`),
## walking about with Godot navigation (see SettlementNav).
##
## Daily routine (by the sun's clock): by day they walk to their job and work at its furniture
## (bending to it, now and then wandering a little inside the plot); in the evening they walk home
## and idle there; at night they sleep in their bed. With no job they idle around their home; with
## no home they sleep by the nearest campfire or fireplace (or where they stand, if there's none).
## If their workplace isn't working, they idle there and say why ("Can't work: missing door").
## They open closed doors as they pass through, and close the ones they opened behind them.
##
## Aim at one and press E to talk: their panel shows their name, home, job and what they're doing,
## and lets you assign a home and a job (see SettlerPanel).

## Their collision layer (3): not solid to the player, but the player's look ray finds them
const LAYER := 4
const WALK_SPEED := 1.7
const GRAVITY := 12.0
## The sun's clock: work from WORK_START to WORK_END, sleep from SLEEP_START until WAKE
const WAKE := 0.26
const WORK_START := 0.28
const WORK_END := 0.7
const SLEEP_START := 0.78
## How close counts as arrived, and how close to the bed or fire before lying down
const ARRIVE := 0.6
const LIE_DOWN_REACH := 1.6
## At work: how long they work at the furniture, and how long a wander inside the plot lasts
const WORK_SPELL := Vector2(12.0, 25.0)
const WANDER_SPELL := Vector2(5.0, 9.0)
## Idling about: how long they stand before strolling somewhere else nearby
const IDLE_SPELL := Vector2(6.0, 14.0)
## How often they think about what to do next, in seconds
const PLAN_SECONDS := 0.5
## Doors: opened within this distance while walking, closed again past the second
const DOOR_OPEN_REACH := 1.8
const DOOR_CLOSE_REACH := 2.8
## Stuck: no real progress for this long makes them hop (a step), then skip ahead
const STUCK_HOP := 1.5
const STUCK_SKIP := 6.0
## The highest ledge they step up onto without hopping (a floor laid on the ground, a threshold)
const STEP_HEIGHT := 0.5

## Their id (kept in saves), name, and look (colours as [r, g, b], height, hair style, bundle)
var settler_id := ""
var settler_name := ""
var look := {}
## The plot ids of their House and their workplace (empty: none)
var home_id := ""
var job_id := ""
## Their manager (plots, beds, fires)
var manager: Node
## Days in a row they've gone without their evening meal (0: fed). Hungry workers make half.
var hungry_days := 0
## Leaving the settlement for good (walking off toward `leave_to`, for `leave_time` seconds so far)
var leaving := false
var leave_to := Vector3.ZERO
var leave_time := 0.0

var _agent: NavigationAgent3D
var _model: Node3D
var _hips: Node3D
var _torso: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _head: Node3D
# What they're doing: "walk", "work", "idle", "sleep"
var _activity := "idle"
var _status := "Idle"
# Where they're heading, and which way to face on arriving (NAN: no matter)
var _goal := Vector3.INF
var _face_yaw := NAN
# Their current plan's kind, so a new plan of the same kind doesn't restart their spell
var _plan_kind := ""
var _spell_left := 0.0
var _at_main_spot := true
var _plan_in := 0.0
var _phase := 0.0
var _rng := RandomNumberGenerator.new()
# The bed or fire they're lying at (and how), while asleep
var _lying := false
var _doors_opened: Array[BuildPiece] = []
var _door_check_in := 0.0
var _last_spot := Vector3.ZERO
var _stuck_for := 0.0


## Makes a new settler's look from a seed (colours, height, hair, a bundle on the back or not)
static func make_look(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tunics := [Color(0.42, 0.33, 0.24), Color(0.33, 0.4, 0.48), Color(0.36, 0.42, 0.3), Color(0.46, 0.45, 0.42),
			Color(0.55, 0.32, 0.22), Color(0.58, 0.49, 0.29), Color(0.43, 0.22, 0.21), Color(0.3, 0.33, 0.36)]
	var trousers := [Color(0.27, 0.22, 0.17), Color(0.22, 0.22, 0.23), Color(0.33, 0.29, 0.23), Color(0.24, 0.27, 0.3), Color(0.36, 0.33, 0.29)]
	var scarves := [Color(0.5, 0.18, 0.2), Color(0.66, 0.5, 0.24), Color(0.25, 0.42, 0.42), Color(0.78, 0.73, 0.62), Color(0.4, 0.3, 0.45), Color(0.3, 0.36, 0.24)]
	var skins := [Color(0.95, 0.8, 0.68), Color(0.88, 0.68, 0.53), Color(0.74, 0.54, 0.4), Color(0.56, 0.39, 0.27), Color(0.38, 0.26, 0.19)]
	var hairs := [Color(0.08, 0.07, 0.06), Color(0.2, 0.13, 0.08), Color(0.36, 0.23, 0.13), Color(0.5, 0.22, 0.12), Color(0.7, 0.58, 0.36), Color(0.62, 0.6, 0.57)]
	var pick := func(list: Array) -> Array:
		var c: Color = list[rng.randi() % list.size()]
		var shade := rng.randf_range(0.9, 1.08)
		return [clampf(c.r * shade, 0, 1), clampf(c.g * shade, 0, 1), clampf(c.b * shade, 0, 1)]
	return {
		"tunic": pick.call(tunics),
		"trousers": pick.call(trousers),
		"scarf": pick.call(scarves),
		"skin": pick.call(skins),
		"hair": pick.call(hairs),
		"hair_style": rng.randi() % 4,
		"height": rng.randf_range(0.9, 1.06),
		"build": rng.randf_range(0.9, 1.12),
		"bundle": rng.randf() < 0.5,
	}


func _ready() -> void:
	add_to_group("settlers")
	collision_layer = LAYER
	collision_mask = 1
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	_rng.seed = hash(settler_id)
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7 * float(look.get("height", 1.0))
	body.shape = capsule
	body.position.y = capsule.height / 2.0
	add_child(body)
	_agent = NavigationAgent3D.new()
	_agent.radius = SettlementNav.AGENT_RADIUS
	_agent.height = SettlementNav.AGENT_HEIGHT
	_agent.path_desired_distance = 0.5
	_agent.target_desired_distance = ARRIVE
	_agent.path_max_distance = 4.0
	add_child(_agent)
	_build_model()
	_last_spot = global_position


## What they're doing, for their panel: "Working at Forager's Hut", "Sleeping", "Idle: no job"
func status_text() -> String:
	return _status


func is_sleeping() -> bool:
	return _activity == "sleep"


## True after a dusk with no meal (until they eat their fill again)
func is_hungry() -> bool:
	return hungry_days > 0


## "Fed", or "Hungry (2 days)"
func food_text() -> String:
	if not is_hungry():
		return "Fed"
	return "Hungry (%d %s)" % [hungry_days, "day" if hungry_days == 1 else "days"]


## Leaves the settlement for good, walking off toward a spot (the manager removes them on the way)
func leave(toward: Vector3) -> void:
	_get_up()
	leaving = true
	leave_to = toward
	leave_time = 0.0
	_plan_kind = "leave"
	_status = "Leaving the settlement"
	_goal = manager.nav.closest_point(toward)


# ---- Talking (E aimed at them) ----

func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "Talk to %s" % settler_name


func interact(player) -> void:
	player.open_settler_panel(self)


# ---- Thinking and moving ----

func _physics_process(delta: float) -> void:
	var timing := SpikeLog.begin()
	_think_and_move(delta)
	SpikeLog.end("settlers (thinking, paths, moving)", timing)


func _think_and_move(delta: float) -> void:
	_plan_in -= delta
	_spell_left -= delta
	if _plan_in <= 0.0:
		_plan_in = PLAN_SECONDS
		_plan()
	_door_check_in -= delta
	if _door_check_in <= 0.0:
		_door_check_in = 0.25
		_handle_doors()
	if _lying:
		_animate(delta, 0.0)
		return
	var move := Vector3.ZERO
	if _goal != Vector3.INF and manager and manager.nav.is_ready_at(global_position):
		if _agent.target_position.distance_to(_goal) > 0.3:
			_agent.target_position = _goal
		var flat_to_goal := Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length()
		if flat_to_goal > ARRIVE and not _agent.is_navigation_finished():
			var next := _agent.get_next_path_position()
			move = next - global_position
			move.y = 0.0
			if move.length() > 0.05:
				move = move.normalized()
	if move != Vector3.ZERO:
		_activity = "walk"
		velocity.x = move.x * WALK_SPEED
		velocity.z = move.z * WALK_SPEED
		rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z), 1.0 - exp(-8.0 * delta))
		_check_stuck(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * 6.0 * delta)
		_stuck_for = 0.0
		if _activity == "walk":
			_activity = "work" if _plan_kind == "work" and _at_main_spot else "idle"
		if not is_nan(_face_yaw):
			rotation.y = lerp_angle(rotation.y, _face_yaw, 1.0 - exp(-5.0 * delta))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	# A low step in the way (a floor's edge, a doorway's threshold): step up onto it, or hop if
	# stepping can't
	if move != Vector3.ZERO and is_on_wall() and not _step_up(move):
		if is_on_floor() and _clear_ahead(move, 0.65):
			velocity.y = 4.2
	_animate(delta, Vector2(velocity.x, velocity.z).length())


# Steps up onto a ledge no higher than STEP_HEIGHT just ahead, if there's room to stand on it.
# True if it stepped.
func _step_up(direction: Vector3) -> bool:
	var ahead := direction.normalized() * 0.35
	var probe := global_transform.translated(Vector3.UP * STEP_HEIGHT)
	# Room above the step, moving forward at step height
	if test_move(probe, ahead):
		return false
	# Where the step's top is
	var from := global_position + ahead + Vector3.UP * (STEP_HEIGHT + 0.05)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (STEP_HEIGHT + 0.1), 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var rise: float = hit["position"].y - global_position.y
	if rise < 0.02 or rise > STEP_HEIGHT:
		return false
	global_position += Vector3.UP * (rise + 0.01) + ahead * 0.3
	return true


# True if nothing solid is just ahead at this height (doors don't count)
func _clear_ahead(direction: Vector3, height: float) -> bool:
	var from := global_position + Vector3.UP * height
	var query := PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * 0.6, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["collider"] is BuildPiece and hit["collider"].is_door())


# No real progress while walking: hop (a step or a lip in the way); still stuck, skip ahead along
# the path
func _check_stuck(delta: float) -> void:
	# Only real progress along the ground counts (hopping on the spot doesn't)
	if Vector2(global_position.x - _last_spot.x, global_position.z - _last_spot.z).length() > 0.4:
		_last_spot = global_position
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for > STUCK_SKIP:
		_stuck_for = 0.0
		var next := _agent.get_next_path_position()
		global_position = next + Vector3.UP * 0.1
		_last_spot = global_position
	elif _stuck_for > STUCK_HOP and is_on_floor() and fmod(_stuck_for, 1.0) < delta * 1.5:
		velocity.y = 3.6


# Decides what to do now: sleep, work, or idle, and where
func _plan() -> void:
	if manager == null:
		return
	# Fallen through the ground somehow: back up onto it
	if not _lying and global_position.y < Plot.ground_at(self, global_position.x, global_position.z) - 2.0:
		global_position = manager.standing_spot(global_position)
		velocity = Vector3.ZERO
	if leaving:
		leave_time += PLAN_SECONDS
		_status = "Leaving the settlement"
		_goal = manager.nav.closest_point(leave_to)
		return
	var sun = get_tree().get_first_node_in_group("sun")
	var t: float = sun.time_of_day if sun else 0.5
	var home: Plot = manager.plot(home_id)
	var job: Plot = manager.plot(job_id)
	if t >= SLEEP_START or t < WAKE:
		_plan_sleep(home)
		return
	_get_up()
	if t >= WORK_START and t < WORK_END and job:
		if job.working:
			_plan_work(job)
			return
		_plan_idle(job, "Can't work: %s" % _reason(job))
		return
	if home:
		var evening := t >= WORK_END
		_plan_idle(home, "Relaxing at home" if evening else ("Idle: no job" if job == null else "At home"))
		return
	_plan_idle(null, "Idle: no home" if job else "Idle: no home or job")


func _reason(plot: Plot) -> String:
	if plot.missing.is_empty():
		return "not working"
	return "missing %s" % ", ".join(plot.missing)


func _plan_work(job: Plot) -> void:
	var furniture: Node3D = manager.work_furniture(job)
	if furniture == null:
		_plan_idle(job, "Can't work: no %s" % job.plot_type.work_at.to_lower())
		return
	if _plan_kind != "work":
		_plan_kind = "work"
		_at_main_spot = true
		_spell_left = _rng.randf_range(WORK_SPELL.x, WORK_SPELL.y)
		_set_goal(_work_spot(furniture), furniture)
	elif _spell_left <= 0.0:
		_at_main_spot = not _at_main_spot
		if _at_main_spot:
			_spell_left = _rng.randf_range(WORK_SPELL.x, WORK_SPELL.y)
			_set_goal(_work_spot(furniture), furniture)
		else:
			_spell_left = _rng.randf_range(WANDER_SPELL.x, WANDER_SPELL.y)
			_set_goal(_wander_spot(job, furniture.global_position, 2.5), null)
	var arrived := _arrived()
	_status = ("Working at %s" % job.plot_name) if arrived else ("Walking to %s" % job.plot_name)
	if arrived and _at_main_spot:
		_activity = "work"
	elif arrived:
		_activity = "idle"


func _plan_idle(area: Plot, status: String) -> void:
	var kind := "idle:%s" % (area.plot_id if area else "")
	if _plan_kind != kind or _spell_left <= 0.0:
		_plan_kind = kind
		_spell_left = _rng.randf_range(IDLE_SPELL.x, IDLE_SPELL.y)
		if area:
			_set_goal(_wander_spot(area, area.global_position, 99.0), null)
		else:
			var fire: Node3D = manager.nearest_fire(global_position)
			var middle: Vector3 = fire.global_position if fire else global_position
			_set_goal(manager.nav.closest_point(middle + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))), null)
	if area and not _arrived() and global_position.distance_to(area.global_position) > maxf(area.size.x, area.size.y):
		_status = "Heading home" if area.plot_id == home_id else "Walking to %s" % area.plot_name
	else:
		_status = status


func _plan_sleep(home: Plot) -> void:
	var bed: BuildPiece = manager.bed_for(self) if home else null
	var fire: Node3D = null if bed else manager.nearest_fire(global_position)
	var kind := "sleep:%s" % (str(bed.get_instance_id()) if bed else (str(fire.get_instance_id()) if fire else "ground"))
	if _plan_kind != kind:
		_get_up()
		_plan_kind = kind
		if bed:
			_set_goal(_bed_side(bed), null)
		elif fire:
			_set_goal(_fire_side(fire), null)
		else:
			_goal = Vector3.INF
	if _lying:
		return
	var at: Vector3 = bed.global_position if bed else (fire.global_position if fire else global_position)
	var close := global_position.distance_to(at) < LIE_DOWN_REACH + (1.2 if bed else 0.6) or _arrived() or (bed == null and fire == null)
	if close:
		_lie_down(bed, fire)
	else:
		_status = "Heading to bed" if bed else "Heading to the fire to sleep"


func _set_goal(spot: Vector3, face: Node3D) -> void:
	_goal = spot
	_face_yaw = NAN
	if face:
		var to := face.global_position - spot
		_face_yaw = atan2(-to.x, -to.z)


func _arrived() -> bool:
	return _goal == Vector3.INF or Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length() <= ARRIVE + 0.2


# Where a worker stands: in front of the furniture (or beside it, if the front is blocked)
func _work_spot(furniture: Node3D) -> Vector3:
	var depth := 0.6
	if furniture is BuildPiece:
		var box := PieceShapes.bounds_of(furniture.shape_def())
		depth = maxf(box.size.z, box.size.x) / 2.0
	var best := furniture.global_position
	var best_gap := INF
	for side in [Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]:
		var wanted: Vector3 = furniture.global_transform * (side * (depth + 0.45))
		var found: Vector3 = manager.nav.closest_point(wanted)
		var gap := found.distance_to(wanted)
		if gap < 0.25:
			return found
		if gap < best_gap:
			best_gap = gap
			best = found
	return best


# A random walkable spot inside a plot (kept a little in from its edges), within `reach` of a point
func _wander_spot(plot: Plot, near: Vector3, reach: float) -> Vector3:
	for i in 8:
		var x := _rng.randf_range(-plot.size.x / 2.0 + 0.8, plot.size.x / 2.0 - 0.8)
		var z := _rng.randf_range(-plot.size.y / 2.0 + 0.8, plot.size.y / 2.0 - 0.8)
		var spot := plot.global_transform * Vector3(x, 0, z)
		spot.y = near.y
		if spot.distance_to(near) > reach:
			continue
		var found: Vector3 = manager.nav.closest_point(spot + Vector3.UP * 1.0)
		if plot.contains(found):
			return found
	return manager.nav.closest_point(near)


func _bed_side(bed: BuildPiece) -> Vector3:
	var half := PieceShapes.bounds_of(bed.shape_def()).size.x / 2.0
	var best := bed.global_position
	var best_gap := INF
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK]:
		var wanted: Vector3 = bed.global_transform * (side * (half + 0.45) + Vector3(0, 0, 0.3 if side != Vector3.BACK else 1.4))
		var found: Vector3 = manager.nav.closest_point(wanted)
		var gap := found.distance_to(wanted)
		if gap < best_gap:
			best_gap = gap
			best = found
	return best


func _fire_side(fire: Node3D) -> Vector3:
	var away := global_position - fire.global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	var front := fire.global_transform.basis.z if fire is BuildPiece else away.normalized()
	return manager.nav.closest_point(fire.global_position + front.normalized() * 1.6)


# Lies down: in the bed (on its mattress, head to the headboard), or on the ground by the fire
# (feet to it), or where they stand
func _lie_down(bed: BuildPiece, fire: Node3D) -> void:
	_lying = true
	_activity = "sleep"
	_status = "Sleeping"
	_goal = Vector3.INF
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	# Close the doors they opened on the way, unless someone else is in them
	for door in _doors_opened:
		if is_instance_valid(door) and not door.is_closed() and not manager.anyone_near(door.global_position, DOOR_OPEN_REACH * 0.6):
			door.set_open(false)
	_doors_opened.clear()
	var flat := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, PI / 2.0)
	if bed:
		var box := PieceShapes.bounds_of(bed.shape_def())
		var length := 1.7 * float(look.get("height", 1.0))
		global_transform = Transform3D(bed.global_basis * flat, bed.global_transform * Vector3(0, box.size.y * 0.8, length / 2.0 - 0.02))
		return
	var yaw := rotation.y
	var spot := global_position
	if fire:
		var away := global_position - fire.global_position
		away.y = 0.0
		if away.length() > 0.1:
			# Feet toward the fire: the body runs away from it
			yaw = atan2(away.x, away.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw) * flat, spot + Vector3.UP * 0.14)


func _get_up() -> void:
	if not _lying:
		return
	_lying = false
	var yaw := global_basis.get_euler().y
	var spot := global_position
	# Step off the bed to its side
	var bed: BuildPiece = manager.bed_for(self) if manager else null
	if bed and spot.distance_to(bed.global_position) < 2.0:
		spot = _bed_side(bed)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), spot + Vector3.UP * 0.05)
	collision_layer = LAYER
	collision_mask = 1
	_plan_kind = ""


# Opens closed doors they're about to walk through (doors never block them), and closes the ones
# they opened once they're past
func _handle_doors() -> void:
	var moving := _activity == "walk"
	for door in manager.doors_near(global_position, DOOR_CLOSE_REACH + 1.0):
		add_collision_exception_with(door)
		var gap: float = door.global_position.distance_to(global_position)
		if moving and gap < DOOR_OPEN_REACH and door.is_closed():
			door.set_open(true)
			if not _doors_opened.has(door):
				_doors_opened.append(door)
	for door in _doors_opened.duplicate():
		if not is_instance_valid(door):
			_doors_opened.erase(door)
			continue
		if door.global_position.distance_to(global_position) > DOOR_CLOSE_REACH:
			_doors_opened.erase(door)
			if not door.is_closed() and not manager.anyone_near(door.global_position, DOOR_OPEN_REACH):
				door.set_open(false)


# ---- The figure ----

func _animate(delta: float, speed: float) -> void:
	if _model == null:
		return
	var walking := speed > 0.15
	_phase += delta * (speed * 4.2 if walking else 2.2)
	var swing := sin(_phase) * (0.55 if walking else 0.0)
	var bend := 0.0
	var arm_forward := 0.0
	var arm_bob := 0.0
	if _activity == "work" and not walking:
		# Bent over the work, hands reaching down into it and busy
		bend = 0.62
		arm_forward = 0.75
		arm_bob = sin(_phase * 1.8) * 0.25
	elif not walking:
		# Standing about: breathing, a slight sway
		bend = sin(_phase * 0.6) * 0.03
	var k := 1.0 - exp(-10.0 * delta)
	_torso.rotation.x = lerpf(_torso.rotation.x, -bend, k)
	_legs[0].rotation.x = lerpf(_legs[0].rotation.x, swing, k)
	_legs[1].rotation.x = lerpf(_legs[1].rotation.x, -swing, k)
	_arms[0].rotation.x = lerpf(_arms[0].rotation.x, -swing * 0.8 + arm_forward + arm_bob, k)
	_arms[1].rotation.x = lerpf(_arms[1].rotation.x, swing * 0.8 + arm_forward - arm_bob, k)
	_head.rotation.x = lerpf(_head.rotation.x, bend * 0.4 if not _lying else 0.0, k)
	# A little bob in the step
	_hips.position.y = lerpf(_hips.position.y, _hip_height() + (absf(sin(_phase)) * 0.03 if walking else 0.0), k)


func _hip_height() -> float:
	return 0.85


# A blocky low-poly person, standing on their feet at the origin and facing -Z
func _build_model() -> void:
	var tunic := _color("tunic")
	var trousers := _color("trousers")
	var scarf := _color("scarf")
	var skin := _color("skin")
	var hair := _color("hair")
	var boots := Color(0.18, 0.13, 0.09)
	var height := float(look.get("height", 1.0))
	var build := float(look.get("build", 1.0))
	_model = Node3D.new()
	_model.name = "Figure"
	_model.scale = Vector3(build, height, build) * Vector3(1, 1, 1)
	add_child(_model)
	_hips = Node3D.new()
	_hips.position.y = _hip_height()
	_model.add_child(_hips)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position.x = side * 0.1
		_hips.add_child(leg)
		_part(leg, Vector3(0.14, 0.68, 0.16), Vector3(0, -0.36, 0), trousers)
		_part(leg, Vector3(0.15, 0.16, 0.24), Vector3(0, -0.78, -0.03), boots)
		_legs.append(leg)
	_torso = Node3D.new()
	_hips.add_child(_torso)
	_part(_torso, Vector3(0.4, 0.56, 0.24), Vector3(0, 0.3, 0), tunic)
	# The tunic's hem over the hips, a belt, and a scarf round the shoulders
	_part(_torso, Vector3(0.43, 0.2, 0.27), Vector3(0, -0.02, 0), tunic.darkened(0.08))
	_part(_torso, Vector3(0.42, 0.05, 0.26), Vector3(0, 0.07, 0), Color(0.16, 0.11, 0.08))
	_part(_torso, Vector3(0.36, 0.1, 0.27), Vector3(0, 0.56, 0), scarf)
	_part(_torso, Vector3(0.1, 0.24, 0.04), Vector3(0.07, 0.43, -0.135), scarf.darkened(0.1))
	if look.get("bundle", false):
		# A bedroll bundle tied on the back
		_part(_torso, Vector3(0.38, 0.16, 0.16), Vector3(0, 0.52, 0.2), Color(0.5, 0.42, 0.32))
		_part(_torso, Vector3(0.3, 0.3, 0.1), Vector3(0, 0.3, 0.17), Color(0.4, 0.33, 0.24))
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.26, 0.54, 0)
		_torso.add_child(arm)
		_part(arm, Vector3(0.11, 0.5, 0.12), Vector3(0, -0.24, 0), tunic)
		_part(arm, Vector3(0.1, 0.1, 0.1), Vector3(0, -0.53, 0), skin)
		_arms.append(arm)
	_head = Node3D.new()
	_head.position.y = 0.62
	_torso.add_child(_head)
	var face := SphereMesh.new()
	face.radius = 0.12
	face.height = 0.25
	face.radial_segments = 8
	face.rings = 5
	_mesh(_head, face, Vector3(0, 0.14, 0), skin)
	for side in [-1.0, 1.0]:
		_part(_head, Vector3(0.03, 0.025, 0.02), Vector3(side * 0.045, 0.16, -0.112), Color(0.08, 0.06, 0.05))
	match int(look.get("hair_style", 0)):
		0:
			# Short hair
			_part(_head, Vector3(0.25, 0.09, 0.25), Vector3(0, 0.25, 0.01), hair)
			_part(_head, Vector3(0.25, 0.14, 0.1), Vector3(0, 0.17, 0.08), hair)
		1:
			# A hood in the scarf's cloth
			_part(_head, Vector3(0.28, 0.27, 0.27), Vector3(0, 0.17, 0.03), scarf.darkened(0.15))
		2:
			# A flat cap over short hair
			_part(_head, Vector3(0.25, 0.12, 0.1), Vector3(0, 0.17, 0.08), hair)
			_part(_head, Vector3(0.27, 0.06, 0.27), Vector3(0, 0.27, 0.0), trousers.lightened(0.1))
			_part(_head, Vector3(0.2, 0.025, 0.1), Vector3(0, 0.25, -0.15), trousers.lightened(0.1))
		_:
			# Long hair down the back
			_part(_head, Vector3(0.25, 0.08, 0.25), Vector3(0, 0.25, 0.01), hair)
			_part(_head, Vector3(0.24, 0.36, 0.08), Vector3(0, 0.08, 0.1), hair)


func _color(key: String) -> Color:
	var c: Array = look.get(key, [0.5, 0.5, 0.5])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _part(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(parent, box, at, color)


static var _materials := {}


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> void:
	var key := color.to_html(false)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.92
		_materials[key] = material
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	shown.material_override = _materials[key]
	shown.position = at
	parent.add_child(shown)


# ---- Saving ----

func save_data() -> Dictionary:
	return {
		"id": settler_id,
		"name": settler_name,
		"look": look,
		"home": home_id,
		"job": job_id,
		"hungry_days": hungry_days,
		"position": SaveGame.from_vector(global_position if not _lying else _standing_spot()),
		"turn": rotation.y if not _lying else global_basis.get_euler().y,
	}


func _standing_spot() -> Vector3:
	var bed: BuildPiece = manager.bed_for(self) if manager else null
	if bed:
		return _bed_side(bed)
	return global_position
