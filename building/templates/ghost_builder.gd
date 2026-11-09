class_name GhostBuilder
extends Node
## Building a placed template's ghosts, with the hammer out and nothing being placed (run by the
## BuildPlacer):
##
##   - Aim at a ghost: it shows brighter, and the placement panel shows its name and cost (red if
##     you're short).
##   - Left-click: builds it with materials from your inventory (never from chests), turning it into
##     the real piece (or workbench, chest, campfire). Not if you're standing in its way.
##   - Hold left-click: carries on, about FILL_RATE a second, with the ghost under the crosshair and
##     then the nearest ghosts of the same plot joined to what's been built this hold, until you
##     run out of materials or there's nothing joined left.
##   - Middle-click a ghost: takes it away (free; nothing was paid for it).
## When a plot's last ghost is built: "House is finished!", and its requirements take over as usual.
##
## Ghosts aren't solid, so the crosshair finds them by their boxes, not by physics; anything solid
## nearer than a ghost hides it.

## How far the hammer reaches a ghost, how many a second holding builds, and how close (meters
## between middles) a ghost must be to something built this hold to count as joined to it
const REACH := 7.0
const FILL_RATE := 4.0
const JOINED := 3.2

var registry: PieceRegistry
var plots: PlotRegistry
var pieces: PiecePlacer
var builder: BuildPlacer

var _player: CharacterBody3D
var _target: Node3D
var _holding := false
var _fill_in := 0.0
var _hold_plot := ""
var _built_this_hold: Array[Vector3] = []


func _ready() -> void:
	_player = get_parent().get_parent()


## Called every frame: `active` while the hammer is out with nothing being placed and no menu open.
## Keeps the ghost under the crosshair lit, and keeps building while left-click is held.
func update(delta: float, active: bool) -> void:
	var found: Node3D = ghost_in_view() if active else null
	if found != _target:
		if is_instance_valid(_target):
			_target.set_ghost_targeted(false)
		_target = found
		if _target:
			_target.set_ghost_targeted(true)
	if not _holding:
		return
	if not active or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_holding = false
		return
	_fill_in -= delta
	if _fill_in <= 0.0:
		_fill_in = 1.0 / FILL_RATE
		_build_next()


## The ghost under the crosshair (within reach), or null
func targeted() -> Node3D:
	return _target if is_instance_valid(_target) and not _target.is_queued_for_deletion() else null


## Left-click pressed: builds the ghost under the crosshair and starts holding. False if there's no
## ghost there (the click is for something else).
func press() -> bool:
	var ghost := targeted()
	if ghost == null:
		return false
	var problem := build(ghost)
	if not problem.is_empty():
		_player.flash(problem)
		return true
	_holding = true
	_fill_in = 1.0 / FILL_RATE
	_hold_plot = plots.plot_of(ghost)
	_built_this_hold = [_middle_of(ghost)]
	return true


func release() -> void:
	_holding = false


## Middle-click: takes the ghost under the crosshair away. True if there was one.
func remove_targeted() -> bool:
	var ghost := targeted()
	if ghost == null:
		return false
	var what: String = ghost.display_name()
	_target = null
	plots.remove_ghost(ghost)
	_player.flash("Removed the %s ghost" % what)
	return true


## The panel for the ghost under the crosshair (see HudControls), or empty
func info() -> Dictionary:
	var ghost := targeted()
	if ghost == null:
		return {}
	var buildable: Buildable = ghost.buildable
	var plot := plots.find(plots.plot_of(ghost))
	var affordable := buildable.can_afford(_player.inventory)
	var detail := "Ghost" + (" of %s" % plot.plot_name if plot else "")
	detail += "  ·  Click to build it" if affordable else "  ·  Missing %s" % buildable.missing_text(_player.inventory)
	return {
		"icon": buildable.icon,
		"title": buildable.display_name,
		"cost": buildable.cost_text(),
		"cost_bad": not affordable,
		"detail": detail,
		"detail_bad": not affordable,
	}


