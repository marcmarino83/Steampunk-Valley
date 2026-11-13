class_name Interaction
extends Node
## What the crosshair is on: the thing E would use (within the look ray's reach), a plot whose
## ground it points at in plot view (or when what's aimed at does nothing itself, with the hammer
## out), and the valley's scattered rocks (they have no collision, so the look ray can't see them)
## with the pickaxe. Also which plot the plot tracker shows, and the E prompt under the crosshair.
## A child of the player (see player.gd, which forwards its old functions here).

## How far ahead the plot whose ground you're aiming at is found, in plot view
const PLOT_REACH := 20.0

## The player's body (where you stand, its rays), its camera and look ray, the placer (placing or
## not, the plots), the hammer's controls (plot view) and what's in your hand. Set by the player.
var body: CharacterBody3D
var camera: Camera3D
var interact_ray: RayCast3D
var placer: BuildPlacer
var build: BuildControls
var held: Callable

# The grass, ferns and scattered rocks, found the first time a pickaxe needs them
var _foliage: Node


## The thing in front of you (within reach) that E would use, or null
func looked_at() -> Object:
	var target = interact_ray.get_collider() if interact_ray.is_colliding() else null
	var held_item: String = held.call()
	# With the hammer out (not placing), the ground or a building piece inside a plot opens that
	# plot's panel (move, resize, checklist): in plot view always, otherwise unless what you aim
	# at does something itself (a door, the Storehouse's storage, a chest)
	if held_item == "Hammer" and not placer.is_placing():
		var plain: bool = target == null or not target.has_method("interact") \
				or not target.can_interact()
		if (build.plot_view_on() and (plain or target is BuildPiece)) or plain:
			var plot := plot_looked_at()
			if plot:
				return plot
	# Stumps and emptied piles are still there, but have nothing left
	if target and target.has_method("interact") and target.can_interact():
		return target
	if held_item == MineableRock.TOOL:
		return _scattered_rock_looked_at()
	return null


## The E prompt under the crosshair: [["E", what it does]], or none
func prompts() -> Array:
	var target = looked_at()
	if not target:
		return []
	var what: String = target.get_prompt()
	if target is ResourceNode and target.needs_tool(body):
		what += " (equip the %s)" % target.required_tool
	return [["E", what]]


## The plot the tracker shows, with the hammer out: the one aimed at in plot view, or else the one
## you're standing in (of overlapping plots, the one whose middle is nearest); null for none
func tracked_plot() -> Plot:
	if held.call() != "Hammer":
		return null
	var plot: Plot = plot_looked_at() if build.plot_view_on() else null
	if plot == null:
		var here := body.global_position
		plot = placer.plots.find(placer.plots.owner_for(here, here))
	return plot


## The plot whose ground the crosshair points at (within PLOT_REACH): of overlapping plots, the one
## whose middle is nearest you
func plot_looked_at() -> Plot:
	var from := camera.global_position
	var ahead := from - camera.global_basis.z * PLOT_REACH
	var query := PhysicsRayQueryParameters3D.create(from, ahead)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return placer.plots.find(placer.plots.owner_for(hit["position"], body.global_position))


# A scattered rock between you and whatever the look ray did hit, so rocks behind a hillside don't
# count
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
