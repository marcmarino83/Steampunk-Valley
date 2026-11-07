class_name ResourceNode
extends StaticBody3D

## What you get from this, as shown on the counter (e.g. "Scrap", "Coal")
@export var resource_name := "Scrap"
## How much each press of E gives you
@export var amount_per_gather := 1
## How many times you can gather before it's used up
@export var gathers_left := 3
## The tool you must be holding to gather this, or empty if bare hands will do
@export var required_tool := ""
## A tool that gets you extra from each gather while it's in your hand, and how much extra
@export var bonus_tool := ""
@export var bonus_amount := 0

var _tween: Tween


## True if this player isn't holding the tool it takes
func needs_tool(player) -> bool:
	return not required_tool.is_empty() and player.held_item != required_tool


## Whether looking at this shows a prompt (stumps and emptied piles don't)
func can_interact() -> bool:
	return gathers_left > 0


## The text shown after "[E]" when you look at this
func get_prompt() -> String:
	return "Gather %s" % resource_name


## What happens when you press E on this
func interact(player) -> void:
	if needs_tool(player):
		player.flash("Equip the %s first" % required_tool)
		return
	var amount := gather()
	# Some things (like trees) take a few hits before giving anything
	if amount > 0:
		if not bonus_tool.is_empty() and player.held_item == bonus_tool:
			amount += bonus_amount
		player.gathered(resource_name, amount)


## Takes one gather's worth from this pile and returns how much you got
func gather() -> int:
	var mesh: Node3D = $MeshInstance3D
	gathers_left -= 1
	if _tween:
		_tween.kill()
	_tween = create_tween()

	if gathers_left <= 0:
		# Used up: stop being solid or lookable, shrink away, then disappear (booking its return
		# first, if it's a kind that comes back)
		collision_layer = 0
		_book_respawn()
		_tween.tween_property(mesh, "scale", Vector3.ZERO, 0.25)
		_tween.tween_callback(queue_free)
	else:
		# A quick squash so you can see it worked
		_tween.tween_property(mesh, "scale", Vector3(1.15, 0.8, 1.15), 0.06)
		_tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)

	return amount_per_gather


# Scattered pickups come back after a while, if the valley gives their kind a respawn time
func _book_respawn() -> void:
	var valley = get_tree().get_first_node_in_group("valley")
	if valley and not Engine.is_editor_hint():
		valley.pickup_gathered(self)
