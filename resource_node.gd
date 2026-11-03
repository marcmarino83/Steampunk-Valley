class_name ResourceNode
extends StaticBody3D

## What you get from this, as shown on the counter (e.g. "Scrap", "Coal")
@export var resource_name := "Scrap"
## How much each press of E gives you
@export var amount_per_gather := 1
## How many times you can gather before it's used up
@export var gathers_left := 3

var _tween: Tween


## Whether looking at this shows a prompt (stumps and emptied piles don't)
func can_interact() -> bool:
	return gathers_left > 0


## The text shown after "[E]" when you look at this
func get_prompt() -> String:
	return "Gather %s" % resource_name


## What happens when you press E on this
func interact(player) -> void:
	var amount := gather()
	# Some things (like trees) take a few hits before giving anything
	if amount > 0:
		player.add_item(resource_name, amount)


## Takes one gather's worth from this pile and returns how much you got
func gather() -> int:
	var mesh: Node3D = $MeshInstance3D
	gathers_left -= 1
	if _tween:
		_tween.kill()
	_tween = create_tween()

	if gathers_left <= 0:
		# Used up: stop being solid or lookable, shrink away, then disappear
		collision_layer = 0
		_tween.tween_property(mesh, "scale", Vector3.ZERO, 0.25)
		_tween.tween_callback(queue_free)
	else:
		# A quick squash so you can see it worked
		_tween.tween_property(mesh, "scale", Vector3(1.15, 0.8, 1.15), 0.06)
		_tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)

	return amount_per_gather
