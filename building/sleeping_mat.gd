extends StaticBody3D
## The bed of leaves in a lean-to. E sleeps through to morning, if it's night.


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "Sleep"


func interact(player) -> void:
	player.sleep(global_position)