## Builds one ghost with materials from the inventory. Returns why it couldn't, or empty if it did.
func build(ghost: Node3D) -> String:
	var buildable: Buildable = ghost.buildable
	var what := buildable.display_name
	var cost := buildable.cost_to_pay(_player.inventory)
	if cost.is_empty():
		return "Not enough for the %s: you need %s" % [what, buildable.missing_text(_player.inventory)]
	if ghost is BuildPiece:
		var hit: Object = pieces.piece_blocked(ghost, ghost.global_transform, [])
		if hit == _player:
			return "You're in the way: step out to build the %s" % what
		if hit:
			return "Someone's in the way of the %s" % what
	var plot_id := plots.plot_of(ghost)
	cost = _player.pay(cost)
	if ghost == _target:
		_target = null
	if ghost is BuildPiece:
		ghost.set_ghost_targeted(false)
		registry.fill(ghost, cost)
	else:
		builder.fill_ghost_building(ghost, cost)
	_player.report_progress("Build", what)
	plots.mark_dirty()
	var plot := plots.find(plot_id)
	if plot and plots.ghosts_of(plot).is_empty():
		_holding = false
		_player.flash("%s is finished!" % plot.plot_name, 5.0)
	return ""


# Holding: the ghost under the crosshair, else the nearest one of the same plot joined to what's
# been built this hold. Stops when none of those can be built.
func _build_next() -> void:
	var tried := []
	var aimed := targeted()
	if aimed:
		tried.append(aimed)
	var plot := plots.find(_hold_plot)
	if plot:
		var last: Vector3 = _built_this_hold[-1] if not _built_this_hold.is_empty() else _player.global_position
		var joined := plots.ghosts_of(plot).filter(func(g):
			var middle := _middle_of(g)
			for spot in _built_this_hold:
				if spot.distance_to(middle) <= JOINED:
					return true
			return false)
		joined.sort_custom(func(a, b): return _middle_of(a).distance_to(last) < _middle_of(b).distance_to(last))
		for ghost in joined:
			if not tried.has(ghost):
				tried.append(ghost)
	var first_problem := ""
	for ghost in tried:
		var middle := _middle_of(ghost)
		var problem := build(ghost)
		if problem.is_empty():
			_built_this_hold.append(middle)
			return
		if first_problem.is_empty():
			first_problem = problem
	_holding = false
	if plot and not plots.ghosts_of(plot).is_empty():
		_player.flash(first_problem if not first_problem.is_empty() else "Nothing joined left to build here")


# The ghost the crosshair passes through first (by its box), unless something solid is nearer
func ghost_in_view() -> Node3D:
	var camera: Camera3D = _player.camera
	var from := camera.global_position
	var direction := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * REACH)
	query.exclude = [_player.get_rid()]
	var solid := _player.get_world_3d().direct_space_state.intersect_ray(query)
	var nearest := REACH
	if not solid.is_empty():
		nearest = from.distance_to(solid["position"]) + 0.2
	var best: Node3D = null
	for ghost in registry.ghost_pieces() + plots.ghost_buildings():
		var node := ghost as Node3D
		if node.global_position.distance_to(from) > REACH + 8.0:
			continue
		var box: AABB = PieceShapes.bounds_of(node.shape_def()) if node is BuildPiece else node.bounds
		var back := node.global_transform.affine_inverse()
		var hit = box.grow(0.03).intersects_ray(back * from, back.basis * direction)
		if hit == null:
			continue
		var distance := from.distance_to(node.global_transform * (hit as Vector3))
		if distance < nearest:
			nearest = distance
			best = node
	return best


func _middle_of(ghost: Node3D) -> Vector3:
	if ghost is BuildPiece:
		return ghost.center()
	return ghost.global_transform * (ghost.bounds as AABB).get_center()
